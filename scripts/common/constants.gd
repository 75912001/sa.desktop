# 公共常量集合.
# 这个脚本只放项目级常量, 不放会修改运行状态的数据, 也不承担资源加载逻辑.
# 其它脚本可以直接通过 `Constants.CONFIG_PET_PATH` 或 `Constants.Direction.Down` 这类 `class_name` 全局类型引用这里的 const.
# 调用方不需要 `preload`, 也不需要执行 `Constants.new()`.
# 这里继承 RefCounted 只是为了符合 GDScript 脚本类型写法, 本文件没有 Godot Node 生命周期函数.
class_name Constants
extends RefCounted

# 项目配置文件、资源路径、动画播放参数和运行期枚举集中放在这里.
# 配置表中的字符串 key 只允许在具体解析边界写死并转换为枚举, 不在公共常量中扩散.

# 配置文件路径由 ConfigManager 统一读取.
# 这些 YAML 是运行时配置源数据, 必须保持标准空格缩进; 读取阶段不修正 tab 缩进.
# `res://` 表示 Godot 项目根目录, 所以下面的路径对应项目内的 config 目录.
const CONFIG_PET_PATH := "res://config/pet.yaml"
const CONFIG_CHARACTER_PATH := "res://config/character.yaml"
const CONFIG_ENEMY_GROUP_PATH := "res://config/enemy.group.yaml"

# 配置表声明的 ID 范围.
# 动画显示入口会用这些范围从 id 推导资源类型; 配置加载也会用宠物范围暴露非法 pet_id.
const PET_ID_MIN := 4000101
const PET_ID_MAX := 4999999
const CHARACTER_ID_MIN := 1000001
const CHARACTER_ID_MAX := 1999999
const RARITY_MIN := 1
const RARITY_MAX := 5

# 宠物资源目录由 ConfigAssets, 宠物动画构建器和测试页共用.
# 每个宠物仍使用同 ID 的 PNG 和 .tpsheet, 宠物每帧 offset 直接内联在 `.tpsheet` sprite 的 `offset: [x, y]` 字段中.
# ConfigAssets 会根据宠物 ID 在 ASSET_PET_DIR 下查找 `{id}.png` 和 `{id}.tpsheet`.
const ASSET_PET_DIR := "res://assets/pet"

# 角色资源目录由 ConfigAssets, 角色播放缓存和测试页共用.
# 每个角色使用同 ID 的 PNG 和 .tpsheet, 角色每帧 offset 直接内联在 `.tpsheet` sprite 的 `offset: [x, y]` 字段中.
# ConfigAssets 会根据角色 ID 在 ASSET_CHARACTER_DIR 下查找 `{id}.png` 和 `{id}.tpsheet`.
const ASSET_CHARACTER_DIR := "res://assets/character"

# 动画播放默认参数.
# 普通动作使用默认速度, walk 动作单独使用更快的行走速度; 默认循环表示基础动画播完后回到第一帧.
const ANIMATION_DEFAULT_SPEED := 8.0
const ANIMATION_WALK_SPEED := 10.0
const ANIMATION_DEFAULT_LOOP := true

# 元素枚举.
# 枚举数值是运行时配置解析使用的稳定值; 调整名称时不要改变已有数值.
enum Element {
    Unknown = 0,
    Earth = 1,
    Water = 2,
    Fire = 3,
    Wind = 4,
    Max = 5,
}

# 方向枚举.
# 枚举数值是运行时配置解析和帧表索引使用的稳定值; 调整名称时不要改变已有数值.
enum Direction {
    Unknown = 0,
    Up = 1,
    UpRight = 2,
    Right = 3,
    DownRight = 4,
    Down = 5,
    DownLeft = 6,
    Left = 7,
    UpLeft = 8,
    Max = 9,
}

# 宠物动作枚举.
# YAML 和菜单继续使用字符串 key, 宠物配置结构使用这些稳定枚举值做 Dictionary key.
enum PetAction {
    Unknown = 0,
    Attack = 1,
    Faint = 2,
    Hurt = 3,
    Defense = 4,
    Stand = 5,
    Walk = 6,
    AttackShort = 7,
    Max = 8,
}

# 角色动作枚举.
# 角色动作集合和宠物不同, 因此使用独立枚举空间, 避免运行时误用另一类动作 key.
enum CharacterAction {
    Unknown = 0,
    Attack = 1,
    Wave = 2,
    Faint = 3,
    Hurt = 4,
    Defense = 5,
    Sad = 6,
    Angry = 7,
    Sit = 8,
    Stand = 9,
    Throw = 10,
    Nod = 11,
    Walk = 12,
    Happy = 13,
    Max = 14,
}

# 角色武器类型枚举.
# 角色 YAML 仍使用 weapon 字段下的字符串武器类型名, 运行时 ConfigCharacter 使用这些枚举值做 Dictionary key.
enum WeaponType {
    Unknown = 0,
    Unarmed = 1,
    Axe = 2,
    Bow = 3,
    Spear = 4,
    Stick = 5,
    Max = 6,
}

# 运行时内部使用的方向枚举顺序.
# 调整顺序会影响默认动画构建顺序和托盘方向显示顺序.
const DIRECTION_VALUES := [
    Direction.Down,
    Direction.DownLeft,
    Direction.Left,
    Direction.UpLeft,
    Direction.Up,
    Direction.UpRight,
    Direction.Right,
    Direction.DownRight,
]

# 运行时内部使用的宠物动作枚举顺序.
# 动作显示标签和配置字符串属于具体 UI/解析用途, 不放在公共常量里.
const PET_ACTION_VALUES := [
    PetAction.Attack,
    PetAction.Faint,
    PetAction.Hurt,
    PetAction.Defense,
    PetAction.Stand,
    PetAction.Walk,
    PetAction.AttackShort,
]

# 运行时内部使用的角色动作枚举顺序.
# 角色动作比宠物多武器类型维度, 播放缓存会把方向, 武器类型和动作一起作为 key.
const CHARACTER_ACTION_VALUES := [
    CharacterAction.Attack,
    CharacterAction.Wave,
    CharacterAction.Faint,
    CharacterAction.Hurt,
    CharacterAction.Defense,
    CharacterAction.Sad,
    CharacterAction.Angry,
    CharacterAction.Sit,
    CharacterAction.Stand,
    CharacterAction.Throw,
    CharacterAction.Nod,
    CharacterAction.Walk,
    CharacterAction.Happy,
]

# 运行时内部使用的角色武器类型枚举顺序.
# 配置字符串只在角色配置解析边界转换成这些枚举值.
const CHARACTER_WEAPON_TYPE_VALUES := [
    WeaponType.Unarmed,
    WeaponType.Axe,
    WeaponType.Bow,
    WeaponType.Spear,
    WeaponType.Stick,
]

static func is_pet_id(id: int) -> bool:
    return id >= PET_ID_MIN and id <= PET_ID_MAX

static func is_character_id(id: int) -> bool:
    return id >= CHARACTER_ID_MIN and id <= CHARACTER_ID_MAX

# 根据运行期资源 ID 返回对应图集路径.
# 调用方只传宠物或角色 ID, 资源类型由配置表约定的 ID 范围推导.
static func get_atlas_path(id: int) -> String:
    if is_pet_id(id):
        return "%s/%d.png" % [ASSET_PET_DIR, id]
    if is_character_id(id):
        return "%s/%d.png" % [ASSET_CHARACTER_DIR, id]

    assert(false, "资源ID不属于宠物或角色范围: %d" % id)
    return ""
