class_name ConfigPet
extends RefCounted

# 统一读取 config/pet.yaml 的宠物配置.
# 这个类使用 MiniYAML 解析 YAML, 并同时加载 skill, attribute 和 pet 三段数据.
# pet 段会被转换为 Entry, 调用方通过 get_by_id(id) 取得结构化字段, 不需要再手动从 Dictionary 里猜 key.

# 单个宠物技能配置条目.
# 目前桌宠只需要读取技能槽位 ID, 但保留完整技能名称和描述, 方便后续 UI 或战斗逻辑直接按 ID 查询.
class SkillEntry extends RefCounted:
    var id: int
    var name: String
    var description: String

    func show() -> String:
        return name

# 宠物某个方向和动作组合下的帧配置.
# Entry.frame_entries 使用 Vector2i(direction, action) 直接定位这个对象.
# YAML 里的字符串方向和动作只在 load() 阶段出现, 进入内存后统一转成 Constants 枚举值.
class FrameDirectionActionEntry extends RefCounted:
    var direction: int = Constants.AssetDirection.AssetDirection_Unknown
    var action: int = Constants.AssetPetAction.AssetPetAction_Unknown
    var frame_ids: Array = []

# 宠物配置条目.
# 字段名称尽量贴近 config/pet.yaml 和服务端配置管理器, 这样迁移字段或对照配置时不用在多套命名之间转换.
class Entry extends RefCounted:
    var id: int
    var name: String
    var rarity: int
    var elemental: Dictionary = {}
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
    var skill_slots: Array = []
    var habitat: String
    var level1_spawn: String
    var description: String
    # Vector2i(direction, action) -> FrameDirectionActionEntry.
    # 宠物资源要求每个方向和动作组合都存在, 因此动画构建器可直接定位帧号表.
    var frame_entries: Dictionary = {}
    # 这里保存 AssetPetMgr 启动阶段创建的 AssetPetMgr.Entry 引用.
    # 它不是资源数据拷贝, 只是同一个 RefCounted 对象引用, 便于动画构建器从宠物配置直接拿到 PNG 路径和帧表.
    var asset: AssetPetMgr.Entry

    func show() -> String:
        return name

    func get_frame_entry(direction: int, action: int) -> FrameDirectionActionEntry:
        return frame_entries.get(Vector2i(direction, action), null) as FrameDirectionActionEntry

# 技能 ID -> SkillEntry.
# ConfigManager.get_shared() 首次创建共享管理器时统一加载, 后续查询复用这份内存缓存.
var _skills_by_id: Dictionary = {}

# 默认属性名 -> 默认值.
# config/pet.yaml 顶层 attribute 段是默认属性配置, 单个宠物缺少对应倍率时会用这里兜底.
var _default_attributes: Dictionary = {}

# 宠物 ID -> Entry.
# 这是主缓存, 调用方通过 get_by_id(id) 取得结构化宠物配置.
var _by_id: Dictionary = {}

# 配置管理流程的第一步.
# 只负责读取 YAML 并建立技能, 默认属性和宠物 ID 索引; 跨条目引用校验放到 check().
func load() -> void:
    var config_data := ConfigManager.load_yaml(Constants.CONFIG_PET_PATH)

    # skill 段先加载成 id -> SkillEntry.
    # pet 段的 skill_slots 只保存技能 ID, 真正的引用合法性在 check() 阶段统一验证.
    var raw_skills = config_data.get("skill", [])
    assert(raw_skills is Array, "宠物配置 skill 段不是数组: %s" % Constants.CONFIG_PET_PATH)

    for skill_item in raw_skills:
        assert(skill_item is Dictionary, "宠物技能条目须为对象: %s" % Constants.CONFIG_PET_PATH)

        var skill_entry := SkillEntry.new()
        skill_entry.id = int(skill_item.get("id", 0))
        assert(skill_entry.id > 0, "宠物技能ID非法: %d" % skill_entry.id)
        assert(not _skills_by_id.has(skill_entry.id), "宠物技能ID重复: %d" % skill_entry.id)

        skill_entry.name = str(skill_item.get("name", ""))
        assert(not skill_entry.name.is_empty(), "宠物技能名称为空: ID:%d" % skill_entry.id)
        skill_entry.description = str(skill_item.get("description", ""))
        _skills_by_id[skill_entry.id] = skill_entry

    # attribute 段是默认属性表.
    # 单个宠物 attribute 缺少倍率字段时, _parse_rate() 会从这里取默认值.
    var raw_attributes = config_data.get("attribute", [])
    assert(raw_attributes is Array, "宠物配置 attribute 段不是数组: %s" % Constants.CONFIG_PET_PATH)

    for attribute_row in raw_attributes:
        assert(attribute_row is Dictionary, "宠物默认属性条目须为对象: %s" % Constants.CONFIG_PET_PATH)
        for attribute_key in attribute_row:
            _default_attributes[str(attribute_key)] = attribute_row[attribute_key]

    # pet 段是主数据.
    # 每条记录会被转换成 Entry, 供桌宠选择, 战斗单位和动画构建器按 ID 读取.
    var raw_pets = config_data.get("pet", config_data.get("pets", []))
    assert(raw_pets is Array, "宠物配置 pet 段不是数组: %s" % Constants.CONFIG_PET_PATH)

    for pet_item in raw_pets:
        assert(pet_item is Dictionary, "宠物配置条目须为对象: %s" % Constants.CONFIG_PET_PATH)

        var entry := Entry.new()
        entry.id = int(pet_item.get("id", 0))
        assert(entry.id >= Constants.PET_ID_MIN and entry.id <= Constants.PET_ID_MAX, "宠物ID超出范围: %d" % entry.id)

        assert(not _by_id.has(entry.id), "宠物ID重复: %d" % entry.id)

        entry.name = str(pet_item.get("name", ""))
        assert(not entry.name.is_empty(), "宠物名称为空: ID:%d" % entry.id)

        entry.rarity = int(pet_item.get("rarity", 0))
        assert(entry.rarity >= Constants.RARITY_MIN and entry.rarity <= Constants.RARITY_MAX, "宠物稀有度非法: ID:%d rarity:%d" % [entry.id, entry.rarity])

        # elemental 当前要求总和为 10.
        # elemental 允许单元素, 或两个相邻元素组合; earth 和 wind 视为首尾相邻.
        # 这里只校验配置真实值, 不自动补齐缺失元素, 避免隐藏配置表问题.
        var elemental_value = pet_item.get("elemental", {})
        assert(elemental_value is Dictionary, "宠物 elemental 须为对象: ID:%d" % entry.id)
        entry.elemental = (elemental_value as Dictionary).duplicate(true)
        _check_elemental(entry)

        var attribute_value = pet_item.get("attribute", pet_item.get("attributes", {}))
        assert(attribute_value is Dictionary, "宠物 attribute 须为对象: ID:%d" % entry.id)
        var attribute_data := attribute_value as Dictionary
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

        var growth_value = pet_item.get("growth", {})
        assert(growth_value is Dictionary, "宠物 growth 须为对象: ID:%d" % entry.id)
        var growth_data := growth_value as Dictionary
        # 成长值允许小数, 因此使用 Vector2 保存 [min, max].
        entry.growth_hp = _parse_float_range(growth_data.get("hp", null), "宠物 growth.hp 非法: ID:%d" % entry.id)
        entry.growth_attack = _parse_float_range(growth_data.get("attack", null), "宠物 growth.attack 非法: ID:%d" % entry.id)
        entry.growth_defense = _parse_float_range(growth_data.get("defense", null), "宠物 growth.defense 非法: ID:%d" % entry.id)
        entry.growth_agility = _parse_float_range(growth_data.get("agility", null), "宠物 growth.agility 非法: ID:%d" % entry.id)

        var skill_slots = pet_item.get("skill", [])
        assert(skill_slots is Array, "宠物 skill 须为数组: ID:%d" % entry.id)
        entry.skill_slots = (skill_slots as Array).duplicate()
        assert(entry.skill_slots.size() == 4, "宠物 skill 须为4个槽位: ID:%d" % entry.id)

        entry.habitat = str(pet_item.get("habitat", ""))
        entry.level1_spawn = str(pet_item.get("level1Spawn", ""))
        entry.description = str(pet_item.get("description", ""))
        assert(not entry.description.is_empty(), "宠物描述为空: ID:%d" % entry.id)

        # frame 源结构是 direction -> action -> frame ids.
        # 这里把 direction 和 action 一起收敛成 FrameDirectionActionEntry, 上层可直接定位帧号表.
        var raw_frame = pet_item.get("sprite", {})
        var frame_entries := {}
        assert(raw_frame is Dictionary, "宠物 frame 须为对象: ID:%d" % entry.id)
        var frame_dict := raw_frame as Dictionary
        for frame_direction in frame_dict.keys():
            var direction := Constants.direction_from_key(str(frame_direction))
            assert(direction != Constants.AssetDirection.AssetDirection_Unknown, "宠物 frame 方向未知: pet:%d direction:%s" % [entry.id, str(frame_direction)])

            var direction_data = frame_dict[frame_direction]
            assert(direction_data is Dictionary, "宠物 frame 方向配置须为对象: pet:%d direction:%s" % [entry.id, str(frame_direction)])

            var action_dict := direction_data as Dictionary
            for frame_action in action_dict.keys():
                var action := Constants.pet_action_from_key(str(frame_action))
                assert(action != Constants.AssetPetAction.AssetPetAction_Unknown, "宠物 frame 动作未知: pet:%d direction:%s action:%s" % [entry.id, str(frame_direction), str(frame_action)])

                var frame_ids = action_dict[frame_action]
                assert(frame_ids is Array, "宠物 frame 动作配置须为帧号数组: pet:%d direction:%s action:%s" % [entry.id, str(frame_direction), str(frame_action)])

                var parsed_frame_ids := []
                for frame_id_raw in frame_ids:
                    parsed_frame_ids.append(int(frame_id_raw))

                var frame_entry := FrameDirectionActionEntry.new()
                frame_entry.direction = direction
                frame_entry.action = action
                frame_entry.frame_ids = parsed_frame_ids
                var frame_key := Vector2i(frame_entry.direction, frame_entry.action)
                assert(not frame_entries.has(frame_key), "宠物 frame 方向动作重复: pet:%d direction:%s action:%s" % [entry.id, str(frame_direction), str(frame_action)])
                frame_entries[frame_key] = frame_entry
        for required_direction in Constants.DIRECTION_VALUES:
            for required_action in Constants.PET_ACTION_VALUES:
                assert(frame_entries.has(Vector2i(int(required_direction), int(required_action))), "宠物 frame 缺少方向动作: pet:%d direction:%s action:%s" % [entry.id, Constants.direction_to_key(int(required_direction)), Constants.pet_action_to_key(int(required_action))])
        entry.frame_entries = frame_entries

        _by_id[entry.id] = entry

# 配置管理流程的第二步.
# 这里检查是否读到宠物数据, 校验技能槽位引用, 并校验宠物配置引用的资源帧是否存在.
func check() -> void:
    if _by_id.is_empty():
        push_warning("宠物配置中没有解析到 pet 数据: %s" % Constants.CONFIG_PET_PATH)
    if _skills_by_id.is_empty():
        push_warning("宠物配置中没有解析到 skill 数据: %s" % Constants.CONFIG_PET_PATH)

    # skill_slots 允许 0 表示空槽位.
    # 非 0 ID 必须能在 skill 段找到, 否则后续 UI 或战斗逻辑会拿不到技能定义.
    for pet_id in _by_id:
        var entry: Entry = _by_id[pet_id]
        for slot in entry.skill_slots:
            var skill_id := int(slot)
            if skill_id == 0:
                continue
            assert(_skills_by_id.has(skill_id), "宠物引用了未定义技能: pet:%d skill:%d" % [pet_id, skill_id])

    var asset_manager := ConfigManager.get_shared().asset_manager
    assert(asset_manager != null, "宠物配置校验缺少 AssetManager")

    var pet_mgr := asset_manager.pet_mgr
    assert(pet_mgr != null, "宠物配置校验缺少 AssetPetMgr")

    # AssetPetMgr.load() 已经确保 PNG 和 .tpsheet 可用.
    # 这里验证 pet.yaml 引用的宠物 ID 和 frame id 都能在资源索引中找到.
    for asset_pet_id in _by_id:
        var asset_entry: Entry = _by_id[asset_pet_id]
        var pet_asset := pet_mgr.get_by_id(asset_entry.id)
        assert(pet_asset != null, "宠物缺少资源: pet:%d missing:[png]" % asset_entry.id)

        # 逐帧检查 YAML 动作表和 TexturePacker 帧表是否对齐.
        # 缺帧通常说明 pet.yaml 写错帧号, 或对应 .tpsheet 没有导出该 frame.
        for frame_value in asset_entry.frame_entries.values():
            var frame_entry := frame_value as FrameDirectionActionEntry
            assert(frame_entry != null, "宠物 frame entry 类型非法: pet:%d" % asset_entry.id)
            var direction_key := Constants.direction_to_key(frame_entry.direction)
            var action_key := Constants.pet_action_to_key(frame_entry.action)
            for frame_id in frame_entry.frame_ids:
                assert(pet_asset.sheet_frames.has(int(frame_id)), "宠物 frame 引用了不存在的可播放帧: pet:%d direction:%s action:%s frame:%d" % [asset_entry.id, direction_key, action_key, int(frame_id)])

# 配置管理流程的第三步.
# 这里把 Entry 和同 ID AssetPetMgr.Entry 组装到一起.
# check() 已经确认 pet.yaml 引用的资源和帧都存在, 所以这里只保存引用, 不再复制 sheet_frames 或 PNG 路径.
func assemble() -> void:
    for pet_id in _by_id.keys():
        var pet := _by_id[pet_id] as Entry
        pet.asset = ConfigManager.get_shared().asset_manager.pet_mgr.get_by_id(int(pet_id))
        assert(pet.asset != null, "宠物配置组装缺少资源引用: pet:%d" % int(pet_id))

# 校验宠物元素配置.
# config/pet.yaml 中允许省略某些元素, 省略项按 0 处理; 但出现的 key 必须属于 earth/water/fire/wind.
# 有效配置必须满足: 每个元素是 [0, 10] 的整数, 总和为 10, 且正值元素只能是 1 个或 2 个相邻元素.
func _check_elemental(entry: Entry) -> void:
    var elemental_sum := 0
    var active_indexes: Array[int] = []

    for raw_key in entry.elemental.keys():
        var elemental_key := str(raw_key)
        assert(Constants.ELEMENT_KEYS.has(elemental_key), "宠物 elemental 元素未知: ID:%d key:%s" % [entry.id, elemental_key])

    for elemental_index in range(Constants.ELEMENT_KEYS.size()):
        var elemental_key := str(Constants.ELEMENT_KEYS[elemental_index])
        var raw_value = entry.elemental.get(elemental_key, 0)
        assert(raw_value is int, "宠物 elemental 值必须为整数: ID:%d key:%s value:%s" % [entry.id, elemental_key, str(raw_value)])

        var elemental_value := int(raw_value)
        assert(elemental_value >= 0 and elemental_value <= 10, "宠物 elemental 值必须在[0,10]: ID:%d key:%s value:%d" % [entry.id, elemental_key, elemental_value])

        elemental_sum += elemental_value
        if elemental_value > 0:
            active_indexes.append(elemental_index)

    assert(elemental_sum == 10, "宠物元素分配总和须为10: ID:%d sum:%d" % [entry.id, elemental_sum])

    var active_keys: Array[String] = []
    for active_index in active_indexes:
        active_keys.append(str(Constants.ELEMENT_KEYS[int(active_index)]))

    var active_count := active_indexes.size()
    assert(active_count == 1 or active_count == 2, "宠物 elemental 只能是单元素或两个相邻元素: ID:%d active:%s" % [entry.id, str(active_keys)])
    if active_count == 2:
        var distance: int = absi(int(active_indexes[0]) - int(active_indexes[1]))
        var wrap_distance: int = Constants.ELEMENT_KEYS.size() - 1
        var is_adjacent: bool = distance == 1 or distance == wrap_distance
        assert(is_adjacent, "宠物 elemental 两个元素必须相邻: ID:%d active:%s" % [entry.id, str(active_keys)])

# 解析整数范围配置.
# value 来自 YAML 中的 `[min, max]` 数组, err_msg 是调用方传入的字段级错误说明.
# 返回 Vector2i(min, max), 供生命、攻击、防御和敏捷这类整数基础属性直接使用.
func _parse_int_range(value, err_msg: String) -> Vector2i:
    # 宠物基础属性里的 hp/attack/defense/agility 必须写成 `[min, max]`.
    # 这里先检查 Variant 的真实类型, 配置错误必须在启动读取阶段直接暴露.
    assert(value is Array, err_msg)

    var values := value as Array
    # 只消费前两个元素作为最小值和最大值.
    # 少于两个值说明配置不完整, 继续解析会产生误导性的属性范围.
    assert(values.size() >= 2, err_msg)

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
    # 成长范围至少需要最小值和最大值; 额外元素当前不消费, 避免过早设计复杂格式.
    assert(values.size() >= 2, err_msg)

    # 保留 YAML 中的小数精度, 用 Vector2 表示 `[min, max]` 成长区间.
    return Vector2(float(values[0]), float(values[1]))

# 解析宠物倍率属性.
# attribute_data 是单个宠物的 attribute 字典, key 是要读取的倍率字段名, err_msg 是字段级错误说明.
# 返回范围为 [0, 1] 的 float; 单个宠物未配置时会读取顶层默认 attribute, 再缺失则按 0.0 处理.
func _parse_rate(attribute_data: Dictionary, key: String, err_msg: String) -> float:
    # 单个宠物未配置某个倍率时, 使用顶层 attribute 段加载出的默认值兜底.
    # 如果默认表也没有该字段, 使用 0.0, 让缺失字段在范围断言和后续业务中表现一致.
    var rate := float(attribute_data.get(key, _default_attributes.get(key, 0.0)))
    # 当前倍率字段都按百分比区间处理, 有效范围是 [0, 1].
    # 超出范围通常意味着配置单位写错, 例如把 12% 写成了 12.
    assert(rate >= 0.0 and rate <= 1.0, "%s %s:%f" % [err_msg, key, rate])
    return rate

# 返回 config/pet.yaml 中声明过的技能 ID.
func get_skill_ids() -> Array[int]:
    var ids: Array[int] = []
    for skill_id in _skills_by_id.keys():
        ids.append(int(skill_id))
    return ids

# 根据技能 ID 返回单个技能配置.
func get_skill(skill_id: int) -> SkillEntry:
    return _skills_by_id.get(skill_id, null) as SkillEntry

# 返回默认属性表副本.
# 调用方可以读取默认值, 但不应该通过返回值修改 ConfigPet 内部缓存.
func get_default_attributes() -> Dictionary:
    return _default_attributes.duplicate()

# 根据属性名返回默认属性值.
func get_default_attribute(attribute_name: String, fallback = null):
    return _default_attributes.get(attribute_name, fallback)

# 返回 config/pet.yaml 中声明过的宠物 ID.
# Godot 4 Dictionary 会保留插入顺序, 这里的 keys() 顺序与 YAML 中 pet 段的声明顺序一致.
# 调用方应通过 ConfigManager.get_shared().config_pet 取得已经加载好的实例.
func get_ids() -> Array[int]:
    var ids: Array[int] = []
    for pet_id in _by_id.keys():
        ids.append(int(pet_id))
    return ids

# 根据宠物 ID 返回结构化宠物配置.
# 例如 get_by_id(4000101).name, get_by_id(4000101).hp_range, get_by_id(4000101).skill_slots.
func get_by_id(pet_id: int) -> Entry:
    return _by_id.get(pet_id, null) as Entry
