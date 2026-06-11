class_name AssetParse
extends RefCounted

# 资源解析通用工具.
# 宠物和角色资源管理器都会从 `{id}.png`, `{id}.tpsheet` 文件名里提取数字 ID,
# 也都会把 TexturePacker JSON 中的 x, y, w, h 字段转换成 Godot Rect2.
# 这些函数不依赖具体资源类型, 因此集中放在这里, 避免两套 manager 复制同一份实现.

# 从指定文件后缀前解析数字资源 ID.
static func id_from_suffix(file_name: String, suffix: String) -> int:
	# 从固定后缀前的文件名提取资源 ID.
	# 文件名不是纯数字时返回 0, 调用方会忽略它.
	# 例如 `1000011.png` + `.png` 得到 1000011; `1000011.png.import` 因后缀不匹配会返回 0.
	if not file_name.ends_with(suffix):
		return 0

	var id_text := file_name.substr(0, file_name.length() - suffix.length())
	if not id_text.is_valid_int():
		return 0
	return int(id_text)

# 把 TexturePacker 的 x, y, w, h 字段转换为 Godot Rect2.
static func rect_from_texturepacker_data(data: Dictionary) -> Rect2:
	# TexturePacker 使用 x, y, w, h 字段, Godot 绘制更适合用 Rect2.
	# 缺字段时按 0 处理, 让格式错误在上游 JSON 或资源校验阶段继续暴露, 本函数只做安全转换.
	return Rect2(
		float(data.get("x", 0)),
		float(data.get("y", 0)),
		float(data.get("w", 0)),
		float(data.get("h", 0))
	)
