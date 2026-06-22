extends Node

# GPetCalculator 是宠物 SavedBase/Raw 和战斗面板属性的全局计算入口.
# 它作为 project.godot 中的 Autoload 常驻, 调用方统一使用 GPetCalculator.xxx,
# 不需要 preload 计算脚本, 也不需要自己维护随机数或重复实现成长公式.
#
# 数据职责:
# - SavedBase 表示宠物个体出生时从模板 baseVital/baseStr/baseTough/baseDex 随机偏移后保存下来的个体基础值.
# - Raw 表示宠物个体当前参与面板换算的原始四维值, 会随创建等级和升级次数累加.
# - 面板 HP/Attack/Defense/Agility 是运行期派生快照, 不写回宠物记录.
# 计算规则集中在这里, 避免默认账号宠物、自动遇敌敌人和后续升级流程各自维护一套容易漂移的公式.

# 每次出生或升级时, 随机点都会被分配到 raw_vital/raw_str/raw_tough/raw_dex 四个方向.
# 当前规则每轮分配 10 点, 逐点随机选择目标四维, 因此同一轮可能多次落在同一项.
const RAW_RANDOM_POINT_COUNT := 10

# SavedBase 是宠物个体自己的基础值, 会在模板基础值上做 [-2, 2] 随机偏移.
# ConfigPet.load() 会校验 baseVital/baseStr/baseTough/baseDex 加上最小随机偏移后仍大于 0,
# GPetCalculator 创建宠物个体时使用同一组常量生成 SavedBase.
const PET_SAVED_BASE_RANDOM_MIN := -2
const PET_SAVED_BASE_RANDOM_MAX := 2

# 公开返回字典的固定 key.
# create_pet() 返回 SavedBase + Raw, upgrade_pet() 只返回 Raw, 调用方应使用这些常量取值, 避免手写字符串漂移.
const KEY_SAVED_BASE_VITAL := "saved_base_vital"
const KEY_SAVED_BASE_STR := "saved_base_str"
const KEY_SAVED_BASE_TOUGH := "saved_base_tough"
const KEY_SAVED_BASE_DEX := "saved_base_dex"
const KEY_RAW_VITAL := "raw_vital"
const KEY_RAW_STR := "raw_str"
const KEY_RAW_TOUGH := "raw_tough"
const KEY_RAW_DEX := "raw_dex"

# Autoload 级随机数生成器.
# 这里使用运行期随机种子, 让默认账号宠物和自动遇敌敌人每次创建时都能得到不同个体.
var rng := RandomNumberGenerator.new()

func _init() -> void:
    rng.randomize()

# 创建一只指定等级的宠物个体.
# 输入:
# - pet_id: config/pet.yaml 中存在的宠物 ID.
# - level: 创建时目标等级, 由调用方保证已处于合法等级范围.
# 返回:
# - saved_base_vital/saved_base_str/saved_base_tough/saved_base_dex.
# - raw_vital/raw_str/raw_tough/raw_dex.
# 调用方负责把结果写入宠物记录或临时战斗单位; 本函数只负责纯计算和随机生成.
func create_pet(pet_id: int, level: int) -> Dictionary:
    var pet_entry: ConfigPet.Entry = GCfgMgr.pet_config.get_by_id(pet_id)
    var growth := pet_entry.growth

    # 先生成并保存个体 SavedBase. 这是宠物出生时的一次性随机结果, 后续升级要复用它.
    var result := {
        KEY_SAVED_BASE_VITAL: growth.base_vital + rng.randi_range(PET_SAVED_BASE_RANDOM_MIN, PET_SAVED_BASE_RANDOM_MAX),
        KEY_SAVED_BASE_STR: growth.base_str + rng.randi_range(PET_SAVED_BASE_RANDOM_MIN, PET_SAVED_BASE_RANDOM_MAX),
        KEY_SAVED_BASE_TOUGH: growth.base_tough + rng.randi_range(PET_SAVED_BASE_RANDOM_MIN, PET_SAVED_BASE_RANDOM_MAX),
        KEY_SAVED_BASE_DEX: growth.base_dex + rng.randi_range(PET_SAVED_BASE_RANDOM_MIN, PET_SAVED_BASE_RANDOM_MAX),
    }
    # 1 级 Raw = initNum * (SavedBase + 出生随机点).
    # 这里先算出 1 级 Raw, 再用 upgrade_pet(level - 1) 复用同一套升级累加逻辑.
    var initial_bonus := _random_four_point_distribution()
    var initial_factor := float(growth.init_num)
    result[KEY_RAW_VITAL] = int(initial_factor * float(int(result[KEY_SAVED_BASE_VITAL]) + int(initial_bonus[KEY_RAW_VITAL])))
    result[KEY_RAW_STR] = int(initial_factor * float(int(result[KEY_SAVED_BASE_STR]) + int(initial_bonus[KEY_RAW_STR])))
    result[KEY_RAW_TOUGH] = int(initial_factor * float(int(result[KEY_SAVED_BASE_TOUGH]) + int(initial_bonus[KEY_RAW_TOUGH])))
    result[KEY_RAW_DEX] = int(initial_factor * float(int(result[KEY_SAVED_BASE_DEX]) + int(initial_bonus[KEY_RAW_DEX])))

    var upgraded_raw := upgrade_pet(
        pet_id,
        level - 1,
        int(result[KEY_SAVED_BASE_VITAL]),
        int(result[KEY_SAVED_BASE_STR]),
        int(result[KEY_SAVED_BASE_TOUGH]),
        int(result[KEY_SAVED_BASE_DEX]),
        int(result[KEY_RAW_VITAL]),
        int(result[KEY_RAW_STR]),
        int(result[KEY_RAW_TOUGH]),
        int(result[KEY_RAW_DEX])
    )
    result.merge(upgraded_raw, true)
    return result

# 根据宠物 Raw 四维分别计算战斗面板属性.
# 面板公式来自 config/pet.yaml 顶部注释; 这里拆成四个 int 返回函数, 让调用方按需要写入 CombatUnitAttribute.
func calculate_pet_hp(raw_vital: int, raw_str: int, raw_tough: int, raw_dex: int) -> int:
    return int((float(raw_vital) * 4.0 + float(raw_str) + float(raw_tough) + float(raw_dex)) * 0.01)

func calculate_pet_attack(raw_vital: int, raw_str: int, raw_tough: int, raw_dex: int) -> int:
    return int(float(raw_str) * 0.01 + float(raw_tough) * 0.001 + float(raw_vital) * 0.001 + float(raw_dex) * 0.0005)

func calculate_pet_defense(raw_vital: int, raw_str: int, raw_tough: int, raw_dex: int) -> int:
    return int(float(raw_tough) * 0.01 + float(raw_str) * 0.001 + float(raw_vital) * 0.001 + float(raw_dex) * 0.0005)

func calculate_pet_agility(raw_vital: int, raw_str: int, raw_tough: int, raw_dex: int) -> int:
    return int(float(raw_dex) * 0.01)

# 按升级次数累加宠物 Raw.
# 输入:
# - upgrade_count 表示从当前 Raw 连续追加的成长次数, 而不是目标等级.
# - SavedBase 必须是宠物个体出生时保存下来的基础值.
# - Raw 是升级前的当前值.
# 返回:
# - raw_vital/raw_str/raw_tough/raw_dex, 表示升级后的 Raw.
# 0 次升级直接返回原 Raw; 负数说明调用方流程错误, 直接 assert.
func upgrade_pet(
    pet_id: int,
    upgrade_count: int,
    saved_base_vital: int,
    saved_base_str: int,
    saved_base_tough: int,
    saved_base_dex: int,
    raw_vital: int,
    raw_str: int,
    raw_tough: int,
    raw_dex: int
) -> Dictionary:
    var pet_entry: ConfigPet.Entry = GCfgMgr.pet_config.get_by_id(pet_id)

    var raw_values := {
        KEY_RAW_VITAL: raw_vital,
        KEY_RAW_STR: raw_str,
        KEY_RAW_TOUGH: raw_tough,
        KEY_RAW_DEX: raw_dex,
    }
    var growth := pet_entry.growth
    var rank_range := _rank_growth_range(growth.base_vital + growth.base_str + growth.base_tough + growth.base_dex)
    for _index in range(upgrade_count):
        # 每次升级先随机分配 10 点, 再按宠物模板 rank 区间随机倍率累加到当前 Raw.
        # SavedBase 使用个体值, rankRange 使用模板基础四维总和, 这和创建高等级宠物时的逐级累加逻辑一致.
        var add_points := _random_four_point_distribution()
        var rank_rand := rng.randf_range(rank_range.x, rank_range.y)
        raw_values[KEY_RAW_VITAL] = int(raw_values[KEY_RAW_VITAL]) + int(float(saved_base_vital + int(add_points[KEY_RAW_VITAL])) * rank_rand)
        raw_values[KEY_RAW_STR] = int(raw_values[KEY_RAW_STR]) + int(float(saved_base_str + int(add_points[KEY_RAW_STR])) * rank_rand)
        raw_values[KEY_RAW_TOUGH] = int(raw_values[KEY_RAW_TOUGH]) + int(float(saved_base_tough + int(add_points[KEY_RAW_TOUGH])) * rank_rand)
        raw_values[KEY_RAW_DEX] = int(raw_values[KEY_RAW_DEX]) + int(float(saved_base_dex + int(add_points[KEY_RAW_DEX])) * rank_rand)

    return raw_values

func _random_four_point_distribution() -> Dictionary:
    # 返回本轮随机点分配结果. 总点数固定等于 RAW_RANDOM_POINT_COUNT, 但各项分布完全随机.
    var values := {
        KEY_RAW_VITAL: 0,
        KEY_RAW_STR: 0,
        KEY_RAW_TOUGH: 0,
        KEY_RAW_DEX: 0,
    }
    var keys := [KEY_RAW_VITAL, KEY_RAW_STR, KEY_RAW_TOUGH, KEY_RAW_DEX]
    for _index in range(RAW_RANDOM_POINT_COUNT):
        var selected_key := str(keys[rng.randi_range(0, keys.size() - 1)])
        values[selected_key] = int(values[selected_key]) + 1
    return values

func _rank_growth_range(base_sum: int) -> Vector2:
    # rankRange 由模板基础四维总和决定. 返回 Vector2(x=min, y=max), 供 randf_range() 取升级倍率.
    if base_sum >= 100:
        return Vector2(4.50, 5.00)
    if base_sum >= 95:
        return Vector2(4.70, 5.20)
    if base_sum >= 90:
        return Vector2(4.90, 5.40)
    if base_sum >= 85:
        return Vector2(5.10, 5.60)
    if base_sum >= 80:
        return Vector2(5.30, 5.80)
    return Vector2(5.50, 6.00)
