class_name ConfigEnemyGroup
extends RefCounted

# 统一读取 config/enemy.group.yaml 的敌人组配置.
# 这个类使用 MiniYAML 解析 YAML, 只消费 enemyGroups: 段, 并转换成结构化敌人组条目.

class EnemyEntry extends RefCounted:
    var id: int
    var weight: int
    var level: int

class EnemyGroupEntry extends RefCounted:
    var id: int
    var name: String
    var is_boss: bool
    var count_range: Vector2i = Vector2i(1, 1)
    var level_range: Vector2i = Vector2i(1, 1)
    var role_level_offset: Vector2i = Vector2i.ZERO
    var captured: bool = true
    var baby_rate: int
    var enemies: Array = []

# 按敌人组 ID 建立的主缓存.
# 配置加载后常驻内存只保留这一份 id -> EnemyGroupEntry.
# 这个缓存由 ConfigManager.get_shared() 首次创建共享管理器时统一加载.
var _by_id: Dictionary = {}

# 配置管理流程的第一步.
# 只负责读取 YAML 并按 enemyGroups: 段的声明顺序写入 ID 索引; 业务校验和派生组装放到后续阶段.
func load() -> void:
    var config_data := ConfigManager.load_yaml(Constants.CONFIG_ENEMY_GROUP_PATH)
    var groups = config_data.get("enemyGroups", [])
    assert(groups is Array, "敌人组配置 enemyGroups 段不是数组: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)

    # enemyGroups 是战斗敌方模板的主数据.
    # 每条记录转换成 EnemyGroupEntry, 之后 BattleScene 只按结构体字段读取, 不直接访问 YAML 字典.
    for raw_group in groups:
        assert(raw_group is Dictionary, "敌人组条目须为对象: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)

        # 基础字段控制敌人组名称, 是否 Boss, 数量范围, 等级范围和捕捉相关参数.
        # 范围字段统一解析成 Vector2i, 让战斗逻辑可以直接使用 Godot 原生类型.
        var raw_group_dict := raw_group as Dictionary
        var group := EnemyGroupEntry.new()
        group.id = int(raw_group_dict.get("id", 0))
        group.name = str(raw_group_dict.get("name", ""))
        group.is_boss = bool(raw_group_dict.get("isBoss", false))
        group.count_range = _parse_int_range(raw_group_dict.get("countRange", [1, 1]), "敌人组 countRange 非法: group:%d" % group.id)
        group.level_range = _parse_int_range(raw_group_dict.get("levelRange", [1, 1]), "敌人组 levelRange 非法: group:%d" % group.id)
        group.role_level_offset = _parse_int_range(raw_group_dict.get("roleLevelOffset", [0, 0]), "敌人组 roleLevelOffset 非法: group:%d" % group.id)
        group.captured = bool(raw_group_dict.get("captured", true))
        group.baby_rate = int(raw_group_dict.get("babyRate", 0))

        # enemies 中的 id 复用 pet.yaml 里的宠物 ID.
        # 这里只解析成 EnemyEntry, 引用是否合法放到 check() 阶段统一验证.
        var raw_enemies = raw_group_dict.get("enemies", [])
        var enemies := []
        assert(raw_enemies is Array, "敌人组 enemies 须为数组: group:%d" % group.id)

        for raw_enemy in raw_enemies:
            assert(raw_enemy is Dictionary, "敌人组 enemy 须为对象: group:%d" % group.id)
            var enemy_data := raw_enemy as Dictionary
            var enemy := EnemyEntry.new()
            enemy.id = int(enemy_data.get("id", 0))
            enemy.weight = int(enemy_data.get("weight", 0))
            enemy.level = int(enemy_data.get("level", 0))
            enemies.append(enemy)
        group.enemies = enemies

        # group.id 是战斗入口选择敌人组的 key.
        # 非法或重复 ID 会让默认敌人组和测试场景无法稳定定位, 因此写入缓存前立刻校验.
        var group_id := group.id
        assert(group_id > 0, "敌人组ID非法: %d" % group_id)
        assert(not _by_id.has(group_id), "敌人组ID重复: %d" % group_id)
        _by_id[group_id] = group

# 配置管理流程的第二步.
# 检查是否读到了敌人组数据, 并校验敌人组引用的宠物配置和宠物资源是否存在.
func check(pet_config: ConfigPet = null, asset_manager: AssetManager = null) -> void:
    if _by_id.is_empty():
        push_warning("敌人组配置中没有解析到 enemyGroups 数据: %s" % Constants.CONFIG_ENEMY_GROUP_PATH)

    if pet_config != null:
        # 敌人模板复用宠物配置和宠物资源.
        # check() 阶段同时确认 pet.yaml 中有该宠物, AssetPetMgr 中也有同 ID 可播放资源.
        for group_id in _by_id:
            var group: EnemyGroupEntry = _by_id[group_id]
            for enemy in group.enemies:
                var enemy_entry := enemy as EnemyEntry
                if enemy_entry == null:
                    continue
                var pet_id := enemy_entry.id
                assert(pet_config.get_by_id(pet_id) != null, "敌人组引用了未定义宠物: group:%d pet:%d" % [int(group_id), pet_id])
                if asset_manager != null:
                    var pet_asset := asset_manager.pet_mgr.get_by_id(pet_id)
                    assert(pet_asset != null, "敌人组引用的宠物资源不存在: group:%d pet:%d missing:[png]" % [int(group_id), pet_id])

# 配置管理流程的第三步.
# 当前敌人组配置没有额外派生缓存, 所以保留空实现, 保持和其它配置类一致的生命周期.
func assemble() -> void:
    pass

func _parse_int_range(value, err_msg: String) -> Vector2i:
    # 敌人组范围字段写成 [min, max].
    # 格式非法时直接 assert 暴露配置表错误, 不返回兜底值掩盖问题.
    assert(value is Array, err_msg)
    var values := value as Array
    assert(values.size() >= 2, err_msg)
    return Vector2i(int(values[0]), int(values[1]))

# 返回 config/enemy.group.yaml 中声明过的敌人组 ID.
# Godot 4 Dictionary 会保留插入顺序, 这里的 keys() 顺序与 YAML 中 enemyGroups: 段的声明顺序一致.
# 调用方应通过 ConfigManager.get_shared().config_enemy_group 取得已经加载好的实例.
func get_enemy_group_ids() -> Array[int]:
    var ids: Array[int] = []
    for group_id in _by_id.keys():
        ids.append(int(group_id))
    return ids

# 根据敌人组 ID 返回单个结构化敌人组配置.
func get_enemy_group(group_id: int) -> EnemyGroupEntry:
    return _by_id.get(group_id, null) as EnemyGroupEntry

# 判断指定敌人组 ID 是否存在于配置中.
func has_enemy_group(group_id: int) -> bool:
    return _by_id.has(group_id)
