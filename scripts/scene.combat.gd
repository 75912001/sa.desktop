class_name CombatScene
extends Node2D

@onready var unit_root: Node2D = $UnitRoot

var combat_units := []

# 根据外部开战快照生成一场战斗展示.
# CombatScene 不再内置模拟战斗或敌人组选择逻辑, 避免展示层和战斗创建规则重复维护.
func start_combat(battle_start) -> void:
    assert(battle_start != null, "开战快照不能为空.")
    _clear_units()

    # CombatBattleStart 是业务边界数据, CombatScene 只消费其中的显示资源 ID, 阵营和站位,
    # 不在展示层重新计算属性、等级或战斗规则.
    var unit_list: Array = battle_start.get_UnitList()
    assert(not unit_list.is_empty(), "开战快照没有可见单位: battle_id=%s" % str(battle_start.get_BattleID()))
    for unit_snapshot in unit_list:
        assert(unit_snapshot != null, "开战快照包含空单位.")

        var position_index := int(unit_snapshot.get_Position())
        assert(position_index >= 0 and position_index < PB.CombatCampPosition.CombatCampPosition_Count, "战斗单位站位越界: %d" % position_index)

        var camp := int(unit_snapshot.get_Camp())
        var direction := GPB.AssetDirection.AssetDirection_UpLeft
        if camp == GPB.CombatCamp.CombatCamp_Defender:
            direction = GPB.AssetDirection.AssetDirection_DownRight
        elif camp != GPB.CombatCamp.CombatCamp_Initiator:
            assert(false, "未知战斗阵营: %d" % camp)

        var character_id := int(unit_snapshot.get_CharacterID())
        var pet_id := int(unit_snapshot.get_PetID())
        assert(character_id != 0 or pet_id != 0, "战斗单位 CharacterID 和 PetID 不能同时为空.")

        var unit_id := pet_id
        if unit_id == 0:
            unit_id = character_id
        assert(Share.is_pet_id(unit_id) or Share.is_character_id(unit_id), "战斗单位 ID 不在已知配置范围内: id=%d" % unit_id)

        var target_anchor_position: Vector2 = GCombatFormation.position_for(camp, position_index)
        var unit: FramePlayer = PetFramePlayer.new() if Share.is_pet_id(unit_id) else CharacterFramePlayer.new()
        unit.name = "camp_%d_%d_%d" % [camp, unit_id, position_index]
        unit_root.add_child(unit)

        if unit is PetFramePlayer:
            (unit as PetFramePlayer).play_pet(
                unit_id,
                direction,
                GPB.PetAction.PetAction_Stand,
                target_anchor_position
            )
        else:
            (unit as CharacterFramePlayer).play_character(
                unit_id,
                GPB.CharacterWeaponType.CharacterWeaponType_Unarmed,
                direction,
                GPB.CharacterAction.CharacterAction_Stand,
                target_anchor_position
            )

        unit.z_index = GCombatFormation.z_index_for(camp, position_index)
        combat_units.append(unit)

    queue_redraw()

# 清空战斗单位, 用于重置展示内容.
func clear_combat() -> void:
    _clear_units()
    queue_redraw()

# 释放旧单位.
# `queue_free()` 会在安全时机删除节点, 适合在运行中清场.
func _clear_units() -> void:
    for unit in combat_units:
        if is_instance_valid(unit):
            unit.queue_free()
    combat_units.clear()
