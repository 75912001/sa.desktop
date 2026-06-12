class_name FramePlayer
extends Node2D

# FramePlayer 是项目通用的图集帧播放器.
# 它只负责 `按给定帧表播放和绘制`, 不负责读取 YAML, 解析 `.tpsheet`, 计算动作帧序列或加载配置.
# 宠物和角色的 AnimationBuilder 会把源数据整理成统一字典, 再交给这里播放.

# 每次当前帧变化时发出信号.
# 测试页用它显示 frame id, draw_position 和 region, 主流程也可以用它做调试信息.
signal frame_changed(frame_index: int, frame_id: int, draw_position: Vector2, region: Rect2)

# 辅助线颜色只在 `show_guides` 打开时绘制.
# baseline 表示脚底基线, origin 表示统一原点, frame 表示当前图集裁剪矩形.
const GUIDE_BASELINE_COLOR := Color(0.2, 0.95, 0.35, 0.9)
const GUIDE_ORIGIN_COLOR := Color(1.0, 0.35, 0.25, 0.95)
const GUIDE_FRAME_COLOR := Color(0.35, 0.65, 1.0, 0.8)

# atlas 是整张 PNG 图集, region 才是每一帧在图集里的裁剪区域.
# draw_texture_rect_region() 会从 atlas 中截取 region, 再绘制到当前 Node2D 的局部坐标中.
var atlas: Texture2D
# frames 保存资源级帧表, key 是 frame_id, value 至少包含:
# - region: 当前帧在 atlas 中的 Rect2 裁剪范围.
# - draw_position: 当前帧相对统一原点的绘制偏移.
var frames := {}
# animations 的结构由 PetAnimationBuilder 或 CharacterAnimationBuilder 生成.
# 每个动画名对应一组 frame_ids, speed, loop 等播放信息.
# 动画名通常是 `动作_方向`, 例如 `stand_down` 或 `walk_left`.
var animations := {}
# 当前正在播放的动画名. 为空表示 setup 后尚未选择动画.
var animation_name := ""
# 当前动画实际使用的 frame_id 列表. 播放时只移动 frame_index, 不复制帧数据.
var frame_ids := []
# 当前帧在 frame_ids 中的下标, 不是资源里的 frame_id.
var frame_index := 0
# 每秒播放多少帧. speed <= 0 时 `_process()` 不推进帧.
var speed := 8.0
# 是否自动播放. 手动逐帧会把它设为 false, 便于停在某一帧检查.
var playing := false
# 当前动画播到末尾后是否回到第一帧.
var loop := true
# 累积的播放时间. 它让低帧率情况下也能补足多个动画帧, 避免动画速度变慢.
var elapsed := 0.0
# 统一绘制原点. 对桌宠和战斗单位来说, 它通常对应脚底基准点.
var origin := Vector2.ZERO
# 动画内容的固定画布大小. 窗口控制器和调试辅助线都会使用它.
var base_size := Vector2i(128, 128)
# 是否绘制调试辅助线. 主流程通常关闭, 偏移测试页可以打开.
var show_guides := false

# 注入新的动画数据.
# 注意: 这个播放器不负责解析 YAML 或 tpsheet, 它只消费已经整理好的动画字典.
# 每次 setup 都会重置播放状态, 避免切换宠物或角色资源后沿用旧帧下标.
func setup(animation_data: Dictionary) -> void:
	atlas = animation_data.get("atlas", null) as Texture2D
	frames = animation_data.get("frames", {})
	animations = animation_data.get("animations", {})
	animation_name = ""
	frame_ids = []
	frame_index = 0
	elapsed = 0.0
	playing = false
	origin = animation_data.get("origin", Vector2.ZERO)
	base_size = animation_data.get("base_size", Vector2i(128, 128))
	queue_redraw()

# base_size 是动画内容的统一画布大小, 窗口控制器会用它计算窗口尺寸.
func get_base_size() -> Vector2i:
	return base_size

# 返回全部动画名, 主要给测试页或兜底播放逻辑使用.
func get_animation_names() -> Array:
	var names := animations.keys()
	names.sort()
	return names

# 检查某个动作方向组合是否存在, 例如 `stand_down`.
func has_animation(next_animation_name: String) -> bool:
	return animations.has(next_animation_name)

# 切换动画.
# 找不到目标动画时回退到 `stand_down`, 这是桌宠最安全的默认站立动作.
# reset_frame=false 时会尽量保留当前 frame_index, 适合未来做同帧切动作或调试切换.
func play_animation(next_animation_name: String, reset_frame := true) -> void:
	if not animations.has(next_animation_name):
		if animations.has("stand_down"):
			next_animation_name = "stand_down"
		else:
			return

	animation_name = next_animation_name
	var animation: Dictionary = animations[animation_name]
	frame_ids = animation.get("frame_ids", [])
	if frame_ids.is_empty():
		frame_index = 0
		elapsed = 0.0
		playing = false
		queue_redraw()
		return

	speed = float(animation.get("speed", 8.0))
	loop = bool(animation.get("loop", true))
	if reset_frame:
		frame_index = 0
		elapsed = 0.0
	else:
		frame_index = clampi(frame_index, 0, max(frame_ids.size() - 1, 0))
	playing = true
	_emit_frame_changed()
	queue_redraw()

# 只控制播放/暂停, 不改变当前帧.
func set_playing(enabled: bool) -> void:
	playing = enabled

# 测试页可以切换循环, 便于停在最后一帧观察 draw_position.
func set_loop_enabled(enabled: bool) -> void:
	loop = enabled

# 辅助线开关会触发重绘, 因为 `_draw()` 才是真正绘制线的位置.
func set_guides_visible(enabled: bool) -> void:
	show_guides = enabled
	queue_redraw()

# 手动前进或后退帧.
# 调用后会暂停自动播放, 便于逐帧检查每一帧的 region 和 draw_position.
func step_frame(delta_frames: int) -> void:
	if frame_ids.is_empty():
		return

	playing = false
	frame_index = posmod(frame_index + delta_frames, frame_ids.size())
	elapsed = 0.0
	_emit_frame_changed()
	queue_redraw()

# 返回当前帧的完整数据字典.
# 如果没有帧, 返回空字典, 调用方要先判断 `is_empty()`.
# 返回值会复制一份帧数据并补上 `id`, 避免调用方直接改到播放器内部的 frames 缓存.
func get_current_frame_info() -> Dictionary:
	if frame_ids.is_empty():
		return {}

	var frame_id := int(frame_ids[frame_index])
	var frame_info: Dictionary = frames.get(frame_id, {})
	if frame_info.is_empty():
		return {}

	var result := frame_info.duplicate()
	result["id"] = frame_id
	return result

# Godot 每帧调用 `_process`.
# 这里用累计时间决定是否切换到下一帧, `speed` 表示每秒播放多少帧.
# while 循环用于处理掉帧: 如果某一帧 delta 很大, 动画会一次补进多帧来保持整体速度.
func _process(delta: float) -> void:
	if not playing or frame_ids.is_empty() or speed <= 0.0:
		return

	elapsed += delta
	var frame_time := 1.0 / speed
	while elapsed >= frame_time:
		elapsed -= frame_time
		if not _advance_frame():
			break

# Node2D 的自定义绘制入口.
# 真正显示的是 atlas 的一个 region, 而不是为每帧创建独立 Texture.
# 绘制发生在本节点局部坐标中, 所以外部可以通过移动/缩放 FramePlayer 节点来统一控制显示位置.
func _draw() -> void:
	if atlas == null or frame_ids.is_empty():
		return

	var frame_id := int(frame_ids[frame_index])
	var frame: Dictionary = frames.get(frame_id, {})
	if frame.is_empty():
		return

	var region: Rect2 = frame["region"]
	# origin 是统一原点, draw_position 是当前帧相对于原点的绘制偏移.
	# 两者相加后, 不同帧的脚底会稳定落在同一条基线上.
	var draw_position: Vector2 = origin + frame["draw_position"]
	var draw_rect := Rect2(draw_position, region.size)
	draw_texture_rect_region(atlas, draw_rect, region)

	if show_guides:
		_draw_guides(draw_rect)

# 前进一帧并处理循环或停止.
# 返回值告诉 `_process()` 是否还能继续在同一帧里补进度.
# 非循环动画停在最后一帧, 这样受击, 倒下等动作未来可以保留末帧姿态.
func _advance_frame() -> bool:
	if frame_ids.is_empty():
		return false

	frame_index += 1
	if frame_index >= frame_ids.size():
		if loop:
			frame_index = 0
		else:
			frame_index = frame_ids.size() - 1
			playing = false
			_emit_frame_changed()
			queue_redraw()
			return false

	_emit_frame_changed()
	queue_redraw()
	return true

# 统一发出帧变化信号, 避免播放切换和逐帧逻辑各写一遍.
# 信号只暴露调用方常用的调试信息, 不把整份 frame 字典直接传出去.
func _emit_frame_changed() -> void:
	var frame_info := get_current_frame_info()
	if frame_info.is_empty():
		return

	frame_changed.emit(
		frame_index,
		int(frame_info.get("id", 0)),
		frame_info.get("draw_position", Vector2.ZERO),
		frame_info.get("region", Rect2())
	)

# 绘制调试辅助线.
# 横线是脚底基线, 竖线是原点 x, 矩形是当前帧实际绘制区域.
# 这些线只帮助检查资源偏移, 不参与游戏逻辑.
func _draw_guides(frame_rect: Rect2) -> void:
	var view_size := Vector2(base_size)
	draw_line(Vector2(0.0, origin.y), Vector2(view_size.x, origin.y), GUIDE_BASELINE_COLOR, 1.0)
	draw_line(Vector2(origin.x, 0.0), Vector2(origin.x, view_size.y), GUIDE_ORIGIN_COLOR, 1.0)
	draw_line(origin - Vector2(5.0, 0.0), origin + Vector2(5.0, 0.0), GUIDE_ORIGIN_COLOR, 2.0)
	draw_line(origin - Vector2(0.0, 5.0), origin + Vector2(0.0, 5.0), GUIDE_ORIGIN_COLOR, 2.0)
	draw_rect(frame_rect, GUIDE_FRAME_COLOR, false, 1.0)
