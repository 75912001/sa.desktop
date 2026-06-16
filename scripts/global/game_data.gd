extends Node

# GGameData 是项目运行期的全局数据入口, 通过 Godot Autoload 在主场景之前加入场景树.
# 它不直接解析 YAML 或扫描资源, 而是负责在启动阶段触发 ConfigManager 的共享实例初始化.
# 这样后续业务脚本可以直接访问 GGameData.pet_config / GGameData.character_config 等全局入口,
# 不需要在各自脚本里显式调用 ConfigManager.get_shared() 来间接触发配置加载.

var _config_manager: ConfigManager = null

# 共享配置总入口.
# 属性 getter 会先调用 _ensure_initialized(), 防止某些脚本在 GGameData._ready() 前访问全局数据时拿到空值.
var config_manager: ConfigManager:
    get:
        _ensure_initialized()
        return _config_manager

# 宠物配置表入口, 可通过宠物 ID 查询完整的 ConfigPet.Entry.
var pet_config: ConfigPet:
    get:
        return config_manager.pet

# 角色配置表入口, 给角色播放缓存和测试页按 ID 查询角色配置.
var character_config: ConfigCharacter:
    get:
        return config_manager.character

# 敌人组配置表入口, 给战斗展示场景按 enemyGroupId 查询敌方单位配置.
var enemy_group_config: ConfigEnemyGroup:
    get:
        return config_manager.enemy_group

# Autoload 节点 ready 时主动初始化共享配置.
# project.godot 中会把 GGameData 放在 YAML Autoload 后面, 保证 MiniYAML 已经可用于 ConfigManager.load_yaml().
func _ready() -> void:
    _ensure_initialized()

# 确保配置只初始化一次.
# ConfigManager.get_shared() 内部顺序固定为 assets load -> config load -> config check -> assemble.
# ConfigAssets 会先扫描同 ID 动画资源, ConfigPet.assemble() 和 ConfigCharacter.assemble() 再挂载帧表引用.
func _ensure_initialized() -> void:
    if _config_manager != null:
        return

    _config_manager = ConfigManager.get_shared()
