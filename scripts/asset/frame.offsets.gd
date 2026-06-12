# FrameOffsets 是 offsets.json 解析后的单资源偏移结构.
#
# 项目里的宠物和角色 offsets 总表都是按资源 ID 分组的 JSON:
# {
#   "4000101": {
#     "1": [0, 0],
#     "2": [3, -1]
#   }
# }
#
# AssetManager 读取总表后会为每个资源 ID 创建一个 FrameOffsets:
# - id 保存资源 ID, 例如 pet_id 或 character_id.
# - frames 保存这个资源内部每一帧的额外绘制偏移.
#
# 这个结构只描述“偏移输入”, 不直接参与动画播放.
# 真正给 FramePlayer 使用的是 TexturePackerFrame.draw_position,
# 它由 `.tpsheet` 的 margin.position 加上这里的帧偏移合成得到.
class_name FrameOffsets
extends RefCounted

# 单个资源 ID 的帧偏移表.
# offsets JSON 解析后不再把嵌套 Dictionary 直接传递给动画帧合成逻辑, 而是通过这个结构读取单帧偏移.
# 这个 ID 来自 offsets 总表第一层 key.
# 对宠物资源来说它对应 pet_id, 对角色资源来说它对应 character_id.
var id: int

# frame_id -> Vector2i.
# key 是 `.tpsheet` 中帧文件名解析出的数字帧号, 也是 YAML 动画配置引用的帧号.
# value 是绘制时需要额外叠加的像素偏移.
# 这里只保存 offsets.json 中显式声明过的帧; 没声明的帧会在 get_frame_offset() 中按零偏移处理.
var frames: Dictionary = {}

# 记录某一帧的偏移.
#
# 解析 offsets.json 时调用:
# - frame_id 来自 offsets JSON 第二层 key.
# - offset 来自当前项目约定的 `[x, y]` 数组.
# 如果同一个 frame_id 被重复写入, Dictionary 会保留最后一次赋值.
# 正常资源文件不应该出现重复 key; JSON 解析层通常也已经折叠重复 key.
func set_frame_offset(frame_id: int, offset: Vector2i) -> void:
	frames[frame_id] = offset

# 读取某一帧的偏移.
#
# 缺少 offset 不再表示资源不完整.
# 当前资源管线约定: 没有配置 offset 就代表这一帧不需要额外偏移,
# 因此返回 Vector2i.ZERO, 让 `.tpsheet` 的 margin.position 原样参与 draw_position 合成.
func get_frame_offset(frame_id: int) -> Vector2i:
	return frames.get(frame_id, Vector2i.ZERO)
