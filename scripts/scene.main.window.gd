class_name MainWindow
extends Node2D

# MainWindow 是 scenes/main.window.tscn 的根节点脚本, 只管理同一个 Godot 主窗口.
# 它负责透明无边框窗口外壳、调试边框、空白区域拖拽、ContentRoot 页面挂载、
# 运行时 WindowController helper 的生命周期, 把真实主窗口实例注册到 GMainWindow,
# 再触发 GTray 初始化托盘流程.
# 页面切换只替换 ContentRoot 的子节点, 不调用 change_scene_to_file(),
# 因此 Autoload、系统托盘和真实 OS 窗口不会被业务页面释放影响.

# 当前挂载在 ContentRoot 下的业务页面实例.
# 这里只保存运行时实例, 不保存 PackedScene; clear_scene() 会把旧实例从 ContentRoot 移除并释放.
var current_scene: Node = null

# ContentRoot 是 main.window.tscn 里的业务页面挂载点.
# @onready 会等 MainWindow 和子节点都进入场景树后再取节点, 避免脚本加载阶段访问不存在的子节点.
@onready var content_root: Node2D = get_node_or_null("ContentRoot") as Node2D

# MainWindow 内部创建并持有的窗口行为控制器.
# WindowController 不作为 Autoload 暴露, 由 MainWindow 统一封装拖拽、缩放、透明度、鼠标穿透和窗口显隐行为.
# 它是运行时 helper 节点, 会挂到 MainWindow 生命周期下, 所以 Godot IDE 的静态场景树里不会显示它.
var window_controller: WindowController = null

# `_ready()` 是 Godot 的生命周期函数.
# 当 MainWindow 节点和它的子节点都已经创建完成、可以安全访问 `$子节点` 时, Godot 会自动调用它.
# 这里的启动顺序很重要:
# 1. 校验 ContentRoot, 防止主场景结构变化后继续执行外部窗口副作用.
# 2. 创建窗口控制器并配置主窗口, 保证透明、无边框和尺寸正确.
# 3. 注册 GMainWindow.main_window, GTray 再从全局入口读取主窗口和窗口控制器.
# 4. 不自动加载业务页. 未登录时 ContentRoot 保持为空, 账号登录从托盘选项窗口进入.
func _ready() -> void:
    assert(content_root != null, "MainWindow 缺少 ContentRoot, 无法初始化主窗口.")
    GMainWindow.main_window = self
    _ensure_window_controller()
    _configure_window()
    GTray.initialize()

# 清空当前业务页面.
# 未登录启动和从战斗返回到空内容都会用到它.
func clear_scene() -> void:
    if current_scene != null and is_instance_valid(current_scene):
        content_root.remove_child(current_scene)
        current_scene.queue_free()

    current_scene = null

# 切换窗口中的业务内容.
# 这里先加载新场景, 加载成功后再释放旧页面; 如果路径错误, 当前页面会保留, 方便暴露错误且避免黑屏.
# 新页面只作为 ContentRoot 子节点加入当前窗口, 不调用子场景的可选 initialize() 约定.
# 需要页面初始化参数时, 优先设计明确的页面脚本 API, 不在 MainWindow 里用动态方法名隐式分发.
func switch_scene(scene_path: String) -> void:
    var packed_scene: PackedScene = load(scene_path) as PackedScene
    assert(packed_scene != null, "无法加载场景: %s" % scene_path)

    clear_scene()

    current_scene = packed_scene.instantiate()
    content_root.add_child(current_scene)
    _set_passive_controls_to_pass(current_scene)

# Node2D 的 `_draw()` 只负责绘制调试线框.
# 这里不使用额外 UI 节点, 是为了让红边纯粹作为视觉提示, 不参与鼠标命中和输入分发.
func _draw() -> void:
    if not GTray.get_window_debug_border_enabled():
        return

    var half_width: float = Constants.DEBUG_BORDER_WIDTH * 0.5
    var current_window_size: Vector2i = DisplayServer.window_get_size()
    var window_size: Vector2 = Vector2(float(current_window_size.x), float(current_window_size.y))
    var border_rect: Rect2 = Rect2(
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

    var mouse_event: InputEventMouseButton = event as InputEventMouseButton
    if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
        return

    # 当前窗口会随托盘缩放改变真实尺寸; 只有事件坐标仍在真实窗口矩形内,
    # 且事件没有被业务 UI 消费, 才允许拖动整个 OS 窗口.
    var current_window_size: Vector2i = DisplayServer.window_get_size()
    var window_rect: Rect2 = Rect2(
        Vector2.ZERO,
        Vector2(float(current_window_size.x), float(current_window_size.y))
    )
    if not window_rect.has_point(mouse_event.position):
        return

    window_controller.start_drag()
    set_process(true)
    get_viewport().set_input_as_handled()

# 主窗口只在拖拽期间开启逐帧处理.
# WindowController 负责移动和吸附真实窗口, GTray 负责保存最终位置.
func _process(_delta: float) -> void:
    if window_controller == null or not window_controller.is_drag_active():
        set_process(false)
        return

    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        window_controller.update_drag()
        return

    var final_position := window_controller.finish_drag()
    assert(GTray.set_window_position(final_position), "保存窗口拖拽位置失败, 请检查 config/tray.yaml.")
    set_process(false)

# 统一设置主窗口透明行为.
# project.godot 已经提供同样的默认值, 这里再次设置是为了从测试场景或编辑器运行回主场景时恢复透明窗口状态.
# DisplayServer 操作的是真实 OS 窗口;
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
    # 主桌宠窗口默认永远置顶, 避免被 普通应用窗口盖住.
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
    # 开启窗口透明标志, 让透明像素可以透出桌面.
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
    # 当前模式只管理 Constants.WINDOW_SIZE 指定的主窗口范围.
    window_controller.initialize_window()

# 递归处理当前业务页下的 Control.
# Button、LineEdit、Slider 等真正可交互控件保留默认行为; 容器和标签这类布局控件改为 MOUSE_FILTER_PASS.
# 这样 game 页里的按钮仍然优先响应, 但空白区域不会被普通 Control 截断, 可以冒泡到 MainWindow 拖动整个窗口.
func _set_passive_controls_to_pass(node: Node) -> void:
    if node is Control:
        var control: Control = node as Control
        var is_interactive_control := (
            control is BaseButton
            or control is LineEdit
            or control is TextEdit
            or control is Range
        )
        if not is_interactive_control:
            control.mouse_filter = Control.MOUSE_FILTER_PASS

    for child in node.get_children():
        _set_passive_controls_to_pass(child)

# 创建或返回内部窗口控制器.
# 这个控制器必须挂在 MainWindow 下, 才能在主窗口生命周期内处理拖拽、缩放、透明度和点击穿透状态.
func _ensure_window_controller() -> WindowController:
    if window_controller != null and is_instance_valid(window_controller):
        return window_controller

    window_controller = WindowController.new()
    window_controller.name = "WindowController"
    add_child(window_controller)
    return window_controller
