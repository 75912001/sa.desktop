class_name ConfigEnemyGroup
extends RefCounted

# 统一读取 config/enemy.group.yaml 的敌人组配置.
# 这个类使用 MiniYAML 解析 YAML, 只消费 enemyGroups: 段, 并转换成结构化敌人组条目.

const GROUP_KEYS := ["id", "name", "isBoss", "countRange", "levelRange", "roleLevelOffset", "captured", "babyRate", "enemies"]
const ENEMY_KEYS := ["id", "weight", "level"]

class EnemyEntry extends RefCounted:
    var id: int
    var weight: int
    var level: int

class EnemyGroupEntry extends RefCounted:
    var id: int
    var name: String
    var is_boss: bool = false
    var count_range: Vector2i = Vector2i(1, 1)
    var level_range: Vector2i = Vector2i(1, 1)
    var role_level_offset: Vector2i = Vector2i.ZERO
    var captured: bool = true
    var baby_rate: int
    var enemies: Array[EnemyEntry] = []

# 按敌人组 ID 建立的主缓存.
# Dictionary[int, EnemyGroupEntry] 的 int 表示 config/enemy.group.yaml 中 enemyGroups 段的敌人组 ID.
# 配置加载后常驻内存只保留这一份 id -> EnemyGroupEntry.
# 这个缓存由 ConfigManager.get_shared() 首次创建共享管理器时统一加载.
var _by_id: Dictionary[int, EnemyGroupEntry] = {}

# 配置管理流程的第一步.
# 读取 YAML 并按 enemyGroups: 段的声明顺序写入 ID 索引.
# 同一配置文件内的结构, 字段, 范围和 Boss/普通组规则必须在这里校验并尽早暴露.
func load() -> void:
    var config_data := ConfigManager.load_yaml(Constants.CONFIG_ENEMY_GROUP_PATH)
    assert(config_data.has("enemyGroups"), "敌人组配置缺少 enemyGroups 段: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)
    var groups = config_data.get("enemyGroups", [])
    assert(groups is Array, "敌人组配置 enemyGroups 段不是数组: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)
    assert(not (groups as Array).is_empty(), "敌人组配置中没有解析到 enemyGroups 数据: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)

    # enemyGroups 是战斗敌方模板的主数据.
    # 每条记录转换成 EnemyGroupEntry, 之后 CombatScene 只按结构体字段读取, 不直接访问 YAML 字典.
    for raw_group in groups:
        assert(raw_group is Dictionary, "敌人组条目须为对象: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)

        # 基础字段控制敌人组名称, 是否 Boss, 数量范围, 等级范围和捕捉相关参数.
        # 范围字段统一解析成 Vector2i, 让战斗逻辑可以直接使用 Godot 原生类型.
        var raw_group_dict := raw_group as Dictionary
        _assert_known_keys(raw_group_dict, GROUP_KEYS, "敌人组字段未知")
        assert(raw_group_dict.has("id"), "敌人组缺少 id: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)
        assert(raw_group_dict.has("name"), "敌人组缺少 name: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)
        assert(raw_group_dict.has("enemies"), "敌人组缺少 enemies: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)

        var group := EnemyGroupEntry.new()
        group.id = _parse_int(raw_group_dict.get("id", null), "敌人组ID非法")
        assert(group.id > 0, "敌人组ID非法: %d" % group.id)
        assert(not _by_id.has(group.id), "敌人组ID重复: %d" % group.id)
        group.name = str(raw_group_dict.get("name", ""))
        assert(not group.name.is_empty(), "敌人组名称为空: group:%d" % group.id)

        group.is_boss = _parse_bool(raw_group_dict.get("isBoss", false), "敌人组 isBoss 非法: group:%d" % group.id)
        if group.is_boss:
            _assert_absent(raw_group_dict, "countRange", "Boss 敌人组 countRange 无效, 不应配置: group:%d" % group.id)
            _assert_absent(raw_group_dict, "levelRange", "Boss 敌人组 levelRange 无效, 不应配置: group:%d" % group.id)
            _assert_absent(raw_group_dict, "roleLevelOffset", "Boss 敌人组 roleLevelOffset 无效, 不应配置: group:%d" % group.id)
            _assert_absent(raw_group_dict, "captured", "Boss 敌人组 captured 无效, 不应配置: group:%d" % group.id)
            _assert_absent(raw_group_dict, "babyRate", "Boss 敌人组 babyRate 无效, 不应配置: group:%d" % group.id)
            group.captured = false
            group.baby_rate = 0
        else:
            assert(raw_group_dict.has("countRange"), "普通敌人组缺少 countRange: group:%d" % group.id)
            assert(raw_group_dict.has("levelRange") or raw_group_dict.has("roleLevelOffset"), "普通敌人组缺少 levelRange 或 roleLevelOffset: group:%d" % group.id)
            group.count_range = _parse_int_range(raw_group_dict.get("countRange", null), "敌人组 countRange 非法: group:%d" % group.id)
            _assert_range_bounds(group.count_range, GPB.CombatEnemyGroupEnemyCountRange.CombatEnemyGroupEnemyCountRange_Min, GPB.CombatEnemyGroupEnemyCountRange.CombatEnemyGroupEnemyCountRange_Max, "敌人组 countRange 超出范围: group:%d" % group.id)
            if raw_group_dict.has("levelRange"):
                group.level_range = _parse_int_range(raw_group_dict.get("levelRange", null), "敌人组 levelRange 非法: group:%d" % group.id)
                _assert_range_bounds(group.level_range, GPB.LevelRange.LevelRange_Min, GPB.LevelRange.LevelRange_Max, "敌人组 levelRange 超出范围: group:%d" % group.id)
            if raw_group_dict.has("roleLevelOffset"):
                group.role_level_offset = _parse_int_range(raw_group_dict.get("roleLevelOffset", null), "敌人组 roleLevelOffset 非法: group:%d" % group.id)
            group.captured = _parse_bool(raw_group_dict.get("captured", true), "敌人组 captured 非法: group:%d" % group.id)
            group.baby_rate = _parse_int(raw_group_dict.get("babyRate", 0), "敌人组 babyRate 非法: group:%d" % group.id)
            assert(group.baby_rate >= GPB.CombatEnemyGroupBabyRate.CombatEnemyGroupBabyRate_Min and group.baby_rate <= GPB.CombatEnemyGroupBabyRate.CombatEnemyGroupBabyRate_Max, "敌人组 babyRate 超出范围: group:%d value:%d" % [group.id, group.baby_rate])

        # enemies 中的 id 复用 pet.yaml 里的宠物 ID.
        # 这里只解析成 EnemyEntry, 引用是否合法放到 check() 阶段统一验证.
        var raw_enemies = raw_group_dict.get("enemies", [])
        var enemies: Array[EnemyEntry] = []
        assert(raw_enemies is Array, "敌人组 enemies 须为数组: group:%d" % group.id)
        assert(not (raw_enemies as Array).is_empty(), "敌人组 enemies 不能为空: group:%d" % group.id)
        assert((raw_enemies as Array).size() <= GPB.CombatEnemyGroupEnemyCountRange.CombatEnemyGroupEnemyCountRange_Max, "敌人组 enemies 超过最大站位数量: group:%d size:%d" % [group.id, (raw_enemies as Array).size()])

        for raw_enemy in raw_enemies:
            assert(raw_enemy is Dictionary, "敌人组 enemy 须为对象: group:%d" % group.id)
            var enemy_data := raw_enemy as Dictionary
            _assert_known_keys(enemy_data, ENEMY_KEYS, "敌人组 enemy 字段未知: group:%d" % group.id)
            assert(enemy_data.has("id"), "敌人组 enemy 缺少 id: group:%d" % group.id)
            var enemy := EnemyEntry.new()
            enemy.id = _parse_int(enemy_data.get("id", null), "敌人组 enemy id 非法: group:%d" % group.id)
            assert(enemy.id > 0, "敌人组 enemy id 非法: group:%d enemy:%d" % [group.id, enemy.id])
            if group.is_boss:
                _assert_absent(enemy_data, "weight", "Boss 敌人组 enemy.weight 无效, 不应配置: group:%d enemy:%d" % [group.id, enemy.id])
                assert(enemy_data.has("level"), "Boss 敌人组 enemy 必须指定 level: group:%d enemy:%d" % [group.id, enemy.id])
                enemy.level = _parse_int(enemy_data.get("level", null), "Boss 敌人组 enemy level 非法: group:%d enemy:%d" % [group.id, enemy.id])
                assert(enemy.level >= GPB.LevelRange.LevelRange_Min and enemy.level <= GPB.LevelRange.LevelRange_Max, "Boss 敌人组 enemy level 超出范围: group:%d enemy:%d level:%d" % [group.id, enemy.id, enemy.level])
                enemy.weight = 0
            else:
                enemy.weight = _parse_int(enemy_data.get("weight", 0), "敌人组 enemy weight 非法: group:%d enemy:%d" % [group.id, enemy.id])
                assert(enemy.weight >= 0, "敌人组 enemy weight 不能为负数: group:%d enemy:%d weight:%d" % [group.id, enemy.id, enemy.weight])
                if enemy_data.has("level"):
                    enemy.level = _parse_int(enemy_data.get("level", null), "敌人组 enemy level 非法: group:%d enemy:%d" % [group.id, enemy.id])
                    assert(enemy.level >= GPB.LevelRange.LevelRange_Min and enemy.level <= GPB.LevelRange.LevelRange_Max, "敌人组 enemy level 超出范围: group:%d enemy:%d level:%d" % [group.id, enemy.id, enemy.level])
            enemies.append(enemy)
        group.enemies = enemies

        _by_id[group.id] = group

# 配置管理流程的第二步.
# 检查是否读到了敌人组数据, 并校验敌人组引用的宠物配置是否存在.
func check(pet_config: ConfigPet = null) -> void:
    if pet_config != null:
        # 敌人条目复用宠物模板配置.
        # 这里仅确认敌人组引用的宠物模板 ID 已在 pet.yaml 中声明.
        # 使用 has_id() 避免配置检查阶段触发宠物图集懒加载.
        for group_id in _by_id:
            var group: EnemyGroupEntry = _by_id[group_id]
            for enemy in group.enemies:
                var enemy_entry := enemy as EnemyEntry
                if enemy_entry == null:
                    continue
                var pet_id := enemy_entry.id
                assert(pet_config.has_id(pet_id), "敌人组引用了未定义宠物: group:%d pet:%d" % [int(group_id), pet_id])

# 配置管理流程的第三步.
# 当前敌人组配置没有额外派生缓存, 所以保留空实现, 保持和其它配置类一致的生命周期.
func assemble() -> void:
    pass

func _assert_known_keys(data: Dictionary, allowed_keys: Array, err_msg: String) -> void:
    for raw_key in data.keys():
        var key := str(raw_key)
        assert(allowed_keys.has(key), "%s key:%s" % [err_msg, key])

func _assert_absent(data: Dictionary, key: String, err_msg: String) -> void:
    assert(not data.has(key), err_msg)

func _parse_int(value, err_msg: String) -> int:
    assert(value is int, "%s value:%s" % [err_msg, str(value)])
    return int(value)

func _parse_bool(value, err_msg: String) -> bool:
    assert(value is bool, "%s value:%s" % [err_msg, str(value)])
    return bool(value)

func _parse_int_range(value, err_msg: String) -> Vector2i:
    # 敌人组范围字段写成 [min, max].
    # 格式非法时直接 assert 暴露配置表错误, 不返回兜底值掩盖问题.
    assert(value is Array, err_msg)
    var values := value as Array
    assert(values.size() == 2, err_msg)
    assert(values[0] is int and values[1] is int, err_msg)
    var parsed_range := Vector2i(int(values[0]), int(values[1]))
    assert(parsed_range.x <= parsed_range.y, "%s min:%d max:%d" % [err_msg, parsed_range.x, parsed_range.y])
    return parsed_range

func _assert_range_bounds(value: Vector2i, min_value: int, max_value: int, err_msg: String) -> void:
    assert(value.x >= min_value and value.y <= max_value, "%s range:%s expected:[%d,%d]" % [err_msg, str(value), min_value, max_value])

# 返回 config/enemy.group.yaml 中声明过的敌人组 ID.
# Godot 4 Dictionary 会保留插入顺序, 这里的 keys() 顺序与 YAML 中 enemyGroups: 段的声明顺序一致.
# 调用方应通过 ConfigManager.get_shared().enemy_group 取得已经加载好的实例.
func get_enemy_group_ids() -> Array[int]:
    # Array[int] 中的 int 表示敌人组 ID.
    var ids: Array[int] = []
    for group_id in _by_id.keys():
        ids.append(int(group_id))
    return ids

# 根据敌人组 ID 返回单个结构化敌人组配置.
func get_enemy_group(group_id: int) -> EnemyGroupEntry:
    return _by_id.get(group_id, null) as EnemyGroupEntry
