class_name ConfigManager
extends RefCounted

# 配置总入口是 RefCounted, 不是 Node.
# 它不会被 Godot 场景树自动调用 _ready(), 只有业务代码主动调用 ConfigManager.get_shared() 时才会创建和加载.

# 保存整个运行期间共享的配置管理器实例.
# 第一次调用 ConfigManager.get_shared() 时创建, 后续调用都会复用同一个对象, 避免重复解析 YAML.
static var _shared_manager = null

# 这个字段持有启动阶段先加载的资产管理器.
# 配置 check() 会使用它检查配置里引用的 PNG, .tpsheet, offsets 和 frame id 是否存在.
var asset_manager: AssetManager

# 这三个字段分别持有具体配置管理器.
# ConfigManager 只负责统一创建、加载、校验和组装, 具体查询逻辑仍放在各自的管理器里.
var config_pet: PetConfig
var config_character: CharacterConfig
var config_enemy_group: EnemyGroupConfig

# RefCounted 没有 Node 的 _ready() 生命周期.
# 这里的 _init() 会在执行 ConfigManager.new() 时立即调用, 用来先创建空的资源和配置管理器.
func _init() -> void:
	_create_managers()

# 对外获取共享配置入口.
# 调用顺序是:
# 1. 业务代码调用 ConfigManager.get_shared().
# 2. 如果还没有共享实例, 这里执行 ConfigManager.new().
# 3. new() 会自动触发 _init(), 先创建 asset 和 pet/character/enemy_group 管理器.
# 4. 回到 get_shared(), 再调用内部的 _load_all_cfg() 统一加载资源、加载配置、校验和组装.
# 5. 返回已经准备好的共享管理器; 后续 get_shared() 直接返回缓存实例.
static func get_shared() -> ConfigManager:
	if _shared_manager == null:
		_shared_manager = ConfigManager.new()
		_shared_manager._load_all_cfg()
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
# 这是 ConfigManager 内部流程, 外部代码应该只通过 get_shared() 获取已经加载好的共享实例.
# 顺序固定为 asset load -> config load -> config check -> assemble:
# asset load: 先扫描 PNG, .tpsheet 和 offsets 资源, 建立资源索引.
# config load: 再读取 YAML 并建立基础缓存和 ID 索引.
# config check: 做跨字段, 跨配置和配置到资源的校验.
# assemble: 做加载后的组装或预处理.
func _load_all_cfg() -> void:
	# 第一阶段先加载资源索引.
	# 配置 check() 会依赖这份索引验证 YAML 里声明的 frame id 是否能在资源中找到.
	asset_manager.load()

	# 第二阶段只读取配置源文件并建立各自的基础缓存.
	# 这个阶段不要做依赖其它配置的组装, 避免读取顺序互相影响.
	config_pet.load(Constants.CONFIG_PET_PATH)
	config_character.load(Constants.CONFIG_CHARACTER_PATH)
	config_enemy_group.load(Constants.CONFIG_ENEMY_GROUP_PATH)

	# 第三阶段做校验.
	# 这里资源和所有配置都已经完成 load, 可以做跨配置和配置到资源的检查.
	config_pet.check(asset_manager)
	config_character.check(asset_manager)
	config_enemy_group.check(config_pet, asset_manager)

	# 第四阶段做组装.
	# 这里适合生成派生缓存或跨配置引用, 当前各配置类先保留入口.
	config_pet.assemble()
	config_character.assemble()
	config_enemy_group.assemble()

# 创建具体资源和配置管理器实例.
# 这里只创建空对象, 不读取文件; 真正读取发生在 get_shared() 调用的 _load_all_cfg() 中.
func _create_managers() -> void:
	asset_manager = AssetManager.new()
	config_pet = PetConfig.new()
	config_character = CharacterConfig.new()
	config_enemy_group = EnemyGroupConfig.new()
