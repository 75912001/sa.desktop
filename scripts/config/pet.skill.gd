class_name ConfigPetSkill
extends RefCounted

# 统一读取 config/pet.skill.yaml 的宠物技能配置.
# 技能表独立于宠物主体配置, ConfigPet 只保存每个宠物的技能槽位 ID.
# 宠物槽位引用是否合法由 ConfigPet.check() 在跨配置检查阶段验证.

class Entry extends RefCounted:
    var id: int
    var name: String
    var description: String

    func show() -> String:
        return name

# 技能 ID -> Entry.
# Dictionary[int, Entry] 的 int 表示 config/pet.skill.yaml 中 skill 段的技能 ID.
# ConfigManager.get_shared() 首次创建共享管理器时统一加载, 后续查询复用这份内存缓存.
var _by_id: Dictionary[int, Entry] = {}

# 配置管理流程的第一步.
# 读取 skill 段并建立技能 ID 索引; 同一配置文件内的结构, 字段和重复 ID 在这里校验.
func load() -> void:
    var config_data := ConfigManager.load_yaml(Constants.CONFIG_PET_SKILL_PATH)
    assert(config_data.has("skill"), "宠物技能配置缺少 skill 段: %s" % Constants.CONFIG_PET_SKILL_PATH)
    var raw_skills = config_data.get("skill", [])
    assert(raw_skills is Array, "宠物技能配置 skill 段不是数组: %s" % Constants.CONFIG_PET_SKILL_PATH)
    assert(not (raw_skills as Array).is_empty(), "宠物技能配置中没有解析到 skill 数据: %s" % Constants.CONFIG_PET_SKILL_PATH)

    for skill_item in raw_skills:
        assert(skill_item is Dictionary, "宠物技能条目须为对象: %s" % Constants.CONFIG_PET_SKILL_PATH)
        var skill_data := skill_item as Dictionary

        var entry := Entry.new()
        entry.id = int(skill_data.get("id", 0))
        assert(Constants.is_pet_skill_id(entry.id), "宠物技能ID超出范围: %d" % entry.id)
        assert(not _by_id.has(entry.id), "宠物技能ID重复: %d" % entry.id)

        entry.name = str(skill_data.get("name", ""))
        assert(not entry.name.is_empty(), "宠物技能名称为空: ID:%d" % entry.id)
        entry.description = str(skill_data.get("description", ""))
        assert(not entry.description.is_empty(), "宠物技能描述为空: ID:%d" % entry.id)

        _by_id[entry.id] = entry

# 配置管理流程的第二步.
# 宠物技能配置没有跨表引用, 单表结构已在 load() 阶段完成.
func check() -> void:
    pass

# 配置管理流程的第三步.
# 宠物技能配置没有额外派生缓存, 保留空实现以匹配配置管理生命周期.
func assemble() -> void:
    pass

# 返回 config/pet.skill.yaml 中声明过的技能 ID.
# Godot 4 Dictionary 会保留插入顺序, 这里的 keys() 顺序与 YAML 中 skill 段的声明顺序一致.
func get_ids() -> Array[int]:
    var ids: Array[int] = []
    for skill_id in _by_id.keys():
        ids.append(int(skill_id))
    return ids

# 判断 config/pet.skill.yaml 是否声明了指定技能 ID.
func has_id(skill_id: int) -> bool:
    return _by_id.has(skill_id)

# 根据技能 ID 返回结构化宠物技能配置.
func get_by_id(skill_id: int) -> Entry:
    return _by_id.get(skill_id, null) as Entry
