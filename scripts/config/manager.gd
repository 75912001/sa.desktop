class_name ConfigManager
extends Node

# ConfigManager 是项目运行期的全局配置入口.
# project.godot 会把它注册为 GCfgMgr Autoload, 让主场景运行前先完成配置初始化.

# 保存整个运行期间共享的配置管理器实例.
# Autoload 场景下指向 GCfgMgr 节点; 非 Autoload 测试场景中首次调用 get_shared() 时会懒创建 fallback 实例.
static var _shared_manager: ConfigManager = null

# 标记共享配置是否已经完成 assets load -> config load -> config check -> assemble.
var _is_initialized := false

# 初始化过程中配置 assemble() 可能通过 ConfigManager.get_shared() 读取 assets.
# 该标记用于避免 get_shared() 在初始化中途再次递归触发完整加载流程.
var _is_initializing := false

# 这些字段分别持有 assets 加载器和具体配置管理器.
# ConfigManager 只负责统一创建、加载、校验和组装, 具体查询逻辑仍放在各自的管理器里.
var assets: AssetsConfig
var petskill: ConfigPetSkill
var pet: ConfigPet
var character: ConfigCharacter
var enemy_group: ConfigEnemyGroup
var exp: ConfigExp

# 共享配置总入口, 保留旧 wrapper 的访问形态, 方便业务脚本通过 GCfgMgr.config_manager 明确拿到自身.
var config_manager: ConfigManager:
    get:
        _ensure_initialized()
        return self

# 宠物配置表入口, 可通过宠物 ID 查询完整的 ConfigPet.Entry.
var pet_config: ConfigPet:
    get:
        _ensure_initialized()
        return pet

# 角色配置表入口, 给角色播放缓存和测试页按 ID 查询角色配置.
var character_config: ConfigCharacter:
    get:
        _ensure_initialized()
        return character

# 敌人组配置表入口, 给战斗展示场景按 enemyGroupId 查询敌方单位配置.
var enemy_group_config: ConfigEnemyGroup:
    get:
        _ensure_initialized()
        return enemy_group

# _init() 只创建各配置管理器对象, 不读取文件.
# 这样节点实例化保持轻量, 真正可能失败的资源目录扫描和 YAML 读取集中在 _ensure_initialized() 的统一流程里.
func _init() -> void:
    assets = AssetsConfig.new()
    petskill = ConfigPetSkill.new()
    pet = ConfigPet.new()
    character = ConfigCharacter.new()
    enemy_group = ConfigEnemyGroup.new()
    exp = ConfigExp.new()

# Autoload 节点进入场景树时, 先把自身登记为共享配置实例.
# 这样初始化过程中 ConfigPet/ConfigCharacter 再调用 ConfigManager.get_shared() 时, 会拿到同一个 GCfgMgr 节点.
func _enter_tree() -> void:
    _shared_manager = self

# Autoload ready 时主动初始化共享配置.
# project.godot 中 GCfgMgr 位于 YAML Autoload 后面, 保证 MiniYAML 已经可用于 ConfigManager.load_yaml().
func _ready() -> void:
    _ensure_initialized()

# 对外获取共享配置入口.
# 调用顺序是:
# 1. 业务代码调用 ConfigManager.get_shared().
# 2. Autoload 场景下直接返回 GCfgMgr; 非 Autoload 测试场景中会先创建 fallback 实例.
# 3. get_shared() 会确保共享实例已经完成初始化, 后续调用直接返回同一份缓存.
static func get_shared() -> ConfigManager:
    if _shared_manager == null:
        _shared_manager = ConfigManager.new()
    _shared_manager._ensure_initialized()
    return _shared_manager

# 确保配置只初始化一次.
# 内部顺序固定为 assets load -> config load -> config check -> assemble.
# ConfigPet.check(petskill) 在 check 阶段校验宠物技能槽位引用; 此时各配置已完成 load().
func _ensure_initialized() -> void:
    if _is_initialized or _is_initializing:
        return

    _is_initializing = true

    # 第一阶段集中扫描 assets.
    # 宠物和角色资源都在这里统一加载, 避免分散到各配置 load() 中隐式读取目录.
    assets.load()

    # 第二阶段读取配置源文件并建立各自的基础缓存.
    # ConfigPetSkill, ConfigPet 和 ConfigCharacter 的 load() 都只解析 YAML, 后续在 check()/assemble() 中校验跨表关系和挂载帧表.
    petskill.load()
    pet.load()
    character.load()
    enemy_group.load()
    exp.load()

    # 第三阶段做校验.
    # 这里资源索引和所有配置都已经完成 load, 可以做跨配置和配置到资源的检查.
    petskill.check()
    pet.check(petskill)
    character.check()
    enemy_group.check(pet)
    exp.check()

    # 第四阶段做组装.
    # 这里适合生成派生缓存或跨配置引用, 例如宠物和角色会挂载同 ID 帧表引用.
    petskill.assemble()
    pet.assemble()
    character.assemble()
    enemy_group.assemble()
    exp.assemble()

    _is_initialized = true
    _is_initializing = false

# 统一 YAML 读取入口, 由各配置类按固定配置路径调用.
# 这个函数不属于 Godot 自动生命周期, 只是普通静态工具函数.
# YAML 标准不允许使用 tab 缩进, 配置源文件必须保持标准空格缩进.
# 这里直接解析原始内容, 不在读取阶段修正不规范格式, 让配置错误尽早暴露.
static func load_yaml(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        assert(false, "配置文件不存在: %s" % path)
        return {} as Dictionary

    # FileAccess.open() 可能因为权限, 路径或导出包缺文件失败.
    # 这里把 Godot 的错误码转成文本写入 assert, 方便启动失败时直接定位到具体配置文件.
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        assert(false, "无法打开配置文件: %s, 错误: %s" % [path, error_string(FileAccess.get_open_error())])
        return {} as Dictionary

    var content := file.get_as_text()
    file.close()

    # MiniYAML 返回的是解析结果对象, 需要先检查 has_error().
    # 不在这里吞掉错误或返回默认配置, 启动阶段应尽早暴露 YAML 格式问题.
    var result = YAML.parse(content)
    if result.has_error():
        assert(false, "YAML解析失败: %s, 错误: %s" % [path, result.get_error()])
        return {} as Dictionary

    var data = result.get_data()
    if data is Array and data.size() > 0:
        # MiniYAML 可能按多文档格式返回 Array; 项目配置只使用第一份文档.
        data = data[0]

    if not (data is Dictionary):
        assert(false, "配置文件根节点必须是对象: %s" % path)
        return {} as Dictionary

    return data as Dictionary
