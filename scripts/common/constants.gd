# 公共常量集合.
# 这个脚本只放项目级常量, 不放会修改运行状态的数据, 也不承担资源加载逻辑.
# 其它脚本可以直接通过 `Constants.CONFIG_PET_PATH` 或 `Constants.DIRECTION_VALUES` 这类 `class_name` 全局类型引用这里的 const.
# 调用方不需要 `preload`, 也不需要执行 `Constants.new()`.
# 这里继承 RefCounted 只是为了符合 GDScript 脚本类型写法, 本文件没有 Godot Node 生命周期函数.
class_name Constants
extends RefCounted

# 项目配置文件、资源路径、动画播放参数和运行期枚举顺序集中放在这里.
# 业务枚举统一来自 Godobuf 生成的 proto 脚本, 避免客户端再维护一套同值枚举.
# 配置表中的字符串 key 只允许在具体解析边界写死并转换为枚举, 不在公共常量中扩散.
const Proto := preload("res://proto/sa.pb.gd")

# 配置文件路径由 ConfigManager 统一读取.
# 这些 YAML 是运行时配置源数据, 必须保持标准空格缩进; 读取阶段不修正 tab 缩进.
# `res://` 表示 Godot 项目根目录, 所以下面的路径对应项目内的 config 目录.
const CONFIG_PET_PATH := "res://config/pet.yaml"
const CONFIG_CHARACTER_PATH := "res://config/character.yaml"
const CONFIG_ENEMY_GROUP_PATH := "res://config/enemy.group.yaml"

# 账号记录 YAML 路径和元素字段顺序由 GRecord 读写复用.
const RECORD_DIR := "res://record"
const RECORD_PATH := "res://record/account.yaml"
const ELEMENT_KEYS := ["earth", "water", "fire", "wind"]

# 元素身份统一使用 proto AssetElemental 枚举.
# pet.yaml 和本地存档仍使用 earth/water/fire/wind 字符串, 只在配置和显示边界转换为枚举.
const ELEMENT_ORDER := [
    Proto.AssetElemental.AssetElemental_Earth,
    Proto.AssetElemental.AssetElemental_Water,
    Proto.AssetElemental.AssetElemental_Fire,
    Proto.AssetElemental.AssetElemental_Wind,
]
const ELEMENT_KEY_BY_ENUM := {
    Proto.AssetElemental.AssetElemental_Earth: "earth",
    Proto.AssetElemental.AssetElemental_Water: "water",
    Proto.AssetElemental.AssetElemental_Fire: "fire",
    Proto.AssetElemental.AssetElemental_Wind: "wind",
}
const ELEMENT_ENUM_BY_KEY := {
    "earth": Proto.AssetElemental.AssetElemental_Earth,
    "water": Proto.AssetElemental.AssetElemental_Water,
    "fire": Proto.AssetElemental.AssetElemental_Fire,
    "wind": Proto.AssetElemental.AssetElemental_Wind,
}
const ELEMENT_LABEL_BY_ENUM := {
    Proto.AssetElemental.AssetElemental_Earth: "地",
    Proto.AssetElemental.AssetElemental_Water: "水",
    Proto.AssetElemental.AssetElemental_Fire: "火",
    Proto.AssetElemental.AssetElemental_Wind: "风",
}

# pet.yaml 顶层 attribute 段只允许这些默认倍率字段.
# 字段名直接对应配置表和服务端协议命名, 不接受大小写变体或临时别名, 避免配置拼写错误被静默吞掉.
const DEFAULT_RATE_ATTRIBUTE_KEYS := ["critRate", "counterRate", "dodgeRate", "hitRate", "critDamageBonusRate", "statusResistRate"]

# 单个宠物 attribute 段允许的基础区间字段.
# 倍率字段复用 DEFAULT_RATE_ATTRIBUTE_KEYS, 缺失时从顶层默认 attribute 段继承.
const PET_BASE_ATTRIBUTE_KEYS := ["hp", "attack", "defense", "agility"]

# 宠物动作帧表中的动作 key 到运行期枚举的映射.
const PET_ACTION_BY_KEY := {
    "attack": Proto.PetAction.PetAction_Attack,
    "faint": Proto.PetAction.PetAction_Faint,
    "hurt": Proto.PetAction.PetAction_Hurt,
    "defense": Proto.PetAction.PetAction_Defense,
    "stand": Proto.PetAction.PetAction_Stand,
    "walk": Proto.PetAction.PetAction_Walk,
    "attackShort": Proto.PetAction.PetAction_AttackShort,
}

# 宠物资源目录由 AssetsConfig, 宠物动画构建器和测试页共用.
# 每个宠物仍使用同 ID 的 PNG 和 .tpsheet, 宠物每帧 offset 直接内联在 `.tpsheet` sprite 的 `offset: [x, y]` 字段中.
# AssetsConfig 会根据宠物 ID 在 ASSET_PET_DIR 下查找 `{id}.png` 和 `{id}.tpsheet`.
const ASSET_PET_DIR := "res://assets/pet"

# 角色资源目录由 AssetsConfig, 角色播放缓存和测试页共用.
# 每个角色使用同 ID 的 PNG 和 .tpsheet, 角色每帧 offset 直接内联在 `.tpsheet` sprite 的 `offset: [x, y]` 字段中.
# AssetsConfig 会根据角色 ID 在 ASSET_CHARACTER_DIR 下查找 `{id}.png` 和 `{id}.tpsheet`.
const ASSET_CHARACTER_DIR := "res://assets/character"

# 动画播放默认参数.
# 普通动作使用默认速度, walk 动作单独使用更快的行走速度; 默认循环表示基础动画播完后回到第一帧.
const ANIMATION_DEFAULT_SPEED := 8.0
const ANIMATION_WALK_SPEED := 10.0
const ANIMATION_DEFAULT_LOOP := true

# 辅助线颜色只在 `guides_visible` 打开时绘制.
# anchor_row 表示锚点所在横线, anchor_column 表示锚点所在竖线, frame 表示当前图集裁剪矩形.
const GUIDE_ANCHOR_ROW_COLOR := Color(0.2, 0.95, 0.35, 0.9)
const GUIDE_ANCHOR_COLUMN_COLOR := Color(1.0, 0.35, 0.25, 0.95)
const GUIDE_FRAME_COLOR := Color(0.35, 0.65, 1.0, 0.8)

# 配置 YAML sprite 字段中的方向 key 到 proto AssetDirection 枚举的映射.
# 宠物和角色的动作帧表都使用同一套方向字符串, 统一放在这里避免重复维护.
const DIRECTION_BY_KEY := {
    "up": Proto.AssetDirection.AssetDirection_Up,
    "upright": Proto.AssetDirection.AssetDirection_UpRight,
    "right": Proto.AssetDirection.AssetDirection_Right,
    "downright": Proto.AssetDirection.AssetDirection_DownRight,
    "down": Proto.AssetDirection.AssetDirection_Down,
    "downleft": Proto.AssetDirection.AssetDirection_DownLeft,
    "left": Proto.AssetDirection.AssetDirection_Left,
    "upleft": Proto.AssetDirection.AssetDirection_UpLeft,
}

# 运行时内部使用的方向枚举顺序.
# 调整顺序会影响默认动画构建顺序和托盘方向显示顺序.
const DIRECTION_VALUES := [
    Proto.AssetDirection.AssetDirection_Down,
    Proto.AssetDirection.AssetDirection_DownLeft,
    Proto.AssetDirection.AssetDirection_Left,
    Proto.AssetDirection.AssetDirection_UpLeft,
    Proto.AssetDirection.AssetDirection_Up,
    Proto.AssetDirection.AssetDirection_UpRight,
    Proto.AssetDirection.AssetDirection_Right,
    Proto.AssetDirection.AssetDirection_DownRight,
]

# 运行时内部使用的宠物动作枚举顺序.
# 动作显示标签和配置字符串属于具体 UI/解析用途, 不放在公共常量里.
const PET_ACTION_VALUES := [
    Proto.PetAction.PetAction_Attack,
    Proto.PetAction.PetAction_Faint,
    Proto.PetAction.PetAction_Hurt,
    Proto.PetAction.PetAction_Defense,
    Proto.PetAction.PetAction_Stand,
    Proto.PetAction.PetAction_Walk,
    Proto.PetAction.PetAction_AttackShort,
]

# 运行时内部使用的角色动作枚举顺序.
# 角色动作比宠物多武器类型维度, 播放缓存会把方向, 武器类型和动作一起作为 key.
const CHARACTER_ACTION_VALUES := [
    Proto.CharacterAction.CharacterAction_Attack,
    Proto.CharacterAction.CharacterAction_Wave,
    Proto.CharacterAction.CharacterAction_Faint,
    Proto.CharacterAction.CharacterAction_Hurt,
    Proto.CharacterAction.CharacterAction_Defense,
    Proto.CharacterAction.CharacterAction_Sad,
    Proto.CharacterAction.CharacterAction_Angry,
    Proto.CharacterAction.CharacterAction_Sit,
    Proto.CharacterAction.CharacterAction_Stand,
    Proto.CharacterAction.CharacterAction_Throw,
    Proto.CharacterAction.CharacterAction_Nod,
    Proto.CharacterAction.CharacterAction_Walk,
    Proto.CharacterAction.CharacterAction_Happy,
]

# character.yaml sprite 字段中的动作 key 到 proto CharacterAction 枚举的映射.
const CHARACTER_ACTION_BY_KEY := {
    "attack": Proto.CharacterAction.CharacterAction_Attack,
    "wave": Proto.CharacterAction.CharacterAction_Wave,
    "faint": Proto.CharacterAction.CharacterAction_Faint,
    "hurt": Proto.CharacterAction.CharacterAction_Hurt,
    "defense": Proto.CharacterAction.CharacterAction_Defense,
    "sad": Proto.CharacterAction.CharacterAction_Sad,
    "angry": Proto.CharacterAction.CharacterAction_Angry,
    "sit": Proto.CharacterAction.CharacterAction_Sit,
    "stand": Proto.CharacterAction.CharacterAction_Stand,
    "throw": Proto.CharacterAction.CharacterAction_Throw,
    "nod": Proto.CharacterAction.CharacterAction_Nod,
    "walk": Proto.CharacterAction.CharacterAction_Walk,
    "happy": Proto.CharacterAction.CharacterAction_Happy,
}

# 运行时内部使用的角色武器类型枚举顺序.
# 配置字符串只在角色配置解析边界转换成这些枚举值.
const CHARACTER_WEAPON_TYPE_VALUES := [
    Proto.CharacterWeaponType.CharacterWeaponType_Unarmed,
    Proto.CharacterWeaponType.CharacterWeaponType_Axe,
    Proto.CharacterWeaponType.CharacterWeaponType_Bow,
    Proto.CharacterWeaponType.CharacterWeaponType_Spear,
    Proto.CharacterWeaponType.CharacterWeaponType_Stick,
]

# character.yaml sprite 字段中的武器类型 key 到 proto CharacterWeaponType 枚举的映射.
const WEAPON_TYPE_BY_KEY := {
    "unarmed": Proto.CharacterWeaponType.CharacterWeaponType_Unarmed,
    "axe": Proto.CharacterWeaponType.CharacterWeaponType_Axe,
    "bow": Proto.CharacterWeaponType.CharacterWeaponType_Bow,
    "spear": Proto.CharacterWeaponType.CharacterWeaponType_Spear,
    "stick": Proto.CharacterWeaponType.CharacterWeaponType_Stick,
}

static func is_pet_id(id: int) -> bool:
    return id >= Proto.AssetIDRange.AssetIDRange_Pet_Start and id <= Proto.AssetIDRange.AssetIDRange_Pet_End

static func is_character_id(id: int) -> bool:
    return id >= Proto.AssetIDRange.AssetIDRange_Character_Start and id <= Proto.AssetIDRange.AssetIDRange_Character_End

# 根据运行期资源 ID 返回对应图集路径.
# 调用方只传宠物或角色 ID, 资源类型由配置表约定的 ID 范围推导.
static func get_atlas_path(id: int) -> String:
    if is_pet_id(id):
        return "%s/%d.png" % [ASSET_PET_DIR, id]
    if is_character_id(id):
        return "%s/%d.png" % [ASSET_CHARACTER_DIR, id]

    assert(false, "资源ID不属于宠物或角色范围: %d" % id)
    return ""
