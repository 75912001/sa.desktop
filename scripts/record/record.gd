extends Node

# GRecord 是运行期 AccountRecord 的全局入口.
# 它不再读取或写入本地记录文件; 登录时直接创建一份内存记录, 后续页面只消费这份记录.
# 这样第一版流程可以稳定进入游戏页, 同时保留和服务端协议一致的 AccountRecord 数据结构.

const DEFAULT_CHARACTER_ID := 1000011
const DEFAULT_CHARACTER_NAME := "吉米"
const DEFAULT_HP := 10
const DEFAULT_CHARACTER_ATTRIBUTE := 10
const DEFAULT_ELEMENTAL := {
    "earth": 10,
    "water": 0,
    "fire": 0,
    "wind": 0,
}
const DEFAULT_PET_RECORDS := [
    {
        "asset_id": 4000101,
        "nick": "利則諾頓",
        "exp": 0,
        "hp": 39,
        "attack": 9,
        "defense": 5,
        "agility": 3,
    },
    {
        "asset_id": 4000102,
        "nick": "揚奇洛斯",
        "exp": 0,
        "hp": 51,
        "attack": 10,
        "defense": 7,
        "agility": 5,
    },
]

var record = null

# 创建一份新的运行期 AccountRecord.
# 登录流程直接创建固定默认角色, 记录只保存在本次运行内存中.
func create_record() -> void:
    assert(Constants.is_character_id(DEFAULT_CHARACTER_ID), "账号记录角色资源 ID 非法: %d" % DEFAULT_CHARACTER_ID)
    assert(not DEFAULT_CHARACTER_NAME.is_empty(), "账号记录 Nick 不能为空.")

    record = GPB.AccountRecord.new()
    record.set_UsedUUID(0)

    var character_uuid := _next_uuid()
    var character_record = record.add_CharacterRecordMap(character_uuid)
    character_record.set_UUID(character_uuid)
    character_record.set_Nick(DEFAULT_CHARACTER_NAME)
    var asset_records := {
        GPB.AssetIDRecord.AssetIDRecord_AssetID: DEFAULT_CHARACTER_ID,
        GPB.AssetIDRecord.AssetIDRecord_HP: DEFAULT_HP,
        GPB.AssetIDRecord.AssetIDRecord_ElementalEarth: DEFAULT_ELEMENTAL["earth"],
        GPB.AssetIDRecord.AssetIDRecord_ElementalWater: DEFAULT_ELEMENTAL["water"],
        GPB.AssetIDRecord.AssetIDRecord_ElementalFire: DEFAULT_ELEMENTAL["fire"],
        GPB.AssetIDRecord.AssetIDRecord_ElementalWind: DEFAULT_ELEMENTAL["wind"],
        GPB.AssetIDRecord.AssetIDRecord_Character_AttributesStrength: DEFAULT_CHARACTER_ATTRIBUTE,
        GPB.AssetIDRecord.AssetIDRecord_Character_AttributesEndurance: DEFAULT_CHARACTER_ATTRIBUTE,
        GPB.AssetIDRecord.AssetIDRecord_Character_AttributesAgility: DEFAULT_CHARACTER_ATTRIBUTE,
        GPB.AssetIDRecord.AssetIDRecord_Character_AttributesStamina: DEFAULT_CHARACTER_ATTRIBUTE,
    }
    for asset_key in asset_records.keys():
        character_record.add_AssetIDRecordMap(int(asset_key), int(asset_records[asset_key]))

    for pet_record_data in DEFAULT_PET_RECORDS:
        var pet_uuid := _next_uuid()
        var pet_asset_id := int(pet_record_data["asset_id"])
        var pet_nick := str(pet_record_data["nick"])
        assert(Constants.is_pet_id(pet_asset_id), "宠物记录资源 ID 非法: %d" % pet_asset_id)
        assert(not pet_nick.is_empty(), "宠物记录 Nick 不能为空.")

        var pet_record = character_record.add_PetRecordMap(pet_uuid)
        pet_record.set_UUID(pet_uuid)
        pet_record.set_Nick(pet_nick)
        pet_record.add_AssetRecordBaseMap(GPB.AssetIDRecord.AssetIDRecord_AssetID, pet_asset_id)
        pet_record.add_AssetRecordBaseMap(GPB.AssetIDRecord.AssetIDRecord_Exp, int(pet_record_data["exp"]))
        pet_record.add_AssetRecordBaseMap(GPB.AssetIDRecord.AssetIDRecord_HP, int(pet_record_data["hp"]))
        pet_record.add_AssetRecordBaseMap(GPB.AssetIDRecord.AssetIDRecord_Pet_AttributesAttack, int(pet_record_data["attack"]))
        pet_record.add_AssetRecordBaseMap(GPB.AssetIDRecord.AssetIDRecord_Pet_AttributesDefense, int(pet_record_data["defense"]))
        pet_record.add_AssetRecordBaseMap(GPB.AssetIDRecord.AssetIDRecord_Pet_AttributesAgility, int(pet_record_data["agility"]))

func _next_uuid() -> int:
    assert(record != null, "生成 UUID 前必须先创建账号记录.")
    var uuid := int(record.get_UsedUUID()) + 1
    record.set_UsedUUID(uuid)
    return uuid
