class_name WindowController
extends Node

# MainWindow 内部的真实 OS 窗口控制器.
# 这个脚本只负责窗口外壳行为: 透明无边框窗口、尺寸缩放、内容透明度、位置约束、
# 拖拽吸附、显示隐藏和 Windows 原生点击穿透. 业务页面切换由 MainWindow 自己处理,
# 托盘侧负责读取配置、写回配置和刷新菜单 UI, 这里只接收参数并操作真实窗口.

# 释放拖拽时距离屏幕边缘小于这个值就吸附.
const SNAP_DISTANCE := 48

# 缩放和透明度的边界统一放在 Constants 中, 确保托盘输入、配置恢复和脚本调用走同一套约束.

# 拖拽状态只在鼠标按下到释放之间有效.
# drag_offset 记录鼠标点击点到 OS 窗口左上角的距离, 这样拖拽中窗口不会跳到鼠标坐标.
var drag_active := false
var drag_offset := Vector2i.ZERO

# Windows 的真实鼠标穿透需要修改原生窗口扩展样式.
# Godot 自带 WINDOW_FLAG_MOUSE_PASSTHROUGH 对透明桌宠窗口不够稳定, 因此这里统一走 helper.
var native_click_through := WindowsClickThroughHelper.new()

# 初始化主流程窗口.
# 主流程使用同一个透明窗口承载游戏内容.
func initialize_window() -> void:
    # 只恢复真实窗口基础形态. 托盘流程读取配置后再传入这里应用.
    _apply_window_flags()
    _apply_window_layout(1.0)
    set_opacity(1.0)

# 开始拖拽窗口.
func start_drag() -> void:
    drag_active = true
    drag_offset = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()

# 返回是否仍处于拖拽中, 由 MainWindow 决定是否继续逐帧调用 update_drag().
func is_drag_active() -> bool:
    return drag_active

# 拖拽过程中按当前鼠标全局坐标移动真实 OS 窗口.
func update_drag() -> void:
    if not drag_active:
        return

    # Godot 的窗口坐标使用屏幕像素, 鼠标全局坐标也来自 DisplayServer.
    # 两者相减得到左上角目标位置, 再经过可用屏幕区域约束.
    var next_position := DisplayServer.mouse_get_position() - drag_offset
    DisplayServer.window_set_position(_clamp_position(next_position))

# 结束拖拽并返回最终左上角位置, 由调用方决定是否写入配置.
func finish_drag() -> Vector2i:
    if not drag_active:
        return DisplayServer.window_get_position()

    drag_active = false
    _snap_to_edge()
    return DisplayServer.window_get_position()

# 设置点击穿透.
# Windows 真实点击穿透依赖 native helper; helper 不可用时直接 assert 暴露.
func set_click_through(enabled: bool) -> void:
    # helper 失败会 assert, 让开发阶段尽早发现 native 组件缺失或路径错误.
    assert(native_click_through.set_click_through(DisplayServer.MAIN_WINDOW_ID, enabled), "Windows 原生点击穿透 helper 不可用.")

    # 原生 helper 已经接管 Windows 层面的鼠标穿透.
    # 这里保持 Godot 标志关闭, 避免 Godot 与 Win32 helper 同时改变命中测试造成状态不一致.
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false)

# 设置主窗口缩放.
# 100% 对应 Constants.WINDOW_SIZE, 低于 100% 时真实 OS 窗口和 ContentRoot 一起缩小.
func set_scale(value: float) -> void:
    # 缩放前先记录当前窗口中心点.
    # 后续改变真实窗口尺寸后再按中心点反推左上角, 避免缩放导致桌宠明显漂移.
    var current_position := DisplayServer.window_get_position()
    var current_size := DisplayServer.window_get_size()
    var current_center := Vector2(
        float(current_position.x) + float(current_size.x) * 0.5,
        float(current_position.y) + float(current_size.y) * 0.5
    )

    var next_scale := clampf(value, Constants.WINDOW_MIN_SCALE, Constants.WINDOW_MAX_SCALE)
    var next_size := _scaled_window_size(next_scale)
    _apply_window_layout(next_scale)
    var next_position := Vector2i(
        int(round(current_center.x - float(next_size.x) * 0.5)),
        int(round(current_center.y - float(next_size.y) * 0.5))
    )
    DisplayServer.window_set_position(_clamp_position(next_position))

# 设置窗口内容透明度.
# 这里不改 OS 窗口透明背景, 只改 ContentRoot 的 alpha.
func set_opacity(value: float) -> void:
    # 透明度只影响业务内容根节点.
    # 主窗口透明背景和调试边框不跟随 alpha 改变, 方便观察真实窗口范围.
    var next_opacity := clampf(value, Constants.WINDOW_MIN_OPACITY, Constants.WINDOW_MAX_OPACITY)
    GMainWindow.main_window.content_root.modulate.a = next_opacity

# 把窗口放到当前屏幕右下角附近.
func reset_position() -> void:
    var usable_rect := _screen_usable_rect()
    var size := DisplayServer.window_get_size()
    var position := usable_rect.position + usable_rect.size - size - Vector2i(32, 32)
    DisplayServer.window_set_position(_clamp_position(position))

# 设置窗口左上角位置.
func set_position(position: Vector2i) -> void:
    DisplayServer.window_set_position(_clamp_position(position))

# 隐藏窗口时同时临时启用运行时穿透.
# 这样透明窗口即使处于隐藏流程中, 也不容易挡住桌面点击.
func hide_window() -> void:
    drag_active = false
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

# 显示窗口并恢复基础 flags.
func show_window() -> void:
    # 恢复顺序保持为 mode -> flags -> focus.
    # 最小化恢复后部分窗口 flag 可能被平台重置, 所以先重新应用基础窗口形态.
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    _apply_window_flags()
    get_window().grab_focus()

# 提供给托盘菜单判断当前按钮文案.
func is_window_visible() -> bool:
    return DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED

# 主流程窗口最大尺寸由 Constants.WINDOW_SIZE 控制, 这里恢复透明、无边框、置顶和不可缩放等基础特性.
# 主桌宠窗口需要始终压在普通应用窗口上方, 所以 Godot flag 和 native helper 都保持置顶语义.
func _apply_window_flags() -> void:
    # Viewport 透明背景决定 Godot 渲染结果是否保留 alpha.
    # Window 透明和 DisplayServer 透明 flag 决定 OS 原生窗口是否允许透明合成.
    get_viewport().transparent_bg = true
    var window := get_window()
    window.transparent = true
    window.borderless = true
    window.always_on_top = true
    window.unresizable = true

    # Window 属性和 DisplayServer flag 都设置一遍, 是为了覆盖编辑器启动、导出启动和窗口恢复后的差异.
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)

# 按传入缩放比例设置真实 OS 窗口尺寸, 再让 ContentRoot 用相同倍率绘制业务内容.
func _apply_window_layout(next_scale: float) -> void:
    # 真实窗口尺寸先改变, 再设置 ContentRoot 缩放.
    # 这样当前帧内绘制区域和 OS 命中区域尽量保持一致.
    DisplayServer.window_set_size(_scaled_window_size(next_scale))

    # ContentRoot 使用与 OS 窗口一致的缩放倍率.
    # 这样输入坐标、动画绘制区域和窗口可见尺寸保持同一套比例关系.
    GMainWindow.main_window.content_root.scale = Vector2.ONE * next_scale
    GMainWindow.main_window.content_root.position = Vector2.ZERO

# 根据基础窗口尺寸和当前倍率计算真实 OS 窗口尺寸.
# 每个方向至少保留 1 像素, 避免极端配置产生非法窗口大小.
func _scaled_window_size(next_scale: float) -> Vector2i:
    return Vector2i(
        max(1, int(round(float(Constants.WINDOW_SIZE.x) * next_scale))),
        max(1, int(round(float(Constants.WINDOW_SIZE.y) * next_scale)))
    )

# 松开拖拽时吸附到最近屏幕边缘.
# 只在距离边缘足够近时吸附, 否则仅把位置限制在屏幕可用区域内.
func _snap_to_edge() -> void:
    var usable_rect := _screen_usable_rect()
    var window_size := DisplayServer.window_get_size()
    var position := DisplayServer.window_get_position()

    # Dictionary[String, int] 的 int 表示窗口边缘到屏幕可用区域边缘的像素距离.
    # 只比较四条边, 不做角落特殊吸附; 靠近角落时选择距离更近的那条边.
    var distances: Dictionary[String, int] = {
        "left": abs(position.x - usable_rect.position.x),
        "right": abs((usable_rect.position.x + usable_rect.size.x) - (position.x + window_size.x)),
        "top": abs(position.y - usable_rect.position.y),
        "bottom": abs((usable_rect.position.y + usable_rect.size.y) - (position.y + window_size.y)),
    }

    var nearest_edge := ""
    var nearest_distance := SNAP_DISTANCE + 1
    for edge in distances.keys():
        var distance := int(distances[edge])
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_edge = edge

    if nearest_distance <= SNAP_DISTANCE:
        match nearest_edge:
            "left":
                position.x = usable_rect.position.x
            "right":
                position.x = usable_rect.position.x + usable_rect.size.x - window_size.x
            "top":
                position.y = usable_rect.position.y
            "bottom":
                position.y = usable_rect.position.y + usable_rect.size.y - window_size.y

    DisplayServer.window_set_position(_clamp_position(position))

# 把窗口位置限制到当前屏幕可用区域内.
func _clamp_position(position: Vector2i) -> Vector2i:
    # 所有外部传入位置都经过这里, 包括拖拽、缩放后回算和配置恢复.
    # 这样窗口不会被保存或移动到任务栏遮挡区之外的不可见区域.
    var usable_rect := _screen_usable_rect()
    var window_size := DisplayServer.window_get_size()

    # 当窗口尺寸大于可用区域时, max 值至少等于屏幕起点, 避免 clamp 范围反转.
    var max_x := maxi(usable_rect.position.x, usable_rect.position.x + usable_rect.size.x - window_size.x)
    var max_y := maxi(usable_rect.position.y, usable_rect.position.y + usable_rect.size.y - window_size.y)
    return Vector2i(
        clampi(position.x, usable_rect.position.x, max_x),
        clampi(position.y, usable_rect.position.y, max_y)
    )

# 当前屏幕可用区域, 会排除任务栏.
func _screen_usable_rect() -> Rect2i:
    # 使用当前窗口所在屏幕, 兼容多显示器拖拽后的边界计算.
    var screen := DisplayServer.window_get_current_screen()
    return DisplayServer.screen_get_usable_rect(screen)
