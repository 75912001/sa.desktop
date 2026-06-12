class_name ConfigCharacter
extends RefCounted

# 统一读取 config/character.yaml 的角色配置.
# 这个类使用 MiniYAML 解析 YAML, 只消费 character: 段, 并转换成结构化角色条目.

# 角色某个方向, 武器和动作组合下的帧配置.
# key 由 Entry.sprite_entries 使用 Vector3i(orientation, weapon, action) 直接定位,
# 避免运行时先取方向或武器对象, 再取动作字典的多层包装.
class SpriteDirectionWeaponActionEntry extends RefCounted:
    var orientation: int = Constants.AssetOrientation.AssetOrientation_Unknown
    var weapon: int = Constants.AssetWeapon.AssetWeapon_Unknown
    var action: int = Constants.AssetCharacterAction.AssetCharacterAction_Unknown
    var frame_ids: Array = []

# 单个角色配置条目.
class Entry extends RefCounted:
    var id: int
    var name: String
    var is_role: bool
    var description: String
    var color: String
    # Vector3i(orientation, weapon, action) -> SpriteDirectionWeaponActionEntry.
    # 角色资源要求每个方向, 武器和动作组合都存在, 因此上层构建动画时可直接定位帧号表.
    var sprite_entries: Dictionary = {}
    # 这里保存 AssetCharacterMgr 启动阶段创建的 AssetCharacterMgr.Entry 引用.
    # 它不是资源数据拷贝, 只是同一个 RefCounted 对象引用, 便于动画构建器从角色配置直接拿到 PNG 路径和帧表.
    var asset: AssetCharacterMgr.Entry

    func get_sprite_entry(orientation: int, weapon: int, action: int) -> SpriteDirectionWeaponActionEntry:
        return sprite_entries.get(Vector3i(orientation, weapon, action), null) as SpriteDirectionWeaponActionEntry

# 按角色 ID 建立的主缓存.
# 配置加载后常驻内存只保留这一份 id -> Entry.
# 这个缓存由 ConfigManager.get_shared() 首次创建共享管理器时统一加载.
var _by_id: Dictionary = {}

# 配置管理流程的第一步.
# 只负责读取 YAML 并按 character: 段的声明顺序写入 ID 索引; 校验和派生组装放到后续阶段.
func load() -> void:
    _by_id.clear()

    var config_data := ConfigManager.load_yaml(Constants.CONFIG_CHARACTER_PATH)
    var raw_characters = config_data.get("character", [])
    if not (raw_characters is Array):
        push_error("角色配置 character 段不是数组: %s" % Constants.CONFIG_CHARACTER_PATH)
        return

    # character.yaml 的每个元素都会被转换成 Entry.
    # 转换后业务代码只读结构体字段, 不再直接依赖 YAML 字典里的原始 key.
    for raw_character in raw_characters:
        if not (raw_character is Dictionary):
            continue

        # 基础字段只做类型收敛和默认值处理.
        # 字段之间的引用关系, 例如 sprite 帧是否存在于资源中, 放到 check() 阶段统一处理.
        var raw_character_dict := raw_character as Dictionary
        var character := Entry.new()
        character.id = int(raw_character_dict.get("id", 0))
        character.name = str(raw_character_dict.get("name", ""))
        character.is_role = bool(raw_character_dict.get("isRole", false))
        character.description = str(raw_character_dict.get("description", ""))
        character.color = str(raw_character_dict.get("color", ""))

        var raw_sprite = raw_character_dict.get("sprite", {})
        var sprite_entries := {}
        assert(raw_sprite is Dictionary, "角色 sprite 须为对象: character:%d" % character.id)
        if raw_sprite is Dictionary:
            # YAML sprite 源结构是 weapon -> direction -> action -> frame ids.
            # 这里把 direction, weapon 和 action 一起收敛成 SpriteDirectionWeaponActionEntry, 上层可直接定位帧号表.
            var sprite_dict := raw_sprite as Dictionary
            for weapon in sprite_dict.keys():
                var weapon_value := Constants.weapon_from_key(str(weapon))
                assert(weapon_value != Constants.AssetWeapon.AssetWeapon_Unknown, "角色 sprite 武器未知: character:%d weapon:%s" % [character.id, str(weapon)])
                if weapon_value == Constants.AssetWeapon.AssetWeapon_Unknown:
                    continue

                var weapon_data = sprite_dict[weapon]
                assert(weapon_data is Dictionary, "角色 sprite 武器配置须为对象: character:%d weapon:%s" % [character.id, str(weapon)])
                if not (weapon_data is Dictionary):
                    continue

                var weapon_dict := weapon_data as Dictionary
                for direction in weapon_dict.keys():
                    var orientation := Constants.orientation_from_key(str(direction))
                    assert(orientation != Constants.AssetOrientation.AssetOrientation_Unknown, "角色 sprite 方向未知: character:%d weapon:%s direction:%s" % [character.id, str(weapon), str(direction)])
                    if orientation == Constants.AssetOrientation.AssetOrientation_Unknown:
                        continue

                    var direction_data = weapon_dict[direction]
                    assert(direction_data is Dictionary, "角色 sprite 方向配置须为对象: character:%d weapon:%s direction:%s" % [character.id, str(weapon), str(direction)])
                    if not (direction_data is Dictionary):
                        continue

                    var direction_dict := direction_data as Dictionary
                    for action in direction_dict.keys():
                        var action_value := Constants.character_action_from_key(str(action))
                        assert(action_value != Constants.AssetCharacterAction.AssetCharacterAction_Unknown, "角色 sprite 动作未知: character:%d weapon:%s direction:%s action:%s" % [character.id, str(weapon), str(direction), str(action)])
                        if action_value == Constants.AssetCharacterAction.AssetCharacterAction_Unknown:
                            continue

                        var frame_ids = direction_dict[action]
                        assert(frame_ids is Array, "角色 sprite 动作配置须为帧号数组: character:%d weapon:%s direction:%s action:%s" % [character.id, str(weapon), str(direction), str(action)])
                        if not (frame_ids is Array):
                            continue

                        var parsed_frame_ids := []
                        for frame_id_raw in frame_ids:
                            parsed_frame_ids.append(int(frame_id_raw))

                        var sprite_entry := SpriteDirectionWeaponActionEntry.new()
                        sprite_entry.orientation = orientation
                        sprite_entry.weapon = weapon_value
                        sprite_entry.action = action_value
                        sprite_entry.frame_ids = parsed_frame_ids
                        var sprite_key := Vector3i(sprite_entry.orientation, sprite_entry.weapon, sprite_entry.action)
                        assert(not sprite_entries.has(sprite_key), "角色 sprite 方向武器动作重复: character:%d direction:%s weapon:%s action:%s" % [character.id, str(direction), str(weapon), str(action)])
                        sprite_entries[sprite_key] = sprite_entry

        for required_weapon in Constants.CHARACTER_WEAPON_VALUES:
            for required_orientation in Constants.ORIENTATION_VALUES:
                for required_action in Constants.CHARACTER_ACTION_VALUES:
                    assert(sprite_entries.has(Vector3i(int(required_orientation), int(required_weapon), int(required_action))), "角色 sprite 缺少方向武器动作: character:%d direction:%s weapon:%s action:%s" % [character.id, Constants.orientation_to_key(int(required_orientation)), Constants.weapon_to_key(int(required_weapon)), Constants.character_action_to_key(int(required_action))])
        character.sprite_entries = sprite_entries

        # ID 是角色配置和 assets/character 资源文件名的连接点.
        # 非法或重复 ID 会让后续资源校验失去确定目标, 因此在写入缓存前立刻拦截.
        var character_id := character.id
        assert(character_id > 0, "角色ID非法: %d" % character_id)
        if character_id <= 0:
            continue
        assert(not _by_id.has(character_id), "角色ID重复: %d" % character_id)
        if _by_id.has(character_id):
            continue
        _by_id[character_id] = character

# 配置管理流程的第二步.
# 检查是否读到了角色数据, 并校验角色配置引用的资源帧是否存在.
func check() -> void:
    if _by_id.is_empty():
        push_warning("角色配置中没有解析到 character 数据: %s" % Constants.CONFIG_CHARACTER_PATH)

    var asset_manager := ConfigManager.get_shared().asset_manager
    assert(asset_manager != null, "角色配置校验缺少 AssetManager")
    if asset_manager == null:
        return

    var character_mgr := asset_manager.character_mgr
    assert(character_mgr != null, "角色配置校验缺少 AssetCharacterMgr")
    if character_mgr == null:
        return

    # AssetCharacterMgr.load() 已经完成 PNG 和 .tpsheet 的启动期检查.
    # 这里关心的是 character.yaml 中声明的角色 ID 和 frame id 是否能在资源索引中找到.
    for character_id in _by_id:
        var character: Entry = _by_id[character_id]
        var character_asset := character_mgr.get_by_id(int(character_id))
        assert(character_asset != null, "角色缺少资源: character:%d missing:[png]" % int(character_id))
        if character_asset == null:
            continue

        # 逐帧检查 YAML 动作表和 TexturePacker 帧表是否对齐.
        # 缺帧通常说明 character.yaml 写错帧号, 或对应 .tpsheet 没有导出该 sprite.
        for sprite_value in character.sprite_entries.values():
            var sprite_entry := sprite_value as SpriteDirectionWeaponActionEntry
            if sprite_entry == null:
                continue
            var weapon_key := Constants.weapon_to_key(sprite_entry.weapon)
            var direction_key := Constants.orientation_to_key(sprite_entry.orientation)
            var action_key := Constants.character_action_to_key(sprite_entry.action)
            for frame_id in sprite_entry.frame_ids:
                assert(character_asset.sheet_frames.has(int(frame_id)), "角色 sprite 引用了不存在的可播放帧: character:%d weapon:%s direction:%s action:%s frame:%d" % [int(character_id), weapon_key, direction_key, action_key, int(frame_id)])

# 配置管理流程的第三步.
# 这里把 Entry 和同 ID AssetCharacterMgr.Entry 组装到一起.
# check() 已经确认 character.yaml 引用的资源和帧都存在, 所以这里只保存引用, 不再复制 sheet_frames 或 PNG 路径.
func assemble(asset_manager: AssetManager = null) -> void:
    assert(asset_manager != null, "角色配置组装缺少 AssetManager")
    if asset_manager == null or asset_manager.character_mgr == null:
        return

    for character_id in _by_id.keys():
        var character := _by_id[character_id] as Entry
        character.asset = asset_manager.character_mgr.get_by_id(int(character_id))
        assert(character.asset != null, "角色配置组装缺少资源引用: character:%d" % int(character_id))

# 返回 config/character.yaml 中声明过的角色 ID.
# Godot 4 Dictionary 会保留插入顺序, 这里的 keys() 顺序与 YAML 中 character: 段的声明顺序一致.
# 调用方应通过 ConfigManager.get_shared().config_character 取得已经加载好的实例.
func get_ids() -> Array[int]:
    var ids: Array[int] = []
    for character_id in _by_id.keys():
        ids.append(int(character_id))
    return ids

# 根据角色 ID 返回单个结构化角色配置.
func get_by_id(character_id: int) -> Entry:
    return _by_id.get(character_id, null) as Entry
