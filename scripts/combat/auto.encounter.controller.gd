class_name AutoEncounterController
extends Node

# GameScene 专用的自动遇敌运行期控制器.
# 它不创建 UI, 也不直接读取敌人组配置细节; 每帧只消费设置窗口写入的
# setting.combat.auto_encounter 状态, 在游戏页停留满固定时间后委托工厂生成开战快照.
# 控制器作为 GameScene 子节点存在, 因此离开游戏页时会随场景释放, 计时自然归零.
const BattleStartFactoryScript := preload("res://scripts/combat/combat.battle.start.factory.gd")

const ENCOUNTER_INTERVAL_SECONDS := 5.0

var elapsed_seconds := 0.0
var triggering := false
var battle_start_factory = BattleStartFactoryScript.new()

func _process(delta: float) -> void:
    if triggering:
        return

    if not _auto_encounter_enabled():
        elapsed_seconds = 0.0
        return

    elapsed_seconds += delta
    if elapsed_seconds < ENCOUNTER_INTERVAL_SECONDS:
        return

    _trigger_encounter()

func _auto_encounter_enabled() -> bool:
    var setting := GTrayConfig.get_setting_state()
    assert(setting.get("combat") is Dictionary, "自动遇敌读取设置失败: setting.combat 必须是字典.")

    var combat_setting := setting["combat"] as Dictionary
    return bool(combat_setting.get("auto_encounter", false))

func _trigger_encounter() -> void:
    triggering = true
    elapsed_seconds = 0.0

    var battle_start = battle_start_factory.create_for_current_record()
    assert(GMainWindow.main_window != null and is_instance_valid(GMainWindow.main_window), "自动遇敌缺少有效 MainWindow, 无法进入战斗.")
    GMainWindow.main_window.switch_to_combat(battle_start)
