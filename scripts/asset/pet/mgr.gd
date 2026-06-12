class_name AssetPetMgr
extends RefCounted

# 宠物资源管理器.
# 当前桌面版直接使用 `assets/pet/{id}.png`, `{id}.tpsheet` 和宠物 offsets 总表.
# 这个类只负责建立“宠物资源索引”和“帧播放元数据”, 不读取 pet.yaml, 也不在启动阶段加载 Texture2D.
# Godot 的 RefCounted 不进入场景树, 因此这里没有 _ready() 生命周期; ConfigManager 创建 AssetManager 后会主动调用 load().
# 资源加载顺序固定为 PNG -> offsets -> .tpsheet:
# 1. PNG 文件名决定有哪些宠物资源存在.
# 2. offsets.json 只是可选的额外绘制偏移输入.
# 3. .tpsheet 会和 offsets 合成为播放器直接消费的 TexturePackerFrame.

# 单个宠物资源的索引条目.
# 启动时只加载资源元数据, 真实图集纹理由动画构建器按需加载.
class Entry extends RefCounted:
	# 宠物资源 ID, 对应 config/pet.yaml 中的 pet.id.
	var id: int
	# PNG 图集路径. 这里只保存路径, 不在启动阶段加载 Texture2D.
	# 动画构建器真正需要显示某个宠物时, 才会通过这个路径 load() Texture2D.
	var png_path: String
	# frame_id -> TexturePackerFrame.
	# 这是从 `.tpsheet` 的 region/margin 和可选 offsets 总表合成出的帧播放数据.
	# key 是 TexturePacker sprites[].filename 转成的 int frame_id.
	# value 是 TexturePackerFrame, 只保存播放器需要的 region 和 draw_position.
	# 这里不保存 `.tpsheet` 原始 JSON, 也不保存 offsets 原始表, 启动解析后就收敛成可播放帧数据.
	var sheet_frames: Dictionary = {}

# pet_id -> Entry.
# ConfigManager 启动时只加载这一份索引, 后续配置校验和动画构建器都通过它查询资源.
# 这个索引的 key 来自 PNG 文件名, 因此 `get(pet_id) != null` 就表示同 ID PNG 存在.
# `.tpsheet` 或 offsets 不会反向创建宠物条目, 避免孤立配置文件被误认为可播放宠物.
var _by_id: Dictionary = {}

# 以 PNG 文件中的宠物 ID 为主导扫描宠物资源目录, 再读取可选 offsets 总表补充绘制偏移.
# `.tpsheet` 只服务于已经存在 PNG 的宠物, 不反向创建宠物资源条目.
func load() -> void:
	# 第一步: 扫描宠物资源目录并收集文件名.
	# 只读取一次目录, 后面分别用同一份 file_names 做 PNG 注册和 `.tpsheet` 绑定.
	_by_id.clear()
	var dir := DirAccess.open(Constants.ASSET_PET_DIR)
	if dir == null:
		assert(false, "宠物资源目录不存在或无法打开: %s" % Constants.ASSET_PET_DIR)
		return

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# 第二步: 只按 PNG 创建资源条目.
	# 宠物资源以 `{pet_id}.png` 为主导; 同 ID `.tpsheet` 或 offsets 不会反向创建 entry.
	for current_file_name in file_names:
		if not current_file_name.ends_with(".png"):
			continue

		var png_pet_id := AssetParse.id_from_suffix(current_file_name, ".png")
		if png_pet_id <= 0:
			continue

		assert(not _by_id.has(png_pet_id), "宠物 PNG 资源 ID 重复: %d" % png_pet_id)
		var png_entry := Entry.new()
		png_entry.id = png_pet_id
		png_entry.png_path = "%s/%s" % [Constants.ASSET_PET_DIR, current_file_name]
		_by_id[png_pet_id] = png_entry

	# 第三步: 读取可选 offsets 总表.
	# offsets JSON 只作为 `.tpsheet` 合成 draw_position 的输入; 总表不存在时使用空字典, 表示所有帧都没有额外偏移.
	var offsets := {}
	var offsets_path := Constants.PET_OFFSETS_PATH
	var offsets_file := FileAccess.open(offsets_path, FileAccess.READ)
	if offsets_file != null:
		var parsed_offsets = JSON.parse_string(offsets_file.get_as_text())
		if parsed_offsets is Dictionary:
			for pet_key in parsed_offsets.keys():
				var raw_offsets = parsed_offsets[pet_key]
				if not (raw_offsets is Dictionary):
					push_error("宠物总偏移配置条目不是对象: %s pet=%s" % [offsets_path, str(pet_key)])
					continue

				var offset_pet_id := int(pet_key)
				var frame_offsets := FrameOffsets.new()
				frame_offsets.id = offset_pet_id
				for offset_frame_key in (raw_offsets as Dictionary).keys():
					var offset_data = raw_offsets[offset_frame_key]
					if offset_data is Array and offset_data.size() == 2:
						# JSON 里的 key 是字符串, 这里统一转成 int frame_id, 便于和 `.tpsheet` 的 filename 对齐.
						frame_offsets.set_frame_offset(int(offset_frame_key), Vector2i(int(offset_data[0]), int(offset_data[1])))
					else:
						push_error("宠物偏移帧格式非法, 必须是 [x, y] 两项数组: frame=%s" % str(offset_frame_key))
				offsets[offset_pet_id] = frame_offsets
		else:
			push_error("宠物总偏移配置不是有效 JSON: %s" % offsets_path)

	# 第四步: 为已有 PNG entry 绑定同 ID `.tpsheet`.
	# 如果 `.tpsheet` 没有对应 PNG, 直接跳过; 后续 pet.yaml 引用该宠物时会按缺 PNG 报错.
	for current_file_name in file_names:
		if not current_file_name.ends_with(".tpsheet"):
			continue

		var sheet_pet_id := AssetParse.id_from_suffix(current_file_name, ".tpsheet")
		if sheet_pet_id <= 0 or not _by_id.has(sheet_pet_id):
			continue

		var sheet_entry: Entry = _by_id[sheet_pet_id]
		var sheet_path := "%s/%s" % [Constants.ASSET_PET_DIR, current_file_name]
		var sheet_file := FileAccess.open(sheet_path, FileAccess.READ)
		if sheet_file == null:
			push_error("无法读取宠物图集配置: %s" % sheet_path)
			sheet_entry.sheet_frames = {}
			continue

		var parsed_sheet = JSON.parse_string(sheet_file.get_as_text())
		if not (parsed_sheet is Dictionary):
			push_error("宠物图集配置不是有效 JSON: %s" % sheet_path)
			sheet_entry.sheet_frames = {}
			continue

		# TexturePacker 把帧号放在 textures[].sprites[].filename 中.
		# 这里直接合成 frame_id -> TexturePackerFrame, 不保留 `.tpsheet` 原始 JSON.
		var entry_offsets: FrameOffsets = offsets.get(sheet_pet_id, null)
		var sheet_frames := {}
		for sheet in (parsed_sheet as Dictionary).get("textures", []):
			if not (sheet is Dictionary):
				continue

			for sprite in sheet.get("sprites", []):
				if not (sprite is Dictionary):
					continue

				var sheet_frame_key := str(sprite.get("filename", ""))
				if sheet_frame_key.is_empty():
					continue

				var frame_id := int(sheet_frame_key)
				var region: Dictionary = sprite.get("region", {})
				var margin: Dictionary = sprite.get("margin", {})
				var margin_rect := AssetParse.rect_from_texturepacker_data(margin)
				var offset := entry_offsets.get_frame_offset(frame_id) if entry_offsets != null else Vector2i.ZERO
				var frame := TexturePackerFrame.new()
				frame.region = AssetParse.rect_from_texturepacker_data(region)
				# margin 是 TexturePacker 对被裁剪透明边缘的补偿, offset 是素材偏移表给出的额外绘制偏移.
				# 两者相加后就是播放器绘制当前帧时使用的最终局部坐标.
				frame.draw_position = Vector2(offset.x, offset.y) + margin_rect.position
				sheet_frames[frame_id] = frame
		sheet_entry.sheet_frames = sheet_frames

	# 第五步: 检查本次宠物资源加载结果.
	# 宠物资源以 PNG 为主导; 只要目录里存在 `{pet_id}.png`, 同 ID `.tpsheet` 就必须可解析.
	assert(not _by_id.is_empty(), "宠物资源目录没有加载到任何 PNG: %s" % Constants.ASSET_PET_DIR)
	for loaded_pet_id in _by_id.keys():
		var loaded_entry: Entry = _by_id[loaded_pet_id]
		var missing_sources: Array[String] = []
		if loaded_entry.png_path.is_empty():
			missing_sources.append("png")
		if loaded_entry.sheet_frames.is_empty():
			missing_sources.append("tpsheet")
		assert(missing_sources.is_empty(), "宠物资源不完整: pet:%d missing:%s" % [int(loaded_pet_id), str(missing_sources)])

# 按宠物 ID 返回已加载的宠物资源条目.
func get(pet_id: int) -> Entry:
	# 返回启动阶段建立的索引条目; 不存在时返回 null, 调用方据此输出缺资源错误.
	# 这里不自动创建条目, 因为宠物资源必须以 PNG 文件为主导.
	return _by_id.get(pet_id, null)
