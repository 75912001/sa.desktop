class_name CombatFormation
extends Node

# CombatFormation 由 project.godot 注册为 GCombatFormation Autoload.
# 它只负责战斗展示的站位纯计算, 不读取配置, 不创建战斗单位节点, 也不访问窗口状态.
# CombatScene 会通过全局 GCombatFormation 读取锚点并交给具体 FramePlayer.

# 战斗站位当前固定为窗口坐标. position_index 仍使用协议中的 0-9,
# 这里按数组顺序映射到配置注释里的 1-10 号点位.
const INITIATOR_POSITIONS: Array[Vector2] = [
    Vector2(560.0, 420.0),
    Vector2(480.0, 480.0),
    Vector2(640.0, 360.0),
    Vector2(400.0, 540.0),
    Vector2(720.0, 300.0),
    Vector2(480.0, 360.0),
    Vector2(400.0, 420.0),
    Vector2(560.0, 300.0),
    Vector2(320.0, 480.0),
    Vector2(640.0, 240.0),
]

const DEFENDER_POSITIONS: Array[Vector2] = [
    Vector2(240.0, 180.0),
    Vector2(160.0, 240.0),
    Vector2(320.0, 120.0),
    Vector2(80.0, 300.0),
    Vector2(400.0, 60.0),
    Vector2(320.0, 240.0),
    Vector2(240.0, 300.0),
    Vector2(400.0, 180.0),
    Vector2(160.0, 360.0),
    Vector2(480.0, 120.0),
]


func position_for(camp: int, position_index: int) -> Vector2:
    assert(camp == PB.CombatCamp.CombatCamp_Initiator or camp == PB.CombatCamp.CombatCamp_Defender, "未知战斗阵营: %d" % camp)
    assert(position_index >= 0 and position_index < PB.CombatCampPosition.CombatCampPosition_Count, "战斗站位索引越界: %d" % position_index)

    if camp == PB.CombatCamp.CombatCamp_Defender:
        return DEFENDER_POSITIONS[position_index]

    return INITIATOR_POSITIONS[position_index]


func z_index_for(camp: int, position_index: int) -> int:
    # Godot 2D 中 z_index 越大越后绘制. 直接按锚点 y 排序, 可以让屏幕下方单位覆盖上方单位.
    return int(position_for(camp, position_index).y)
