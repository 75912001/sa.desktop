extends Control

# GameScene 消费 GRecord 中已经由登录流程准备好的角色, 并在透明窗口内展示角色站立动画.
# 后续真实游戏主界面可以继续挂在这个场景里, 主场景仍只负责切换内容场景.
const CHARACTER_POSITION := Vector2(400, 360)

var status_label: Label
var info_label: Label
var character_root: Node2D
var character_player: CharacterFramePlayer
var auto_encounter_controller

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()
    _show_character()
    _start_auto_encounter_controller()

# 游戏场景也不绘制全屏背景, 只绘制文本和角色动画.
func _build_ui() -> void:
    var top_margin := MarginContainer.new()
    top_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    top_margin.offset_bottom = 130
    top_margin.add_theme_constant_override("margin_left", 24)
    top_margin.add_theme_constant_override("margin_top", 18)
    top_margin.add_theme_constant_override("margin_right", 24)
    add_child(top_margin)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 8)
    top_margin.add_child(vbox)

    var title := Label.new()
    title.text = "游戏场景"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title)

    info_label = Label.new()
    info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vbox.add_child(info_label)

    status_label = Label.new()
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(status_label)

    character_root = Node2D.new()
    character_root.position = CHARACTER_POSITION
    add_child(character_root)

func _show_character() -> void:
    assert(GRecord.record != null, "没有运行期角色记录.")

    var character_record = _default_character_record()
    assert(character_record != null, "没有角色记录.")

    var asset_records: Dictionary = character_record.get_AssetIDRecordMap()
    var character_id := int(asset_records.get(GPB.AssetIDRecord.AssetIDRecord_AssetID, 0))
    var character_entry: ConfigCharacter.Entry = GCfgMgr.character_config.get_by_id(character_id)
    assert(character_entry != null, "角色配置不存在: %d" % character_id)

    info_label.text = "%s  角色:%s  HP:%s 活力:%s 腕力:%s 耐力:%s 敏捷:%s" % [
        str(character_record.get_Nick()),
        character_entry.name,
        _asset_record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_HP),
        _asset_record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Vitality),
        _asset_record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Strength),
        _asset_record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Toughness),
        _asset_record_value(asset_records, GPB.AssetIDRecord.AssetIDRecord_Character_Attributes_Dexterity),
    ]
    _set_status("角色已进入游戏.")

    character_player = CharacterFramePlayer.new()
    # 游戏页按角色资源原始尺寸 100% 显示, 不额外放大.
    character_player.scale = Vector2.ONE
    character_root.add_child(character_player)
    character_player.play_character(
        character_id,
        GPB.CharacterWeaponType.CharacterWeaponType_Unarmed,
        GPB.AssetDirection.AssetDirection_Down,
        GPB.CharacterAction.CharacterAction_Stand,
        Vector2.ZERO
    )

func _default_character_record():
    var character_map: Dictionary = GRecord.record.get_CharacterRecordMap()
    assert(not character_map.is_empty(), "没有角色记录.")

    var character_keys := character_map.keys()
    character_keys.sort()
    return character_map[character_keys[0]]

func _asset_record_value(asset_records: Dictionary, key: int) -> String:
    return str(int(asset_records.get(key, 0)))

func _set_status(text: String) -> void:
    status_label.text = text

# 自动遇敌只在游戏页生命周期内生效.
# 控制器挂为 GameScene 子节点后, 离开游戏页进入战斗时会随当前场景释放, 不需要额外清理计时状态.
func _start_auto_encounter_controller() -> void:
    auto_encounter_controller = AutoEncounterController.new()
    auto_encounter_controller.name = "AutoEncounterController"
    add_child(auto_encounter_controller)
