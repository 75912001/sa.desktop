extends Node

# 托盘配置 helper.
# 该节点由 GTray 在运行期创建, 只负责 `config/tray.yaml` 的初始化, 读取, 校验, 归一化和写回.
# 真实托盘 UI, 菜单窗口和选项窗口都由 TrayController 负责, 这里不创建任何 Control 或 Window,
# 也不直接调用 DisplayServer, 避免配置层和窗口副作用耦合.

# 解析后的配置缓存.
# data 保存已经完成必填校验和归一化的运行期结构:
# - data["window"] 是运行期窗口状态, 所有 setter 修改后会同步写回 `config/tray.yaml`.
# - data["menu"] 是托盘菜单样式, 读取时会把颜色字符串转换成 Color, 写回时再转回 HTML 字符串.
# get/set 方法都通过 _ensure_config_loaded() 懒加载, 写回成功后继续复用这份缓存.
var data: Dictionary = {}

# 加载配置并校验必需字段.
# 如果运行期配置文件不存在, 先从模板复制生成一份完整配置.
# 这个函数不执行窗口副作用, 只做文件初始化, MiniYAML 读取, 必填校验和字段归一化.
func load_config() -> Dictionary:
    _ensure_config_file()

    # 项目已经通过 YAML Autoload 接入 MiniYAML, ConfigManager.load_yaml() 统一封装了解析错误和根节点类型校验.
    # tray 配置也走同一入口, 避免维护一套只覆盖部分 YAML 语法的手写解析器.
    data = ConfigManager.load_yaml(Constants.CONFIG_TRAY_PATH)

    # window 是主窗口状态契约. 这里按字段逐项取值, 缺失直接 assert,
    # 不使用代码默认坐标, 默认缩放或默认穿透状态, 避免不同用户屏幕环境被固定值污染.
    var window: Dictionary = Share._required_dictionary(data, "window", "window")
    var position: Dictionary = Share._required_dictionary(window, "position", "window.position")
    position["x"] = Share._int_value(Share._required_value(position, "x", "window.position.x"))
    position["y"] = Share._int_value(Share._required_value(position, "y", "window.position.y"))
    window["position"] = position
    window["scale"] = clampf(Share._float_value(Share._required_value(window, "scale", "window.scale")), Constants.WINDOW_MIN_SCALE, Constants.WINDOW_MAX_SCALE)
    window["opacity"] = clampf(Share._float_value(Share._required_value(window, "opacity", "window.opacity")), Constants.WINDOW_MIN_OPACITY, Constants.WINDOW_MAX_OPACITY)
    window["click_through"] = Share._bool_value(Share._required_value(window, "click_through", "window.click_through"))
    window["hidden"] = Share._bool_value(Share._required_value(window, "hidden", "window.hidden"))
    window["debug_border"] = Share._bool_value(Share._required_value(window, "debug_border", "window.debug_border"))
    data["window"] = window

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
    return data

# 读取主窗口位置.
# 返回的是屏幕坐标, 直接交给 WindowController/DisplayServer 使用.
func get_window_position() -> Vector2i:
    _ensure_config_loaded()
    var window := _data_window()
    var position := window["position"] as Dictionary
    return Vector2i(int(position["x"]), int(position["y"]))

# 修改主窗口位置并写回 config/tray.yaml.
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
    var window := _data_window()
    return float(window["scale"])

# 修改主窗口缩放比例并写回 config/tray.yaml.
# 这里不再次 clamp, 因为窗口控制器会负责运行期边界; 本层只保存调用方确认后的状态.
func set_window_scale(value: float) -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    window["scale"] = value
    data["window"] = window
    return _save_config()

# 读取内容透明度.
# 透明度只作用于 MainWindow/ContentRoot 当前业务页面, 不影响窗口外壳和调试红边.
func get_window_opacity() -> float:
    _ensure_config_loaded()
    var window := _data_window()
    return float(window["opacity"])

# 修改内容透明度并写回 config/tray.yaml.
# 透明度同样由窗口控制器保证运行期有效范围; 写回层避免重复业务判断.
func set_window_opacity(value: float) -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    window["opacity"] = value
    data["window"] = window
    return _save_config()

# 读取鼠标穿透状态.
# 该值表示用户期望的持久化状态, 不等同于隐藏窗口期间的临时穿透状态.
func get_window_click_through() -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    return bool(window["click_through"])

# 修改鼠标穿透状态并写回 config/tray.yaml.
# Windows 原生穿透是否真正应用由 WindowController/WindowsClickThroughHelper 负责,
# 配置层只记录托盘勾选状态, 便于重启后恢复.
func set_window_click_through(enabled: bool) -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    window["click_through"] = enabled
    data["window"] = window
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

# 读取主窗口启动时是否隐藏.
# 这是启动策略配置, 与当前窗口是否已经最小化不是同一个概念.
func get_window_hidden() -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    return bool(window["hidden"])

# 修改主窗口启动隐藏配置并写回 config/tray.yaml.
# 托盘显示/隐藏主窗口时会把用户当前选择同步为下一次启动行为.
func set_window_hidden(hidden: bool) -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    window["hidden"] = hidden
    data["window"] = window
    return _save_config()

# 读取调试红边开关.
# 这是配置值, 用户在选项窗口中勾选后会直接写回 config/tray.yaml.
func get_window_debug_border_enabled() -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    return bool(window["debug_border"])

# 修改调试红边配置并写回 config/tray.yaml.
# 调试边框属于 window 运行期状态, 因此仍然通过统一整文件写回流程持久化.
func set_window_debug_border_enabled(enabled: bool) -> bool:
    _ensure_config_loaded()
    var window := _data_window()
    window["debug_border"] = enabled
    data["window"] = window
    return _save_config()

# 确保本地运行期托盘配置存在且结构完整.
# `tray.yaml` 是会被整体写回的本地文件, 用户中断写入或手工编辑时可能留下半截配置;
# 这里在正式读取前先做轻量结构检查, 文件缺失或缺少必需字段时直接用模板重建.
func _ensure_config_file() -> void:
    assert(FileAccess.file_exists(Constants.CONFIG_TRAY_TEMPLATE_PATH), "托盘配置模板不存在: %s" % Constants.CONFIG_TRAY_TEMPLATE_PATH)

    var template_data = _load_config_file(Constants.CONFIG_TRAY_TEMPLATE_PATH)
    assert(_is_config_complete(template_data), "托盘配置模板不完整: %s" % Constants.CONFIG_TRAY_TEMPLATE_PATH)

    var should_copy := not FileAccess.file_exists(Constants.CONFIG_TRAY_PATH)
    if not should_copy:
        should_copy = not _is_config_complete(_load_config_file(Constants.CONFIG_TRAY_PATH))

    if should_copy:
        _copy_config_template()

    var config_data = _load_config_file(Constants.CONFIG_TRAY_PATH)
    assert(_is_config_complete(config_data), "托盘配置文件不完整: %s" % Constants.CONFIG_TRAY_PATH)

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

# 只检查当前代码需要消费的结构和字段是否存在.
# 字段类型, 数值范围和颜色字符串合法性仍由 load_config() 后续流程统一校验.
func _is_config_complete(config_data) -> bool:
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

    for key in ["scale", "opacity", "click_through", "hidden", "debug_border"]:
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

# 整体覆盖写回运行期 tray.yaml.
# 写回使用 MiniYAML dump, 因此不会保留运行期文件里的注释; 注释只维护在 tray.yaml.tpl.
# 写入前先把 Color 转回 HTML 字符串, 避免 MiniYAML 把 Godot Color 对象序列化成不适合手工维护的结构.
func _save_config() -> bool:
    var window := _data_window()
    var menu := _data_menu()
    var colors := menu["colors"] as Dictionary[String, Color]

    var output_colors: Dictionary = {}
    for color_key in Constants.TRAY_COLOR_KEYS:
        var color := colors[color_key]
        output_colors[color_key] = "#" + color.to_html(true).to_upper()

    var output_menu: Dictionary = {}
    output_menu["font_size"] = int(menu["font_size"])
    output_menu["colors"] = output_colors

    var output: Dictionary = {}
    output["window"] = window.duplicate(true)
    output["menu"] = output_menu

    var file := FileAccess.open(Constants.CONFIG_TRAY_PATH, FileAccess.WRITE)
    assert(file != null, "无法写入托盘配置: %s" % Constants.CONFIG_TRAY_PATH)
    file.store_string(YAML.dump(output))
    return true

func _ensure_config_loaded() -> void:
    if data.is_empty():
        load_config()
