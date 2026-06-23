extends Node

# GRecord 是运行期 AccountRecord 的全局入口.
# 它不再读取或写入本地记录文件; 登录时直接创建一份内存记录, 后续页面只消费这份记录.
# 这样第一版流程可以稳定进入游戏页, 同时保留和服务端协议一致的 AccountRecord 数据结构.

const DEFAULT_CHARACTER_ID := 1000011
const DEFAULT_CHARACTER_NAME := "吉米"
const DEFAULT_HP := 10
const DEFAULT_CHARACTER_ATTRIBUTE := 10
const DEFAULT_CHARACTER_AVAILABLE_POINT := 0
const DEFAULT_PET_LOYALTY := 100
const DEFAULT_ELEMENTAL := {
    "earth": 10,
    "water": 0,
    "fire": 0,
    "wind": 0,
}
const DEFAULT_PET_RECORDS := [
    {
        "asset_id": 4000101,
        "nick": "利则诺顿",
        "exp": 0,
    },
    {
        "asset_id": 4000102,
        "nick": "扬奇洛斯",
        "exp": 0,
    },
]

# 当前登录账号的运行期记录实例.
# 第一版没有本地存档和后端登录, 所以它只在点击登录后创建, 进程退出后自然丢弃.
var record = null

# 创建一份新的运行期 AccountRecord.
# 登录流程直接创建固定默认角色, 记录只保存在本次运行内存中.
func create_record() -> void:
    _validate_default_record_data()

    record = GPB.AccountRecord.new()
    record.set_UsedUUID(0)

    var character_record = _create_default_character_record()
    _add_default_pet_records(character_record)

# 校验写死在 GRecord 内的默认账号数据.
# 这些数据不是外部输入, 但它们决定登录后能否进入游戏页; 启动链路应在错误数据进入协议记录前直接暴露问题.
func _validate_default_record_data() -> void:
    assert(Share.is_character_id(DEFAULT_CHARACTER_ID), "账号记录角色资源 ID 非法: %d" % DEFAULT_CHARACTER_ID)
    assert(not DEFAULT_CHARACTER_NAME.is_empty(), "账号记录 Nick 不能为空.")

    for raw_pet_record_data in DEFAULT_PET_RECORDS:
        var pet_record_data: Dictionary = raw_pet_record_data as Dictionary
        var pet_asset_id: int = int(pet_record_data["asset_id"])
        var pet_nick: String = str(pet_record_data["nick"])
        assert(Share.is_pet_id(pet_asset_id), "宠物记录资源 ID 非法: %d" % pet_asset_id)
        assert(not pet_nick.is_empty(), "宠物记录 Nick 不能为空.")

# 创建默认角色并写入角色基础协议字段.
# 返回值是 Godobuf 生成的 CharacterRecord 实例; 这里不额外声明具体类型, 避免脚本和生成协议类形成不必要的强类型耦合.
func _create_default_character_record():
    var character_uuid: int = _next_uuid()
    var character_record = record.add_CharacterRecordMap(character_uuid)
    character_record.set_UUID(character_uuid)
    character_record.set_Nick(DEFAULT_CHARACTER_NAME)

    var asset_records: Dictionary = {
        GPB.AssetIDRecord.AssetIDRecord_AssetID: DEFAULT_CHARACTER_ID,
        GPB.AssetIDRecord.AssetIDRecord_HP: DEFAULT_HP,
        GPB.AssetIDRecord.AssetIDRecord_ElementalEarth: DEFAULT_ELEMENTAL["earth"],
        GPB.AssetIDRecord.AssetIDRecord_ElementalWater: DEFAULT_ELEMENTAL["water"],
        GPB.AssetIDRecord.AssetIDRecord_ElementalFire: DEFAULT_ELEMENTAL["fire"],
        GPB.AssetIDRecord.AssetIDRecord_ElementalWind: DEFAULT_ELEMENTAL["wind"],
        GPB.AssetIDRecord.AssetIDRecord_Character_Available_Point: DEFAULT_CHARACTER_AVAILABLE_POINT,
        GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Vitality: DEFAULT_CHARACTER_ATTRIBUTE,
        GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Strength: DEFAULT_CHARACTER_ATTRIBUTE,
        GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Toughness: DEFAULT_CHARACTER_ATTRIBUTE,
        GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Dexterity: DEFAULT_CHARACTER_ATTRIBUTE,
    }
    for asset_key in asset_records:
        character_record.add_AssetIDRecordMap(int(asset_key), int(asset_records[asset_key]))

    return character_record

# 为默认角色挂载第一版内置宠物记录.
# 宠物记录属于角色下的 map, 所以调用方必须先创建角色记录.
func _add_default_pet_records(character_record) -> void:
    for raw_pet_record_data in DEFAULT_PET_RECORDS:
        var pet_record_data: Dictionary = raw_pet_record_data as Dictionary
        _add_default_pet_record(character_record, pet_record_data)

# 把单个默认宠物转换成 Godobuf PetRecord.
# DEFAULT_PET_RECORDS 使用便于人工维护的字段名, 写入协议时在这里集中转换成 AssetIDRecord 枚举字段.
func _add_default_pet_record(character_record, pet_record_data: Dictionary) -> void:
    var pet_uuid: int = _next_uuid()
    var pet_asset_id: int = int(pet_record_data["asset_id"])
    var pet_nick: String = str(pet_record_data["nick"])
    var pet_exp := int(pet_record_data["exp"])

    var pet_record = character_record.add_PetRecordMap(pet_uuid)
    pet_record.set_UUID(pet_uuid)
    pet_record.set_Nick(pet_nick)

    var level := GCfgMgr.exp.get_level(pet_exp)
    var generated_attributes := GPetCalculator.create_pet(pet_asset_id, level)
    var asset_records: Dictionary = {
        GPB.AssetIDRecord.AssetIDRecord_AssetID: pet_asset_id,
        GPB.AssetIDRecord.AssetIDRecord_Exp: pet_exp,
        GPB.AssetIDRecord.AssetIDRecord_Pet_Loyalty: DEFAULT_PET_LOYALTY,
        GPB.AssetIDRecord.AssetIDRecord_Pet_SavedBase_Vitality: int(generated_attributes[GPetCalculator.KEY_SAVED_BASE_VITAL]),
        GPB.AssetIDRecord.AssetIDRecord_Pet_SavedBase_Strength: int(generated_attributes[GPetCalculator.KEY_SAVED_BASE_STR]),
        GPB.AssetIDRecord.AssetIDRecord_Pet_SavedBase_Toughness: int(generated_attributes[GPetCalculator.KEY_SAVED_BASE_TOUGH]),
        GPB.AssetIDRecord.AssetIDRecord_Pet_SavedBase_Dexterity: int(generated_attributes[GPetCalculator.KEY_SAVED_BASE_DEX]),
        GPB.AssetIDRecord.AssetIDRecord_Pet_Raw_Vitality: int(generated_attributes[GPetCalculator.KEY_RAW_VITAL]),
        GPB.AssetIDRecord.AssetIDRecord_Pet_Raw_Strength: int(generated_attributes[GPetCalculator.KEY_RAW_STR]),
        GPB.AssetIDRecord.AssetIDRecord_Pet_Raw_Toughness: int(generated_attributes[GPetCalculator.KEY_RAW_TOUGH]),
        GPB.AssetIDRecord.AssetIDRecord_Pet_Raw_Dexterity: int(generated_attributes[GPetCalculator.KEY_RAW_DEX]),
    }
    for asset_key in asset_records:
        pet_record.add_AssetRecordBaseMap(int(asset_key), int(asset_records[asset_key]))

# 从当前账号记录中分配新的运行期 UUID.
# UsedUUID 存在 AccountRecord 里, 保证同一份内存记录中的角色和宠物使用同一个递增序列.
func _next_uuid() -> int:
    assert(record != null, "生成 UUID 前必须先创建账号记录.")
    var uuid: int = int(record.get_UsedUUID()) + 1
    record.set_UsedUUID(uuid)
    return uuid
