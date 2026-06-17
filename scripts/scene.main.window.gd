class_name MainWindow
extends Node2D

# MainWindow 是项目唯一主场景, 负责真实主窗口外壳、绘制、输入和 ContentRoot 页面切换.
# 它持有同一个 Godot 主窗口、一个 ContentRoot 和一个 WindowController,
# 页面切换时只替换 ContentRoot 的子节点,
# 不调用 change_scene_to_file(), 这样 Autoload 和窗口实例都不会被页面释放影响.

# `@onready` 表示等节点进入场景树以后再取子节点.
# 因为 `$ContentRoot` 是 scenes/main.window.tscn 里的子节点, 如果在脚本刚加载时就读取,
# 子节点还没准备好; 用 @onready 可以等 Godot 完成节点创建.

# ContentRoot 是业务页面的挂载点.
# 游戏页会作为它的子节点显示.
@onready var content_root: Node2D = get_node_or_null("ContentRoot") as Node2D

# 当前挂载在 ContentRoot 下的业务页面实例.
# switch_scene() 会先移除并释放旧页面, 再实例化新页面; clear_scene() 会把它恢复为 null.
# 这里保存 Node 而不是 PackedScene, 是因为后续需要读取当前页面的 scene_file_path.
var current_scene: Node = null

# MainWindow 内部创建并持有的窗口行为控制器.
# WindowController 不作为 Autoload 暴露, 由 MainWindow 统一封装拖拽、缩放、透明度、鼠标穿透和窗口显隐行为.
# helper 挂到 MainWindow 生命周期下; 页面切换只替换 ContentRoot 子节点, 不会释放这个控制器.
var window_controller: WindowController = null

# `_ready()` 是 Godot 的生命周期函数.
# 当 MainWindow 节点和它的子节点都已经创建完成、可以安全访问 `$子节点` 时, Godot 会自动调用它.
# 这里的启动顺序很重要:
# 1. 校验 ContentRoot, 防止主场景结构变化后继续执行外部窗口副作用.
# 2. 创建窗口控制器并配置主窗口, 保证透明、无边框和尺寸正确.
# 3. 再把 MainWindow 和 WindowController 交给 GTray, 让托盘能触发页面切换和窗口行为.
# 4. 不自动加载业务页. 未登录时 ContentRoot 保持为空, 账号登录从托盘选项窗口进入.
func _ready() -> void:
    if content_root == null:
        push_error("MainWindow 缺少 ContentRoot, 无法初始化主窗口.")
        return

    _ensure_window_controller()
    _configure_window()
    GTray.initialize(self)

# 清空当前业务页面.
# 未登录启动和从战斗返回到空内容都会用到它.
func clear_scene() -> void:
    if current_scene != null and is_instance_valid(current_scene):
        content_root.remove_child(current_scene)
        current_scene.queue_free()

    current_scene = null

# 切换窗口中的业务内容.
# 旧页面先从 ContentRoot 移除再 queue_free(), 避免下一页 ready 时两页同时响应输入.
func switch_scene(scene_path: String) -> void:
    if content_root == null or not is_instance_valid(content_root):
        push_error("MainWindow 缺少有效 ContentRoot, 无法切换场景.")
        return

    if scene_path.is_empty():
        clear_scene()
        return

    if current_scene != null and is_instance_valid(current_scene):
        content_root.remove_child(current_scene)
        current_scene.queue_free()
        current_scene = null

    var packed_scene := load(scene_path) as PackedScene
    if packed_scene == null:
        push_error("无法加载场景: %s" % scene_path)
        return

    current_scene = packed_scene.instantiate()
    if current_scene.has_method("initialize"):
        current_scene.call("initialize", self)
    content_root.add_child(current_scene)
    _prepare_scene_input_routing(current_scene)

# 返回当前业务页面资源路径.
# 空内容或无效节点返回空字符串.
func get_current_scene_path() -> String:
    if current_scene == null or not is_instance_valid(current_scene):
        return ""

    return current_scene.scene_file_path

# Node2D 的 `_draw()` 只负责绘制调试线框.
# 这里不使用额外 UI 节点, 是为了让红边纯粹作为视觉提示, 不参与鼠标命中和输入分发.
func _draw() -> void:
    if not GTray.get_window_debug_border_enabled():
        return

    var half_width := Constants.DEBUG_BORDER_WIDTH * 0.5
    var current_window_size := DisplayServer.window_get_size()
    var window_size := Vector2(float(current_window_size.x), float(current_window_size.y))
    var border_rect := Rect2(
        Vector2(half_width, half_width),
        window_size - Vector2(Constants.DEBUG_BORDER_WIDTH, Constants.DEBUG_BORDER_WIDTH)
    )
    draw_rect(border_rect, Constants.DEBUG_BORDER_COLOR, false, Constants.DEBUG_BORDER_WIDTH)

# `_unhandled_input()` 只接收没有被业务 UI 消费的输入事件.
# 例如 game 里的按钮和输入框会先拿到鼠标事件; 如果它们没有处理, 才会轮到 MainWindow.
# 这里把“窗口范围内空白区域拖拽”视为窗口级行为, 最终交给 WindowController 移动真实 OS 窗口.
# 红色调试边框只是帮助观察窗口范围, 是否显示红边不影响拖拽区域.
func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton):
        return

    var mouse_event := event as InputEventMouseButton
    if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
        return
    if not _is_inside_window_drag_area(mouse_event.position):
        return

    _ensure_window_controller().start_drag()
    get_viewport().set_input_as_handled()

# 统一设置主窗口透明行为.
# project.godot 已经提供同样的默认值, 这里再次设置是为了从测试场景或编辑器运行回主场景时恢复透明窗口状态.
func _configure_window() -> void:
    # 让 root viewport 支持透明背景. 没有这一句, 即使窗口透明, 画布也可能被默认底色填满.
    get_viewport().transparent_bg = true
    # 设置默认清屏颜色为完全透明. Color 的第四个参数是 alpha, 0 表示完全透明.
    RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
    # 确保主窗口是普通窗口模式, 而不是最小化、全屏或其他模式.
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    # 先设置真实系统窗口的最大尺寸. WindowController 初始化后会按托盘缩放配置应用最终尺寸.
    DisplayServer.window_set_size(Constants.WINDOW_SIZE)
    # 无边框窗口没有系统标题栏和边框, 更接近桌面宠物/透明应用的显示方式.
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    # 禁止用户直接拖动系统边框缩放窗口, 保持 UI 布局和设计尺寸一致.
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
    # 开启窗口透明标志, 让透明像素可以透出桌面.
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
    # 当前模式只管理最大 800x600 的主窗口.
    _ensure_window_controller().initialize_window(Constants.WINDOW_SIZE, content_root)

# 判断鼠标是否在当前窗口逻辑范围内.
# 当前窗口会随托盘缩放改变真实尺寸; 只要在这个矩形内且事件没有被业务 UI 消费, 就允许测试期拖动窗口.
func _is_inside_window_drag_area(mouse_position: Vector2) -> bool:
    var current_window_size := DisplayServer.window_get_size()
    var window_rect := Rect2(
        Vector2.ZERO,
        Vector2(float(current_window_size.x), float(current_window_size.y))
    )
    return window_rect.has_point(mouse_position)

# 调整业务页的鼠标过滤规则.
# Button、LineEdit、Slider 等真正可交互控件保持默认行为; 容器和标签这类布局控件不应吞掉空白区域点击.
func _prepare_scene_input_routing(root: Node) -> void:
    _set_passive_controls_to_pass(root)

# 递归处理当前业务页下的 Control.
# 这样 game 页里的按钮仍然优先响应, 但空白区域可以冒泡到 MainWindow 拖动整个窗口.
func _set_passive_controls_to_pass(node: Node) -> void:
    if node is Control:
        var control := node as Control
        if not _is_interactive_control(control):
            control.mouse_filter = Control.MOUSE_FILTER_PASS

    for child in node.get_children():
        _set_passive_controls_to_pass(child)

# 判断一个 Control 是否需要保留自己的鼠标事件处理.
# 这些控件要么能点击, 要么需要拖动/输入, 所以不改它们的 mouse_filter.
func _is_interactive_control(control: Control) -> bool:
    return (
        control is BaseButton
        or control is LineEdit
        or control is TextEdit
        or control is Range
    )

# 创建或返回内部窗口控制器.
# 这个控制器必须挂在 MainWindow 下, 才能在主窗口生命周期内处理拖拽、缩放、透明度和点击穿透状态.
func _ensure_window_controller() -> WindowController:
    if window_controller != null and is_instance_valid(window_controller):
        return window_controller

    window_controller = WindowController.new()
    window_controller.name = "WindowController"
    add_child(window_controller)
    return window_controller
