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

# 宠物配置基础校验范围.
# ConfigPet.load() 使用这些范围在启动阶段直接暴露非法 pet_id 或 rarity.
const PET_ID_MIN := 4000101
const PET_ID_MAX := 4999999
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

# 资产方向枚举.
# 编号先在 GDScript 中固定为 protobuf 风格, 后续如果接入真实 `.proto`, 需要保持这些数值不变.
enum AssetDirection {
	AssetDirection_Unknown = 0,
	AssetDirection_Up = 1,
	AssetDirection_UpRight = 2,
	AssetDirection_Right = 3,
	AssetDirection_DownRight = 4,
	AssetDirection_Down = 5,
	AssetDirection_DownLeft = 6,
	AssetDirection_Left = 7,
	AssetDirection_UpLeft = 8,
	AssetDirection_Max = 9,
}

# 宠物动作枚举.
# YAML 和菜单继续使用字符串 key, 宠物配置结构使用这些稳定枚举值做 Dictionary key.
enum AssetPetAction {
	AssetPetAction_Unknown = 0,
	AssetPetAction_Attack = 1,
	AssetPetAction_Faint = 2,
	AssetPetAction_Hurt = 3,
	AssetPetAction_Defense = 4,
	AssetPetAction_Stand = 5,
	AssetPetAction_Walk = 6,
	AssetPetAction_AttackShort = 7,
	AssetPetAction_Max = 8,
}

# 角色动作枚举.
# 角色动作集合和宠物不同, 因此使用独立枚举空间, 避免运行时误用另一类动作 key.
enum AssetCharacterAction {
	AssetCharacterAction_Unknown = 0,
	AssetCharacterAction_Attack = 1,
	AssetCharacterAction_Wave = 2,
	AssetCharacterAction_Faint = 3,
	AssetCharacterAction_Hurt = 4,
	AssetCharacterAction_Defense = 5,
	AssetCharacterAction_Sad = 6,
	AssetCharacterAction_Angry = 7,
	AssetCharacterAction_Sit = 8,
	AssetCharacterAction_Stand = 9,
	AssetCharacterAction_Throw = 10,
	AssetCharacterAction_Nod = 11,
	AssetCharacterAction_Walk = 12,
	AssetCharacterAction_Happy = 13,
	AssetCharacterAction_Max = 14,
}

# 角色武器枚举.
# 角色 YAML 仍使用字符串武器名, 运行时 ConfigCharacter 使用这些枚举值做 Dictionary key.
enum AssetWeapon {
	AssetWeapon_Unknown = 0,
	AssetWeapon_Unarmed = 1,
	AssetWeapon_Axe = 2,
	AssetWeapon_Bow = 3,
	AssetWeapon_Spear = 4,
	AssetWeapon_Stick = 5,
	AssetWeapon_Max = 6,
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
	AssetDirection.AssetDirection_Down,
	AssetDirection.AssetDirection_DownLeft,
	AssetDirection.AssetDirection_Left,
	AssetDirection.AssetDirection_UpLeft,
	AssetDirection.AssetDirection_Up,
	AssetDirection.AssetDirection_UpRight,
	AssetDirection.AssetDirection_Right,
	AssetDirection.AssetDirection_DownRight,
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
	AssetPetAction.AssetPetAction_Attack,
	AssetPetAction.AssetPetAction_Faint,
	AssetPetAction.AssetPetAction_Hurt,
	AssetPetAction.AssetPetAction_Defense,
	AssetPetAction.AssetPetAction_Stand,
	AssetPetAction.AssetPetAction_Walk,
	AssetPetAction.AssetPetAction_AttackShort,
]

# 角色动作顺序用于角色动画构建兜底和角色偏移测试页.
# 角色动作比宠物多武器维度, 但动画名仍使用 `动作_方向` 的组合规则.
# CharacterAnimationBuilder 会在具体武器下读取这些动作对应的帧序列.
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
	AssetCharacterAction.AssetCharacterAction_Attack,
	AssetCharacterAction.AssetCharacterAction_Wave,
	AssetCharacterAction.AssetCharacterAction_Faint,
	AssetCharacterAction.AssetCharacterAction_Hurt,
	AssetCharacterAction.AssetCharacterAction_Defense,
	AssetCharacterAction.AssetCharacterAction_Sad,
	AssetCharacterAction.AssetCharacterAction_Angry,
	AssetCharacterAction.AssetCharacterAction_Sit,
	AssetCharacterAction.AssetCharacterAction_Stand,
	AssetCharacterAction.AssetCharacterAction_Throw,
	AssetCharacterAction.AssetCharacterAction_Nod,
	AssetCharacterAction.AssetCharacterAction_Walk,
	AssetCharacterAction.AssetCharacterAction_Happy,
]

# 角色武器顺序用于配置完整性校验和角色偏移测试页展示.
const CHARACTER_WEAPONS := [
	"unarmed",
	"axe",
	"bow",
	"spear",
	"stick",
]

# 运行时内部使用的角色武器枚举顺序, 与 CHARACTER_WEAPONS 字符串顺序一一对应.
const CHARACTER_WEAPON_VALUES := [
	AssetWeapon.AssetWeapon_Unarmed,
	AssetWeapon.AssetWeapon_Axe,
	AssetWeapon.AssetWeapon_Bow,
	AssetWeapon.AssetWeapon_Spear,
	AssetWeapon.AssetWeapon_Stick,
]

# 方向字符串协议和运行时枚举的双向映射.
# YAML, 托盘菜单和动画名使用字符串; 配置对象内部使用枚举值.
const DIRECTION_BY_KEY := {
	"up": AssetDirection.AssetDirection_Up,
	"upright": AssetDirection.AssetDirection_UpRight,
	"right": AssetDirection.AssetDirection_Right,
	"downright": AssetDirection.AssetDirection_DownRight,
	"down": AssetDirection.AssetDirection_Down,
	"downleft": AssetDirection.AssetDirection_DownLeft,
	"left": AssetDirection.AssetDirection_Left,
	"upleft": AssetDirection.AssetDirection_UpLeft,
}

const DIRECTION_KEY_BY_VALUE := {
	AssetDirection.AssetDirection_Up: "up",
	AssetDirection.AssetDirection_UpRight: "upright",
	AssetDirection.AssetDirection_Right: "right",
	AssetDirection.AssetDirection_DownRight: "downright",
	AssetDirection.AssetDirection_Down: "down",
	AssetDirection.AssetDirection_DownLeft: "downleft",
	AssetDirection.AssetDirection_Left: "left",
	AssetDirection.AssetDirection_UpLeft: "upleft",
}

# 宠物动作字符串协议和运行时枚举的双向映射.
const PET_ACTION_BY_KEY := {
	"attack": AssetPetAction.AssetPetAction_Attack,
	"faint": AssetPetAction.AssetPetAction_Faint,
	"hurt": AssetPetAction.AssetPetAction_Hurt,
	"defense": AssetPetAction.AssetPetAction_Defense,
	"stand": AssetPetAction.AssetPetAction_Stand,
	"walk": AssetPetAction.AssetPetAction_Walk,
	"attackShort": AssetPetAction.AssetPetAction_AttackShort,
}

const PET_ACTION_KEY_BY_VALUE := {
	AssetPetAction.AssetPetAction_Attack: "attack",
	AssetPetAction.AssetPetAction_Faint: "faint",
	AssetPetAction.AssetPetAction_Hurt: "hurt",
	AssetPetAction.AssetPetAction_Defense: "defense",
	AssetPetAction.AssetPetAction_Stand: "stand",
	AssetPetAction.AssetPetAction_Walk: "walk",
	AssetPetAction.AssetPetAction_AttackShort: "attackShort",
}

# 角色动作字符串协议和运行时枚举的双向映射.
const CHARACTER_ACTION_BY_KEY := {
	"attack": AssetCharacterAction.AssetCharacterAction_Attack,
	"wave": AssetCharacterAction.AssetCharacterAction_Wave,
	"faint": AssetCharacterAction.AssetCharacterAction_Faint,
	"hurt": AssetCharacterAction.AssetCharacterAction_Hurt,
	"defense": AssetCharacterAction.AssetCharacterAction_Defense,
	"sad": AssetCharacterAction.AssetCharacterAction_Sad,
	"angry": AssetCharacterAction.AssetCharacterAction_Angry,
	"sit": AssetCharacterAction.AssetCharacterAction_Sit,
	"stand": AssetCharacterAction.AssetCharacterAction_Stand,
	"throw": AssetCharacterAction.AssetCharacterAction_Throw,
	"nod": AssetCharacterAction.AssetCharacterAction_Nod,
	"walk": AssetCharacterAction.AssetCharacterAction_Walk,
	"happy": AssetCharacterAction.AssetCharacterAction_Happy,
}

const CHARACTER_ACTION_KEY_BY_VALUE := {
	AssetCharacterAction.AssetCharacterAction_Attack: "attack",
	AssetCharacterAction.AssetCharacterAction_Wave: "wave",
	AssetCharacterAction.AssetCharacterAction_Faint: "faint",
	AssetCharacterAction.AssetCharacterAction_Hurt: "hurt",
	AssetCharacterAction.AssetCharacterAction_Defense: "defense",
	AssetCharacterAction.AssetCharacterAction_Sad: "sad",
	AssetCharacterAction.AssetCharacterAction_Angry: "angry",
	AssetCharacterAction.AssetCharacterAction_Sit: "sit",
	AssetCharacterAction.AssetCharacterAction_Stand: "stand",
	AssetCharacterAction.AssetCharacterAction_Throw: "throw",
	AssetCharacterAction.AssetCharacterAction_Nod: "nod",
	AssetCharacterAction.AssetCharacterAction_Walk: "walk",
	AssetCharacterAction.AssetCharacterAction_Happy: "happy",
}

# 武器字符串协议和运行时枚举的双向映射.
const WEAPON_BY_KEY := {
	"unarmed": AssetWeapon.AssetWeapon_Unarmed,
	"axe": AssetWeapon.AssetWeapon_Axe,
	"bow": AssetWeapon.AssetWeapon_Bow,
	"spear": AssetWeapon.AssetWeapon_Spear,
	"stick": AssetWeapon.AssetWeapon_Stick,
}

const WEAPON_KEY_BY_VALUE := {
	AssetWeapon.AssetWeapon_Unarmed: "unarmed",
	AssetWeapon.AssetWeapon_Axe: "axe",
	AssetWeapon.AssetWeapon_Bow: "bow",
	AssetWeapon.AssetWeapon_Spear: "spear",
	AssetWeapon.AssetWeapon_Stick: "stick",
}

static func direction_from_key(key: String) -> int:
	return int(DIRECTION_BY_KEY.get(key, AssetDirection.AssetDirection_Unknown))

static func direction_to_key(direction: int) -> String:
	return str(DIRECTION_KEY_BY_VALUE.get(direction, ""))

static func pet_action_from_key(key: String) -> int:
	return int(PET_ACTION_BY_KEY.get(key, AssetPetAction.AssetPetAction_Unknown))

static func pet_action_to_key(action: int) -> String:
	return str(PET_ACTION_KEY_BY_VALUE.get(action, ""))

static func character_action_from_key(key: String) -> int:
	return int(CHARACTER_ACTION_BY_KEY.get(key, AssetCharacterAction.AssetCharacterAction_Unknown))

static func character_action_to_key(action: int) -> String:
	return str(CHARACTER_ACTION_KEY_BY_VALUE.get(action, ""))

static func weapon_from_key(key: String) -> int:
	return int(WEAPON_BY_KEY.get(key, AssetWeapon.AssetWeapon_Unknown))

static func weapon_to_key(weapon: int) -> String:
	return str(WEAPON_KEY_BY_VALUE.get(weapon, ""))
