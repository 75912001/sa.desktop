class_name CombatBattleStartFactory
extends RefCounted

# 生成 CombatBattleStart 的本地工厂.
# 当前只负责自动遇敌的第一版开战快照: 从运行期账号记录生成己方可见单位,
# 从敌人组配置随机生成敌方宠物. 回合指令和结算流程后续再接入.

const MAX_SIDE_UNITS := PB.CombatCampPosition.CombatCampPosition_Count
const MAX_CARRIED_PETS := 5
const INITIATOR_CHARACTER_POSITION_START := 0
const CARRIED_PET_POSITION_START := 5

var rng := RandomNumberGenerator.new()

func _init() -> void:
    rng.randomize()

func create_for_current_record():
    assert(GRecord.record != null, "生成开战快照前必须存在运行期账号记录.")

    var battle_start = GPB.CombatBattleStart.new()
    var battle_id := _new_battle_id()
    battle_start.set_BattleID(battle_id)

    var character_record = _default_character_record()
    var character_uuid := int(character_record.get_UUID())
    var character_asset_records: Dictionary = character_record.get_AssetIDRecordMap()
    var character_id := int(character_asset_records.get(GPB.AssetIDRecord.AssetIDRecord_AssetID, 0))
    assert(Share.is_character_id(character_id), "开战角色资源 ID 非法: %d" % character_id)

    _add_character_unit(battle_start, character_uuid, character_id, character_asset_records)
    _add_pet_units(battle_start, character_record, character_uuid, character_id)
    _add_enemy_units(battle_start, battle_id, _random_enemy_group(), character_asset_records)

    assert(not battle_start.get_UnitList().is_empty(), "开战快照没有任何可见单位.")
    return battle_start

func _new_battle_id() -> int:
    var unix_msec := int(Time.get_unix_time_from_system() * 1000.0)
    return unix_msec * 1000 + rng.randi_range(1, 999)

func _default_character_record():
    var character_map: Dictionary = GRecord.record.get_CharacterRecordMap()
    assert(not character_map.is_empty(), "生成开战快照失败: 没有角色记录.")

    var character_keys := character_map.keys()
    character_keys.sort()
    return character_map[character_keys[0]]

func _add_character_unit(battle_start, character_uuid: int, character_id: int, asset_records: Dictionary) -> void:
    var unit = battle_start.add_UnitList()
    _set_unit_key(unit, character_uuid, 0)
    unit.set_Camp(GPB.CombatCamp.CombatCamp_Initiator)
    unit.set_Position(INITIATOR_CHARACTER_POSITION_START)
    unit.set_CharacterID(character_id)
    unit.set_PetID(0)
    unit.set_MountPetID(0)

    var vitality := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Vitality)
    var strength := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Strength)
    var toughness := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Toughness)
    var dexterity := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Dexterity)
    var hp := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_HP)

    var attribute = unit.new_Attribute()
    attribute.set_Exp(_record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Exp))
    attribute.set_HP(maxi(hp, vitality * 4 + strength + toughness + dexterity))
    attribute.set_Attack(maxi(1, int(float(strength) + float(toughness) * 0.1 + float(vitality) * 0.1 + float(dexterity) * 0.05)))
    attribute.set_Defense(maxi(1, int(float(toughness) + float(strength) * 0.1 + float(vitality) * 0.1 + float(dexterity) * 0.05)))
    attribute.set_Agility(maxi(1, dexterity))
    attribute.set_Loyalty(0)

func _add_pet_units(battle_start, character_record, character_uuid: int, character_id: int) -> void:
    var pet_map: Dictionary = character_record.get_PetRecordMap()
    if pet_map.is_empty():
        return

    var pet_keys := pet_map.keys()
    pet_keys.sort()
    var pet_count := mini(pet_keys.size(), MAX_CARRIED_PETS)
    for index in range(pet_count):
        var pet_uuid := int(pet_keys[index])
        var pet_record = pet_map[pet_keys[index]]
        var asset_records: Dictionary = pet_record.get_AssetRecordBaseMap()
        var pet_id := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_AssetID)
        assert(Share.is_pet_id(pet_id), "开战宠物资源 ID 非法: %d" % pet_id)
        var pet_entry: ConfigPet.Entry = GCfgMgr.pet_config.get_by_id(pet_id)
        assert(pet_entry != null, "开战宠物配置不存在: %d" % pet_id)

        var unit = battle_start.add_UnitList()
        _set_unit_key(unit, character_uuid, pet_uuid)
        unit.set_Camp(GPB.CombatCamp.CombatCamp_Initiator)
        unit.set_Position(CARRIED_PET_POSITION_START + index)
        unit.set_CharacterID(character_id)
        unit.set_PetID(pet_id)
        unit.set_MountPetID(0)

        var pet_exp := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Exp)
        var raw_vital := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Pet_Raw_Vitality)
        var raw_str := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Pet_Raw_Strength)
        var raw_tough := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Pet_Raw_Toughness)
        var raw_dex := _record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Pet_Raw_Dexterity)

        var attribute = unit.new_Attribute()
        attribute.set_Exp(pet_exp)
        attribute.set_HP(GPetCalculator.calculate_pet_hp(raw_vital, raw_str, raw_tough, raw_dex))
        attribute.set_Attack(GPetCalculator.calculate_pet_attack(raw_vital, raw_str, raw_tough, raw_dex))
        attribute.set_Defense(GPetCalculator.calculate_pet_defense(raw_vital, raw_str, raw_tough, raw_dex))
        attribute.set_Agility(GPetCalculator.calculate_pet_agility(raw_vital, raw_str, raw_tough, raw_dex))
        attribute.set_Loyalty(_record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Pet_Loyalty))

func _add_enemy_units(battle_start, battle_id: int, enemy_group: ConfigEnemyGroup.EnemyGroupEntry, character_asset_records: Dictionary) -> void:
    assert(enemy_group != null, "自动遇敌敌人组不能为空.")
    var selected_enemies := _select_enemies(enemy_group)
    for index in range(mini(selected_enemies.size(), MAX_SIDE_UNITS)):
        var enemy = selected_enemies[index]
        assert(enemy != null, "自动遇敌敌人选择结果包含空值: group=%d index=%d" % [enemy_group.id, index])

        var pet_id := int(enemy.id)
        var pet_entry: ConfigPet.Entry = GCfgMgr.pet_config.get_by_id(pet_id)
        assert(pet_entry != null, "自动遇敌敌人宠物配置不存在: %d" % pet_id)

        var level := _enemy_level(enemy_group, enemy, character_asset_records)
        var generated_attributes := GPetCalculator.create_pet(pet_id, level)
        var raw_vital := int(generated_attributes[GPetCalculator.KEY_RAW_VITAL])
        var raw_str := int(generated_attributes[GPetCalculator.KEY_RAW_STR])
        var raw_tough := int(generated_attributes[GPetCalculator.KEY_RAW_TOUGH])
        var raw_dex := int(generated_attributes[GPetCalculator.KEY_RAW_DEX])

        var unit = battle_start.add_UnitList()
        _set_unit_key(unit, 0, _enemy_pet_uuid(battle_id, index))
        unit.set_Camp(GPB.CombatCamp.CombatCamp_Defender)
        unit.set_Position(index)
        unit.set_CharacterID(0)
        unit.set_PetID(pet_id)
        unit.set_MountPetID(0)

        var attribute = unit.new_Attribute()
        attribute.set_Exp(GCfgMgr.exp.get_level_min_exp(level))
        attribute.set_HP(GPetCalculator.calculate_pet_hp(raw_vital, raw_str, raw_tough, raw_dex))
        attribute.set_Attack(GPetCalculator.calculate_pet_attack(raw_vital, raw_str, raw_tough, raw_dex))
        attribute.set_Defense(GPetCalculator.calculate_pet_defense(raw_vital, raw_str, raw_tough, raw_dex))
        attribute.set_Agility(GPetCalculator.calculate_pet_agility(raw_vital, raw_str, raw_tough, raw_dex))
        attribute.set_Loyalty(0)

func _set_unit_key(unit, character_uuid: int, pet_uuid: int) -> void:
    var key = unit.new_Key()
    key.set_CharacterUUID(character_uuid)
    key.set_PetUUID(pet_uuid)

func _enemy_pet_uuid(battle_id: int, index: int) -> int:
    return battle_id * 100 + index + 1

func _random_enemy_group() -> ConfigEnemyGroup.EnemyGroupEntry:
    var group_ids: Array[int] = GCfgMgr.enemy_group_config.get_enemy_group_ids()
    assert(not group_ids.is_empty(), "自动遇敌没有可用敌人组.")

    var group_id := group_ids[rng.randi_range(0, group_ids.size() - 1)]
    var enemy_group: ConfigEnemyGroup.EnemyGroupEntry = GCfgMgr.enemy_group_config.get_enemy_group(group_id)
    assert(enemy_group != null, "自动遇敌随机到不存在的敌人组: %d" % group_id)
    return enemy_group

func _select_enemies(enemy_group: ConfigEnemyGroup.EnemyGroupEntry) -> Array:
    var enemies: Array = enemy_group.enemies
    assert(not enemies.is_empty(), "自动遇敌敌人组没有 enemies: %d" % enemy_group.id)

    if enemy_group.is_boss:
        return enemies.slice(0, mini(enemies.size(), MAX_SIDE_UNITS))

    var target_count := _enemy_target_count(enemy_group)
    var required := []
    var weighted := []
    for enemy in enemies:
        assert(enemy != null, "自动遇敌敌人组包含空 enemy: %d" % enemy_group.id)
        var weight := int(enemy.weight)
        if weight <= 0:
            required.append(enemy)
        else:
            weighted.append(enemy)

    var selected := []
    for enemy in required:
        if selected.size() >= MAX_SIDE_UNITS:
            break
        selected.append(enemy)

    target_count = clampi(maxi(target_count, selected.size()), 1, MAX_SIDE_UNITS)
    while selected.size() < target_count:
        var next_enemy = _choose_weighted_enemy(weighted)
        if next_enemy == null:
            next_enemy = required[selected.size() % required.size()] if not required.is_empty() else null
        assert(next_enemy != null, "自动遇敌敌人组无法选择下一个 enemy: %d" % enemy_group.id)
        selected.append(next_enemy)

    return selected

func _enemy_target_count(enemy_group: ConfigEnemyGroup.EnemyGroupEntry) -> int:
    var min_count := clampi(enemy_group.count_range.x, 1, MAX_SIDE_UNITS)
    var max_count := clampi(enemy_group.count_range.y, min_count, MAX_SIDE_UNITS)
    return rng.randi_range(min_count, max_count)

func _enemy_level(enemy_group: ConfigEnemyGroup.EnemyGroupEntry, enemy: ConfigEnemyGroup.EnemyEntry, character_asset_records: Dictionary) -> int:
    if enemy.level > 0:
        return enemy.level

    if enemy_group.role_level_offset != Vector2i.ZERO:
        var character_exp := _record_value(character_asset_records, GPB.AssetIDRecord.AssetIDRecord_Exp)
        var character_level := GCfgMgr.exp.get_level(character_exp)
        var offset := rng.randi_range(enemy_group.role_level_offset.x, enemy_group.role_level_offset.y)
        return clampi(character_level + offset, GPB.LevelRange.LevelRange_Min, GPB.LevelRange.LevelRange_Max)

    return rng.randi_range(enemy_group.level_range.x, enemy_group.level_range.y)

func _choose_weighted_enemy(weighted: Array):
    var total_weight := 0
    for enemy in weighted:
        assert(enemy != null, "自动遇敌权重敌人列表包含空 enemy.")
        total_weight += max(int(enemy.weight), 0)

    if total_weight <= 0:
        return null

    var roll := rng.randi_range(1, total_weight)
    var current := 0
    for enemy in weighted:
        assert(enemy != null, "自动遇敌权重敌人列表包含空 enemy.")
        current += max(int(enemy.weight), 0)
        if roll <= current:
            return enemy

    return null

func _record_value(asset_records: Dictionary, key: int, default_value: int = 0) -> int:
    return int(asset_records.get(key, default_value))
