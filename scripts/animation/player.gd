class_name FramePlayer
extends Node2D

# FramePlayer 是宠物和角色播放器共用的底层图集帧播放器.
# 它只保存播放状态, 推进 frame_index, 绘制 atlas region 和调试辅助线.
# 宠物/角色配置读取, 动作参数校验和业务显示入口由 PetFramePlayer/CharacterFramePlayer 负责.
# 这个脚本继承 Node2D, 因为它需要通过 `_draw()` 直接把图集中的局部区域绘制到 2D 坐标系里.
# 外部调用方可以移动, 缩放或设置 z_index 来控制整个动画节点, 但不应该在这里混入宠物或角色业务判断.

# 辅助线颜色只在 `guides_visible` 打开时绘制.
# anchor_row 表示锚点所在横线, anchor_column 表示锚点所在竖线, frame 表示当前图集裁剪矩形.
const GUIDE_ANCHOR_ROW_COLOR := Color(0.2, 0.95, 0.35, 0.9)
const GUIDE_ANCHOR_COLUMN_COLOR := Color(1.0, 0.35, 0.25, 0.95)
const GUIDE_FRAME_COLOR := Color(0.35, 0.65, 1.0, 0.8)
# 当前播放器只保存播放所需引用, 不持有宠物或角色业务配置对象.
# atlas 是整张 PNG 图集, `_draw()` 会从这张图里裁剪当前帧的 region.
var atlas: Texture2D
# Dictionary[int, TexturePackerFrame] 的 int 表示当前资源的 frame_id.
# TexturePackerFrame 由配置/资源加载阶段创建, 内含 region 和 anchor_position, 播放器只消费结果.
var frame_by_id: Dictionary[int, TexturePackerFrame] = {}
# 当前动画实际使用的 frame_id 列表. 播放时只移动 frame_index, 不复制帧数据.
# Array[int] 中的 int 表示当前动画按顺序播放的 frame_id.
# 同一张图集和同一份 frame_by_id 可以被多个动作复用, 所以这里保存的是轻量的帧号序列.
var frame_ids: Array[int] = []
# 当前帧在 frame_ids 中的下标, 不是资源里的 frame_id.
# 例如 frame_index=0 表示播放序列第一项, 真正的资源帧号要通过 frame_ids[0] 取得.
var frame_index := 0
# 每秒播放多少帧. speed <= 0 时 `_process()` 不推进帧.
# speed 只影响时间推进, 不影响 `_draw()` 如何绘制当前帧.
var speed := Constants.ANIMATION_DEFAULT_SPEED
# 是否自动播放. 手动逐帧会把它设为 false, 便于停在某一帧检查.
# playing=false 时当前帧仍保留在屏幕上, 只是 `_process()` 不再改变 frame_index.
var playing := false
# 当前动画播到末尾后是否回到第一帧.
# loop=false 常用于测试页观察最后一帧或后续一次性动作.
var loop := Constants.ANIMATION_DEFAULT_LOOP
# 累积的播放时间. 它让低帧率情况下也能补足多个动画帧, 避免动画速度变慢.
# elapsed 每次跨过 frame_time 就消耗一段时间, 因此一次较大的 delta 也能推进多帧.
var elapsed := 0.0
# 是否绘制调试辅助线. 主流程通常关闭, 偏移测试页可以打开.
# guides_visible 改变后必须 queue_redraw(), 因为辅助线是在 `_draw()` 里即时绘制的.
var guides_visible := false

# 调用方用这个入口播放已经解析好的帧序列.
# source_frame_by_id 的 Dictionary[int, TexturePackerFrame] 中, int 表示当前资源的 frame_id.
func play(source_atlas: Texture2D, source_frame_by_id: Dictionary[int, TexturePackerFrame], sequence_frame_ids: Array[int], frames_per_second: float, should_loop: bool) -> void:
    # 注入新序列前重置播放进度, 让同一个播放器切换动作时不会继承旧帧下标和时间累计.
    atlas = source_atlas
    frame_by_id = source_frame_by_id
    frame_ids = sequence_frame_ids
    # speed/loop 由具体播放器决定, 基类不判断这是宠物还是角色.
    speed = frames_per_second
    loop = should_loop
    # 新序列始终从第一帧开始播放, 让动作切换结果稳定且容易理解.
    frame_index = 0
    elapsed = 0.0
    playing = true
    queue_redraw()
    
# 继续播放当前帧序列, 不重置当前帧和累计时间.
func start() -> void:
    playing = true

# 暂停当前帧序列, 保留当前帧画面.
func pause() -> void:
    playing = false

# 开启循环播放. 这个状态只影响下一次越过末帧时的行为, 不会立刻改变当前帧.
func enable_loop() -> void:
    loop = true

# 关闭循环播放. 当前动画播到末帧后会停在最后一帧.
func disable_loop() -> void:
    loop = false

# 开启辅助线. 辅助线由 `_draw()` 绘制, 所以状态变化后需要请求重绘.
func enable_guides() -> void:
    guides_visible = true
    queue_redraw()

# 关闭辅助线. 关闭时同样要重绘, 才能把上一帧画出的线擦掉.
func disable_guides() -> void:
    guides_visible = false
    queue_redraw()

# 手动前进或后退帧.
# 调用后会暂停自动播放, 便于逐帧检查每一帧的 region 和 anchor_position.
func step_frame(delta_frames: int) -> void:
    # 没有帧序列时直接返回, 避免 posmod(..., 0) 产生无意义计算.
    if frame_ids.is_empty():
        return

    # 逐帧检查需要稳定画面, 所以任何手动步进都会先暂停自动播放.
    playing = false
    # posmod 支持负数步进, 上一帧从第 0 帧继续向前会绕到最后一帧.
    frame_index = posmod(frame_index + delta_frames, frame_ids.size())
    elapsed = 0.0
    queue_redraw()

# Godot 每帧调用 `_process`.
# 这里用累计时间决定是否切换到下一帧, `speed` 表示每秒播放多少帧.
# while 循环用于处理掉帧: 如果某一帧 delta 很大, 动画会一次补进多帧来保持整体速度.
func _process(delta: float) -> void:
    # `_process()` 是 Godot 每帧调用的生命周期函数.
    # 这里先做所有早退判断, 让暂停, 空动画和异常速度都不会进入时间推进逻辑.
    if not playing or frame_ids.is_empty() or speed <= 0.0:
        return

    elapsed += delta
    # frame_time 是单帧应该停留的秒数; speed 越大, 单帧显示时间越短.
    var frame_time := 1.0 / speed
    while elapsed >= frame_time:
        elapsed -= frame_time
        frame_index += 1
        if frame_index >= frame_ids.size():
            if loop:
                # 循环动画回到第一帧, 常用于站立, 行走和测试页连续预览.
                frame_index = 0
            else:
                # 非循环动画停在最后一帧, 让调用方可以看到动作结束状态.
                frame_index = frame_ids.size() - 1
                playing = false
                queue_redraw()
                break

        # 只要 frame_index 可能变化, 就请求 Godot 在绘制阶段重新调用 `_draw()`.
        queue_redraw()

# Node2D 的自定义绘制入口.
# 真正显示的是 atlas 的一个 region, 而不是为每帧创建独立 Texture.
# 绘制发生在本节点局部坐标中, 所以外部可以通过移动/缩放具体播放器节点来统一控制显示位置.
func _draw() -> void:
    # `_draw()` 是 Godot 的自绘回调, 只应该根据当前状态绘制, 不应该在这里推进动画时间.
    if atlas == null or frame_ids.is_empty():
        return

    # frame_ids 保存的是播放序列, 先用 frame_index 取出资源帧号, 再到 frame_by_id 取帧数据.
    var frame_id := int(frame_ids[frame_index])
    var frame := frame_by_id.get(frame_id, null) as TexturePackerFrame
    if frame == null:
        # 这里静默返回, 因为配置完整性已经在加载/assemble 阶段校验; 运行期不再兜底修正坏数据.
        return

    # FramePlayer 的局部原点就是动画锚点.
    # 把裁剪帧左上角画在 -anchor_position, 就能让帧内部锚点落到本节点原点.
    var frame_position: Vector2 = -frame.anchor_position
    var frame_rect := Rect2(frame_position, frame.region.size)
    # draw_texture_rect_region 使用同一张 atlas 的 region 绘制当前帧, 避免为每帧生成独立 Texture.
    draw_texture_rect_region(atlas, frame_rect, frame.region)

    if guides_visible:
        # 辅助线使用当前播放器局部坐标:
        # 横线和竖线穿过本节点原点, 小十字用于快速定位动画锚点.
        draw_line(Vector2(frame_rect.position.x, 0.0), Vector2(frame_rect.end.x, 0.0), GUIDE_ANCHOR_ROW_COLOR, 1.0)
        draw_line(Vector2(0.0, frame_rect.position.y), Vector2(0.0, frame_rect.end.y), GUIDE_ANCHOR_COLUMN_COLOR, 1.0)
        draw_line(Vector2(-5.0, 0.0), Vector2(5.0, 0.0), GUIDE_ANCHOR_COLUMN_COLOR, 10.0)
        draw_line(Vector2(0.0, -5.0), Vector2(0.0, 5.0), GUIDE_ANCHOR_COLUMN_COLOR, 10.0)
        # 当前帧矩形能直观看到图集裁剪尺寸和锚点位置是否符合预期.
        draw_rect(frame_rect, GUIDE_FRAME_COLOR, false, 1.0)
