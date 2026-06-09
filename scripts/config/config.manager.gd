class_name ConfigManager
extends RefCounted

const ConstantsScript := preload("res://scripts/common/constants.gd")

# 保存整个运行期间共享的配置管理器实例.
# 第一次调用 ConfigManager.get_shared() 时创建, 后续调用都会复用同一个对象, 避免重复解析 YAML.
static var _shared_manager = null

# 这三个字段分别持有具体配置管理器.
# ConfigManager 只负责统一创建、加载、校验和组装, 具体查询逻辑仍放在各自的配置类里.
var pet_config: PetConfig
var character_config: CharacterConfig
var enemy_group_config: EnemyGroupConfig

# RefCounted 没有 Node 的 _ready() 生命周期.
# 这里的 _init() 会在执行 ConfigManager.new() 时立即调用, 用来先创建空的子配置管理器.
func _init() -> void:
	_create_managers()

# 对外获取共享配置入口.
# 调用顺序是:
# 1. 业务代码调用 ConfigManager.get_shared().
# 2. 如果还没有共享实例, 这里执行 ConfigManager.new().
# 3. new() 会自动触发 _init(), 先创建 pet/character/enemy_group 三个子管理器.
# 4. 回到 get_shared(), 再调用 load_all_cfg() 统一加载、校验和组装配置.
# 5. 返回已经准备好的共享管理器; 后续 get_shared() 直接返回缓存实例.
static func get_shared() -> ConfigManager:
	if _shared_manager == null:
		_shared_manager = ConfigManager.new()
		_shared_manager.load_all_cfg()
	return _shared_manager

# 统一 YAML 读取入口, 由各配置类的 load(path) 调用.
# 这个函数不属于 Godot 自动生命周期, 只是普通静态工具函数.
# YAML 标准不允许使用 tab 缩进, 配置源文件必须保持标准空格缩进.
# 这里直接解析原始内容, 不在读取阶段修正不规范格式, 让配置错误尽早暴露.
static func load_yaml(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		assert(false, "配置文件不存在: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		assert(false, "无法打开配置文件: %s, 错误: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}

	var content := file.get_as_text()
	file.close()

	var result = YAML.parse(content)
	if result.has_error():
		assert(false, "YAML解析失败: %s, 错误: %s" % [path, result.get_error()])
		return {}

	var data = result.get_data()
	if data is Array and data.size() > 0:
		# MiniYAML 可能按多文档格式返回 Array; 项目配置只使用第一份文档.
		data = data[0]

	if not (data is Dictionary):
		assert(false, "配置文件根节点必须是对象: %s" % path)
		return {}

	return data

# 管理规则统一加载所有配置.
# 顺序固定为 load -> check -> assemble:
# load: 读取 YAML 并建立基础缓存和 ID 索引.
# check: 做跨字段或跨配置的校验, 当前先保留入口.
# assemble: 做加载后的组装或预处理, 当前先保留入口.
func load_all_cfg() -> void:
	pet_config.load(ConstantsScript.PET_CONFIG_PATH)
	character_config.load(ConstantsScript.CHARACTER_CONFIG_PATH)
	enemy_group_config.load(ConstantsScript.ENEMY_GROUP_CONFIG_PATH)

	pet_config.check()
	character_config.check()
	enemy_group_config.check()

	pet_config.assemble()
	character_config.assemble()
	enemy_group_config.assemble()

# 创建具体配置管理器实例.
# 这里只创建空对象, 不读取文件; 真正读取发生在 get_shared() 调用的 load_all_cfg() 中.
func _create_managers() -> void:
	pet_config = PetConfig.new()
	character_config = CharacterConfig.new()
	enemy_group_config = EnemyGroupConfig.new()
