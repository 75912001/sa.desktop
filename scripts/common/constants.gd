class_name Constants
extends RefCounted

# 项目配置文件、资源路径、动画画布参数和枚举集中放在这里, 避免配置解析、资源检查、动画构建和测试页各维护一份.

# 配置文件路径由 ConfigManager 统一读取.
# 这些 YAML 是运行时配置源数据, 读取时会在内存中做 tab 归一化, 不修改源文件.
const PET_CONFIG_PATH := "res://config/pet.yaml"
const CHARACTER_CONFIG_PATH := "res://config/character.yaml"
const ENEMY_GROUP_CONFIG_PATH := "res://config/enemy.group.yaml"

# 宠物资源目录和偏移总表路径由动画构建器和测试页共用.
# 每个宠物仍使用同 ID 的 PNG 和 .tpsheet, offsets.json 保存 pet_id -> frame_id -> [x, y] 的偏移映射.
const PET_ASSET_DIR := "res://assets/pet"
const PET_OFFSETS_PATH := "res://assets/pet/offsets.json"

# padding 给动画画布四周留一点空白, 避免极限帧贴到窗口边缘.
const ANIMATION_PADDING := Vector2(24.0, 24.0)

# 项目动画配置中的 8 方向统一定义.
# 这个顺序需要和 config/pet.yaml, config/character.yaml, config/tray_menu.yaml 中的方向名保持一致.
# 运行时动画名会由 `动作_方向` 组成, 例如 `stand_down` 或 `attack_left`.
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
