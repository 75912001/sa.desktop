class_name ConfigAssets
extends RefCounted

# 统一扫描 assets 目录中的动画资源.
# 这个类只负责读取 PNG 文件名和同 ID `.tpsheet`, 并合成 frame_id -> TexturePackerFrame 帧表.
# 配置类只消费这里准备好的帧表引用, 不再直接读取 assets 目录.

# 单个资源的帧表.
class FrameTable extends RefCounted:
    var resource_id: int
    var frame_by_id: Dictionary[int, TexturePackerFrame] = {}

# 宠物 ID -> FrameTable.
# Dictionary[int, FrameTable] 的 int 表示宠物 ID.
var pet_frame_table_by_id: Dictionary[int, FrameTable] = {}

# 角色 ID -> FrameTable.
# Dictionary[int, FrameTable] 的 int 表示角色 ID.
var character_frame_table_by_id: Dictionary[int, FrameTable] = {}

# 统一加载当前 assets 下所有运行期动画资源.
# 当前只包含宠物和角色; 每帧 offset 都内联在 `.tpsheet` sprite 中.
func load() -> void:
    pet_frame_table_by_id = _load_resource_frames(Constants.ASSET_PET_DIR, "宠物")
    character_frame_table_by_id = _load_resource_frames(Constants.ASSET_CHARACTER_DIR, "角色")

# 扫描单个资源目录, 以 `{id}.png` 为主导查找同 ID `.tpsheet`.
func _load_resource_frames(asset_dir: String, label: String) -> Dictionary[int, FrameTable]:
    var frame_table_by_resource_id: Dictionary[int, FrameTable] = {}

    var dir := DirAccess.open(asset_dir)
    if dir == null:
        assert(false, "%s资源目录不存在或无法打开: %s" % [label, asset_dir])
        return frame_table_by_resource_id

    var file_names: Array[String] = []
    dir.list_dir_begin()
    var file_name := dir.get_next()
    while not file_name.is_empty():
        if not dir.current_is_dir():
            file_names.append(file_name)
        file_name = dir.get_next()
    dir.list_dir_end()

    var png_resource_ids: Dictionary[int, bool] = {}
    for current_file_name in file_names:
        if not current_file_name.ends_with(".png"):
            continue

        var resource_id_text := current_file_name.get_basename()
        if not resource_id_text.is_valid_int():
            continue
        var resource_id := int(resource_id_text)

        assert(not png_resource_ids.has(resource_id), "%s PNG 资源 ID 重复: %d" % [label, resource_id])
        png_resource_ids[resource_id] = true

    for current_file_name in file_names:
        if not current_file_name.ends_with(".tpsheet"):
            continue

        var resource_id_text := current_file_name.substr(0, current_file_name.length() - ".tpsheet".length())
        if not resource_id_text.is_valid_int():
            continue
        var resource_id := int(resource_id_text)
        if resource_id <= 0 or not png_resource_ids.has(resource_id):
            continue

        var frame_by_id := _load_texturepacker_frames("%s/%s" % [asset_dir, current_file_name], label)
        assert(not frame_by_id.is_empty(), "%s资源不完整: id:%d missing:[tpsheet]" % [label, resource_id])
        var frame_table := FrameTable.new()
        frame_table.resource_id = resource_id
        frame_table.frame_by_id = frame_by_id
        frame_table_by_resource_id[resource_id] = frame_table

    assert(not png_resource_ids.is_empty(), "%s资源目录没有加载到任何 PNG: %s" % [label, asset_dir])
    for loaded_resource_id in png_resource_ids.keys():
        assert(frame_table_by_resource_id.has(int(loaded_resource_id)), "%s资源不完整: id:%d missing:[tpsheet]" % [label, int(loaded_resource_id)])
    return frame_table_by_resource_id

func _load_texturepacker_frames(sheet_path: String, label: String) -> Dictionary[int, TexturePackerFrame]:
    var sheet_file := FileAccess.open(sheet_path, FileAccess.READ)
    if sheet_file == null:
        assert(false, "无法读取%s图集配置: %s" % [label, sheet_path])
        return {} as Dictionary[int, TexturePackerFrame]

    var parsed_sheet = JSON.parse_string(sheet_file.get_as_text())
    sheet_file.close()
    if not (parsed_sheet is Dictionary):
        assert(false, "%s图集配置不是有效 JSON: %s" % [label, sheet_path])
        return {} as Dictionary[int, TexturePackerFrame]

    var frame_by_id: Dictionary[int, TexturePackerFrame] = {}
    var parsed_sheet_data := parsed_sheet as Dictionary
    for sheet in parsed_sheet_data.get("textures", []):
        if not (sheet is Dictionary):
            continue
        var sheet_data := sheet as Dictionary

        for raw_frame in sheet_data.get("sprites", []):
            if not (raw_frame is Dictionary):
                continue
            var raw_frame_data := raw_frame as Dictionary

            if not raw_frame_data.has("frameid"):
                continue

            var frame_id := int(raw_frame_data["frameid"])
            var region_data = raw_frame_data.get("region", {})
            var margin_data = raw_frame_data.get("margin", {})
            assert(region_data is Dictionary, "%s图集帧 region 非法: path=%s frame=%d" % [label, sheet_path, frame_id])
            assert(margin_data is Dictionary, "%s图集帧 margin 非法: path=%s frame=%d" % [label, sheet_path, frame_id])

            var margin_rect := _rect_from_texturepacker_data(margin_data as Dictionary)
            var offset := Vector2i.ZERO
            if raw_frame_data.has("offset"):
                var offset_data = raw_frame_data.get("offset")
                assert(offset_data is Array and offset_data.size() == 2, "%s图集内联 offset 格式非法, 必须是 [x, y] 两项数组: path=%s frame=%d" % [label, sheet_path, frame_id])
                offset = Vector2i(int(offset_data[0]), int(offset_data[1]))
            var frame := TexturePackerFrame.new()
            frame.region = _rect_from_texturepacker_data(region_data as Dictionary)
            # `.tpsheet` 的 offset 表示裁剪帧左上角相对锚点的偏移, margin 是 TexturePacker 对裁剪透明边缘的补偿.
            # 运行期改用更直观的 anchor_position: 锚点在当前裁剪帧内部的位置.
            var frame_top_left_from_anchor := Vector2(offset.x, offset.y) + margin_rect.position
            frame.anchor_position = -frame_top_left_from_anchor
            frame_by_id[frame_id] = frame

    return frame_by_id

func _rect_from_texturepacker_data(data: Dictionary) -> Rect2:
    return Rect2(
        float(data.get("x", 0)),
        float(data.get("y", 0)),
        float(data.get("w", 0)),
        float(data.get("h", 0))
    )
