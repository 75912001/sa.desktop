class_name OptionsDialogController
extends Node

# 账号页登录成功后发出这个信号.
# 选项窗口不直接切换页面, 只通知上层控制器“账号已经保存完成”.
# TrayController 会继续把该信号转发给 GTray, 由 GTray 决定登录完成后切换到哪个业务页面.
signal account_login_completed
# 系统页调试边框开关变化后发出这个信号.
# 主场景监听后只负责重绘红边, 状态直接写入 tray.yaml.
# 这里把“写配置”和“通知重绘”分开, 避免 MainWindow 需要知道选项窗口里的控件细节.
signal debug_border_changed(enabled: bool)

# 选项窗口当前是一个独立 native Window, 不是主窗口里的面板.
# 这样打开设置时不会影响透明主窗口的显示, 也不会改变 ContentRoot 中的业务页面.
# 它由 TrayController 动态创建并复用, 不挂到 main.window.tscn 的静态场景树里.
# 独立 Window 可以保持普通不透明设置界面, 不继承桌宠主窗口的透明度、缩放和鼠标穿透状态.
const DIALOG_SIZE := Vector2i(420, 300)
const DIALOG_MARGIN := 16
const CONTENT_SPACING := 10

var dialog_window: Window
var status_label: Label
var login_button: Button
var debug_border_check: CheckBox

# 初始化时创建窗口和控件.
# 之后重复打开只需要 show, 不需要重新构建控件树.
# 初始化后立即同步一次 UI, 确保第一次打开前账号提示和系统勾选状态已经是当前配置.
func initialize() -> void:
    _build_dialog()
    _sync_account_ui()
    _sync_system_ui()

# 显示选项窗口.
# 每次显示前都会同步账号和系统设置, 以反映外部状态变化.
# 例如用户通过其它流程修改了调试边框配置, 下次打开系统页时复选框应显示最新值.
func show_dialog() -> void:
    if dialog_window == null:
        _build_dialog()

    _sync_account_ui()
    _sync_system_ui()
    var screen := DisplayServer.window_get_current_screen()
    dialog_window.current_screen = screen
    dialog_window.position = _centered_position(DIALOG_SIZE, screen)
    dialog_window.size = DIALOG_SIZE
    dialog_window.min_size = DIALOG_SIZE
    dialog_window.show()
    dialog_window.grab_focus()

# 用代码创建窗口和 TabContainer.
# 这里不依赖 .tscn, 是为了让托盘控制器能按需创建一个轻量选项窗口.
# 选项窗口内容当前很少, 用代码构建可以避免为 MVP 维护额外场景文件.
# 如果后续账号页或系统页变复杂, 再拆成独立场景会更合适.
func _build_dialog() -> void:
    if dialog_window != null:
        return

    dialog_window = Window.new()
    dialog_window.name = "OptionsDialogWindow"
    dialog_window.title = "选项"
    dialog_window.visible = false
    dialog_window.force_native = true
    dialog_window.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
    dialog_window.size = DIALOG_SIZE
    dialog_window.min_size = DIALOG_SIZE
    dialog_window.always_on_top = true
    dialog_window.unresizable = true
    dialog_window.close_requested.connect(_hide_dialog)
    add_child(dialog_window)

    var root_panel := PanelContainer.new()
    root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dialog_window.add_child(root_panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", DIALOG_MARGIN)
    margin.add_theme_constant_override("margin_top", DIALOG_MARGIN)
    margin.add_theme_constant_override("margin_right", DIALOG_MARGIN)
    margin.add_theme_constant_override("margin_bottom", DIALOG_MARGIN)
    root_panel.add_child(margin)

    var tabs := TabContainer.new()
    tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    margin.add_child(tabs)

    tabs.add_child(_build_account_tab())
    tabs.add_child(_build_system_tab())
    tabs.add_child(_build_about_tab())

# 构建账号页.
# 这里是当前登录入口: 点击登录时创建运行期内存记录, 再通知主场景显示游戏页.
func _build_account_tab() -> Control:
    var tab := MarginContainer.new()
    tab.name = "账号"
    tab.add_theme_constant_override("margin_left", 8)
    tab.add_theme_constant_override("margin_top", 12)
    tab.add_theme_constant_override("margin_right", 8)
    tab.add_theme_constant_override("margin_bottom", 8)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", CONTENT_SPACING)
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tab.add_child(vbox)

    status_label = Label.new()
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vbox.add_child(status_label)

    var button_row := HBoxContainer.new()
    button_row.add_theme_constant_override("separation", 8)
    vbox.add_child(button_row)

    login_button = Button.new()
    login_button.text = "登录"
    login_button.pressed.connect(_on_login_pressed)
    button_row.add_child(login_button)

    return tab

# 构建系统页.
# 当前只放调试红边开关, 后续系统级运行期设置可以继续放在这里.
func _build_system_tab() -> Control:
    var tab := MarginContainer.new()
    tab.name = "系统"
    tab.add_theme_constant_override("margin_left", 8)
    tab.add_theme_constant_override("margin_top", 12)
    tab.add_theme_constant_override("margin_right", 8)
    tab.add_theme_constant_override("margin_bottom", 8)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", CONTENT_SPACING)
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tab.add_child(vbox)

    debug_border_check = CheckBox.new()
    debug_border_check.text = "显示调试边框"
    debug_border_check.button_pressed = GTrayConfig.get_window_debug_border_enabled()
    debug_border_check.toggled.connect(_on_debug_border_toggled)
    vbox.add_child(debug_border_check)

    return tab

# 构建关于页.
# 项目名从 ProjectSettings 读取, 这样跟 project.godot 中的应用名保持一致.
func _build_about_tab() -> Control:
    var tab := MarginContainer.new()
    tab.name = "关于"
    tab.add_theme_constant_override("margin_left", 8)
    tab.add_theme_constant_override("margin_top", 12)
    tab.add_theme_constant_override("margin_right", 8)
    tab.add_theme_constant_override("margin_bottom", 8)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", CONTENT_SPACING)
    tab.add_child(vbox)

    var title_label := Label.new()
    title_label.text = str(ProjectSettings.get_setting("application/config/name", "sa.desktop"))
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title_label)

    var description_label := Label.new()
    description_label.text = "Godot 桌面宠物客户端"
    description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vbox.add_child(description_label)

    return tab

# 登录按钮当前只做本地测试登录.
# 它不会调用后端接口; 点击时只创建一份可进入游戏的内存 AccountRecord.
func _on_login_pressed() -> void:
    GRecord.create_record()
    _set_status("登录成功.")
    account_login_completed.emit()

# 系统页勾选状态变化时直接改 tray.yaml, 并通知主场景重绘.
func _on_debug_border_toggled(pressed: bool) -> void:
    if GTrayConfig.set_window_debug_border_enabled(pressed):
        debug_border_changed.emit(pressed)
    else:
        debug_border_check.set_pressed_no_signal(GTrayConfig.get_window_debug_border_enabled())

# 刷新账号页提示文案.
# 打开选项窗口不会创建记录, 内存记录只在点击登录时创建.
func _sync_account_ui() -> void:
    if status_label == null:
        return

    _set_status("点击登录创建本次运行记录.")

# 根据 tray.yaml 刷新系统页勾选状态.
func _sync_system_ui() -> void:
    if debug_border_check == null:
        return

    debug_border_check.set_pressed_no_signal(GTrayConfig.get_window_debug_border_enabled())

# 统一更新状态标签, 避免调用方直接操作 status_label.
func _set_status(text: String) -> void:
    if status_label != null:
        status_label.text = text

# close_requested 信号会调用这里, 只隐藏窗口, 不销毁节点.
func _hide_dialog() -> void:
    if dialog_window != null:
        dialog_window.hide()

# 根据屏幕可用区域计算选项窗口居中位置.
func _centered_position(size: Vector2i, screen: int) -> Vector2i:
    var screen_position := DisplayServer.screen_get_position(screen)
    var screen_size := DisplayServer.screen_get_size(screen)
    return screen_position + Vector2i(
        int((screen_size.x - size.x) * 0.5),
        int((screen_size.y - size.y) * 0.5)
    )
