class_name Share
extends RefCounted

const Proto := preload("res://proto/sa.pb.gd")

# 读取必填配置项.
# path 使用人类可读的配置路径, 让 assert 信息能直接指向缺失字段.
static func _required_value(source: Dictionary, key: String, path: String):
    assert(source.has(key), "配置缺少必填字段: %s" % path)
    return source[key]

# 读取必填字典配置项.
# 用在配置结构边界, 确保后续 `as Dictionary` 是安全的.
static func _required_dictionary(source: Dictionary, key: String, path: String) -> Dictionary:
    var value = _required_value(source, key, path)
    assert(value is Dictionary, "配置字段必须是字典: %s" % path)
    return value as Dictionary

# 读取整数.
# YAML 手写时可能把数字写成字符串, 这里允许合法整数字符串, 但不允许空值或任意文本.
static func _int_value(value) -> int:
    if value is int or value is float:
        return int(value)
    if value is String and value.strip_edges().is_valid_int():
        return int(value)
    assert(false, "托盘配置整数无效: %s" % str(value))
    return 0

# 读取浮点数.
# 与整数读取保持一致, 合法浮点字符串会被接受, 非数值直接 assert.
static func _float_value(value) -> float:
    if value is int or value is float:
        return float(value)
    if value is String and value.strip_edges().is_valid_float():
        return float(value)
    assert(false, "托盘配置浮点数无效: %s" % str(value))
    return 0.0

# 读取布尔值.
# 允许 YAML 解析出的 bool, 也允许手写字符串 true/false; 其它值不做真假兜底.
static func _bool_value(value) -> bool:
    if value is bool:
        return value
    if value is String:
        var text: String = value.strip_edges().to_lower()
        if text == "true":
            return true
        if text == "false":
            return false
    assert(false, "托盘配置布尔值无效: %s" % str(value))
    return false

static func is_pet_id(id: int) -> bool:
    return id >= Proto.AssetIDRange.AssetIDRange_Pet_Start and id <= Proto.AssetIDRange.AssetIDRange_Pet_End

static func is_pet_skill_id(id: int) -> bool:
    return id >= Proto.AssetIDRange.AssetIDRange_Pet_Skill_Start and id <= Proto.AssetIDRange.AssetIDRange_Pet_Skill_End

static func is_character_id(id: int) -> bool:
    return id >= Proto.AssetIDRange.AssetIDRange_Character_Start and id <= Proto.AssetIDRange.AssetIDRange_Character_End

# 根据运行期资源 ID 返回对应图集路径.
# 调用方只传宠物或角色 ID, 资源类型由配置表约定的 ID 范围推导.
static func get_atlas_path(id: int) -> String:
    if is_pet_id(id):
        return "%s/%d.png" % [Constants.ASSET_PET_DIR, id]
    if is_character_id(id):
        return "%s/%d.png" % [Constants.ASSET_CHARACTER_DIR, id]

    assert(false, "资源ID不属于宠物或角色范围: %d" % id)
    return ""
