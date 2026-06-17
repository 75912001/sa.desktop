class_name ConfigCharacter
extends RefCounted

# 统一读取 config/character.yaml 的角色配置.
# 这个类使用 MiniYAML 解析 YAML, 只消费 character: 段, 并转换成结构化角色条目.

const CHARACTER_KEYS := ["id", "name", "isRole", "description", "color", "sprite"]

# 角色某个方向, 武器类型和动作组合下的播放缓存.
# key 由 Entry.direction_weapon_action_frames 使用 Vector3i(direction, weapon, action) 直接定位.
class PlayInfo extends RefCounted:
    # Array[int] 中的 int 表示 YAML sprite 动作帧表里的 frame_id, ids 顺序就是播放顺序.
    var ids: Array[int] = []

# 单个角色配置条目.
class Entry extends RefCounted:
    var id: int
    var name: String
    var is_role: bool
    var description: String
    var color: String
    # Vector3i(direction, weapon, action) -> PlayInfo.
    # Vector3i.x 是 proto AssetDirection, y 是 proto CharacterWeaponType, z 是 proto CharacterAction.
    # 角色资源要求每个方向, 武器类型和动作组合都存在, 因此播放缓存可直接定位帧号表.
    var direction_weapon_action_frames: Dictionary[Vector3i, PlayInfo] = {}
    # frame_id -> TexturePackerFrame.
    # Dictionary[int, TexturePackerFrame] 的 int 表示 YAML 动画帧表引用的 frame_id.
    # 这是 `.tpsheet` 的 region, margin 和内联 offset 合成后的帧索引.
    # Entry 直接持有这份索引引用, PlayInfo 只保存帧号序列, 不复制每帧 TexturePackerFrame.
    var frame_by_id: Dictionary[int, TexturePackerFrame] = {}
    var atlas: Texture2D

    func get_play_info(direction: int, weapon: int, action: int) -> PlayInfo:
        var play_key := Vector3i(direction, weapon, action)
        return direction_weapon_action_frames[play_key] as PlayInfo

# 按角色 ID 建立的主缓存.
# Dictionary[int, Entry] 的 int 表示 config/character.yaml 中 character 段的角色 ID.
# 配置加载后常驻内存只保留这一份 id -> Entry.
# 这个缓存由 ConfigManager.get_shared() 首次创建共享管理器时统一加载.
var _by_id: Dictionary[int, Entry] = {}

# 配置管理流程的第一步.
# 读取 YAML 并按 character: 段的声明顺序写入 ID 索引.
# 资源帧表已由 AssetsConfig 统一加载; 本函数只解析 YAML 字段和方向, 武器类型, 动作到帧号序列的关系.
func load() -> void:
    var config_data := ConfigManager.load_yaml(Constants.CONFIG_CHARACTER_PATH)
    assert(config_data.has("character"), "角色配置缺少 character 段: %s" % Constants.CONFIG_CHARACTER_PATH)
    var raw_characters = config_data.get("character", [])
    assert(raw_characters is Array, "角色配置 character 段不是数组: %s" % Constants.CONFIG_CHARACTER_PATH)
    assert(not (raw_characters as Array).is_empty(), "角色配置中没有解析到 character 数据: %s" % Constants.CONFIG_CHARACTER_PATH)

    # character.yaml 的每个元素都会被转换成 Entry.
    # 转换后业务代码只读结构体字段, 不再直接依赖 YAML 字典里的原始 key.
    for raw_character in raw_characters:
        assert(raw_character is Dictionary, "角色配置条目须为对象: %s" % Constants.CONFIG_CHARACTER_PATH)

        # 基础字段先按 Entry 目标类型收敛; 无默认值字段使用无效默认值, 通过后续断言暴露配置错误.
        # 字段之间的引用关系, 例如 frame 是否存在于资源中, 放到 assemble() 阶段统一处理.
        var raw_character_dict := raw_character as Dictionary
        _assert_known_keys(raw_character_dict, CHARACTER_KEYS, "角色配置字段未知")
        # ID 是角色配置和 assets/character 资源文件名的连接点.
        # 非法或重复 ID 会让后续资源校验失去确定目标, 因此读取后立刻拦截.
        var character_id := int(raw_character_dict.get("id", 0))
        assert(Constants.is_character_id(character_id), "角色ID超出范围: %d" % character_id)
        assert(not _by_id.has(character_id), "角色ID重复: %d" % character_id)

        var character_name := str(raw_character_dict.get("name", ""))
        assert(not character_name.is_empty(), "角色 name 不能为空: id:%d" % character_id)

        var character_is_role := _parse_bool(raw_character_dict.get("isRole", false), "角色 isRole 非法: id:%d" % character_id)

        var character_description := str(raw_character_dict.get("description", ""))
        assert(not character_description.is_empty(), "角色 description 不能为空: id:%d" % character_id)

        var character_color := str(raw_character_dict.get("color", ""))
        assert(not character_color.is_empty(), "角色 color 不能为空: id:%d" % character_id)

        var character := Entry.new()
        character.id = character_id
        character.name = character_name
        character.is_role = character_is_role
        character.description = character_description
        character.color = character_color

        var raw_action_frames = raw_character_dict.get("sprite", {})
        assert(raw_action_frames is Dictionary, "角色动作帧表须为对象: character:%d" % character.id)
        # Dictionary[Vector3i, PlayInfo] 的 Vector3i 为 (direction 枚举值, weapon 枚举值, character_action 枚举值).
        var direction_weapon_action_frames: Dictionary[Vector3i, PlayInfo] = {}
        # YAML sprite 字段的动作帧表源结构是 weapon -> direction -> action -> frame ids.
        # 这里把 direction, weapon 和 action 一起收敛成 direction_weapon_action_frames 的 key, 播放缓存可直接定位帧号序列; weapon 是配置字段名, 语义是武器类型.
        var action_frame_dict := raw_action_frames as Dictionary
        for weapon in action_frame_dict.keys():
            var weapon_value := _weapon_type_from_key(str(weapon))
            assert(weapon_value != GPB.CharacterWeaponType.CharacterWeaponType_Unknow, "角色动作帧表武器类型未知: character:%d weapon:%s" % [character.id, str(weapon)])

            var weapon_data = action_frame_dict[weapon]
            assert(weapon_data is Dictionary, "角色动作帧表武器类型配置须为对象: character:%d weapon:%s" % [character.id, str(weapon)])

            var weapon_dict := weapon_data as Dictionary
            for direction_key in weapon_dict.keys():
                var direction := _direction_from_key(str(direction_key))
                assert(direction != GPB.AssetDirection.AssetDirection_Unknow, "角色动作帧表方向未知: character:%d weapon:%s direction:%s" % [character.id, str(weapon), str(direction_key)])

                var direction_data = weapon_dict[direction_key]
                assert(direction_data is Dictionary, "角色动作帧表方向配置须为对象: character:%d weapon:%s direction:%s" % [character.id, str(weapon), str(direction_key)])

                var direction_dict := direction_data as Dictionary
                for action in direction_dict.keys():
                    var action_value := _character_action_from_key(str(action))
                    assert(action_value != GPB.CharacterAction.CharacterAction_Unknow, "角色动作帧表动作未知: character:%d weapon:%s direction:%s action:%s" % [character.id, str(weapon), str(direction_key), str(action)])

                    var frame_ids = direction_dict[action]
                    assert(frame_ids is Array, "角色动作帧表动作配置须为帧号数组: character:%d weapon:%s direction:%s action:%s" % [character.id, str(weapon), str(direction_key), str(action)])

                    # Array[int] 中的 int 表示当前 direction/weapon/action 对应的 frame_id.
                    var parsed_frame_ids: Array[int] = []
                    for frame_id_raw in frame_ids:
                        parsed_frame_ids.append(int(frame_id_raw))
                    assert(not parsed_frame_ids.is_empty(), "角色动作帧表帧号数组不能为空: character:%d weapon:%s direction:%s action:%s" % [character.id, str(weapon), str(direction_key), str(action)])

                    var play_info := PlayInfo.new()
                    play_info.ids = parsed_frame_ids
                    var action_frame_key := Vector3i(direction, weapon_value, action_value)
                    assert(not direction_weapon_action_frames.has(action_frame_key), "角色动作帧表方向武器类型动作重复: character:%d direction:%s weapon:%s action:%s" % [character.id, str(direction_key), str(weapon), str(action)])
                    direction_weapon_action_frames[action_frame_key] = play_info

        for required_weapon in Constants.CHARACTER_WEAPON_TYPE_VALUES:
            for required_direction in Constants.DIRECTION_VALUES:
                for required_action in Constants.CHARACTER_ACTION_VALUES:
                    assert(direction_weapon_action_frames.has(Vector3i(int(required_direction), int(required_weapon), int(required_action))), "角色动作帧表缺少方向武器类型动作: character:%d direction:%s weapon:%s action:%s" % [character.id, _direction_to_key(int(required_direction)), _weapon_type_to_key(int(required_weapon)), _character_action_to_key(int(required_action))])
        character.direction_weapon_action_frames = direction_weapon_action_frames

        _by_id[character_id] = character
    assert(not _by_id.is_empty(), "角色配置中没有解析到 character 数据: %s" % Constants.CONFIG_CHARACTER_PATH)

# 配置管理流程的第二步.
# check() 只处理跨配置表, 跨管理器或配置到资源索引的关系.
# 当前角色配置的表内结构已在 load() 阶段校验, 角色到帧资源索引的关系在 assemble() 挂载帧表时校验.
func check() -> void:
    pass

# 配置管理流程的第三步.
# 资源扫描已经由 AssetsConfig 完成, assemble() 负责把同 ID 帧索引挂到 Entry 上.
# PNG 路径可由角色 ID 和资源目录常量计算, 不需要在 Entry 中常驻保存.
# 这里关心的是 character.yaml 中声明的角色 ID 和 frame id 是否能在配置 Entry 中直接找到.
func assemble() -> void:
    for character_id in _by_id:
        var character: Entry = _by_id[character_id]
        var frame_table := ConfigManager.get_shared().assets.character_frame_table_by_id.get(int(character_id), null) as AssetsConfig.FrameTable
        assert(frame_table != null, "角色缺少同 ID 可播放资源: character:%d" % int(character_id))
        character.frame_by_id = frame_table.frame_by_id

        # 逐帧检查 YAML 动作帧表和 TexturePacker 帧表是否对齐.
        # 缺帧通常说明 character.yaml 写错帧号, 或对应 .tpsheet 没有导出该 frame.
        for action_frame_key in character.direction_weapon_action_frames.keys():
            var play_info := character.direction_weapon_action_frames[action_frame_key] as PlayInfo
            assert(play_info != null, "角色播放信息类型非法: character:%d" % int(character_id))
            var key := action_frame_key as Vector3i
            var direction_key := _direction_to_key(key.x)
            var weapon_key := _weapon_type_to_key(key.y)
            var action_key := _character_action_to_key(key.z)
            for frame_id in play_info.ids:
                assert(character.frame_by_id.has(int(frame_id)), "角色动作帧表引用了不存在的可播放帧: character:%d weapon:%s direction:%s action:%s frame:%d" % [int(character_id), weapon_key, direction_key, action_key, int(frame_id)])

func _direction_from_key(key: String) -> int:
    return int(Constants.DIRECTION_BY_KEY.get(key, GPB.AssetDirection.AssetDirection_Unknow))

func _direction_to_key(direction: int) -> String:
    for key in Constants.DIRECTION_BY_KEY.keys():
        if int(Constants.DIRECTION_BY_KEY[key]) == direction:
            return str(key)
    return str(direction)

func _character_action_from_key(key: String) -> int:
    return int(Constants.CHARACTER_ACTION_BY_KEY.get(key, GPB.CharacterAction.CharacterAction_Unknow))

func _character_action_to_key(action: int) -> String:
    for key in Constants.CHARACTER_ACTION_BY_KEY.keys():
        if int(Constants.CHARACTER_ACTION_BY_KEY[key]) == action:
            return str(key)
    return str(action)

func _weapon_type_from_key(key: String) -> int:
    return int(Constants.WEAPON_TYPE_BY_KEY.get(key, GPB.CharacterWeaponType.CharacterWeaponType_Unknow))

func _weapon_type_to_key(weapon: int) -> String:
    for key in Constants.WEAPON_TYPE_BY_KEY.keys():
        if int(Constants.WEAPON_TYPE_BY_KEY[key]) == weapon:
            return str(key)
    return str(weapon)

func _assert_known_keys(data: Dictionary, allowed_keys: Array, err_msg: String) -> void:
    for raw_key in data.keys():
        var key := str(raw_key)
        assert(allowed_keys.has(key), "%s key:%s" % [err_msg, key])

func _parse_bool(value, err_msg: String) -> bool:
    assert(value is bool, "%s value:%s" % [err_msg, str(value)])
    return bool(value)

# 返回 config/character.yaml 中声明过的角色 ID.
# Godot 4 Dictionary 会保留插入顺序, 这里的 keys() 顺序与 YAML 中 character: 段的声明顺序一致.
# 调用方应通过 ConfigManager.get_shared().character 取得已经加载好的实例.
func get_ids() -> Array[int]:
    # Array[int] 中的 int 表示角色 ID.
    var ids: Array[int] = []
    for character_id in _by_id.keys():
        ids.append(int(character_id))
    return ids

# 根据角色 ID 返回单个结构化角色配置.
func get_by_id(character_id: int) -> Entry:
    var entry := _by_id.get(character_id, null) as Entry
    if entry == null:
        return null
    if entry.atlas == null: # 懒加载-角色图集
        var atlas_path := Constants.get_atlas_path(int(character_id))
        var atlas_load_started_at := Time.get_ticks_msec()
        entry.atlas = ResourceLoader.load(atlas_path) as Texture2D
        var atlas_load_elapsed_ms := Time.get_ticks_msec() - atlas_load_started_at
        print("角色图集加载完成: character:%d path:%s elapsed_ms:%d" % [int(character_id), atlas_path, atlas_load_elapsed_ms])
        assert(entry.atlas != null, "角色图集不存在: %s" % atlas_path)
    return entry
