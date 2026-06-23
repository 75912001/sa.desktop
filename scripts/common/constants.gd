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
const CONFIG_PET_SKILL_PATH := "res://config/pet.skill.yaml"
const CONFIG_CHARACTER_PATH := "res://config/character.yaml"
const CONFIG_ENEMY_GROUP_PATH := "res://config/enemy.group.yaml"
const CONFIG_EXP_PATH := "res://config/exp.yaml"

# 配置文件分为两类:
# - `config/tray.yaml.tpl` 是入库模板, 保存完整注释, 字段契约和首启配置.
# - `tray.yaml` 是本地运行期文件, 首次缺失时从模板复制生成, 后续由程序整体覆盖写回.
#
# 读取阶段不使用代码默认值补齐字段; 必填字段缺失或类型错误会 assert, 让配置问题在启动阶段暴露.
# 写回阶段会覆盖整个 `tray.yaml`, 因此运行期文件不承担说明文档职责; 需要看注释时查看模板.
const CONFIG_TRAY_PATH := "res://tray.yaml"
const CONFIG_TRAY_TEMPLATE_PATH := "res://config/tray.yaml.tpl"

# 菜单字号允许被配置, 但必须限制到可用范围内.
# 这里 clamp 的目标是避免手工配置出极小或极大的菜单, 不是用默认值吞掉错误字段.
const TRAY_MENU_MIN_FONT_SIZE := 8
const TRAY_MENU_MAX_FONT_SIZE := 32

# 托盘主题颜色字段契约.
# 这些 key 必须在 `menu.colors` 中完整出现; 读取时按该顺序生成强类型颜色字典.
# 配置中额外颜色字段会被忽略, 避免未消费字段误导后续维护者以为已经生效.
const TRAY_COLOR_KEYS: Array[String] = [
    "panel",
    "border",
    "text",
    "hover_text",
    "highlight",
    "pressed",
    "disabled_text",
]

# 缩放和透明度的边界统一放在这里, 确保托盘输入、配置恢复和窗口控制器调用走同一套约束.
const WINDOW_MIN_SCALE := 0.1
const WINDOW_MAX_SCALE := 1.0
const WINDOW_MIN_OPACITY := 0.1
const WINDOW_MAX_OPACITY := 1.0

# 主窗口业务页面路径由 MainWindow 和 GTray 复用.
# 页面切换只替换 MainWindow/ContentRoot 下的子场景, 不调用全局 change_scene_to_file().
const GAME_SCENE := "res://scenes/game.tscn"
const COMBAT_SCENE := "res://scenes/combat.tscn"

# 当前主窗口统一使用 800x600.
const WINDOW_SIZE := Vector2i(800, 600)

# 调试红边只用于测试透明窗口边界.
# 它画在 MainWindow 根节点上, 不创建 Control 节点, 因此不会拦截游戏页的鼠标输入.
const DEBUG_BORDER_COLOR := Color(1, 0, 0, 1)
const DEBUG_BORDER_WIDTH := 2.0
const WINDOW_GUIDE_LINE_COLOR := Color(0.1, 0.85, 1.0, 0.55)
const WINDOW_GUIDE_LINE_WIDTH := 1.0
const WINDOW_GUIDE_POINT_COLOR := Color(1.0, 0.95, 0.2, 0.95)
const WINDOW_GUIDE_TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const WINDOW_GUIDE_POINT_RADIUS := 3.0
const WINDOW_GUIDE_TEXT_FONT_SIZE := 12
const WINDOW_GUIDE_TEXT_OFFSET := Vector2(6.0, 14.0)
const WINDOW_GUIDE_TEXT_EDGE_PADDING := 4.0

# 角色元素字段顺序由 GRecord 生成运行期记录时复用.
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

# pet.yaml 单宠物 attribute 段只允许这些来自 pet_growth_8_0.csv 的原始字段.
# 字段名直接对应配置源命名, 不接受大小写变体或临时别名, 避免配置拼写错误被静默吞掉.
const PET_ATTRIBUTE_KEYS := ["poisonResist", "paralysisResist", "sleepResist", "stoneResist", "drunkResist", "confusionResist", "critical", "counter"]

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
