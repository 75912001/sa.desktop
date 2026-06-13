# 公共常量集合.
# 这个脚本只放项目级常量, 不放会修改运行状态的数据, 也不承担资源加载逻辑.
# 其它脚本可以直接通过 `Constants.CONFIG_PET_PATH` 或 `Constants.DIRECTIONS` 这类 `class_name` 全局类型引用这里的 const.
# 调用方不需要 `preload`, 也不需要执行 `Constants.new()`.
# 这里继承 RefCounted 只是为了符合 GDScript 脚本类型写法, 本文件没有 Godot Node 生命周期函数.
class_name Constants
extends RefCounted

# 项目配置文件、资源路径、动画画布参数和枚举集中放在这里, 避免配置解析、资源检查、动画构建和测试页各维护一份.

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
const ELEMENT_KEYS := ["earth", "water", "fire", "wind"]

# 宠物资源目录和偏移总表路径由资产管理器, 动画构建器和测试页共用.
# 每个宠物仍使用同 ID 的 PNG 和 .tpsheet, offsets.json 可选保存 pet_id -> frame_id -> [x, y] 的偏移映射.
# 资产管理器会根据宠物 ID 在 ASSET_PET_DIR 下查找 `{id}.png` 和 `{id}.tpsheet`.
const ASSET_PET_DIR := "res://assets/pet"
const PET_OFFSETS_PATH := "res://assets/pet/offsets.json"

# 角色资源目录和偏移总表路径由资产管理器, 动画构建器和测试页共用.
# 每个角色仍使用同 ID 的 PNG 和 .tpsheet, offsets.json 可选保存 character_id -> frame_id -> [x, y] 的偏移映射.
# 资产管理器会根据角色 ID 在 ASSET_CHARACTER_DIR 下查找 `{id}.png` 和 `{id}.tpsheet`.
const ASSET_CHARACTER_DIR := "res://assets/character"
const CHARACTER_OFFSETS_PATH := "res://assets/character/offsets.json"

# padding 给动画画布四周留一点空白, 避免极限帧贴到窗口边缘.
# 实际画布大小仍由帧 region, margin 和可选 offsets 计算得出; 这里不是宠物体型上限, 只是统一额外边距.
const ANIMATION_PADDING := Vector2(24.0, 24.0)

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

# 项目动画配置中的 8 方向统一定义.
# 这个顺序需要和 config/pet.yaml, config/character.yaml, config/tray_menu.yaml 中的方向名保持一致.
# 运行时动画名会由 `动作_方向` 组成, 例如 `stand_down` 或 `attack_left`.
# 托盘菜单和测试页也会使用这个顺序展示方向, 所以调整顺序会影响 UI 显示顺序.
const DIRECTIONS := [
    "down",
    "downleft",
    "left",
    "upleft",
    "up",
    "upright",
    "right",
    "downright",
]

# 运行时内部使用的方向枚举顺序, 与 DIRECTIONS 字符串顺序一一对应.
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

# 宠物动作顺序用于托盘菜单、动画构建兜底和宠物偏移测试页.
# 动作显示标签属于具体 UI/菜单用途, 不放在公共常量里.
# 这里保存的是配置和动画资源使用的动作 key, 不是中文显示文案.
const PET_ACTIONS := [
    "attack",
    "faint",
    "hurt",
    "defense",
    "stand",
    "walk",
    "attackShort",
]

# 运行时内部使用的宠物动作枚举顺序, 与 PET_ACTIONS 字符串顺序一一对应.
const PET_ACTION_VALUES := [
    PetAction.Attack,
    PetAction.Faint,
    PetAction.Hurt,
    PetAction.Defense,
    PetAction.Stand,
    PetAction.Walk,
    PetAction.AttackShort,
]

# 角色动作顺序用于角色动画构建兜底和角色偏移测试页.
# 角色动作比宠物多武器类型维度, 但动画名仍使用 `动作_方向` 的组合规则.
# AnimationCharacterBuilder 会在具体武器类型下读取这些动作对应的帧序列.
const CHARACTER_ACTIONS := [
    "attack",
    "wave",
    "faint",
    "hurt",
    "defense",
    "sad",
    "angry",
    "sit",
    "stand",
    "throw",
    "nod",
    "walk",
    "happy",
]

# 运行时内部使用的角色动作枚举顺序, 与 CHARACTER_ACTIONS 字符串顺序一一对应.
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

# 角色武器类型顺序用于配置完整性校验和角色偏移测试页展示.
const CHARACTER_WEAPON_TYPES := [
    "unarmed",
    "axe",
    "bow",
    "spear",
    "stick",
]

# 运行时内部使用的角色武器类型枚举顺序, 与 CHARACTER_WEAPON_TYPES 字符串顺序一一对应.
const CHARACTER_WEAPON_TYPE_VALUES := [
    WeaponType.Unarmed,
    WeaponType.Axe,
    WeaponType.Bow,
    WeaponType.Spear,
    WeaponType.Stick,
]

# 方向字符串协议和运行时枚举的双向映射.
# YAML, 托盘菜单和动画名使用字符串; 配置对象内部使用枚举值.
const DIRECTION_BY_KEY := {
    "up": Direction.Up,
    "upright": Direction.UpRight,
    "right": Direction.Right,
    "downright": Direction.DownRight,
    "down": Direction.Down,
    "downleft": Direction.DownLeft,
    "left": Direction.Left,
    "upleft": Direction.UpLeft,
}

const DIRECTION_KEY_BY_VALUE := {
    Direction.Up: "up",
    Direction.UpRight: "upright",
    Direction.Right: "right",
    Direction.DownRight: "downright",
    Direction.Down: "down",
    Direction.DownLeft: "downleft",
    Direction.Left: "left",
    Direction.UpLeft: "upleft",
}

# 宠物动作字符串协议和运行时枚举的双向映射.
const PET_ACTION_BY_KEY := {
    "attack": PetAction.Attack,
    "faint": PetAction.Faint,
    "hurt": PetAction.Hurt,
    "defense": PetAction.Defense,
    "stand": PetAction.Stand,
    "walk": PetAction.Walk,
    "attackShort": PetAction.AttackShort,
}

const PET_ACTION_KEY_BY_VALUE := {
    PetAction.Attack: "attack",
    PetAction.Faint: "faint",
    PetAction.Hurt: "hurt",
    PetAction.Defense: "defense",
    PetAction.Stand: "stand",
    PetAction.Walk: "walk",
    PetAction.AttackShort: "attackShort",
}

# 角色动作字符串协议和运行时枚举的双向映射.
const CHARACTER_ACTION_BY_KEY := {
    "attack": CharacterAction.Attack,
    "wave": CharacterAction.Wave,
    "faint": CharacterAction.Faint,
    "hurt": CharacterAction.Hurt,
    "defense": CharacterAction.Defense,
    "sad": CharacterAction.Sad,
    "angry": CharacterAction.Angry,
    "sit": CharacterAction.Sit,
    "stand": CharacterAction.Stand,
    "throw": CharacterAction.Throw,
    "nod": CharacterAction.Nod,
    "walk": CharacterAction.Walk,
    "happy": CharacterAction.Happy,
}

const CHARACTER_ACTION_KEY_BY_VALUE := {
    CharacterAction.Attack: "attack",
    CharacterAction.Wave: "wave",
    CharacterAction.Faint: "faint",
    CharacterAction.Hurt: "hurt",
    CharacterAction.Defense: "defense",
    CharacterAction.Sad: "sad",
    CharacterAction.Angry: "angry",
    CharacterAction.Sit: "sit",
    CharacterAction.Stand: "stand",
    CharacterAction.Throw: "throw",
    CharacterAction.Nod: "nod",
    CharacterAction.Walk: "walk",
    CharacterAction.Happy: "happy",
}

# 武器类型字符串协议和运行时枚举的双向映射.
const WEAPON_TYPE_BY_KEY := {
    "unarmed": WeaponType.Unarmed,
    "axe": WeaponType.Axe,
    "bow": WeaponType.Bow,
    "spear": WeaponType.Spear,
    "stick": WeaponType.Stick,
}

const WEAPON_TYPE_KEY_BY_VALUE := {
    WeaponType.Unarmed: "unarmed",
    WeaponType.Axe: "axe",
    WeaponType.Bow: "bow",
    WeaponType.Spear: "spear",
    WeaponType.Stick: "stick",
}

static func direction_from_key(key: String) -> int:
    return int(DIRECTION_BY_KEY.get(key, Direction.Unknown))

static func direction_to_key(direction: int) -> String:
    return str(DIRECTION_KEY_BY_VALUE.get(direction, ""))

static func pet_action_from_key(key: String) -> int:
    return int(PET_ACTION_BY_KEY.get(key, PetAction.Unknown))

static func pet_action_to_key(action: int) -> String:
    return str(PET_ACTION_KEY_BY_VALUE.get(action, ""))

static func character_action_from_key(key: String) -> int:
    return int(CHARACTER_ACTION_BY_KEY.get(key, CharacterAction.Unknown))

static func character_action_to_key(action: int) -> String:
    return str(CHARACTER_ACTION_KEY_BY_VALUE.get(action, ""))

static func weapon_type_from_key(key: String) -> int:
    return int(WEAPON_TYPE_BY_KEY.get(key, WeaponType.Unknown))

static func weapon_type_to_key(weapon: int) -> String:
    return str(WEAPON_TYPE_KEY_BY_VALUE.get(weapon, ""))

static func is_pet_id(id: int) -> bool:
    return id >= PET_ID_MIN and id <= PET_ID_MAX

static func is_character_id(id: int) -> bool:
    return id >= CHARACTER_ID_MIN and id <= CHARACTER_ID_MAX
