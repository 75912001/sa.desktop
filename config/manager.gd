class_name ConfigManager
extends RefCounted

# 配置总入口是 RefCounted, 不是 Node.
# 它不会被 Godot 场景树自动调用 _ready(), 只有业务代码主动调用 ConfigManager.get_shared() 时才会创建和加载.

# 保存整个运行期间共享的配置管理器实例.
# 第一次调用 ConfigManager.get_shared() 时创建, 后续调用都会复用同一个对象, 避免重复解析 YAML.
static var _shared_manager = null

# 这些字段分别持有 assets 加载器和具体配置管理器.
# ConfigManager 只负责统一创建、加载、校验和组装, 具体查询逻辑仍放在各自的管理器里.
var assets: AssetsConfig
var pet: ConfigPet
var character: ConfigCharacter
var enemy_group: ConfigEnemyGroup

# RefCounted 没有 Node 的 _ready() 生命周期.
# 这里的 _init() 会在执行 ConfigManager.new() 时立即调用, 用来先创建空的配置管理器.
func _init() -> void:
    # 这里只做对象创建, 不读取文件.
    # 这样 ConfigManager.new() 本身保持轻量, 真正可能失败的资源目录扫描和 YAML 读取集中在 get_shared() 的统一流程里.
    assets = AssetsConfig.new()
    pet = ConfigPet.new()
    character = ConfigCharacter.new()
    enemy_group = ConfigEnemyGroup.new()

# 对外获取共享配置入口.
# 调用顺序是:
# 1. 业务代码调用 ConfigManager.get_shared().
# 2. 如果还没有共享实例, 这里执行 ConfigManager.new().
# 3. new() 会自动触发 _init(), 先创建 pet/character/enemy_group 管理器.
# 4. 回到 get_shared(), 先统一扫描 assets, 再按 config load -> config check -> assemble 顺序初始化.
# 5. 返回已经准备好的共享管理器; 后续 get_shared() 直接返回缓存实例.
static func get_shared() -> ConfigManager:
    if _shared_manager == null:
        # 共享实例只允许初始化一次.
        # 后续业务代码多次读取 GGameData 或 ConfigManager 时, 都会复用这一份已经校验过的缓存.
        _shared_manager = ConfigManager.new()

        # 第一阶段集中扫描 assets.
        # 宠物和角色资源都在这里统一加载, 避免分散到各配置 load() 中隐式读取目录.
        _shared_manager.assets.load()

        # 第二阶段读取配置源文件并建立各自的基础缓存.
        # ConfigPet 和 ConfigCharacter 的 load() 都只解析 YAML, 后续在 assemble() 中挂载帧表.
        _shared_manager.pet.load()
        _shared_manager.character.load()
        _shared_manager.enemy_group.load()

        # 第三阶段做校验.
        # 这里资源索引和所有配置都已经完成 load, 可以做跨配置和配置到资源的检查.
        _shared_manager.pet.check()
        _shared_manager.character.check()
        _shared_manager.enemy_group.check(_shared_manager.pet)

        # 第四阶段做组装.
        # 这里适合生成派生缓存或跨配置引用, 例如宠物技能槽位会引用同 ID 技能 Entry, 宠物和角色会挂载同 ID 帧表引用.
        _shared_manager.pet.assemble()
        _shared_manager.character.assemble()
        _shared_manager.enemy_group.assemble()
    return _shared_manager

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
