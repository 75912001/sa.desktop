class_name TrayConfig
extends Node

# 托盘配置 helper.
# 该节点由 GTray 在运行期创建, 只负责 `tray.yaml` 的初始化, 读取, 校验, 归一化和写回.
# 真实托盘 UI, 菜单窗口和选项窗口都由 TrayController 负责, 这里不创建任何 Control 或 Window,
# 也不直接调用 DisplayServer, 避免配置层和窗口副作用耦合.

# 解析后的配置缓存.
# data 保存已经完成必填校验和归一化的运行期结构:
# - data["window"] 是运行期窗口状态, 位置和调试边框修改后会同步写回 `tray.yaml`.
# - data["menu"] 是托盘菜单样式, 读取时会把颜色字符串转换成 Color, 写回时再转回 HTML 字符串.
# - data["setting"] 是托盘设置窗口的 UI 状态; setting.window.scale, setting.window.opacity,
#   login.hide_stoneage 和 login.click_through 同时作为主窗口行为持久化开关.
# get/set 方法都通过 _ensure_config_loaded() 懒加载, 写回成功后继续复用这份缓存.
var data: Dictionary = {}

func _ready() -> void:
    pass

# 加载配置并校验必需字段.
# 如果运行期配置文件不存在, 先从模板复制生成一份完整配置.
# 这个函数不执行窗口副作用, 只做文件初始化, MiniYAML 读取, 必填校验和字段归一化.
func load_config() -> Dictionary:
    _ensure_config_file()

    # 项目已经通过 YAML Autoload 接入 MiniYAML, ConfigManager.load_yaml() 统一封装了解析错误和根节点类型校验.
    # tray 配置也走同一入口, 避免维护一套只覆盖部分 YAML 语法的手写解析器.
    data = ConfigManager.load_yaml(Constants.CONFIG_TRAY_PATH)

    # window 是主窗口状态契约. 这里按字段逐项取值, 缺失直接 assert,
    # 不使用代码默认坐标, 避免不同用户屏幕环境被固定值污染.
    var raw_window: Dictionary = Share._required_dictionary(data, "window", "window")
    var raw_position: Dictionary = Share._required_dictionary(raw_window, "position", "window.position")
    var position: Dictionary = {}
    position["x"] = Share._int_value(Share._required_value(raw_position, "x", "window.position.x"))
    position["y"] = Share._int_value(Share._required_value(raw_position, "y", "window.position.y"))

    var normalized_window: Dictionary = {}
    normalized_window["position"] = position
    normalized_window["debug_border"] = Share._bool_value(Share._required_value(raw_window, "debug_border", "window.debug_border"))
    data["window"] = normalized_window

    # menu 是托盘菜单样式契约. 这里只校验当前仍然生效的菜单样式字段.
    var menu: Dictionary = Share._required_dictionary(data, "menu", "menu")
    menu["font_size"] = clampi(Share._int_value(Share._required_value(menu, "font_size", "menu.font_size")), Constants.TRAY_MENU_MIN_FONT_SIZE, Constants.TRAY_MENU_MAX_FONT_SIZE)

    # 颜色必须完整配置并能被 Godot Color.html() 解析.
    # 生成 Dictionary[String, Color] 后, TrayController 可以直接消费强类型 Color.
    var raw_colors = Share._required_value(menu, "colors", "menu.colors")
    assert(raw_colors is Dictionary, "托盘配置 colors 必须是字典.")
    var normalized_colors: Dictionary[String, Color] = {}
    var raw_color_data: Dictionary = raw_colors as Dictionary
    for color_key in Constants.TRAY_COLOR_KEYS:
        var raw_color = Share._required_value(raw_color_data, color_key, "menu.colors.%s" % color_key)
        if raw_color is Color:
            normalized_colors[color_key] = raw_color
            continue

        if raw_color is String:
            var color_text: String = raw_color.strip_edges()
            if Color.html_is_valid(color_text):
                normalized_colors[color_key] = Color.html(color_text)
                continue

        assert(false, "托盘配置颜色无效: %s" % color_key)
        normalized_colors[color_key] = Color(0.0, 0.0, 0.0, 0.0)
    menu["colors"] = normalized_colors
    data["menu"] = menu

    # setting 是复古设置面板的本地 UI 状态.
    # 它和 window/menu 共用同一个运行期配置文件, 但不参与真实业务场景或外部自动化.
    var setting := _normalize_setting_state(
        Share._required_dictionary(data, "setting", "setting")
    )
    data["setting"] = setting
    return data

# 读取主窗口位置.
# 返回的是屏幕坐标, 直接交给 WindowController/DisplayServer 使用.
func get_window_position() -> Vector2i:
    _ensure_config_loaded()
    var window := _data_window()
    var position := window["position"] as Dictionary
    return Vector2i(int(position["x"]), int(position["y"]))

# 修改主窗口位置并写回 tray.yaml.
# 拖拽结束, 缩放后位置修正和托盘操作都会调用这里.
func set_window_position(position: Vector2i) -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    var position_data: Dictionary = {}
    position_data["x"] = position.x
    position_data["y"] = position.y
    window["position"] = position_data
    data["window"] = window
    return _save_config()

# 读取主窗口缩放比例.
# 约定值域是 0.1 到 1.0, load_config() 中已经做过 clamp.
func get_window_scale() -> float:
    _ensure_config_loaded()
    var window_setting := _data_setting_window()
    return float(window_setting["scale"])

# 修改主窗口缩放比例并写回 tray.yaml.
# 缩放属于设置窗口状态, 但外部仍通过窗口语义 getter/setter 访问.
func set_window_scale(value: float) -> bool:
    _ensure_config_loaded()
    var setting := _data_setting()
    var window_setting := _data_setting_window()
    window_setting["scale"] = clampf(value, Constants.WINDOW_MIN_SCALE, Constants.WINDOW_MAX_SCALE)
    setting["window"] = window_setting
    data["setting"] = setting
    return _save_config()

# 读取内容透明度.
# 透明度只作用于 MainWindow/ContentRoot 当前业务页面, 不影响窗口外壳和调试红边.
func get_window_opacity() -> float:
    _ensure_config_loaded()
    var window_setting := _data_setting_window()
    return float(window_setting["opacity"])

# 修改内容透明度并写回 tray.yaml.
# 透明度属于设置窗口状态, 但外部仍通过窗口语义 getter/setter 访问.
func set_window_opacity(value: float) -> bool:
    _ensure_config_loaded()
    var setting := _data_setting()
    var window_setting := _data_setting_window()
    window_setting["opacity"] = clampf(value, Constants.WINDOW_MIN_OPACITY, Constants.WINDOW_MAX_OPACITY)
    setting["window"] = window_setting
    data["setting"] = setting
    return _save_config()

# 读取鼠标穿透状态.
# 该值表示用户期望的持久化状态, 不等同于隐藏窗口期间的临时穿透状态.
func get_window_click_through() -> bool:
    _ensure_config_loaded()
    var login := _data_setting_login()
    return bool(login["click_through"])

# 修改鼠标穿透状态并写回 tray.yaml.
# Windows 原生穿透是否真正应用由 WindowController/WindowsClickThroughHelper 负责,
# 配置层只记录设置窗口勾选状态, 便于重启后恢复.
func set_window_click_through(enabled: bool) -> bool:
    _ensure_config_loaded()
    var setting := _data_setting()
    var login := _data_setting_login()
    login["click_through"] = enabled
    setting["login"] = login
    data["setting"] = setting
    return _save_config()

# 读取菜单字体大小.
# 返回的是已经在 load_config() 中完成范围限制的字号.
func get_font_size() -> int:
    _ensure_config_loaded()
    var menu := _data_menu()
    return int(menu["font_size"])

# 读取菜单颜色字典.
# 返回强类型 Color 字典, TrayController 可以直接消费而无需再次解析 HTML 颜色字符串.
func get_colors() -> Dictionary[String, Color]:
    _ensure_config_loaded()
    var menu := _data_menu()
    return menu["colors"] as Dictionary[String, Color]

# 读取调试红边开关.
# 这是配置值, 用户在选项窗口中勾选后会直接写回 tray.yaml.
func get_window_debug_border_enabled() -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    return bool(window["debug_border"])

# 修改调试红边配置并写回 tray.yaml.
# 调试边框属于 window 运行期状态, 因此仍然通过统一整文件写回流程持久化.
func set_window_debug_border_enabled(enabled: bool) -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    window["debug_border"] = enabled
    data["window"] = window
    return _save_config()

# 读取设置窗口本地 UI 状态.
# 返回深拷贝, 避免调用方直接修改缓存后绕过 set_setting_state() 的结构校验和写回流程.
func get_setting_state() -> Dictionary:
    _ensure_config_loaded()
    return _data_setting().duplicate(true)

# 修改设置窗口本地 UI 状态并立即写回 tray.yaml.
# 调用方需要传入完整 setting 字典; 缺字段或类型错误会 assert, 避免半截状态被写入后下次启动难以定位.
func set_setting_state(state: Dictionary) -> bool:
    _ensure_config_loaded()
    data["setting"] = _normalize_setting_state(state)
    return _save_config()

# 确保本地运行期托盘配置存在且结构完整.
# `tray.yaml` 是会被整体写回的本地文件, 用户中断写入或手工编辑时可能留下半截配置;
# 这里在正式读取前先做轻量结构检查, 文件缺失或 window/menu 损坏时直接用模板重建.
# setting 只保存窗口 UI 状态, 字段会随界面删改变化; 旧结构会保留可识别字段并补齐当前默认字段.
func _ensure_config_file() -> void:
    assert(FileAccess.file_exists(Constants.CONFIG_TRAY_TEMPLATE_PATH), "托盘配置模板不存在: %s" % Constants.CONFIG_TRAY_TEMPLATE_PATH)

    var template_data = _load_config_file(Constants.CONFIG_TRAY_TEMPLATE_PATH)
    assert(_is_config_complete(template_data), "托盘配置模板不完整: %s" % Constants.CONFIG_TRAY_TEMPLATE_PATH)

    var should_copy := not FileAccess.file_exists(Constants.CONFIG_TRAY_PATH)
    if not should_copy:
        var existing_config_data = _load_config_file(Constants.CONFIG_TRAY_PATH)
        should_copy = not _is_core_config_complete(existing_config_data)
        if not should_copy:
            _ensure_setting_section(existing_config_data as Dictionary, template_data as Dictionary)

    if should_copy:
        _copy_config_template()

    var verified_config_data = _load_config_file(Constants.CONFIG_TRAY_PATH)
    assert(_is_config_complete(verified_config_data), "托盘配置文件不完整: %s" % Constants.CONFIG_TRAY_PATH)

# 读取 YAML 并返回根对象; 解析失败时返回 null, 交给调用方决定是重建还是 assert.
# 这里刻意不复用 ConfigManager.load_yaml(), 因为该入口会直接 assert, 不适合用于判断本地运行期文件是否需要从模板恢复.
func _load_config_file(path: String):
    if not FileAccess.file_exists(path):
        return null

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null

    var content := file.get_as_text()
    file.close()

    var result = YAML.parse(content)
    if result.has_error():
        return null

    var parsed_data = result.get_data()
    if parsed_data is Array and parsed_data.size() > 0:
        parsed_data = parsed_data[0]

    if not (parsed_data is Dictionary):
        return null

    return parsed_data as Dictionary

# 只检查当前代码需要消费的完整结构和字段是否存在.
# 字段类型, 数值范围和颜色字符串合法性仍由 load_config() 后续流程统一校验.
func _is_config_complete(config_data) -> bool:
    if not _is_core_config_complete(config_data):
        return false

    var root := config_data as Dictionary
    var setting_data = root.get("setting")
    if not (setting_data is Dictionary):
        return false

    return _setting_state_matches_default_shape(setting_data as Dictionary)

# 检查旧版和新版都必须具备的 window/menu 核心结构.
# 这个函数不检查 setting, 让升级旧配置时可以保留用户已有窗口状态并补入新段.
func _is_core_config_complete(config_data) -> bool:
    if not (config_data is Dictionary):
        return false

    var root := config_data as Dictionary
    var window_data = root.get("window")
    if not (window_data is Dictionary):
        return false

    var window := window_data as Dictionary
    var position_data = window.get("position")
    if not (position_data is Dictionary):
        return false

    var position := position_data as Dictionary
    for key in ["x", "y"]:
        if not position.has(key):
            return false

    for key in ["debug_border"]:
        if not window.has(key):
            return false

    var menu_data = root.get("menu")
    if not (menu_data is Dictionary):
        return false

    var menu := menu_data as Dictionary
    if not menu.has("font_size"):
        return false

    var colors_data = menu.get("colors")
    if not (colors_data is Dictionary):
        return false

    var colors := colors_data as Dictionary
    for color_key in Constants.TRAY_COLOR_KEYS:
        if not colors.has(color_key):
            return false

    return true

# 旧配置缺少或落后于当前 setting 结构时, 保留可识别字段并按模板默认值补齐后写回.
# 旧版 battle_dialog 和 setting.battle 只作为迁移输入存在; 写回后当前配置只保留 setting.combat.
# 分组类型明显错误时仍然 assert, 避免把手工写坏的配置静默覆盖成另一种含义.
func _ensure_setting_section(config_data: Dictionary, template_data: Dictionary) -> void:
    if config_data.has("setting"):
        assert(config_data["setting"] is Dictionary, "托盘配置 setting 必须是字典: %s" % Constants.CONFIG_TRAY_PATH)
        var setting_state := (config_data["setting"] as Dictionary).duplicate(true)
        var should_write := false
        if _apply_legacy_window_scale(config_data, setting_state):
            should_write = true
        if _apply_legacy_window_opacity(config_data, setting_state):
            should_write = true
        if _apply_legacy_window_click_through(config_data, setting_state):
            should_write = true
        if not _setting_state_matches_default_shape(setting_state):
            config_data["setting"] = _upgrade_setting_state(setting_state)
            should_write = true
        else:
            config_data["setting"] = _normalize_setting_state(setting_state)

        if config_data.has("battle_dialog"):
            config_data.erase("battle_dialog")
            should_write = true
        if _erase_legacy_window_scale(config_data):
            should_write = true
        if _erase_legacy_window_opacity(config_data):
            should_write = true
        if _erase_legacy_window_click_through(config_data):
            should_write = true

        if should_write:
            _write_raw_config(config_data)
        return

    if config_data.has("battle_dialog"):
        assert(config_data["battle_dialog"] is Dictionary, "托盘配置 battle_dialog 必须是字典: %s" % Constants.CONFIG_TRAY_PATH)
        var legacy_state := (config_data["battle_dialog"] as Dictionary).duplicate(true)
        _apply_legacy_window_scale(config_data, legacy_state)
        _apply_legacy_window_opacity(config_data, legacy_state)
        _apply_legacy_window_click_through(config_data, legacy_state)
        config_data["setting"] = _upgrade_setting_state(legacy_state)
        config_data.erase("battle_dialog")
        _erase_legacy_window_scale(config_data)
        _erase_legacy_window_opacity(config_data)
        _erase_legacy_window_click_through(config_data)
        _write_raw_config(config_data)
        return

    var setting_state := _template_setting_state(template_data)
    _apply_legacy_window_scale(config_data, setting_state, true)
    _apply_legacy_window_opacity(config_data, setting_state, true)
    _apply_legacy_window_click_through(config_data, setting_state, true)
    config_data["setting"] = setting_state
    _erase_legacy_window_scale(config_data)
    _erase_legacy_window_opacity(config_data)
    _erase_legacy_window_click_through(config_data)
    _write_raw_config(config_data)

# 旧版本把缩放保存在 window.scale.
# 新版本把它归入 setting.window.scale, 让设置窗口成为缩放控件和持久化状态的唯一入口.
func _apply_legacy_window_scale(config_data: Dictionary, setting_state: Dictionary, overwrite_existing: bool = false) -> bool:
    var legacy_value = _legacy_window_scale_value(config_data)
    if legacy_value == null:
        return false

    var window_setting_data = setting_state.get("window")
    if window_setting_data == null:
        window_setting_data = {}
        setting_state["window"] = window_setting_data
    assert(window_setting_data is Dictionary, "托盘配置 setting.window 必须是字典: %s" % Constants.CONFIG_TRAY_PATH)

    var window_setting := window_setting_data as Dictionary
    if window_setting.has("scale") and not overwrite_existing:
        return false

    window_setting["scale"] = clampf(Share._float_value(legacy_value), Constants.WINDOW_MIN_SCALE, Constants.WINDOW_MAX_SCALE)
    setting_state["window"] = window_setting
    return true

func _legacy_window_scale_value(config_data: Dictionary):
    var window_data = config_data.get("window")
    if not (window_data is Dictionary):
        return null

    var window := window_data as Dictionary
    if not window.has("scale"):
        return null

    return window["scale"]

func _erase_legacy_window_scale(config_data: Dictionary) -> bool:
    var window_data = config_data.get("window")
    if not (window_data is Dictionary):
        return false

    var window := window_data as Dictionary
    if not window.has("scale"):
        return false

    window.erase("scale")
    config_data["window"] = window
    return true

# 旧版本把透明度保存在 window.opacity.
# 新版本把它归入 setting.window.opacity, 让设置窗口成为透明度控件和持久化状态的唯一入口.
func _apply_legacy_window_opacity(config_data: Dictionary, setting_state: Dictionary, overwrite_existing: bool = false) -> bool:
    var legacy_value = _legacy_window_opacity_value(config_data)
    if legacy_value == null:
        return false

    var window_setting_data = setting_state.get("window")
    if window_setting_data == null:
        window_setting_data = {}
        setting_state["window"] = window_setting_data
    assert(window_setting_data is Dictionary, "托盘配置 setting.window 必须是字典: %s" % Constants.CONFIG_TRAY_PATH)

    var window_setting := window_setting_data as Dictionary
    if window_setting.has("opacity") and not overwrite_existing:
        return false

    window_setting["opacity"] = clampf(Share._float_value(legacy_value), Constants.WINDOW_MIN_OPACITY, Constants.WINDOW_MAX_OPACITY)
    setting_state["window"] = window_setting
    return true

func _legacy_window_opacity_value(config_data: Dictionary):
    var window_data = config_data.get("window")
    if not (window_data is Dictionary):
        return null

    var window := window_data as Dictionary
    if not window.has("opacity"):
        return null

    return window["opacity"]

func _erase_legacy_window_opacity(config_data: Dictionary) -> bool:
    var window_data = config_data.get("window")
    if not (window_data is Dictionary):
        return false

    var window := window_data as Dictionary
    if not window.has("opacity"):
        return false

    window.erase("opacity")
    config_data["window"] = window
    return true

# 旧版本把鼠标穿透保存在 window.click_through.
# 新版本把它归入 setting.login.click_through, 这样设置窗口可以直接持久化同一行 UI 状态.
func _apply_legacy_window_click_through(config_data: Dictionary, setting_state: Dictionary, overwrite_existing: bool = false) -> bool:
    var legacy_value = _legacy_window_click_through_value(config_data)
    if legacy_value == null:
        return false

    var login_data = setting_state.get("login")
    if login_data == null:
        login_data = {}
        setting_state["login"] = login_data
    assert(login_data is Dictionary, "托盘配置 setting.login 必须是字典: %s" % Constants.CONFIG_TRAY_PATH)

    var login := login_data as Dictionary
    if login.has("click_through") and not overwrite_existing:
        return false

    login["click_through"] = Share._bool_value(legacy_value)
    setting_state["login"] = login
    return true

func _legacy_window_click_through_value(config_data: Dictionary):
    var window_data = config_data.get("window")
    if not (window_data is Dictionary):
        return null

    var window := window_data as Dictionary
    if not window.has("click_through"):
        return null

    return window["click_through"]

func _erase_legacy_window_click_through(config_data: Dictionary) -> bool:
    var window_data = config_data.get("window")
    if not (window_data is Dictionary):
        return false

    var window := window_data as Dictionary
    if not window.has("click_through"):
        return false

    window.erase("click_through")
    config_data["window"] = window
    return true

# 从入库模板重建本地运行期配置.
# 复制失败直接 assert, 避免后续读取到旧的半截配置后继续产生误导性错误.
func _copy_config_template() -> void:
    var template_file := FileAccess.open(Constants.CONFIG_TRAY_TEMPLATE_PATH, FileAccess.READ)
    assert(template_file != null, "无法读取托盘配置模板: %s" % Constants.CONFIG_TRAY_TEMPLATE_PATH)

    var template_text := template_file.get_as_text()
    template_file.close()

    var config_file := FileAccess.open(Constants.CONFIG_TRAY_PATH, FileAccess.WRITE)
    assert(config_file != null, "无法创建托盘配置: %s" % Constants.CONFIG_TRAY_PATH)
    config_file.store_string(template_text)
    config_file.close()

# 读取 window 段时统一返回普通 Dictionary.
# 运行期 getter/setter 都走这里, 防止 data 被外部或后续改动破坏后继续静默运行.
func _data_window() -> Dictionary:
    assert(data.get("window") is Dictionary, "托盘配置 window 必须是字典.")
    return data["window"] as Dictionary

# 读取 menu 段时统一返回普通 Dictionary.
# 不直接把 `{}` 作为 `data.get()` 默认值, 避免 Godot 把空字典推断成 `Dictionary[String, Nil]`.
# menu 目前只有读取入口, 但仍然显式 assert, 保持配置契约和 window 一致.
func _data_menu() -> Dictionary:
    assert(data.get("menu") is Dictionary, "托盘配置 menu 必须是字典.")
    return data["menu"] as Dictionary

# 读取 setting 段时统一返回普通 Dictionary.
# 该段只表示复古设置窗口控件状态, 不参与 ConfigManager 的游戏配置生命周期.
func _data_setting() -> Dictionary:
    assert(data.get("setting") is Dictionary, "托盘配置 setting 必须是字典.")
    return data["setting"] as Dictionary

# 缩放和透明度现在归属于设置窗口 window 分组, 但外部仍通过窗口语义 getter/setter 访问.
func _data_setting_window() -> Dictionary:
    var setting := _data_setting()
    assert(setting.get("window") is Dictionary, "托盘配置 setting.window 必须是字典.")
    return setting["window"] as Dictionary

# 鼠标穿透现在归属于设置窗口登陆分组, 但外部仍通过窗口语义 getter/setter 访问.
func _data_setting_login() -> Dictionary:
    var setting := _data_setting()
    assert(setting.get("login") is Dictionary, "托盘配置 setting.login 必须是字典.")
    return setting["login"] as Dictionary

# 整体覆盖写回运行期 tray.yaml.
# 写回使用 MiniYAML dump, 因此不会保留运行期文件里的注释; 注释只维护在 tray.yaml.tpl.
# 写入前先把 Color 转回 HTML 字符串, 避免 MiniYAML 把 Godot Color 对象序列化成不适合手工维护的结构.
func _save_config() -> bool:
    var window := _data_window()
    var menu := _data_menu()
    var setting := _data_setting()
    var colors := menu["colors"] as Dictionary[String, Color]

    var output_colors: Dictionary = {}
    for color_key in Constants.TRAY_COLOR_KEYS:
        var color := colors[color_key]
        output_colors[color_key] = "#" + color.to_html(true).to_upper()

    var output_menu: Dictionary = {}
    output_menu["font_size"] = int(menu["font_size"])
    output_menu["colors"] = output_colors

    var output_position: Dictionary = {}
    var position := window["position"] as Dictionary
    output_position["x"] = int(position["x"])
    output_position["y"] = int(position["y"])

    var output_window: Dictionary = {}
    output_window["position"] = output_position
    output_window["debug_border"] = bool(window["debug_border"])

    var output: Dictionary = {}
    output["window"] = output_window
    output["menu"] = output_menu
    output["setting"] = setting.duplicate(true)

    _write_raw_config(output)
    return true

# 写入已经准备好的配置字典.
# 该 helper 用在常规保存和旧配置补 setting 段两个路径, 保证运行期文件始终由同一套 YAML dump 输出.
func _write_raw_config(output: Dictionary) -> void:
    var file := FileAccess.open(Constants.CONFIG_TRAY_PATH, FileAccess.WRITE)
    assert(file != null, "无法写入托盘配置: %s" % Constants.CONFIG_TRAY_PATH)
    file.store_string(YAML.dump(output))
    file.close()

func _ensure_config_loaded() -> void:
    if data.is_empty():
        load_config()

# 从模板中复制 setting 默认段.
# 模板已经经过 _is_config_complete() 检查, 这里仍然走 normalize, 让默认值类型和运行期缓存保持一致.
func _template_setting_state(template_data: Dictionary) -> Dictionary:
    assert(template_data.get("setting") is Dictionary, "托盘配置模板 setting 必须是字典.")
    return _normalize_setting_state(template_data["setting"] as Dictionary)

# 以默认结构为契约检查 setting.
# 这里直接复用默认字典的键和类型, 避免 UI 新增控件时还要手动维护一份重复 schema.
func _setting_state_matches_default_shape(state: Dictionary) -> bool:
    return _dictionary_matches_default_shape(state, _default_setting_state())

func _normalize_setting_state(state: Dictionary) -> Dictionary:
    var normalized := _normalize_dictionary_by_default_shape(state, _default_setting_state(), "setting")
    var window_setting := normalized["window"] as Dictionary
    window_setting["scale"] = clampf(float(window_setting["scale"]), Constants.WINDOW_MIN_SCALE, Constants.WINDOW_MAX_SCALE)
    window_setting["opacity"] = clampf(float(window_setting["opacity"]), Constants.WINDOW_MIN_OPACITY, Constants.WINDOW_MAX_OPACITY)
    normalized["window"] = window_setting
    return normalized

func _upgrade_setting_state(state: Dictionary) -> Dictionary:
    var upgrade_source := state.duplicate(true)
    _apply_setting_legacy_aliases(upgrade_source)
    var filled := _fill_missing_defaults(upgrade_source, _default_setting_state(), "setting")
    return _normalize_setting_state(filled)

func _apply_setting_legacy_aliases(state: Dictionary) -> void:
    if state.get("mode") == "副控":
        state["mode"] = "主控"

    var legacy_battle_data = state.get("battle")
    if legacy_battle_data is Dictionary:
        if not state.has("combat"):
            state["combat"] = (legacy_battle_data as Dictionary).duplicate(true)
        elif state["combat"] is Dictionary:
            var combat_state := state["combat"] as Dictionary
            for legacy_key in (legacy_battle_data as Dictionary).keys():
                if not combat_state.has(legacy_key):
                    combat_state[legacy_key] = (legacy_battle_data as Dictionary)[legacy_key]

    var combat_data = state.get("combat")
    if not (combat_data is Dictionary):
        return

    var combat := combat_data as Dictionary
    if not combat.has("auto_combat") and combat.has("auto_battle"):
        combat["auto_combat"] = combat["auto_battle"]

    if not combat.has("quick_combat"):
        if combat.has("quick_battle"):
            combat["quick_combat"] = combat["quick_battle"]
        elif combat.has("auto_challenge"):
            combat["quick_combat"] = combat["auto_challenge"]

func _fill_missing_defaults(state: Dictionary, defaults: Dictionary, path: String) -> Dictionary:
    var filled: Dictionary = {}
    for key in defaults.keys():
        var default_value = defaults[key]
        if not state.has(key):
            if default_value is Dictionary or default_value is Array:
                filled[key] = default_value.duplicate(true)
            else:
                filled[key] = default_value
            continue

        var state_value = state[key]
        if default_value is Dictionary:
            assert(state_value is Dictionary, "托盘配置字段必须是字典: %s.%s" % [path, str(key)])
            filled[key] = _fill_missing_defaults(state_value as Dictionary, default_value as Dictionary, "%s.%s" % [path, str(key)])
        else:
            filled[key] = state_value

    return filled

func _dictionary_matches_default_shape(state: Dictionary, defaults: Dictionary) -> bool:
    if state.size() != defaults.size():
        return false

    for key in defaults.keys():
        if not state.has(key):
            return false

        var default_value = defaults[key]
        var state_value = state[key]
        if default_value is Dictionary:
            if not (state_value is Dictionary):
                return false
            if not _dictionary_matches_default_shape(state_value as Dictionary, default_value as Dictionary):
                return false
        elif default_value is Array:
            if not (state_value is Array):
                return false
        elif default_value is bool:
            if not (state_value is bool):
                return false
        elif default_value is int:
            if not (state_value is int):
                return false
        elif default_value is float:
            if not (state_value is float or state_value is int):
                return false
        elif default_value is String:
            if not (state_value is String):
                return false

    return true

func _normalize_dictionary_by_default_shape(state: Dictionary, defaults: Dictionary, path: String) -> Dictionary:
    var normalized: Dictionary = {}
    for key in defaults.keys():
        var field_path := "%s.%s" % [path, str(key)]
        assert(state.has(key), "托盘配置缺少必填字段: %s" % field_path)

        var default_value = defaults[key]
        var state_value = state[key]
        if default_value is Dictionary:
            assert(state_value is Dictionary, "托盘配置字段必须是字典: %s" % field_path)
            normalized[key] = _normalize_dictionary_by_default_shape(state_value as Dictionary, default_value as Dictionary, field_path)
        elif default_value is Array:
            assert(state_value is Array, "托盘配置字段必须是数组: %s" % field_path)
            normalized[key] = _normalize_array_by_default_shape(state_value as Array, default_value as Array, field_path)
        elif default_value is bool:
            normalized[key] = Share._bool_value(state_value)
        elif default_value is int:
            normalized[key] = Share._int_value(state_value)
        elif default_value is float:
            normalized[key] = Share._float_value(state_value)
        elif default_value is String:
            assert(state_value is String, "托盘配置字段必须是字符串: %s" % field_path)
            normalized[key] = str(state_value)
        else:
            assert(false, "托盘配置默认值类型未支持: %s" % field_path)

    return normalized

func _normalize_array_by_default_shape(state_value: Array, default_value: Array, path: String) -> Array:
    var normalized: Array = []
    if default_value.is_empty():
        return state_value.duplicate(true)

    var item_default = default_value[0]
    for item in state_value:
        if item_default is String:
            assert(item is String, "托盘配置数组元素必须是字符串: %s" % path)
            normalized.append(str(item))
        elif item_default is int:
            normalized.append(Share._int_value(item))
        elif item_default is bool:
            normalized.append(Share._bool_value(item))
        elif item_default is Dictionary:
            assert(item is Dictionary, "托盘配置数组元素必须是字典: %s" % path)
            normalized.append(_normalize_dictionary_by_default_shape(item as Dictionary, item_default as Dictionary, path))
        else:
            assert(false, "托盘配置数组默认值类型未支持: %s" % path)

    return normalized

# setting 的默认值对应复古设置窗口首次打开时的截图状态.
# 这里返回新字典, 避免调用方修改默认结构时影响后续 schema 校验.
func _default_setting_state() -> Dictionary:
    return {
        "mode": "主控",
        "window": {
            "scale": 1.0,
            "opacity": 1.0,
        },
        "login": {
            "auto_login": false,
            "mute_sound": true,
            "hide_stoneage": false,
            "click_through": false,
        },
        "general": {
            "show_floor": true,
        },
        "combat": {
            "auto_combat": false,
            "quick_combat": false,
            "auto_encounter": false,
            "detail_info": false,
            "auto_capture": false,
            "escape_on_encounter": false,
            "auto_escape": false,
            "lock_pet": false,
            "specified_attack": false,
            "specified_escape": false,
            "switch_pet": "1:无",
            "ground_lock": false,
            "show_exp": true,
        },
        "status": {
            "current_coord": "",
            "cash": "",
            "game_time": "",
        },
        "bottom": {
            "team": false,
            "duel": false,
            "trade": false,
            "card": false,
        },
    }
