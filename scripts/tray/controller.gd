class_name TrayController
extends Node

# TrayController 是 main.window.tscn 中的托盘 UI 节点.
# 它直接管理 Godot StatusIndicator、右键自绘菜单, 以及托盘入口打开的两个独立窗口.
# 它不负责业务页面切换: 登录完成和调试边框变化只通过信号抛给 GTray, 由 GTray 和 MainWindow 处理业务结果.
# 菜单不用 StatusIndicator.menu, 而是用 force_native Window 自绘, 目的是避免 Windows 原生 popup 阻塞 Godot 主循环.

# 账号登录在托盘选项窗口完成, 由主场景决定登录后显示哪个页面.
signal account_login_completed
# 系统选项中的调试边框开关变化后, 由主场景负责实际绘制或隐藏.
signal debug_border_changed(enabled: bool)

# 选项窗口用脚本动态创建, 不需要在 main.window.tscn 里额外放节点.
const OptionsDialogControllerScript := preload("res://scripts/tray/options/dialog.controller.gd")
# 设置窗口用脚本动态创建, 不需要在 main.window.tscn 里额外放节点.
const SettingDialogControllerScript := preload("res://scripts/tray/setting/dialog.controller.gd")
# 菜单窗口相对托盘图标和父菜单项的偏移.
const MENU_WINDOW_OFFSET := Vector2i(4, 4)
# 菜单刚弹出时给一点焦点宽限, 避免 Windows 焦点切换瞬间导致菜单立刻关闭.
const MENU_FOCUS_GRACE_MSEC := 250
# 以下尺寸常量控制自绘菜单的间距和 padding.
const MENU_MARGIN := 8
const MENU_SPACING := 4
const MENU_ITEM_PADDING_X := 8
const MENU_ITEM_PADDING_Y := 3
const MENU_TASKBAR_CLEARANCE := 8
const TASKBAR_EDGE_DETECTION_DISTANCE := 96

# 这些控制器由 GTray 初始化时注入.
# WindowController 是 MainWindow 持有的真实窗口控制 helper.
# 托盘菜单只调用它暴露的窗口操作, 不直接散落 DisplayServer 调用.
var window_controller: WindowController
# 菜单主题来自 tray.yaml, 读取失败时使用 GTrayConfig 的默认值.
# 主题值在 initialize() 时读取一次, 后续所有动态创建的按钮和面板都使用这批缓存值.
var menu_font_size := 14
var menu_panel_color := Color(0.98, 0.98, 0.98, 1.0)
var menu_panel_border_color := Color(0.52, 0.56, 0.64, 1.0)
var menu_text_color := Color(0.05, 0.06, 0.08, 1.0)
var menu_text_on_hover_color := Color(1.0, 1.0, 1.0, 1.0)
var menu_highlight_color := Color(0.10, 0.38, 0.82, 1.0)
var menu_pressed_color := Color(0.07, 0.28, 0.64, 1.0)
var menu_disabled_text_color := Color(0.58, 0.61, 0.66, 1.0)
# StatusIndicator 是 Godot 的系统托盘图标节点.
var tray_icon: StatusIndicator
# 主菜单使用独立 native Window, 这样不会阻塞 Godot 主循环.
var menu_window: Window
var menu_vbox: VBoxContainer
# 弹窗控制器不是 .tscn 节点, 而是 TrayController 启动时动态创建的普通 Node.
# 这样 main.window.tscn 只需要保留一个托盘入口节点, 静态场景树不会被选项页和设置页细节污染.
var options_dialog
var setting_dialog
# menu_focus_seen 用于处理菜单刚弹出时的 Windows 焦点抖动.
# 如果菜单还没真正拿到过焦点, 会给 MENU_FOCUS_GRACE_MSEC 宽限时间, 避免弹出后立即关闭.
var menu_focus_seen := false
var menu_shown_msec := 0

# 初始化托盘控制器.
# 这里会创建托盘图标, 主菜单窗口和选项窗口.
# controller 必须是 MainWindow 已初始化过的 WindowController.
# 初始化顺序固定为主题 -> 菜单窗口 -> 弹窗 -> StatusIndicator, 因为菜单和弹窗都依赖主题, StatusIndicator 最后连接用户入口.
func initialize(
    controller: WindowController
) -> void:
    window_controller = controller

    _load_menu_theme()
    _build_menu_window()
    _build_setting_dialog()
    _build_options_dialog()
    _build_status_indicator()
    set_process(false)

# 从 GTrayConfig 读取菜单字体和颜色.
# 读取结果保存成成员变量, 后续创建按钮和面板时统一使用.
func _load_menu_theme() -> void:
    menu_font_size = GTrayConfig.get_font_size()
    var colors := GTrayConfig.get_colors()
    menu_panel_color = colors.get("panel", menu_panel_color)
    menu_panel_border_color = colors.get("border", menu_panel_border_color)
    menu_text_color = colors.get("text", menu_text_color)
    menu_text_on_hover_color = colors.get("hover_text", menu_text_on_hover_color)
    menu_highlight_color = colors.get("highlight", menu_highlight_color)
    menu_pressed_color = colors.get("pressed", menu_pressed_color)
    menu_disabled_text_color = colors.get("disabled_text", menu_disabled_text_color)

# 菜单显示时才开启 `_process`.
# 每帧检查鼠标位置, 更新主菜单高亮, 并在菜单失焦后关闭.
# 平时关闭 process 可以避免托盘常驻时每帧做鼠标和窗口矩形计算.
# 打开菜单后用轮询处理 hover, 是因为 native Window 中的 Control hover 状态不总能覆盖窗口失焦后的关闭判断.
func _process(_delta: float) -> void:
    if menu_window == null or not menu_window.visible:
        set_process(false)
        return

    _update_menu_item_highlights()

    if _menu_group_is_active():
        menu_focus_seen = true
        return

    var elapsed_msec := Time.get_ticks_msec() - menu_shown_msec
    if menu_focus_seen or elapsed_msec > MENU_FOCUS_GRACE_MSEC:
        _hide_menu()

# 根据固定功能创建根菜单.
# 设置窗口, 选项窗口和退出是托盘固定功能, 不从 tray.yaml 读取.
# 缩放和透明度改由 `设置... -> 隐藏石器` 下方的滑动控件控制, 并记录到 setting.window.
# 主窗口显隐改由 `设置... -> 隐藏石器` 控制, 并记录到 setting.login.hide_stoneage.
# 鼠标穿透改由设置窗口控制, 便于和隐藏石器放在同一组窗口行为设置中.
func _build_menu_window() -> void:
    menu_window = _create_native_menu_window("TrayMenuWindow", Vector2i.ONE)
    add_child(menu_window)

    menu_vbox = _add_window_content(menu_window)
    _add_fixed_menu_items()

    var size := _main_menu_size()
    menu_window.size = size
    menu_window.min_size = size

# 添加不可由 tray.yaml 关闭的核心托盘功能.
# 当前 MVP 菜单项是固定能力, 不从配置声明顺序和显隐.
# tray.yaml 只配置菜单样式和窗口运行状态, 避免菜单结构和业务入口过早配置化.
func _add_fixed_menu_items() -> void:
    _add_button(menu_vbox, "设置...", _on_setting_options_pressed)

    _add_button(menu_vbox, "选项...", _on_options_pressed)

    _add_button(menu_vbox, "退出", _on_quit_pressed)

# 设置窗口单独由 SettingDialogController 管理.
func _build_setting_dialog() -> void:
    setting_dialog = SettingDialogControllerScript.new()
    setting_dialog.name = "SettingDialogController"
    add_child(setting_dialog)
    setting_dialog.initialize(window_controller)

# 选项窗口单独由 OptionsDialogController 管理.
func _build_options_dialog() -> void:
    options_dialog = OptionsDialogControllerScript.new()
    options_dialog.name = "OptionsDialogController"
    add_child(options_dialog)
    options_dialog.initialize()
    options_dialog.account_login_completed.connect(_on_options_account_login_completed)
    options_dialog.debug_border_changed.connect(_on_options_debug_border_changed)

# 创建一个原生窗口作为菜单.
# 不使用 StatusIndicator.menu, 是为了避免原生 popup 阻塞 Godot 主循环.
func _create_native_menu_window(window_name: String, size: Vector2i) -> Window:
    var window := Window.new()
    window.name = window_name
    window.visible = false
    window.title = "sa.desktop"
    window.force_native = true
    window.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
    window.borderless = true
    window.unresizable = true
    window.always_on_top = true
    window.transient = false
    window.size = size
    window.min_size = size
    window.close_requested.connect(_hide_menu)
    window.focus_entered.connect(_on_menu_focus_entered)
    window.focus_exited.connect(_on_menu_focus_exited)
    return window

# 给普通菜单窗口添加 PanelContainer, MarginContainer 和 VBoxContainer.
# 返回 VBoxContainer, 后续按钮都添加到这里.
func _add_window_content(window: Window) -> VBoxContainer:
    var panel := PanelContainer.new()
    _apply_menu_panel_theme(panel)
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    window.add_child(panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", MENU_MARGIN)
    margin.add_theme_constant_override("margin_top", MENU_MARGIN)
    margin.add_theme_constant_override("margin_right", MENU_MARGIN)
    margin.add_theme_constant_override("margin_bottom", MENU_MARGIN)
    panel.add_child(margin)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", MENU_SPACING)
    margin.add_child(vbox)
    return vbox

# 添加普通按钮并连接 pressed 回调.
func _add_button(parent: VBoxContainer, text: String, callback: Callable) -> Button:
    var button := _create_button(text)
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

# 创建一个带统一主题的菜单按钮.
func _create_button(text: String) -> Button:
    var button := Button.new()
    button.text = text
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.focus_mode = Control.FOCUS_NONE
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _apply_menu_item_theme(button)
    return button

# 创建系统托盘图标并连接右键点击.
# StatusIndicator 只承担托盘图标和鼠标入口.
# 右键后的位置由 Godot 传入, 如果平台拿不到托盘图标矩形, 后续会用该鼠标位置兜底定位菜单.
func _build_status_indicator() -> void:
    tray_icon = StatusIndicator.new()
    tray_icon.name = "TrayIcon"
    tray_icon.icon = load("res://icon.svg")
    tray_icon.tooltip = "sa.desktop"
    # 保持 StatusIndicator.menu 默认空路径, 避免原生 popup 菜单阻塞 Godot 主循环.
    tray_icon.pressed.connect(_on_tray_icon_pressed)
    add_child(tray_icon)

func _on_tray_icon_pressed(mouse_button: int, mouse_position: Vector2i) -> void:
    if mouse_button != MOUSE_BUTTON_RIGHT:
        return

    _show_menu_at(mouse_position)

# 在托盘图标附近显示主菜单.
# Windows 上托盘图标坐标有时拿不到, 所以后续会用鼠标位置兜底.
func _show_menu_at(mouse_position: Vector2i) -> void:
    var anchor_position := _tray_anchor_position(mouse_position)
    var screen := _screen_for_position(anchor_position)
    var size := _main_menu_size()
    menu_window.current_screen = screen
    menu_window.min_size = size
    menu_window.size = size
    menu_window.position = _clamp_window_position(anchor_position + MENU_WINDOW_OFFSET, size, screen)
    menu_window.show()
    menu_focus_seen = false
    menu_shown_msec = Time.get_ticks_msec()
    set_process(true)
    menu_window.grab_focus()

# 隐藏主菜单.
func _hide_menu() -> void:
    if menu_window != null:
        menu_window.hide()
    menu_focus_seen = false
    set_process(false)

# 菜单窗口获得焦点后, 说明用户正在使用菜单.
func _on_menu_focus_entered() -> void:
    menu_focus_seen = true

# 失焦后延迟到下一帧再判断, 给鼠标回到菜单窗口的机会.
func _on_menu_focus_exited() -> void:
    call_deferred("_hide_menu_if_group_unfocused")

# 如果菜单没有焦点或鼠标停留, 就关闭菜单.
func _hide_menu_if_group_unfocused() -> void:
    if menu_window != null and menu_window.visible and not _menu_group_is_active():
        _hide_menu()

# 菜单活跃的条件: 有焦点或鼠标仍在主菜单窗口内.
func _menu_group_is_active() -> bool:
    return _menu_group_has_focus() or _menu_group_contains_mouse()

# 检查主菜单是否拥有焦点.
func _menu_group_has_focus() -> bool:
    return menu_window != null and menu_window.visible and menu_window.has_focus()

# 鼠标在主菜单窗口内时, 菜单仍保持打开.
func _menu_group_contains_mouse() -> bool:
    var mouse_position := DisplayServer.mouse_get_position()
    return _window_screen_rect(menu_window).has_point(mouse_position)

# 根据鼠标位置刷新主菜单项高亮.
func _update_menu_item_highlights() -> void:
    var mouse_position := DisplayServer.mouse_get_position()
    var hovered_item := _menu_item_at_position(menu_vbox, menu_window, mouse_position)
    _update_menu_group_item_highlights(menu_vbox, hovered_item)

# 更新菜单里的按钮视觉状态.
func _update_menu_group_item_highlights(parent: VBoxContainer, hovered_item: BaseButton) -> void:
    if parent == null:
        return

    for child in parent.get_children():
        if child is BaseButton:
            var item := child as BaseButton
            var highlighted := item == hovered_item
            var suppress_hover := hovered_item != null and not highlighted
            _set_menu_item_visual_state(item, highlighted, suppress_hover)

# 在指定菜单层中查找鼠标下方的按钮.
func _menu_item_at_position(parent: VBoxContainer, window: Window, mouse_position: Vector2i) -> BaseButton:
    if parent == null or window == null or not window.visible:
        return null

    for child in parent.get_children():
        if child is BaseButton and _screen_rect_for_control_in_window(child, window).has_point(mouse_position):
            return child as BaseButton

    return null

# 给普通菜单按钮应用主题.
# hover_enabled=false 时用于压制同层其他按钮的 hover, 避免多项同时高亮.
func _apply_menu_item_theme(button: BaseButton, hover_enabled: bool = true) -> void:
    button.add_theme_font_size_override("font_size", menu_font_size)
    button.add_theme_color_override("font_color", menu_text_color)
    button.add_theme_color_override("font_hover_color", menu_text_on_hover_color if hover_enabled else menu_text_color)
    button.add_theme_color_override("font_pressed_color", menu_text_on_hover_color)
    button.add_theme_color_override("font_focus_color", menu_text_on_hover_color)
    button.add_theme_color_override("font_hover_pressed_color", menu_text_on_hover_color if hover_enabled else menu_text_color)
    button.add_theme_color_override("font_disabled_color", menu_disabled_text_color)
    button.add_theme_stylebox_override("normal", _menu_item_style(menu_panel_color))
    button.add_theme_stylebox_override("hover", _menu_item_style(menu_highlight_color if hover_enabled else menu_panel_color))
    button.add_theme_stylebox_override("pressed", _menu_item_style(menu_pressed_color))
    button.add_theme_stylebox_override("hover_pressed", _menu_item_style(menu_pressed_color if hover_enabled else menu_panel_color))
    button.add_theme_stylebox_override("focus", _menu_item_style(menu_highlight_color if hover_enabled else menu_panel_color))
    button.add_theme_stylebox_override("disabled", _menu_item_style(menu_panel_color))

# 根据 highlighted 和 suppress_hover 更新按钮视觉状态.
# 使用 meta 保存当前状态, 避免每帧重复应用主题造成不必要开销.
func _set_menu_item_visual_state(button: BaseButton, highlighted: bool, suppress_hover: bool) -> void:
    if button == null:
        return

    if bool(button.get_meta("menu_highlighted", false)) == highlighted and bool(button.get_meta("menu_hover_suppressed", false)) == suppress_hover:
        return

    button.set_meta("menu_highlighted", highlighted)
    button.set_meta("menu_hover_suppressed", suppress_hover)
    if not highlighted:
        _apply_menu_item_theme(button, not suppress_hover)
        return

    button.add_theme_font_size_override("font_size", menu_font_size)
    button.add_theme_color_override("font_color", menu_text_on_hover_color)
    button.add_theme_color_override("font_hover_color", menu_text_on_hover_color)
    button.add_theme_color_override("font_pressed_color", menu_text_on_hover_color)
    button.add_theme_color_override("font_focus_color", menu_text_on_hover_color)
    button.add_theme_color_override("font_hover_pressed_color", menu_text_on_hover_color)
    button.add_theme_stylebox_override("normal", _menu_item_style(menu_highlight_color))
    button.add_theme_stylebox_override("hover", _menu_item_style(menu_highlight_color))
    button.add_theme_stylebox_override("pressed", _menu_item_style(menu_highlight_color))
    button.add_theme_stylebox_override("hover_pressed", _menu_item_style(menu_highlight_color))
    button.add_theme_stylebox_override("focus", _menu_item_style(menu_highlight_color))

# 给菜单外层面板应用背景和边框.
func _apply_menu_panel_theme(panel: PanelContainer) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = menu_panel_color
    style.border_color = menu_panel_border_color
    style.set_border_width_all(1)
    style.set_content_margin(SIDE_LEFT, 0)
    style.set_content_margin(SIDE_RIGHT, 0)
    style.set_content_margin(SIDE_TOP, 0)
    style.set_content_margin(SIDE_BOTTOM, 0)
    panel.add_theme_stylebox_override("panel", style)

# 创建菜单项 StyleBox.
# 每次返回新对象, 避免多个按钮共享同一个 StyleBox 后互相影响.
func _menu_item_style(background_color: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = background_color
    style.corner_radius_top_left = 3
    style.corner_radius_top_right = 3
    style.corner_radius_bottom_left = 3
    style.corner_radius_bottom_right = 3
    style.set_content_margin(SIDE_LEFT, MENU_ITEM_PADDING_X)
    style.set_content_margin(SIDE_RIGHT, MENU_ITEM_PADDING_X)
    style.set_content_margin(SIDE_TOP, MENU_ITEM_PADDING_Y)
    style.set_content_margin(SIDE_BOTTOM, MENU_ITEM_PADDING_Y)
    return style

# 主菜单尺寸由内容最小尺寸决定, 不限制高度.
func _main_menu_size() -> Vector2i:
    return _content_window_size(menu_vbox)

# 根据内容计算菜单窗口尺寸.
# 主菜单只有固定三项, 高度不需要额外滚动限制.
func _content_window_size(content_vbox: VBoxContainer) -> Vector2i:
    if content_vbox == null:
        return Vector2i.ONE

    var content_size := content_vbox.get_combined_minimum_size()
    var requested_width := int(ceil(content_size.x + float(MENU_MARGIN * 2)))
    var requested_height := int(ceil(content_size.y + float(MENU_MARGIN * 2)))
    var minimum_height := _minimum_menu_height()
    requested_width = max(1, requested_width)
    requested_height = max(minimum_height, requested_height)

    return Vector2i(requested_width, requested_height)

# 菜单最小高度至少能容纳一项和上下 margin.
func _minimum_menu_height() -> int:
    return int(ceil(float(menu_font_size + MENU_ITEM_PADDING_Y * 2 + MENU_MARGIN * 2)))

# 把控件的窗口内 global_rect 转换为屏幕坐标.
func _screen_rect_for_control_in_window(control: Control, window: Window) -> Rect2i:
    if control == null or window == null:
        return Rect2i()

    var rect := control.get_global_rect()
    return Rect2i(
        window.position + Vector2i(int(round(rect.position.x)), int(round(rect.position.y))),
        Vector2i(int(round(rect.size.x)), int(round(rect.size.y)))
    )

# 获取菜单窗口在屏幕坐标系中的矩形.
func _window_screen_rect(window: Window) -> Rect2i:
    if window == null or not window.visible:
        return Rect2i()

    return Rect2i(window.position, window.size)

# 计算菜单弹出的锚点.
# 优先使用托盘图标矩形中心, 拿不到时用右键点击位置或当前鼠标位置兜底.
func _tray_anchor_position(mouse_position: Vector2i) -> Vector2i:
    var indicator_rect := tray_icon.get_rect()
    if indicator_rect.size.x > 0.0 and indicator_rect.size.y > 0.0:
        return Vector2i(
            int(round(indicator_rect.position.x + indicator_rect.size.x * 0.5)),
            int(round(indicator_rect.position.y + indicator_rect.size.y * 0.5))
        )

    if _is_screen_position_valid(mouse_position):
        return mouse_position

    return DisplayServer.mouse_get_position()

# 判断一个屏幕坐标是否落在任意显示器内.
func _is_screen_position_valid(position: Vector2i) -> bool:
    return DisplayServer.get_screen_from_rect(Rect2i(position, Vector2i.ONE)) >= 0

# 根据屏幕坐标找显示器编号, 找不到时退回主窗口所在显示器.
func _screen_for_position(position: Vector2i) -> int:
    var screen := DisplayServer.get_screen_from_rect(Rect2i(position, Vector2i.ONE))
    if screen < 0:
        screen = DisplayServer.window_get_current_screen()
    return screen

# 把菜单窗口限制在指定显示器的可用区域内.
func _clamp_window_position(position: Vector2i, size: Vector2i, screen: int) -> Vector2i:
    var usable_rect := _menu_usable_rect(screen)
    var max_position := usable_rect.position + usable_rect.size - size
    max_position.x = max(max_position.x, usable_rect.position.x)
    max_position.y = max(max_position.y, usable_rect.position.y)

    return Vector2i(
        clampi(position.x, usable_rect.position.x, max_position.x),
        clampi(position.y, usable_rect.position.y, max_position.y)
    )

# 计算菜单可用区域.
# 除了系统可用区域外, 还会根据托盘图标所在边缘留出任务栏间距.
# DisplayServer.screen_get_usable_rect() 在不同 Windows 任务栏位置下不总能完全表达托盘所在边缘.
# 这里额外根据托盘图标矩形推断任务栏边缘, 避免菜单弹出后覆盖任务栏或出现在图标后面.
func _menu_usable_rect(screen: int) -> Rect2i:
    var usable_rect := DisplayServer.screen_get_usable_rect(screen)
    var screen_rect := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
    var tray_rect := _tray_icon_rect()
    if tray_rect.size == Vector2i.ZERO:
        return usable_rect

    var usable_end := usable_rect.position + usable_rect.size
    var edge := _nearest_tray_screen_edge(tray_rect, screen_rect)
    match edge:
        "bottom":
            usable_end.y = min(usable_end.y, tray_rect.position.y - MENU_TASKBAR_CLEARANCE)
        "top":
            usable_rect.position.y = max(usable_rect.position.y, tray_rect.position.y + tray_rect.size.y + MENU_TASKBAR_CLEARANCE)
        "right":
            usable_end.x = min(usable_end.x, tray_rect.position.x - MENU_TASKBAR_CLEARANCE)
        "left":
            usable_rect.position.x = max(usable_rect.position.x, tray_rect.position.x + tray_rect.size.x + MENU_TASKBAR_CLEARANCE)

    usable_rect.size = Vector2i(
        max(1, usable_end.x - usable_rect.position.x),
        max(1, usable_end.y - usable_rect.position.y)
    )
    return usable_rect

# 判断托盘图标最靠近屏幕哪条边.
# 这能推断任务栏在上, 下, 左还是右, 用于避免菜单盖住任务栏.
func _nearest_tray_screen_edge(tray_rect: Rect2i, screen_rect: Rect2i) -> String:
    var screen_end := screen_rect.position + screen_rect.size
    var distances := {
        "bottom": abs(screen_end.y - (tray_rect.position.y + tray_rect.size.y)),
        "top": abs(tray_rect.position.y - screen_rect.position.y),
        "right": abs(screen_end.x - (tray_rect.position.x + tray_rect.size.x)),
        "left": abs(tray_rect.position.x - screen_rect.position.x),
    }
    var nearest_edge := ""
    var nearest_distance := TASKBAR_EDGE_DETECTION_DISTANCE + 1
    for edge in distances.keys():
        var distance := int(distances[edge])
        if distance < nearest_distance:
            nearest_edge = edge
            nearest_distance = distance

    return nearest_edge if nearest_distance <= TASKBAR_EDGE_DETECTION_DISTANCE else ""

# 获取托盘图标矩形.
# 某些平台可能拿不到有效尺寸, 此时返回空矩形并使用鼠标位置兜底.
func _tray_icon_rect() -> Rect2i:
    if tray_icon == null:
        return Rect2i()

    var rect := tray_icon.get_rect()
    if rect.size.x <= 0.0 or rect.size.y <= 0.0:
        return Rect2i()

    return Rect2i(
        Vector2i(int(round(rect.position.x)), int(round(rect.position.y))),
        Vector2i(int(round(rect.size.x)), int(round(rect.size.y)))
    )

# 打开设置窗口.
func _on_setting_options_pressed() -> void:
    _hide_menu()
    if setting_dialog != null:
        setting_dialog.show_dialog()

# 打开选项窗口.
func _on_options_pressed() -> void:
    _hide_menu()
    if options_dialog != null:
        options_dialog.show_dialog()

# 选项窗口账号页登录成功后, 托盘控制器只转发信号.
# 具体进入游戏页由 GTray 处理.
func _on_options_account_login_completed() -> void:
    account_login_completed.emit()

# 系统页调试边框开关变化后, 托盘控制器只转发给主场景重绘.
func _on_options_debug_border_changed(enabled: bool) -> void:
    debug_border_changed.emit(enabled)

# 退出应用.
func _on_quit_pressed() -> void:
    get_tree().quit()
