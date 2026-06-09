class_name PetConstants
extends RefCounted

# 宠物动作定义同时保存显示顺序和中文标签, 用于动画构建、托盘菜单和测试页兜底.
const ACTIONS := [
	{"id": "attack", "label": "攻击"},
	{"id": "faint", "label": "倒下"},
	{"id": "hurt", "label": "受击"},
	{"id": "defense", "label": "防御"},
	{"id": "stand", "label": "待机"},
	{"id": "walk", "label": "行走"},
	{"id": "attackShort", "label": "短攻击"},
]

static func get_action_ids() -> Array:
	var ids := []
	for action in ACTIONS:
		var action_data: Dictionary = action
		var action_id := str(action_data.get("id", ""))
		if not action_id.is_empty():
			ids.append(action_id)
	return ids

static func get_action_label(action_id: String) -> String:
	for action in ACTIONS:
		var action_data: Dictionary = action
		if str(action_data.get("id", "")) == action_id:
			return str(action_data.get("label", action_id))
	return action_id
