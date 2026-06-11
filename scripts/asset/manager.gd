class_name AssetManager
extends RefCounted

# 项目资产总入口.
# 它先于配置表加载, 负责在启动阶段扫描资源目录, 建立宠物和角色资源索引.
# 配置表的 check() 阶段会使用这里已经准备好的索引, 检查 YAML 中引用的帧是否真的存在.
# 这里本身不解析业务配置, 只关心资源文件是否存在, 图集帧号有哪些, offsets 是否覆盖这些帧.

# 宠物资源索引.
# 负责 assets/pet 下 `{pet_id}.png`, `{pet_id}.tpsheet` 和 offsets 的元数据加载.
var assets_pet: PetAssetManager
# 角色资源索引.
# 负责 assets/character 下 `{character_id}.png`, `{character_id}.tpsheet` 和 offsets 的元数据加载.
var assets_character: CharacterAssetManager

# RefCounted 不会自动进入场景树.
# ConfigManager 创建 AssetManager 时会触发 _init(), 这里只创建子管理器, 不访问文件系统.
func _init() -> void:
	# 直接通过 class_name 创建子管理器, 让资产入口依赖的具体管理器在这里清晰可见.
	assets_pet = PetAssetManager.new()
	assets_character = CharacterAssetManager.new()

# 启动阶段的资源加载入口.
# 这里加载的是资源元数据和索引, 包括 atlas 路径, .tpsheet 帧表和 offsets 偏移表.
# 真实 Texture2D 仍由动画构建器按需 load(), 避免启动时一次性加载所有图集纹理.
func load() -> void:
	# 先加载宠物再加载角色目前没有依赖关系.
	# 顺序保持固定只是为了调试日志和断言输出稳定, 便于定位启动阶段的资源问题.
	assets_pet.load()
	assets_character.load()
