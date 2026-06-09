class_name DirectionConstants
extends RefCounted

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
