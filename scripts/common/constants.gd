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
