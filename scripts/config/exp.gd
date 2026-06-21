class_name ConfigExp
extends RefCounted

# 统一读取 config/exp.yaml 的经验等级配置.
# 经验表只依赖单个 YAML 文件, load() 阶段完成结构, 连续性和区间合法性校验;
# 运行期查询只消费已经排序好的 LevelEntry 数组, 不再直接访问原始 YAML 字典.

const LEVEL_KEYS := ["min", "max"]

# 单个等级经验区间.
# min_exp 和 max_exp 都表示角色或宠物已经累计获得的总经验, 而不是本级内经验.
class LevelEntry extends RefCounted:
    var level: int
    var min_exp: int
    var max_exp: int

# 按等级数字建立的临时索引, 用于 load() 阶段做重复和连续性校验.
# Dictionary[int, LevelEntry] 的 int 表示 config/exp.yaml 中 levels 段的等级.
var _by_level: Dictionary[int, LevelEntry] = {}

# 按等级从小到大排列的运行期查询表.
# 当前最高等级只有 140, 线性查找足够直接且更容易审查边界行为.
var _levels: Array[LevelEntry] = []

# 当前配置中的最高等级.
# load() 完成后写入, 查询接口用它判断是否还有下一等级.
var _max_level := 0

# 配置管理流程的第一步.
# 读取 levels 段, 校验每个等级都有 min/max, 等级从 1 连续递增, 经验区间连续且不重叠.
func load() -> void:
    var config_data := ConfigManager.load_yaml(Constants.CONFIG_EXP_PATH)
    assert(config_data.has("levels"), "经验配置缺少 levels 段: %s" % Constants.CONFIG_EXP_PATH)
    var raw_levels = config_data.get("levels", {})
    assert(raw_levels is Dictionary, "经验配置 levels 段不是对象: %s" % Constants.CONFIG_EXP_PATH)
    assert(not (raw_levels as Dictionary).is_empty(), "经验配置中没有解析到 levels 数据: %s" % Constants.CONFIG_EXP_PATH)

    var level_numbers: Array[int] = []
    var raw_level_data_by_key := raw_levels as Dictionary
    for raw_level_key in raw_level_data_by_key.keys():
        var level := _parse_level_key(raw_level_key)
        assert(level > 0, "经验等级非法: %s" % str(raw_level_key))
        assert(not _by_level.has(level), "经验等级重复: %d" % level)

        var raw_level_data = raw_level_data_by_key[raw_level_key]
        assert(raw_level_data is Dictionary, "经验等级条目须为对象: level:%d" % level)
        var level_data := raw_level_data as Dictionary
        _assert_known_keys(level_data, LEVEL_KEYS, "经验等级字段未知: level:%d" % level)
        assert(level_data.has("min"), "经验等级缺少 min: level:%d" % level)
        assert(level_data.has("max"), "经验等级缺少 max: level:%d" % level)

        var entry := LevelEntry.new()
        entry.level = level
        entry.min_exp = _parse_int(level_data.get("min", null), "经验等级 min 非法: level:%d" % level)
        entry.max_exp = _parse_int(level_data.get("max", null), "经验等级 max 非法: level:%d" % level)
        assert(entry.min_exp >= 0, "经验等级 min 不能为负数: level:%d min:%d" % [level, entry.min_exp])
        assert(entry.min_exp <= entry.max_exp, "经验等级 min 不能大于 max: level:%d min:%d max:%d" % [level, entry.min_exp, entry.max_exp])

        _by_level[level] = entry
        level_numbers.append(level)

    level_numbers.sort()
    assert(level_numbers[0] == 1, "经验等级必须从 1 开始: first:%d" % level_numbers[0])

    var expected_level := 1
    var previous: LevelEntry = null
    for level in level_numbers:
        assert(level == expected_level, "经验等级必须连续: expected:%d actual:%d" % [expected_level, level])

        var entry: LevelEntry = _by_level[level]
        if previous == null:
            assert(entry.min_exp == 0, "经验等级 1 的 min 必须为 0: min:%d" % entry.min_exp)
        else:
            assert(entry.min_exp == previous.max_exp + 1, "经验等级区间必须连续: level:%d min:%d previous_max:%d" % [level, entry.min_exp, previous.max_exp])

        _levels.append(entry)
        previous = entry
        expected_level += 1

    _max_level = _levels[_levels.size() - 1].level

# 配置管理流程的第二步.
# 经验配置没有跨表引用, 单表结构和区间连续性已在 load() 阶段完成.
func check() -> void:
    pass

# 配置管理流程的第三步.
# 经验配置没有额外派生缓存, 保留空实现以匹配配置管理生命周期.
func assemble() -> void:
    pass

# 根据总经验返回所在等级.
# total_exp 是累计总经验, 小于 0 属于调用方数据错误, 直接 assert 暴露.
func get_level(total_exp: int) -> int:
    assert(total_exp >= 0, "总经验不能为负数: %d" % total_exp)
    _assert_loaded()

    for entry in _levels:
        if total_exp <= entry.max_exp:
            return entry.level

    return _max_level

# 根据当前总经验返回下一等级要求达到的总经验.
# 最高等级没有下一等级, 返回 -1 让调用方可以明确区分“没有下一等级”和“下一等级经验为 0”.
func get_next_level_total_exp(total_exp: int) -> int:
    var level := get_level(total_exp)
    if level >= _max_level:
        return -1

    var next_level := level + 1
    var next_entry: LevelEntry = _by_level[next_level]
    return next_entry.min_exp

# 判断当前总经验是否已经处于最高等级区间.
func is_max_level(total_exp: int) -> bool:
    return get_level(total_exp) >= _max_level

func _parse_level_key(value) -> int:
    if value is int:
        return int(value)
    if value is String and (value as String).strip_edges().is_valid_int():
        return int(value)
    assert(false, "经验等级 key 必须是整数: %s" % str(value))
    return 0

func _parse_int(value, err_msg: String) -> int:
    assert(value is int, "%s value:%s" % [err_msg, str(value)])
    return int(value)

func _assert_known_keys(data: Dictionary, allowed_keys: Array, err_msg: String) -> void:
    for raw_key in data.keys():
        var key := str(raw_key)
        assert(allowed_keys.has(key), "%s key:%s" % [err_msg, key])

func _assert_loaded() -> void:
    assert(not _levels.is_empty(), "经验配置尚未加载.")
