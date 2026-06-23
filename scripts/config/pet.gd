class_name ConfigPet
extends RefCounted

# 统一读取 config/pet.yaml 的宠物配置.
# 这个类使用 MiniYAML 解析 YAML, 只加载 pet 段宠物主体数据.
# 技能定义由 ConfigPetSkill 读取 config/pet.skill.yaml, 本类只保存每个宠物的技能槽位 ID.
# pet 段会被转换为 Entry, 调用方通过 get_by_id(id) 取得结构化字段, 不需要再手动从 Dictionary 里猜 key.

# 宠物某个方向和动作组合下的播放缓存.
# key 由 Entry.direction_action_frames 使用 Vector2i(direction, action) 直接定位.
class PlayInfo extends RefCounted:
    # Array[int] 中的 int 表示 YAML sprite 动作帧表里的 frame_id, ids 顺序就是播放顺序.
    var ids: Array[int] = []

# 宠物原始属性配置.
# 字段直接对应 config/pet.yaml 的 attribute 段, 保存 pet_growth_8_0.csv 的抗性和暴击/反击原始整数值.
class AttributeEntry extends RefCounted:
    var poison_resist: int
    var paralysis_resist: int
    var sleep_resist: int
    var stone_resist: int
    var drunk_resist: int
    var confusion_resist: int
    var critical: int
    var counter: int

# 宠物原始成长配置.
# 字段直接对应 config/pet.yaml 的 growth 段, 用于后续按石器时代原始规则计算初始四维和升级四维.
class GrowthEntry extends RefCounted:
    var init_num: int
    var lvup_point_source: float
    var base_vital: int
    var base_str: int
    var base_tough: int
    var base_dex: int

# 宠物配置条目.
# 字段名称尽量贴近 config/pet.yaml 和服务端配置管理器, 这样迁移字段或对照配置时不用在多套命名之间转换.
class Entry extends RefCounted:
    var id: int
    var name: String
    var rarity: int
    # Array[int] 固定按 Constants.ELEMENT_ORDER 的 proto 元素枚举顺序保存元素点数, 方便运行期按下标直接读取.
    var elemental: Array[int] = []
    var attribute: AttributeEntry
    var growth: GrowthEntry
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

# 宠物 ID -> Entry.
# Dictionary[int, Entry] 的 int 表示 config/pet.yaml 中 pet 段的宠物 ID.
# 这是主缓存, 调用方通过 get_by_id(id) 取得结构化宠物配置.
var _by_id: Dictionary[int, Entry] = {}

# 配置管理流程的第一步.
# 读取 YAML 并建立宠物 ID 索引.
# 资源帧表已由 AssetsConfig 统一加载; 本函数只解析 YAML 字段和方向, 动作到帧号序列的关系.
func load() -> void:
    var config_data := ConfigManager.load_yaml(Constants.CONFIG_PET_PATH)

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
        assert(Share.is_pet_id(entry.id), "宠物ID超出范围: %d" % entry.id)

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
        for raw_attribute_key in attribute_data.keys():
            var attribute_key := str(raw_attribute_key)
            assert(Constants.PET_ATTRIBUTE_KEYS.has(attribute_key), "宠物 attribute 字段未知: ID:%d key:%s" % [entry.id, attribute_key])
        for required_attribute_key in Constants.PET_ATTRIBUTE_KEYS:
            assert(attribute_data.has(required_attribute_key), "宠物 attribute 字段缺失: ID:%d key:%s" % [entry.id, required_attribute_key])
        # attribute
        # 抗性允许负数
        entry.attribute = AttributeEntry.new()
        entry.attribute.poison_resist = _parse_int(attribute_data.get("poisonResist", null), "宠物 poisonResist 非法: ID:%d" % entry.id)
        entry.attribute.paralysis_resist = _parse_int(attribute_data.get("paralysisResist", null), "宠物 paralysisResist 非法: ID:%d" % entry.id)
        entry.attribute.sleep_resist = _parse_int(attribute_data.get("sleepResist", null), "宠物 sleepResist 非法: ID:%d" % entry.id)
        entry.attribute.stone_resist = _parse_int(attribute_data.get("stoneResist", null), "宠物 stoneResist 非法: ID:%d" % entry.id)
        entry.attribute.drunk_resist = _parse_int(attribute_data.get("drunkResist", null), "宠物 drunkResist 非法: ID:%d" % entry.id)
        entry.attribute.confusion_resist = _parse_int(attribute_data.get("confusionResist", null), "宠物 confusionResist 非法: ID:%d" % entry.id)
        entry.attribute.critical = _parse_int(attribute_data.get("critical", null), "宠物 critical 非法: ID:%d" % entry.id)
        entry.attribute.counter = _parse_int(attribute_data.get("counter", null), "宠物 counter 非法: ID:%d" % entry.id)

        # growth
        var growth_value = pet_data.get("growth", {})
        assert(growth_value is Dictionary, "宠物 growth 须为对象: ID:%d" % entry.id)
        var growth_data := growth_value as Dictionary
        var allowed_growth_keys := ["initNum", "lvupPointSource", "baseVital", "baseStr", "baseTough", "baseDex"]
        for raw_growth_key in growth_data.keys():
            var growth_key := str(raw_growth_key)
            assert(allowed_growth_keys.has(growth_key), "宠物 growth 字段未知: ID:%d key:%s" % [entry.id, growth_key])
        for required_growth_key in allowed_growth_keys:
            assert(growth_data.has(required_growth_key), "宠物 growth 字段缺失: ID:%d key:%s" % [entry.id, required_growth_key])

        entry.growth = GrowthEntry.new()
        entry.growth.init_num = _parse_non_negative_int(growth_data.get("initNum", null), "宠物 growth.initNum 非法: ID:%d" % entry.id)
        var lvup_point_source := str(growth_data.get("lvupPointSource", ""))
        assert(lvup_point_source.is_valid_float(), "宠物 growth.lvupPointSource 非法: ID:%d value:%s" % [entry.id, lvup_point_source])
        entry.growth.lvup_point_source = float(lvup_point_source)
        assert(entry.growth.lvup_point_source > 0.0, "宠物 growth.lvupPointSource 必须大于0: ID:%d value:%s" % [entry.id, lvup_point_source])
        entry.growth.base_vital = _parse_non_negative_int(growth_data.get("baseVital", null), "宠物 growth.baseVital 非法: ID:%d" % entry.id)
        entry.growth.base_str = _parse_non_negative_int(growth_data.get("baseStr", null), "宠物 growth.baseStr 非法: ID:%d" % entry.id)
        entry.growth.base_tough = _parse_non_negative_int(growth_data.get("baseTough", null), "宠物 growth.baseTough 非法: ID:%d" % entry.id)
        entry.growth.base_dex = _parse_non_negative_int(growth_data.get("baseDex", null), "宠物 growth.baseDex 非法: ID:%d" % entry.id)
        assert(entry.growth.base_vital + GPetCalculator.PET_SAVED_BASE_RANDOM_MIN > 0, "宠物 growth.baseVital 加随机最小偏移后必须大于0: ID:%d baseVital:%d min:%d" % [entry.id, entry.growth.base_vital, GPetCalculator.PET_SAVED_BASE_RANDOM_MIN])
        assert(entry.growth.base_str + GPetCalculator.PET_SAVED_BASE_RANDOM_MIN > 0, "宠物 growth.baseStr 加随机最小偏移后必须大于0: ID:%d baseStr:%d min:%d" % [entry.id, entry.growth.base_str, GPetCalculator.PET_SAVED_BASE_RANDOM_MIN])
        assert(entry.growth.base_tough + GPetCalculator.PET_SAVED_BASE_RANDOM_MIN > 0, "宠物 growth.baseTough 加随机最小偏移后必须大于0: ID:%d baseTough:%d min:%d" % [entry.id, entry.growth.base_tough, GPetCalculator.PET_SAVED_BASE_RANDOM_MIN])
        assert(entry.growth.base_dex + GPetCalculator.PET_SAVED_BASE_RANDOM_MIN > 0, "宠物 growth.baseDex 加随机最小偏移后必须大于0: ID:%d baseDex:%d min:%d" % [entry.id, entry.growth.base_dex, GPetCalculator.PET_SAVED_BASE_RANDOM_MIN])

        assert(pet_data.has("skill"), "宠物 skill 缺失: ID:%d" % entry.id)
        var skill_slots = pet_data.get("skill", [])
        assert(skill_slots is Array, "宠物 skill 须为数组: ID:%d" % entry.id)
        var skill_slot_values := skill_slots as Array
        assert(not skill_slot_values.is_empty(), "宠物 skill 须大于 0 个槽位: ID:%d" % entry.id)
        for skill_slot in skill_slot_values:
            entry.skill_slots.append(_parse_skill_slot(skill_slot, entry.id))

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

# 配置管理流程的第二步.
# check() 只处理跨配置表, 跨管理器或配置到资源索引的关系.
# 宠物技能槽位引用 pet.skill.yaml, 属于跨配置文件引用, 在这里统一校验.
func check(petskill: ConfigPetSkill) -> void:
    assert(petskill != null, "宠物技能配置管理器不能为空.")
    for pet_id in _by_id.keys():
        var entry := _by_id[pet_id] as Entry
        assert(entry != null, "宠物配置缓存类型非法: pet:%d" % int(pet_id))
        # skill_slots 允许 0 表示空槽位.
        # 非 0 ID 必须能在 pet.skill.yaml 找到, 否则后续 UI 或战斗逻辑会拿不到技能定义.
        for slot in entry.skill_slots:
            var skill_id := int(slot)
            if skill_id == 0:
                continue
            assert(petskill.has_id(skill_id), "宠物引用了未定义技能: pet:%d skill:%d" % [entry.id, skill_id])

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

# 解析非负整数配置. growth 中的初始系数和基础四维都是原始整数配置, 负数或小数没有业务意义.
func _parse_non_negative_int(value, err_msg: String) -> int:
    assert(value is int or value is float, "%s value:%s" % [err_msg, str(value)])
    var numeric_value := float(value)
    var parsed_value := int(numeric_value)
    assert(numeric_value == float(parsed_value), "%s value:%s" % [err_msg, str(value)])
    assert(parsed_value >= 0, "%s value:%d" % [err_msg, parsed_value])
    return parsed_value

# 解析原始整数配置.
# 抗性字段可能为负数, 所以这里只要求数值是整数形态.
func _parse_int(value, err_msg: String) -> int:
    assert(value is int or value is float, "%s value:%s" % [err_msg, str(value)])
    var numeric_value := float(value)
    var parsed_value := int(numeric_value)
    assert(numeric_value == float(parsed_value), "%s value:%s" % [err_msg, str(value)])
    return parsed_value

# 解析宠物技能槽位. 0 表示空槽位; 非 0 值只在 load() 校验 ID 段, 是否已定义交给 check(petskill) 做跨表校验.
func _parse_skill_slot(value, pet_id: int) -> int:
    var skill_id := _parse_int(value, "宠物 skill 槽位非法: ID:%d" % pet_id)
    assert(skill_id == 0 or Share.is_pet_skill_id(skill_id), "宠物 skill 槽位ID超出范围: ID:%d skill:%d" % [pet_id, skill_id])
    return skill_id

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
# 例如 get_by_id(4000101).name, get_by_id(4000101).growth, get_by_id(4000101).skill_slots.
func get_by_id(pet_id: int) -> Entry:
    var entry := _by_id.get(pet_id, null) as Entry
    if entry == null:
        return null
    if entry.atlas == null:
        var atlas_path := Share.get_atlas_path(int(pet_id))
        var atlas_load_started_at := Time.get_ticks_msec()
        entry.atlas = ResourceLoader.load(atlas_path) as Texture2D
        var atlas_load_elapsed_ms := Time.get_ticks_msec() - atlas_load_started_at
        print("宠物图集加载完成: pet:%d path:%s elapsed_ms:%d" % [int(pet_id), atlas_path, atlas_load_elapsed_ms])
        assert(entry.atlas != null, "宠物图集不存在: %s" % atlas_path)
    return entry
