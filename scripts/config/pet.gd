class_name ConfigPet
extends RefCounted

# 统一读取 config/pet.yaml 的宠物配置.
# 这个类使用 MiniYAML 解析 YAML, 并同时加载 skill, attribute 和 pet 三段数据.
# pet 段会被转换为 Entry, 调用方通过 get_by_id(id) 取得结构化字段, 不需要再手动从 Dictionary 里猜 key.

# 单个宠物技能配置条目.
# 当前业务主要读取技能槽位 ID, 但保留完整技能名称和描述, 方便后续 UI 或战斗逻辑直接按 ID 查询.
class SkillEntry extends RefCounted:
    var id: int
    var name: String
    var description: String

    func show() -> String:
        return name

# 宠物某个方向和动作组合下的播放缓存.
# key 由 Entry.direction_action_frames 使用 Vector2i(direction, action) 直接定位.
class PlayInfo extends RefCounted:
    # Array[int] 中的 int 表示 YAML sprite 动作帧表里的 frame_id, ids 顺序就是播放顺序.
    var ids: Array[int] = []

# 宠物配置条目.
# 字段名称尽量贴近 config/pet.yaml 和服务端配置管理器, 这样迁移字段或对照配置时不用在多套命名之间转换.
class Entry extends RefCounted:
    var id: int
    var name: String
    var rarity: int
    # Array[int] 固定按 Constants.ELEMENT_ORDER 的 proto 元素枚举顺序保存元素点数, 方便运行期按下标直接读取.
    var elemental: Array[int] = []
    var hp_range: Vector2i
    var attack_range: Vector2i
    var defense_range: Vector2i
    var agility_range: Vector2i
    var crit_rate: float
    var counter_rate: float
    var dodge_rate: float
    var hit_rate: float
    var crit_damage_bonus_rate: float
    var status_resist_rate: float
    var growth_hp: Vector2
    var growth_attack: Vector2
    var growth_defense: Vector2
    var growth_agility: Vector2
    # Array[int] 中的 int 表示技能 ID, 0 表示空技能槽位.
    var skill_slots: Array[int] = []
    var habitat: String
    var level1_spawn: String
    var description: String
    # Vector2i(direction, action) -> PlayInfo.
    # Vector2i.x 是 proto AssetDirection 枚举值, Vector2i.y 是 proto PetAction 枚举值.
    # 宠物资源要求每个方向和动作组合都存在, 因此播放缓存可直接定位帧号表.
    var direction_action_frames: Dictionary[Vector2i, PlayInfo] = {}
    # frame_id -> TexturePackerFrame.
    # Dictionary[int, TexturePackerFrame] 的 int 表示 YAML 动画帧表引用的 frame_id.
    # 这是 `.tpsheet` 的 region/margin/offset 合成后的帧索引.
    # Entry 直接持有这份索引引用, PlayInfo 只保存帧号序列, 不复制每帧 TexturePackerFrame.
    var frame_by_id: Dictionary[int, TexturePackerFrame] = {}
    var atlas: Texture2D

    func get_play_info(direction: int, action: int) -> PlayInfo:
        var play_key := Vector2i(direction, action)
        return direction_action_frames[play_key] as PlayInfo

# 技能 ID -> SkillEntry.
# Dictionary[int, SkillEntry] 的 int 表示 config/pet.yaml 中 skill 段的技能 ID.
# ConfigManager.get_shared() 首次创建共享管理器时统一加载, 后续查询复用这份内存缓存.
var _skills_by_id: Dictionary[int, SkillEntry] = {}

# 默认属性名 -> 默认值.
# config/pet.yaml 顶层 attribute 段是默认属性配置, 单个宠物缺少对应倍率时会用这里兜底.
var _default_attributes: Dictionary[String, Variant] = {}

# 宠物 ID -> Entry.
# Dictionary[int, Entry] 的 int 表示 config/pet.yaml 中 pet 段的宠物 ID.
# 这是主缓存, 调用方通过 get_by_id(id) 取得结构化宠物配置.
var _by_id: Dictionary[int, Entry] = {}

# 配置管理流程的第一步.
# 读取 YAML 并建立技能, 默认属性和宠物 ID 索引.
# 资源帧表已由 AssetsConfig 统一加载; 本函数只解析 YAML 字段和方向, 动作到帧号序列的关系.
func load() -> void:
    var config_data := ConfigManager.load_yaml(Constants.CONFIG_PET_PATH)

    # skill 段先加载成 id -> SkillEntry.
    # pet 段的 skill_slots 只保存技能 ID, 同一 pet.yaml 内的技能引用合法性在本次 load() 中校验.
    var raw_skills = config_data.get("skill", [])
    assert(raw_skills is Array, "宠物配置 skill 段不是数组: %s" % Constants.CONFIG_PET_PATH)

    for skill_item in raw_skills:
        assert(skill_item is Dictionary, "宠物技能条目须为对象: %s" % Constants.CONFIG_PET_PATH)
        var skill_data := skill_item as Dictionary

        var skill_entry := SkillEntry.new()
        skill_entry.id = int(skill_data.get("id", 0))
        assert(skill_entry.id > 0, "宠物技能ID非法: %d" % skill_entry.id)
        assert(not _skills_by_id.has(skill_entry.id), "宠物技能ID重复: %d" % skill_entry.id)

        skill_entry.name = str(skill_data.get("name", ""))
        assert(not skill_entry.name.is_empty(), "宠物技能名称为空: ID:%d" % skill_entry.id)
        skill_entry.description = str(skill_data.get("description", ""))
        assert(not skill_entry.description.is_empty(), "宠物描述为空: ID:%d" % skill_entry.id)
        _skills_by_id[skill_entry.id] = skill_entry

    # attribute 段是默认倍率属性表.
    # 这里只接受配置表声明的固定字段, 单个宠物 attribute 缺少倍率字段时, _parse_rate() 会从这里取默认值.
    var raw_attributes = config_data.get("attribute", [])
    assert(raw_attributes is Array, "宠物配置 attribute 段不是数组: %s" % Constants.CONFIG_PET_PATH)

    for attribute_row in raw_attributes:
        assert(attribute_row is Dictionary, "宠物默认属性条目须为对象: %s" % Constants.CONFIG_PET_PATH)
        var attribute_row_data := attribute_row as Dictionary
        assert(attribute_row_data.size() == 1, "宠物默认属性条目必须只包含一个字段: %s row:%s" % [Constants.CONFIG_PET_PATH, str(attribute_row_data)])
        for raw_attribute_key in attribute_row_data:
            var attribute_key := str(raw_attribute_key)
            assert(Constants.DEFAULT_RATE_ATTRIBUTE_KEYS.has(attribute_key), "宠物默认属性字段未知: %s key:%s" % [Constants.CONFIG_PET_PATH, attribute_key])
            assert(not _default_attributes.has(attribute_key), "宠物默认属性字段重复: %s key:%s" % [Constants.CONFIG_PET_PATH, attribute_key])
            var attribute_value = attribute_row_data[raw_attribute_key]
            _default_attributes[attribute_key] = _parse_rate_value(attribute_value, "宠物默认属性值非法: %s key:%s" % [Constants.CONFIG_PET_PATH, attribute_key])
    for required_attribute_key in Constants.DEFAULT_RATE_ATTRIBUTE_KEYS:
        assert(_default_attributes.has(required_attribute_key), "宠物默认属性字段缺失: %s key:%s" % [Constants.CONFIG_PET_PATH, required_attribute_key])

    # pet 段是主数据.
    # 每条记录会被转换成 Entry, 供战斗单位和动画构建器按 ID 读取.
    assert(config_data.has("pet"), "宠物配置缺少 pet 段: %s" % Constants.CONFIG_PET_PATH)
    var raw_pets = config_data.get("pet", [])
    assert(raw_pets is Array, "宠物配置 pet 段不是数组: %s" % Constants.CONFIG_PET_PATH)

    for pet_item in raw_pets:
        assert(pet_item is Dictionary, "宠物配置条目须为对象: %s" % Constants.CONFIG_PET_PATH)
        var pet_data := pet_item as Dictionary

        var entry := Entry.new()
        entry.id = int(pet_data.get("id", 0))
        assert(Constants.is_pet_id(entry.id), "宠物ID超出范围: %d" % entry.id)

        assert(not _by_id.has(entry.id), "宠物ID重复: %d" % entry.id)

        entry.name = str(pet_data.get("name", ""))
        assert(not entry.name.is_empty(), "宠物名称为空: ID:%d" % entry.id)

        entry.rarity = int(pet_data.get("rarity", 0))
        assert(entry.rarity >= GPB.PetRarity.PetRarity_Common and entry.rarity <= GPB.PetRarity.PetRarity_Mythic, "宠物稀有度非法: ID:%d rarity:%d" % [entry.id, entry.rarity])

        # pet.yaml 中 elemental 仍使用 earth/water/fire/wind 对象表达.
        # 读取时先转换为 proto AssetElemental, 再按 Constants.ELEMENT_ORDER 写入固定顺序数组.
        var elemental_value = pet_data.get("elemental", {})
        assert(elemental_value is Dictionary, "宠物 elemental 须为对象: ID:%d" % entry.id)
        var elemental_data := elemental_value as Dictionary
        for _elemental_index in range(Constants.ELEMENT_ORDER.size()):
            entry.elemental.append(0)
        for raw_elemental_key in elemental_data.keys():
            var elemental_key := str(raw_elemental_key)
            var elemental_enum := elemental_from_key(elemental_key)
            assert(elemental_enum != GPB.AssetElemental.AssetElemental_Unknow, "宠物 elemental 元素未知: ID:%d key:%s" % [entry.id, elemental_key])
            entry.elemental[Constants.ELEMENT_ORDER.find(elemental_enum)] = int(elemental_data[raw_elemental_key])
        _check_elemental(entry)

        assert(pet_data.has("attribute"), "宠物 attribute 缺失: ID:%d" % entry.id)
        var attribute_value = pet_data.get("attribute", {})
        assert(attribute_value is Dictionary, "宠物 attribute 须为对象: ID:%d" % entry.id)
        var attribute_data := attribute_value as Dictionary
        _check_pet_attribute_keys(attribute_data, entry.id)
        # 基础属性使用整数区间, 倍率字段使用 [0, 1] 浮点值.
        # 解析函数会在格式错误时 assert, 让配置错误在启动阶段暴露.
        entry.hp_range = _parse_int_range(attribute_data.get("hp", null), "宠物 hp 范围非法: ID:%d" % entry.id)
        entry.attack_range = _parse_int_range(attribute_data.get("attack", null), "宠物 attack 范围非法: ID:%d" % entry.id)
        entry.defense_range = _parse_int_range(attribute_data.get("defense", null), "宠物 defense 范围非法: ID:%d" % entry.id)
        entry.agility_range = _parse_int_range(attribute_data.get("agility", null), "宠物 agility 范围非法: ID:%d" % entry.id)
        entry.crit_rate = _parse_rate(attribute_data, "critRate", "宠物 critRate 范围非法: ID:%d" % entry.id)
        entry.counter_rate = _parse_rate(attribute_data, "counterRate", "宠物 counterRate 范围非法: ID:%d" % entry.id)
        entry.dodge_rate = _parse_rate(attribute_data, "dodgeRate", "宠物 dodgeRate 范围非法: ID:%d" % entry.id)
        entry.hit_rate = _parse_rate(attribute_data, "hitRate", "宠物 hitRate 范围非法: ID:%d" % entry.id)
        entry.crit_damage_bonus_rate = _parse_rate(attribute_data, "critDamageBonusRate", "宠物 critDamageBonusRate 范围非法: ID:%d" % entry.id)
        entry.status_resist_rate = _parse_rate(attribute_data, "statusResistRate", "宠物 statusResistRate 范围非法: ID:%d" % entry.id)

        var growth_value = pet_data.get("growth", {})
        assert(growth_value is Dictionary, "宠物 growth 须为对象: ID:%d" % entry.id)
        var growth_data := growth_value as Dictionary
        # 成长值允许小数, 因此使用 Vector2 保存 [min, max].
        entry.growth_hp = _parse_float_range(growth_data.get("hp", null), "宠物 growth.hp 非法: ID:%d" % entry.id)
        entry.growth_attack = _parse_float_range(growth_data.get("attack", null), "宠物 growth.attack 非法: ID:%d" % entry.id)
        entry.growth_defense = _parse_float_range(growth_data.get("defense", null), "宠物 growth.defense 非法: ID:%d" % entry.id)
        entry.growth_agility = _parse_float_range(growth_data.get("agility", null), "宠物 growth.agility 非法: ID:%d" % entry.id)

        var skill_slots = pet_data.get("skill", [])
        assert(skill_slots is Array, "宠物 skill 须为数组: ID:%d" % entry.id)
        var skill_slot_values := skill_slots as Array
        for skill_slot in skill_slot_values:
            entry.skill_slots.append(int(skill_slot))
        assert(0 < entry.skill_slots.size(), "宠物 skill 须大于 0 个槽位: ID:%d" % entry.id)
        # skill_slots 允许 0 表示空槽位.
        # 非 0 ID 必须能在 skill 段找到, 否则后续 UI 或战斗逻辑会拿不到技能定义.
        for slot in entry.skill_slots:
            var skill_id := int(slot)
            if skill_id == 0:
                continue
            assert(_skills_by_id.has(skill_id), "宠物引用了未定义技能: pet:%d skill:%d" % [entry.id, skill_id])

        entry.habitat = str(pet_data.get("habitat", ""))
        assert(not entry.habitat.is_empty(), "宠物栖息地为空: ID:%d" % entry.id)
        entry.level1_spawn = str(pet_data.get("level1Spawn", ""))
        assert(not entry.level1_spawn.is_empty(), "宠物1级出生地为空: ID:%d" % entry.id)
        entry.description = str(pet_data.get("description", ""))
        assert(not entry.description.is_empty(), "宠物描述为空: ID:%d" % entry.id)

        # sprite 字段的动作帧表源结构是 direction -> action -> frame ids.
        # 这里把 direction 和 action 一起收敛成 direction_action_frames 的 key, 播放缓存可直接定位帧号序列.
        var raw_action_frames = pet_data.get("sprite", {})
        # Dictionary[Vector2i, PlayInfo] 的 Vector2i 为 (direction 枚举值, pet_action 枚举值).
        var direction_action_frames: Dictionary[Vector2i, PlayInfo] = {}
        assert(raw_action_frames is Dictionary, "宠物动作帧表须为对象: ID:%d" % entry.id)
        var action_frame_dict := raw_action_frames as Dictionary
        for direction_key in action_frame_dict.keys():
            var direction := _direction_from_key(str(direction_key))
            assert(direction != GPB.AssetDirection.AssetDirection_Unknow, "宠物动作帧表方向未知: pet:%d direction:%s" % [entry.id, str(direction_key)])

            var direction_data = action_frame_dict[direction_key]
            assert(direction_data is Dictionary, "宠物动作帧表方向配置须为对象: pet:%d direction:%s" % [entry.id, str(direction_key)])

            var action_dict := direction_data as Dictionary
            for action_key in action_dict.keys():
                var action := _pet_action_from_key(str(action_key))
                assert(action != GPB.PetAction.PetAction_Unknow, "宠物动作帧表动作未知: pet:%d direction:%s action:%s" % [entry.id, str(direction_key), str(action_key)])

                var frame_ids = action_dict[action_key]
                assert(frame_ids is Array, "宠物动作帧表动作配置须为帧号数组: pet:%d direction:%s action:%s" % [entry.id, str(direction_key), str(action_key)])

                # Array[int] 中的 int 表示当前 direction/action 对应的 frame_id.
                var parsed_frame_ids: Array[int] = []
                for frame_id_raw in frame_ids:
                    parsed_frame_ids.append(int(frame_id_raw))
                assert(not parsed_frame_ids.is_empty(), "宠物动作帧表帧号数组不能为空: pet:%d direction:%s action:%s" % [entry.id, str(direction_key), str(action_key)])

                var play_info := PlayInfo.new()
                play_info.ids = parsed_frame_ids
                var action_frame_key := Vector2i(direction, action)
                assert(not direction_action_frames.has(action_frame_key), "宠物动作帧表方向动作重复: pet:%d direction:%s action:%s" % [entry.id, str(direction_key), str(action_key)])
                direction_action_frames[action_frame_key] = play_info
        for required_direction in Constants.DIRECTION_VALUES:
            for required_action in Constants.PET_ACTION_VALUES:
                assert(direction_action_frames.has(Vector2i(int(required_direction), int(required_action))), "宠物动作帧表缺少方向动作: pet:%d direction:%s action:%s" % [entry.id, _direction_to_key(int(required_direction)), _pet_action_to_key(int(required_action))])
        entry.direction_action_frames = direction_action_frames

        _by_id[entry.id] = entry
    assert(not _by_id.is_empty(), "宠物配置中没有解析到 pet 数据: %s" % Constants.CONFIG_PET_PATH)
    assert(not _skills_by_id.is_empty(), "宠物配置中没有解析到 skill 数据: %s" % Constants.CONFIG_PET_PATH)

# 配置管理流程的第二步.
# check() 只处理跨配置表, 跨管理器或配置到资源索引的关系.
# 当前宠物配置的表内结构和同文件 skill 引用已在 load() 阶段校验, 宠物到帧资源索引的关系在 assemble() 挂载帧表时校验.
func check() -> void:
    pass

# 配置管理流程的第三步.
# 资源扫描已经由 AssetsConfig 完成, assemble() 负责把同 ID 帧索引挂到 Entry 上.
func assemble() -> void:
    for pet_id in _by_id.keys():
        var pet := _by_id[pet_id] as Entry
        var frame_table := ConfigManager.get_shared().assets.pet_frame_table_by_id.get(int(pet_id), null) as AssetsConfig.FrameTable
        assert(frame_table != null, "宠物缺少同 ID 可播放资源: pet:%d" % int(pet_id))
        pet.frame_by_id = frame_table.frame_by_id

        # 逐帧检查 YAML 动作帧表和 TexturePacker 帧表是否对齐.
        # 缺帧通常说明 pet.yaml 写错帧号, 或对应 .tpsheet 没有导出该 frame.
        for action_frame_key in pet.direction_action_frames.keys():
            var play_info := pet.direction_action_frames[action_frame_key] as PlayInfo
            assert(play_info != null, "宠物播放信息类型非法: pet:%d" % int(pet_id))
            var key := action_frame_key as Vector2i
            var direction_key := _direction_to_key(key.x)
            var action_key := _pet_action_to_key(key.y)
            for frame_id in play_info.ids:
                assert(pet.frame_by_id.has(int(frame_id)), "宠物动作帧表引用了不存在的可播放帧: pet:%d direction:%s action:%s frame:%d" % [int(pet_id), direction_key, action_key, int(frame_id)])

# 校验宠物元素配置.
# Entry.elemental 是固定长度数组, 下标顺序对应 Constants.ELEMENT_ORDER 中的 proto AssetElemental 枚举.
# 有效配置必须满足: 每个元素是 [0, 10] 的整数, 总和为 10, 且正值元素只能是 1 个或 2 个相邻元素.
func _check_elemental(entry: Entry) -> void:
    assert(entry.elemental.size() == Constants.ELEMENT_ORDER.size(), "宠物 elemental 数组长度非法: ID:%d size:%d" % [entry.id, entry.elemental.size()])

    var elemental_sum := 0
    var active_indexes: Array[int] = []

    for elemental_index in range(Constants.ELEMENT_ORDER.size()):
        var elemental_key := get_elemental_key(int(Constants.ELEMENT_ORDER[elemental_index]))
        var raw_value = entry.elemental[elemental_index]
        assert(raw_value is int, "宠物 elemental 值必须为整数: ID:%d key:%s value:%s" % [entry.id, elemental_key, str(raw_value)])

        var elemental_value := int(raw_value)
        assert(elemental_value >= 0 and elemental_value <= 10, "宠物 elemental 值必须在[0,10]: ID:%d key:%s value:%d" % [entry.id, elemental_key, elemental_value])

        elemental_sum += elemental_value
        if elemental_value > 0:
            active_indexes.append(elemental_index)

    assert(elemental_sum == 10, "宠物元素分配总和须为10: ID:%d sum:%d" % [entry.id, elemental_sum])

    var active_keys: Array[String] = []
    for active_index in active_indexes:
        active_keys.append(get_elemental_key(int(Constants.ELEMENT_ORDER[int(active_index)])))

    var active_count := active_indexes.size()
    assert(active_count == 1 or active_count == 2, "宠物 elemental 只能是单元素或两个相邻元素: ID:%d active:%s" % [entry.id, str(active_keys)])
    if active_count == 2:
        var distance: int = absi(int(active_indexes[0]) - int(active_indexes[1]))
        var wrap_distance: int = Constants.ELEMENT_ORDER.size() - 1
        var is_adjacent: bool = distance == 1 or distance == wrap_distance
        assert(is_adjacent, "宠物 elemental 两个元素必须相邻: ID:%d active:%s" % [entry.id, str(active_keys)])

static func elemental_from_key(key: String) -> int:
    return int(Constants.ELEMENT_ENUM_BY_KEY.get(key, GPB.AssetElemental.AssetElemental_Unknow))

static func get_elemental_key(elemental: int) -> String:
    return str(Constants.ELEMENT_KEY_BY_ENUM.get(elemental, str(elemental)))

static func get_elemental_label(elemental: int) -> String:
    return str(Constants.ELEMENT_LABEL_BY_ENUM.get(elemental, get_elemental_key(elemental)))

# 校验单个宠物 attribute 段字段名.
# 基础区间字段必须显式配置; 倍率字段允许省略并继承顶层默认 attribute, 但不允许出现配置表之外的临时字段.
func _check_pet_attribute_keys(attribute_data: Dictionary, pet_id: int) -> void:
    for raw_attribute_key in attribute_data.keys():
        var attribute_key := str(raw_attribute_key)
        assert(Constants.PET_BASE_ATTRIBUTE_KEYS.has(attribute_key) or Constants.DEFAULT_RATE_ATTRIBUTE_KEYS.has(attribute_key), "宠物 attribute 字段未知: ID:%d key:%s" % [pet_id, attribute_key])
    for required_attribute_key in Constants.PET_BASE_ATTRIBUTE_KEYS:
        assert(attribute_data.has(required_attribute_key), "宠物 attribute 基础字段缺失: ID:%d key:%s" % [pet_id, required_attribute_key])

func _direction_from_key(key: String) -> int:
    return int(Constants.DIRECTION_BY_KEY.get(key, GPB.AssetDirection.AssetDirection_Unknow))

func _direction_to_key(direction: int) -> String:
    for key in Constants.DIRECTION_BY_KEY.keys():
        if int(Constants.DIRECTION_BY_KEY[key]) == direction:
            return str(key)
    return str(direction)

func _pet_action_from_key(key: String) -> int:
    return int(Constants.PET_ACTION_BY_KEY.get(key, GPB.PetAction.PetAction_Unknow))

func _pet_action_to_key(action: int) -> String:
    for key in Constants.PET_ACTION_BY_KEY.keys():
        if int(Constants.PET_ACTION_BY_KEY[key]) == action:
            return str(key)
    return str(action)

# 解析整数范围配置.
# value 来自 YAML 中的 `[min, max]` 数组, err_msg 是调用方传入的字段级错误说明.
# 返回 Vector2i(min, max), 供生命、攻击、防御和敏捷这类整数基础属性直接使用.
func _parse_int_range(value, err_msg: String) -> Vector2i:
    # 宠物基础属性里的 hp/attack/defense/agility 必须写成 `[min, max]`.
    # 这里先检查 Variant 的真实类型, 配置错误必须在启动读取阶段直接暴露.
    assert(value is Array, err_msg)

    var values := value as Array
    # 只消费前两个元素作为最小值和最大值.
    # 不等于两个值说明配置不完整, 继续解析会产生误导性的属性范围.
    assert(values.size() == 2, err_msg)

    # YAML 解析出的数字可能是 int/float 等 Variant 数值, 统一转成 Vector2i 供后续数值逻辑直接使用.
    return Vector2i(int(values[0]), int(values[1]))

# 解析浮点范围配置.
# value 来自 YAML 中的 `[min, max]` 数组, err_msg 是调用方传入的字段级错误说明.
# 返回 Vector2(min, max), 供成长值这类允许小数的属性区间使用.
func _parse_float_range(value, err_msg: String) -> Vector2:
    # 宠物成长属性允许小数, 因此和基础属性范围分开解析为 Vector2.
    # 这里同样要求 YAML 写成 `[min, max]`, 不接受单值或对象形式.
    assert(value is Array, err_msg)

    var values := value as Array
    # 成长范围需要最小值和最大值; 额外元素当前不消费, 避免过早设计复杂格式.
    assert(values.size() == 2, err_msg)

    # 保留 YAML 中的小数精度, 用 Vector2 表示 `[min, max]` 成长区间.
    return Vector2(float(values[0]), float(values[1]))

# 解析宠物倍率数值.
# 顶层默认 attribute 和单宠物倍率字段都使用相同规则: 必须是数值, 且有效范围是 [0, 1].
func _parse_rate_value(value, err_msg: String) -> float:
    assert(value is int or value is float, "%s value:%s" % [err_msg, str(value)])
    var rate := float(value)
    # 超出范围通常意味着配置单位写错, 例如把 12% 写成了 12.
    assert(rate >= 0.0 and rate <= 1.0, "%s value:%f" % [err_msg, rate])
    return rate

# 解析宠物倍率属性.
# attribute_data 是单个宠物的 attribute 字典, key 是要读取的倍率字段名, err_msg 是字段级错误说明.
# 返回范围为 [0, 1] 的 float; 单个宠物未配置时会读取顶层默认 attribute, 默认表缺失表示配置契约错误.
func _parse_rate(attribute_data: Dictionary, key: String, err_msg: String) -> float:
    # 单个宠物未配置某个倍率时, 使用顶层 attribute 段加载出的默认值兜底.
    assert(_default_attributes.has(key), "宠物默认属性字段缺失: key:%s" % key)
    var raw_rate = attribute_data.get(key, _default_attributes[key])
    return _parse_rate_value(raw_rate, "%s key:%s" % [err_msg, key])

# 返回 config/pet.yaml 中声明过的技能 ID.
func get_skill_ids() -> Array[int]:
    # Array[int] 中的 int 表示技能 ID.
    var ids: Array[int] = []
    for skill_id in _skills_by_id.keys():
        ids.append(int(skill_id))
    return ids

# 根据技能 ID 返回单个技能配置.
func get_skill(skill_id: int) -> SkillEntry:
    return _skills_by_id.get(skill_id, null) as SkillEntry

# 返回默认属性表副本.
# 调用方可以读取默认值, 但不应该通过返回值修改 ConfigPet 内部缓存.
func get_default_attributes() -> Dictionary[String, Variant]:
    return _default_attributes.duplicate()

# 根据属性名返回默认属性值.
func get_default_attribute(attribute_name: String, fallback = null):
    return _default_attributes.get(attribute_name, fallback)

# 返回 config/pet.yaml 中声明过的宠物 ID.
# Godot 4 Dictionary 会保留插入顺序, 这里的 keys() 顺序与 YAML 中 pet 段的声明顺序一致.
# 调用方应通过 ConfigManager.get_shared().pet 取得已经加载好的实例.
func get_ids() -> Array[int]:
    # Array[int] 中的 int 表示宠物 ID.
    var ids: Array[int] = []
    for pet_id in _by_id.keys():
        ids.append(int(pet_id))
    return ids

# 判断 config/pet.yaml 是否声明了指定宠物 ID.
# 这个函数只查 ID 索引, 不会触发 get_by_id() 的图集懒加载.
func has_id(pet_id: int) -> bool:
    return _by_id.has(pet_id)

# 根据宠物 ID 返回结构化宠物配置.
# 例如 get_by_id(4000101).name, get_by_id(4000101).hp_range, get_by_id(4000101).skill_slots.
func get_by_id(pet_id: int) -> Entry:
    var entry := _by_id.get(pet_id, null) as Entry
    if entry == null:
        return null
    if entry.atlas == null:
        var atlas_path := Constants.get_atlas_path(int(pet_id))
        var atlas_load_started_at := Time.get_ticks_msec()
        entry.atlas = ResourceLoader.load(atlas_path) as Texture2D
        var atlas_load_elapsed_ms := Time.get_ticks_msec() - atlas_load_started_at
        print("宠物图集加载完成: pet:%d path:%s elapsed_ms:%d" % [int(pet_id), atlas_path, atlas_load_elapsed_ms])
        assert(entry.atlas != null, "宠物图集不存在: %s" % atlas_path)
    return entry
