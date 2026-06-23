class_name SettingDialogController
extends Node

# 设置窗口是托盘 `设置...` 打开的独立 native Window.
# 当前第一版按参考图复刻一个复古辅助面板: 缩放, 透明, `隐藏石器` 和 `鼠标穿透` 会控制主窗口行为,
# 其他控件只保存本地 UI 状态到 tray.yaml, 不启动真实业务场景, 不调用外部自动化.
# 继续使用独立 Window, 是为了让该普通不透明工具面板不受桌宠主窗口透明度, 缩放和鼠标穿透影响.
const DIALOG_SIZE := Vector2i(452, 720)
const DIALOG_MARGIN := 2
const LEFT_COLUMN_WIDTH := 220
const RIGHT_COLUMN_WIDTH := 216
const COLUMN_SPACING := 4
const GROUP_SPACING := 2
const ROW_SPACING := 2
const UI_FONT_SIZE := 14
const COMPACT_FONT_SIZE := 12
const CONTROL_HEIGHT := 18
const BLANK_ROW_HEIGHT := 12
const WINDOW_SLIDER_LABEL_WIDTH := 34.0
const WINDOW_SLIDER_VALUE_WIDTH := 42.0
const WINDOW_SLIDER_WIDTH := 118.0
const PANEL_COLOR := Color(0.86, 0.86, 0.86, 1.0)
const GROUP_COLOR := Color(0.91, 0.91, 0.91, 1.0)
const INPUT_COLOR := Color(0.98, 0.98, 0.98, 1.0)
const INPUT_PRESSED_COLOR := Color(0.84, 0.84, 0.84, 1.0)
const BORDER_COLOR := Color(0.56, 0.56, 0.56, 1.0)
const TEXT_COLOR := Color(0.0, 0.0, 0.0, 1.0)

const MODE_TABS := ["主控", "战况", "脚本"]
const SWITCH_PET_OPTIONS := ["1:无"]

var dialog_window: Window
var state: Dictionary = {}
var window_controller: WindowController
var native_window_helper := WindowsClickThroughHelper.new()

# 初始化时创建窗口和控件树.
# 之后重复打开只同步配置状态并 show, 不在托盘点击路径里重新构建整棵 UI.
func initialize(controller: WindowController) -> void:
    window_controller = controller
    _build_dialog()

# 显示复古设置辅助面板.
# 每次显示前都重新读取 tray.yaml, 让用户手工改配置或旧配置补段后能立即反映到 UI.
func show_dialog() -> void:
    if dialog_window == null:
        _build_dialog()

    _reload_dialog_content()
    var screen := DisplayServer.window_get_current_screen()
    dialog_window.current_screen = screen
    dialog_window.position = _centered_position(DIALOG_SIZE, screen)
    dialog_window.size = DIALOG_SIZE
    dialog_window.min_size = DIALOG_SIZE
    dialog_window.max_size = DIALOG_SIZE
    dialog_window.mode = Window.MODE_WINDOWED
    dialog_window.show()
    set_process(true)
    _schedule_native_window_constraints()
    dialog_window.grab_focus()

# 创建 native 窗口外壳.
# Window.force_native=true 让它成为真实系统窗口, 不继承桌宠主窗口的点击穿透和透明外壳行为.
func _build_dialog() -> void:
    if dialog_window != null:
        return

    state = GTrayConfig.get_setting_state()

    dialog_window = Window.new()
    dialog_window.name = "SettingDialogWindow"
    dialog_window.title = "设置"
    dialog_window.visible = false
    dialog_window.force_native = true
    dialog_window.transparent = false
    dialog_window.transparent_bg = false
    dialog_window.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
    dialog_window.size = DIALOG_SIZE
    dialog_window.min_size = DIALOG_SIZE
    dialog_window.max_size = DIALOG_SIZE
    dialog_window.always_on_top = true
    dialog_window.unresizable = true
    dialog_window.close_requested.connect(_hide_dialog)
    add_child(dialog_window)

    _rebuild_content()

func _process(_delta: float) -> void:
    _enforce_fixed_window_size()

func _enforce_fixed_window_size() -> void:
    if dialog_window == null or not dialog_window.visible:
        return

    dialog_window.min_size = DIALOG_SIZE
    dialog_window.max_size = DIALOG_SIZE
    if dialog_window.mode == Window.MODE_MINIMIZED:
        return

    var is_maximized_mode := dialog_window.mode == Window.MODE_MAXIMIZED
    var is_fullscreen_mode := dialog_window.mode == Window.MODE_FULLSCREEN or dialog_window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
    if is_maximized_mode or is_fullscreen_mode:
        dialog_window.mode = Window.MODE_WINDOWED

    if dialog_window.size != DIALOG_SIZE:
        dialog_window.size = DIALOG_SIZE

func _apply_native_window_flags() -> void:
    if dialog_window == null:
        return

    DisplayServer.window_set_flag(
        DisplayServer.WINDOW_FLAG_RESIZE_DISABLED,
        true,
        dialog_window.get_window_id()
    )

# Window 节点加入树后不会立刻拥有 Windows HWND.
# 标题栏样式必须等 show() 之后再延后一帧应用, 否则 DisplayServer 会找不到 p_window.
func _schedule_native_window_constraints() -> void:
    call_deferred("_apply_native_window_constraints_after_show")

func _apply_native_window_constraints_after_show() -> void:
    await get_tree().process_frame
    if dialog_window == null or not dialog_window.visible:
        return

    _apply_native_window_flags()
    _disable_native_maximize()
    _enforce_fixed_window_size()

func _disable_native_maximize() -> void:
    if dialog_window == null or OS.get_name() != "Windows":
        return

    native_window_helper.set_maximize_enabled(dialog_window.get_window_id(), false)

# 重新读取配置并重建内容树.
# 当前控件数量较多, 但窗口尺寸很小; 重新构建比维护一大批控件引用更直接, 也能避免旧 signal 状态残留.
func _reload_dialog_content() -> void:
    state = GTrayConfig.get_setting_state()
    _clear_window_content()
    _rebuild_content()

func _clear_window_content() -> void:
    if dialog_window == null:
        return

    for child in dialog_window.get_children():
        dialog_window.remove_child(child)
        child.free()

func _rebuild_content() -> void:
    var root_panel := PanelContainer.new()
    _apply_panel_style(root_panel, PANEL_COLOR)
    root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dialog_window.add_child(root_panel)

    var root_margin := MarginContainer.new()
    root_margin.add_theme_constant_override("margin_left", DIALOG_MARGIN)
    root_margin.add_theme_constant_override("margin_top", DIALOG_MARGIN)
    root_margin.add_theme_constant_override("margin_right", DIALOG_MARGIN)
    root_margin.add_theme_constant_override("margin_bottom", DIALOG_MARGIN)
    root_panel.add_child(root_margin)

    root_margin.add_child(_build_mode_tabs())

func _build_mode_tabs() -> TabContainer:
    var tabs := TabContainer.new()
    tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var current_mode := _normalized_mode()
    var main_page := _build_main_tab_page()
    main_page.name = "主控"
    tabs.add_child(main_page)
    for tab_name in ["战况", "脚本"]:
        var blank_page := Control.new()
        blank_page.name = tab_name
        blank_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        blank_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
        tabs.add_child(blank_page)

    var tab_index := MODE_TABS.find(current_mode)
    if tab_index >= 0:
        tabs.current_tab = tab_index
    tabs.tab_changed.connect(_on_tab_changed)
    return tabs

func _build_main_tab_page() -> Control:
    var body := HBoxContainer.new()
    body.add_theme_constant_override("separation", COLUMN_SPACING)
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL

    body.add_child(_build_left_column())
    body.add_child(_build_right_column())
    return body

func _normalized_mode() -> String:
    var current_mode := str(state.get("mode", "主控"))
    if current_mode.is_empty() or not MODE_TABS.has(current_mode):
        current_mode = "主控"
        state["mode"] = current_mode
        _save_state()
    return current_mode

func _build_left_column() -> Control:
    var column := VBoxContainer.new()
    column.custom_minimum_size = Vector2(LEFT_COLUMN_WIDTH, 0.0)
    column.add_theme_constant_override("separation", GROUP_SPACING)
    column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    column.size_flags_vertical = Control.SIZE_EXPAND_FILL

    column.add_child(_build_login_group())
    column.add_child(_blank_area(132.0))
    column.add_child(_blank_area(146.0))
    column.add_child(_build_guess_group())
    return column

func _build_right_column() -> Control:
    var column := VBoxContainer.new()
    column.custom_minimum_size = Vector2(RIGHT_COLUMN_WIDTH, 0.0)
    column.add_theme_constant_override("separation", GROUP_SPACING)
    column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    column.size_flags_vertical = Control.SIZE_EXPAND_FILL

    column.add_child(_blank_row())
    column.add_child(_build_general_group())
    column.add_child(_build_combat_group())
    column.add_child(_build_status_group())
    column.add_child(_build_bottom_group())
    column.add_child(_build_link_grid())
    return column

func _build_login_group() -> Control:
    var box := _create_group("登陆")
    box.add_child(_row([
        _check("自动登入", "login", "auto_login"),
        _check("屏蔽声音", "login", "mute_sound"),
    ]))
    box.add_child(_row([
        _check("隐藏石器", "login", "hide_stoneage"),
        _check("鼠标穿透", "login", "click_through"),
    ]))
    box.add_child(_scale_slider_row())
    box.add_child(_opacity_slider_row())
    box.add_child(_blank_row())
    box.add_child(_row([
        _blank_control(100.0),
        _blank_control(100.0),
    ]))
    box.add_child(_row([
        _blank_control(100.0),
        _blank_control(100.0),
    ]))
    box.add_child(_row([
        _blank_control(100.0),
        _blank_control(100.0),
    ]))
    box.add_child(_row([
        _blank_control(100.0),
        _blank_control(100.0),
    ]))

    box.add_child(_blank_row())
    return _group_panel(box)

func _build_guess_group() -> Control:
    var box := _create_group("")
    box.add_child(_blank_row())
    box.add_child(_blank_row())
    box.add_child(_blank_row())
    return _group_panel(box)

func _build_general_group() -> Control:
    var box := _create_group("一般设定")
    box.add_child(_row([
        _blank_control(100.0),
        _blank_control(100.0),
    ]))

    box.add_child(_blank_row())
    box.add_child(_blank_row())

    box.add_child(_row([
        _blank_control(100.0),
        _check("来信显示", "general", "show_floor", 92.0),
    ]))
    box.add_child(_row([
        _blank_control(100.0),
        _blank_control(100.0),
    ]))
    return _group_panel(box)

func _build_combat_group() -> Control:
    var box := _create_group("战斗设定")
    box.add_child(_row([
        _check("自动战斗", "combat", "auto_combat", 94.0),
        _check("快速战斗", "combat", "quick_combat", 94.0),
    ]))
    box.add_child(_row([
        _check("自动遇敌", "combat", "auto_encounter", 94.0),
        _blank_control(100.0),
    ]))
    box.add_child(_row([
        _blank_control(100.0),
        _check("详细资料", "combat", "detail_info", 94.0),
    ]))
    box.add_child(_row([
        _check("自动捉宠", "combat", "auto_capture", 94.0),
        _check("落马逃跑", "combat", "escape_on_encounter", 94.0),
    ]))
    box.add_child(_row([
        _check("自动逃跑", "combat", "auto_escape", 94.0),
        _check("锁定宠物", "combat", "lock_pet", 94.0),
    ]))
    box.add_child(_row([
        _check("指定攻击", "combat", "specified_attack", 94.0),
        _check("指定逃跑", "combat", "specified_escape", 94.0),
    ]))
    box.add_child(_labeled_option_row("换战宠", SWITCH_PET_OPTIONS, "combat", "switch_pet", 110.0))
    box.add_child(_row([
        _check("原地锁定", "combat", "ground_lock", 94.0),
        _check("显示经验", "combat", "show_exp", 94.0),
    ]))
    return _group_panel(box)

func _build_status_group() -> Control:
    var box := _create_group("状态")
    box.add_child(_blank_row())
    box.add_child(_labeled_line_edit_row("当前坐标:", "status", "current_coord", 126.0))
    box.add_child(_blank_row())
    box.add_child(_labeled_line_edit_row("身上现金:", "status", "cash", 126.0))
    box.add_child(_labeled_line_edit_row("游戏时间:", "status", "game_time", 126.0))
    return _group_panel(box)

func _build_bottom_group() -> Control:
    var box := _create_group("")
    box.add_child(_row([
        _check("组队", "bottom", "team", 50.0),
        _check("决斗", "bottom", "duel", 50.0),
        _blank_control(34.0),
        _blank_control(34.0),
    ]))
    box.add_child(_row([
        _check("交易", "bottom", "trade", 50.0),
        _check("名片", "bottom", "card", 50.0),
        _blank_control(76.0),
    ]))
    return _group_panel(box)

func _build_link_grid() -> Control:
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 30)
    grid.add_theme_constant_override("v_separation", 2)
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for text in ["资料显示", "战斗设置", "情报显示", "脚本制作", "地图显示", "行者在线"]:
        grid.add_child(_label(text))
    return grid

# 创建复古分组面板.
# 标题放在面板内部的紧凑 header 行, 让分组仍由 Godot Container 正常计算尺寸, 避免手工覆盖标题导致控件重叠.
func _create_group(title: String, header_controls: Array = []) -> VBoxContainer:
    var panel := PanelContainer.new()
    _apply_panel_style(panel, GROUP_COLOR)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 4)
    margin.add_theme_constant_override("margin_top", 1)
    margin.add_theme_constant_override("margin_right", 4)
    margin.add_theme_constant_override("margin_bottom", 2)
    panel.add_child(margin)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 0)
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.add_child(box)

    if not title.is_empty() or not header_controls.is_empty():
        var header := HBoxContainer.new()
        header.add_theme_constant_override("separation", ROW_SPACING)
        header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        if not title.is_empty():
            var title_label := _label(title)
            title_label.custom_minimum_size = Vector2(0.0, CONTROL_HEIGHT - 4.0)
            header.add_child(title_label)
        var title_line := HSeparator.new()
        title_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        header.add_child(title_line)
        for control in header_controls:
            header.add_child(control)
        box.add_child(header)

    return box

# _create_group() 返回内部 VBoxContainer 供调用方继续添加控件.
# 真正应该加入列布局的是最外层 PanelContainer, 否则面板背景和边框会留在原父节点上, 内容会显示为空.
func _group_panel(box: VBoxContainer) -> Control:
    var margin := box.get_parent()
    assert(margin != null, "设置窗口分组缺少 MarginContainer.")
    var panel := margin.get_parent()
    assert(panel is Control, "设置窗口分组缺少外层面板.")
    return panel as Control

func _row(children: Array) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", ROW_SPACING)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for child in children:
        row.add_child(child)
    return row

func _labeled_option_row(label_text: String, options: Array, section: String, key: String, width: float) -> Control:
    var label := _label(label_text)
    label.custom_minimum_size = Vector2(48.0, CONTROL_HEIGHT)

    var option := OptionButton.new()
    option.custom_minimum_size = Vector2(width, CONTROL_HEIGHT)
    option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _apply_text_theme(option)
    _apply_button_box_theme(option)
    for item_text in options:
        option.add_item(item_text)
    _select_option(option, _section_string(section, key))
    option.item_selected.connect(_on_option_selected.bind(option, section, key))
    return _row([label, option])

func _labeled_line_edit_row(label_text: String, section: String, key: String, width: float) -> Control:
    var label := _label(label_text)
    label.custom_minimum_size = Vector2(72.0, CONTROL_HEIGHT)

    var edit := LineEdit.new()
    edit.text = _section_string(section, key)
    edit.custom_minimum_size = Vector2(width, CONTROL_HEIGHT)
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    edit.add_theme_font_size_override("font_size", UI_FONT_SIZE)
    edit.add_theme_color_override("font_color", TEXT_COLOR)
    edit.add_theme_color_override("font_uneditable_color", TEXT_COLOR)
    edit.add_theme_color_override("font_placeholder_color", TEXT_COLOR)
    edit.add_theme_color_override("font_outline_color", TEXT_COLOR)
    _apply_line_edit_theme(edit)
    edit.text_changed.connect(_on_line_text_changed.bind(section, key))
    return _row([label, edit])

func _scale_slider_row() -> Control:
    var current_scale := _section_float("window", "scale")

    var title := _label("缩放")
    title.custom_minimum_size = Vector2(WINDOW_SLIDER_LABEL_WIDTH, CONTROL_HEIGHT)

    var value_label := _label(_label_for_percent(current_scale))
    value_label.custom_minimum_size = Vector2(WINDOW_SLIDER_VALUE_WIDTH, CONTROL_HEIGHT)

    var slider := HSlider.new()
    slider.min_value = Constants.WINDOW_MIN_SCALE * 100.0
    slider.max_value = Constants.WINDOW_MAX_SCALE * 100.0
    slider.step = 1.0
    slider.value = round(current_scale * 100.0)
    slider.custom_minimum_size = Vector2(WINDOW_SLIDER_WIDTH, CONTROL_HEIGHT)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(_on_scale_slider_value_changed.bind(value_label))
    return _row([title, value_label, slider])

func _opacity_slider_row() -> Control:
    var current_opacity := _section_float("window", "opacity")

    var title := _label("透明")
    title.custom_minimum_size = Vector2(WINDOW_SLIDER_LABEL_WIDTH, CONTROL_HEIGHT)

    var value_label := _label(_label_for_percent(current_opacity))
    value_label.custom_minimum_size = Vector2(WINDOW_SLIDER_VALUE_WIDTH, CONTROL_HEIGHT)

    var slider := HSlider.new()
    slider.min_value = Constants.WINDOW_MIN_OPACITY * 100.0
    slider.max_value = Constants.WINDOW_MAX_OPACITY * 100.0
    slider.step = 1.0
    slider.value = round(current_opacity * 100.0)
    slider.custom_minimum_size = Vector2(WINDOW_SLIDER_WIDTH, CONTROL_HEIGHT)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(_on_opacity_slider_value_changed.bind(value_label))
    return _row([title, value_label, slider])

func _check(label_text: String, section: String, key: String, width: float = 100.0) -> CheckBox:
    var check := CheckBox.new()
    check.text = label_text
    check.focus_mode = Control.FOCUS_NONE
    check.custom_minimum_size = Vector2(width, CONTROL_HEIGHT)
    check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    check.set_pressed_no_signal(_section_bool(section, key))
    _apply_text_theme(check)
    _apply_check_box_theme(check)
    check.toggled.connect(_on_check_toggled.bind(section, key))
    return check

func _blank_control(width: float) -> Control:
    var blank := Control.new()
    blank.custom_minimum_size = Vector2(width, CONTROL_HEIGHT)
    blank.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    return blank

func _blank_row() -> Control:
    var blank := Control.new()
    blank.custom_minimum_size = Vector2(0.0, BLANK_ROW_HEIGHT)
    blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return blank

func _blank_area(height: float) -> Control:
    var blank := Control.new()
    blank.custom_minimum_size = Vector2(0.0, height)
    blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return blank

func _label(label_text: String, font_size: int = UI_FONT_SIZE) -> Label:
    var label := Label.new()
    label.text = label_text
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", TEXT_COLOR)
    label.add_theme_color_override("font_outline_color", TEXT_COLOR)
    return label

func _apply_panel_style(panel: PanelContainer, color: Color) -> void:
    panel.add_theme_stylebox_override("panel", _flat_box(color, BORDER_COLOR))

func _apply_line_edit_theme(edit: LineEdit) -> void:
    edit.add_theme_stylebox_override("normal", _flat_box(INPUT_COLOR, BORDER_COLOR, 2.0, 1.0))
    edit.add_theme_stylebox_override("focus", _flat_box(INPUT_COLOR, BORDER_COLOR, 2.0, 1.0))
    edit.add_theme_stylebox_override("read_only", _flat_box(INPUT_COLOR, BORDER_COLOR, 2.0, 1.0))

func _apply_button_box_theme(button: BaseButton) -> void:
    button.add_theme_stylebox_override("normal", _flat_box(INPUT_COLOR, BORDER_COLOR, 2.0, 1.0))
    button.add_theme_stylebox_override("hover", _flat_box(INPUT_COLOR, BORDER_COLOR, 2.0, 1.0))
    button.add_theme_stylebox_override("pressed", _flat_box(INPUT_PRESSED_COLOR, BORDER_COLOR, 2.0, 1.0))
    button.add_theme_stylebox_override("focus", _flat_box(INPUT_COLOR, BORDER_COLOR, 2.0, 1.0))
    button.add_theme_stylebox_override("disabled", _flat_box(INPUT_COLOR, BORDER_COLOR, 2.0, 1.0))

func _apply_check_box_theme(button: BaseButton) -> void:
    var transparent_style := _transparent_box()
    button.add_theme_stylebox_override("normal", transparent_style)
    button.add_theme_stylebox_override("hover", transparent_style)
    button.add_theme_stylebox_override("pressed", transparent_style)
    button.add_theme_stylebox_override("focus", transparent_style)
    button.add_theme_stylebox_override("disabled", transparent_style)

func _flat_box(color: Color, border_color: Color, horizontal_margin: float = 0.0, vertical_margin: float = 0.0) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border_color
    style.set_border_width_all(1)
    style.content_margin_left = horizontal_margin
    style.content_margin_top = vertical_margin
    style.content_margin_right = horizontal_margin
    style.content_margin_bottom = vertical_margin
    return style

func _transparent_box() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
    style.border_color = Color(0.0, 0.0, 0.0, 0.0)
    style.set_border_width_all(0)
    style.content_margin_left = 0.0
    style.content_margin_top = 0.0
    style.content_margin_right = 0.0
    style.content_margin_bottom = 0.0
    return style

func _apply_text_theme(control: Control) -> void:
    control.add_theme_font_size_override("font_size", UI_FONT_SIZE)
    control.add_theme_color_override("font_color", TEXT_COLOR)
    control.add_theme_color_override("font_hover_color", TEXT_COLOR)
    control.add_theme_color_override("font_pressed_color", TEXT_COLOR)
    control.add_theme_color_override("font_focus_color", TEXT_COLOR)
    control.add_theme_color_override("font_hover_pressed_color", TEXT_COLOR)
    control.add_theme_color_override("font_disabled_color", TEXT_COLOR)
    control.add_theme_color_override("font_selected_color", TEXT_COLOR)
    control.add_theme_color_override("font_outline_color", TEXT_COLOR)
    control.add_theme_color_override("font_uneditable_color", TEXT_COLOR)
    control.add_theme_color_override("font_placeholder_color", TEXT_COLOR)

func _select_option(option: OptionButton, selected_text: String) -> void:
    for index in range(option.get_item_count()):
        if option.get_item_text(index) == selected_text:
            option.select(index)
            return

    if option.get_item_count() > 0:
        option.select(0)

func _on_tab_changed(tab_index: int) -> void:
    if tab_index < 0 or tab_index >= MODE_TABS.size():
        return

    state["mode"] = MODE_TABS[tab_index]
    _save_state()

func _on_check_toggled(pressed: bool, section: String, key: String) -> void:
    var section_data := _section(section)
    section_data[key] = pressed
    state[section] = section_data
    if not _save_state():
        return

    if section == "login" and key == "hide_stoneage":
        _apply_hide_stoneage(pressed)
    elif section == "login" and key == "click_through":
        _apply_click_through(pressed)

func _on_option_selected(index: int, option: OptionButton, section: String, key: String) -> void:
    var section_data := _section(section)
    section_data[key] = option.get_item_text(index)
    state[section] = section_data
    _save_state()

func _on_line_text_changed(text: String, section: String, key: String) -> void:
    var section_data := _section(section)
    section_data[key] = text
    state[section] = section_data
    _save_state()

func _on_scale_slider_value_changed(percent: float, label: Label) -> void:
    var value := clampf(percent / 100.0, Constants.WINDOW_MIN_SCALE, Constants.WINDOW_MAX_SCALE)
    if label != null:
        label.text = _label_for_percent(value)

    var window_state := _section("window")
    window_state["scale"] = value
    state["window"] = window_state
    if not _save_state():
        return

    _apply_scale(value)

func _on_opacity_slider_value_changed(percent: float, label: Label) -> void:
    var value := clampf(percent / 100.0, Constants.WINDOW_MIN_OPACITY, Constants.WINDOW_MAX_OPACITY)
    if label != null:
        label.text = _label_for_percent(value)

    var window_state := _section("window")
    window_state["opacity"] = value
    state["window"] = window_state
    if not _save_state():
        return

    _apply_opacity(value)

func _save_state() -> bool:
    assert(GTrayConfig.set_setting_state(state), "保存设置窗口配置失败, 请检查 tray.yaml.")
    return true

# 缩放会改变真实 OS 窗口尺寸.
# 配置写回成功后再操作真实窗口, 避免窗口已经缩放但 tray.yaml 没有记录成功.
func _apply_scale(value: float) -> void:
    assert(window_controller != null and is_instance_valid(window_controller), "设置窗口缺少有效 WindowController, 无法控制主窗口缩放.")

    if _section_bool("login", "hide_stoneage"):
        return

    window_controller.set_scale(value)
    assert(GTrayConfig.set_window_position(DisplayServer.window_get_position()), "保存窗口缩放后位置失败, 请检查 tray.yaml.")

# 透明度只影响 ContentRoot 内容, 不改变主窗口透明外壳和调试红边.
# 配置写回成功后再操作真实窗口内容, 避免界面已变化但 tray.yaml 没有记录成功.
func _apply_opacity(value: float) -> void:
    assert(window_controller != null and is_instance_valid(window_controller), "设置窗口缺少有效 WindowController, 无法控制主窗口透明度.")

    if _section_bool("login", "hide_stoneage"):
        return

    window_controller.set_opacity(value)

# `隐藏石器` 会产生主窗口显隐副作用.
# 配置写回成功后再操作真实窗口, 避免窗口状态已经变化但 tray.yaml 没有记录成功.
func _apply_hide_stoneage(should_hide: bool) -> void:
    assert(window_controller != null and is_instance_valid(window_controller), "设置窗口缺少有效 WindowController, 无法控制主窗口显隐.")

    if should_hide:
        window_controller.hide_window()
        return

    window_controller.show_window()
    window_controller.set_scale(GTrayConfig.get_window_scale())
    window_controller.set_opacity(GTrayConfig.get_window_opacity())
    window_controller.set_click_through(GTrayConfig.get_window_click_through())

# `鼠标穿透` 写入 setting.login.click_through 后才应用到真实窗口.
# 如果主窗口已经被隐藏, 运行时会保持临时穿透; 取消隐藏时再恢复用户配置状态.
func _apply_click_through(enabled: bool) -> void:
    assert(window_controller != null and is_instance_valid(window_controller), "设置窗口缺少有效 WindowController, 无法控制鼠标穿透.")

    if _section_bool("login", "hide_stoneage"):
        return

    window_controller.set_click_through(enabled)

func _section(section: String) -> Dictionary:
    assert(state.get(section) is Dictionary, "设置窗口状态缺少分组: %s" % section)
    return state[section] as Dictionary

func _section_string(section: String, key: String) -> String:
    var section_data := _section(section)
    return str(section_data[key])

func _section_bool(section: String, key: String) -> bool:
    var section_data := _section(section)
    return bool(section_data[key])

func _section_float(section: String, key: String) -> float:
    var section_data := _section(section)
    return float(section_data[key])

# 把 0.1-1.0 的数值转成百分比文案, 设置窗口的缩放和透明滑条保持同一显示方式.
func _label_for_percent(value: float) -> String:
    return "%d%%" % int(round(value * 100.0))

# close_requested 信号会调用这里, 只隐藏窗口, 不销毁节点.
func _hide_dialog() -> void:
    if dialog_window != null:
        dialog_window.hide()
    set_process(false)

# 根据屏幕可用区域计算设置窗口居中位置.
func _centered_position(size: Vector2i, screen: int) -> Vector2i:
    var screen_position := DisplayServer.screen_get_position(screen)
    var screen_size := DisplayServer.screen_get_size(screen)
    return screen_position + Vector2i(
        int((screen_size.x - size.x) * 0.5),
        int((screen_size.y - size.y) * 0.5)
    )
