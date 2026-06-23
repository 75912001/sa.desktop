extends Control

# 这个测试页用于手动观察角色动画的偏移效果.
# 和宠物测试页不同, 角色会按四个颜色变体一组同时预览.
# 重点观察目标: 同一个动作和方向下, 四个角色变体是否同步播放, 锚点是否稳定.

# Godot 学习提示:
# - 这个脚本是一个完整的 Control 测试页, UI 主体来自 .tscn, 预览格里的播放器由代码动态创建.
# - 代码里同时使用了 Control 系 UI 和 Node2D 系绘制节点: Control 负责按钮, 下拉框和布局; Node2D 负责绘制图集帧.
# - 角色动画不是预先做成 Godot AnimationPlayer 资源, 而是在运行时由 AssetsConfig 先准备同 ID 帧表, ConfigCharacter.load() 读取 YAML, ConfigCharacter.Entry 按方向/武器/动作缓存 PlayInfo.
# - 每个角色变体使用独立 SubViewport, 这样四个播放器可以在同一 UI 页面中并排显示, 且每个播放器有自己的 2D 坐标系.
# - CharacterFramePlayer 的辅助线用于观察锚点横线, 锚点竖线和当前帧矩形, 方便对照运行期帧数据和图集切片结果.
# - 如果要学习 Godot 的节点生命周期, 信号连接, 动态创建节点, 子视口, 输入事件和资源加载流程, 可以从 _ready() 开始顺着调用链阅读.

# 默认打开测试页时优先选择的角色组 ID.
# 角色资源 ID 形如 1000011, 1000012, 1000013, 1000014.
# 去掉最后一位颜色编号后, 前面的 100001 就是这里的角色组 ID.
const DEFAULT_GROUP_ID := 100001
# 测试窗口尺寸. 角色页要同时显示四个预览槽, 所以比宠物页更宽更高.
const TEST_WINDOW_SIZE := Vector2i(1080, 760)
# 单个角色预览槽里的动画区域大小.
const PREVIEW_CELL := Vector2i(300, 230)
# 预览槽里的固定锚点位置.
# CharacterFramePlayer 的局部原点就是动画锚点, 四个颜色变体共用同一坐标, 方便比较锚点是否稳定.
const PREVIEW_ANCHOR_POSITION := Vector2(150.0, 160.0)
# 一个角色组固定包含四个颜色变体, 最后一位编号分别是 1, 2, 3, 4.
const GROUP_SIZE := 4
# 角色测试页的 UI 仍显示配置协议字符串, 但这些字符串只在测试页边界转成运行期枚举.
const ACTIONS := ["attack", "wave", "faint", "hurt", "defense", "sad", "angry", "sit", "stand", "throw", "nod", "walk", "happy"]
const WEAPON_TYPES := ["unarmed", "axe", "bow", "spear", "stick"]
# 键盘左右键切方向时使用这个顺序. 右键按顺时针方向循环, 左键按相反方向循环.
const DIRECTION_SHORTCUT_ORDER := ["upleft", "up", "upright", "right", "downright", "down", "downleft", "left"]

# @onready 表示等场景节点都创建完成后, 再按节点唯一名称拿到引用.
# 这些变量连接到 test_character_offsets.tscn 中的 UI 控件.
# 循环播放开关. 勾选后每个预览槽的 CharacterFramePlayer 播到末尾会回到第一帧.
@onready var _loop_check: CheckBox = %LoopCheck
# 顶部标题标签, 显示当前角色组和武器类型.
@onready var _title_label: Label = %Title
# 角色组下拉框, 每一项是一组四个颜色变体.
@onready var _character_select: OptionButton = %CharacterSelect
# 武器类型下拉框. ConfigCharacter 加载期已经要求每个角色具备全部武器类型, 这里直接使用公共武器类型顺序.
@onready var _weapon_select: OptionButton = %WeaponSelect
# 播放/暂停按钮. Button 的 pressed 状态会传给 _on_play_toggled.
@onready var _play_button: Button = %PlayButton
# 上一帧按钮, 用于暂停后同步查看四个变体的前一帧.
@onready var _prev_button: Button = %PrevButton
# 下一帧按钮, 用于暂停后同步查看四个变体的后一帧.
@onready var _next_button: Button = %NextButton
# 辅助线开关. 勾选后四个预览槽都会画出锚点横线, 锚点竖线和当前帧矩形.
@onready var _guides_check: CheckBox = %GuidesCheck
# 动作按钮容器. 代码会按 ACTIONS 动态往里面添加 Button.
@onready var _action_grid: GridContainer = %ActionGrid
# 方向按钮容器. 代码会按九宫格布局动态添加方向 Button 和占位节点.
@onready var _direction_grid: GridContainer = %DirectionGrid
# 四个角色预览槽所在的容器.
@onready var _preview_grid: GridContainer = %PreviewGrid

# ButtonGroup 可以让一组 Button 像单选按钮一样工作, 同一时间只有一个动作被选中.
var _action_group := ButtonGroup.new()
# 方向按钮也用单选组, 避免同时选中多个方向.
var _direction_group := ButtonGroup.new()
# 动作名到按钮节点的映射, 用于键盘快捷键改变动作后同步按钮选中状态.
var _action_buttons: Dictionary[String, Button] = {}
# 方向名到按钮节点的映射, 用于键盘快捷键改变方向后同步按钮选中状态.
var _direction_buttons: Dictionary[String, Button] = {}
# 角色组数据. key 是组 ID, value 是四个角色 ID.
# Dictionary[int, Array] 的 key int 是角色组 ID, value 中的 Array 元素是 character_id.
var _character_groups: Dictionary[int, Array] = {}
# 当前可用的角色组 ID 列表, 用于构建下拉框.
# Array[int] 中的 int 表示角色组 ID.
var _available_group_ids: Array[int] = []
# 当前可选武器类型列表, 固定来自本测试页的显示顺序.
var _available_weapons: Array[String] = []
# 四个预览槽的数据列表. 每个槽保存角色 ID, 标题 Label, root 和 player.
var _preview_slots: Array[Dictionary] = []
# 当前正在预览的角色组 ID.
var _current_group_id := DEFAULT_GROUP_ID
# 当前组内四个角色 ID, 例如 1000011/1000012/1000013/1000014.
# Array[int] 中的 int 表示 character_id.
var _current_character_ids: Array[int] = []
# 当前武器类型. unarmed 表示空手动作配置.
var _current_weapon := "unarmed"
# 当前动作. 默认 stand, 配合 down 组成 stand_down.
var _current_action := "stand"
# 当前方向. 默认 down.
var _current_direction := "down"
# 当前是否播放中. false 时可以用上一帧/下一帧按钮逐帧查看四个槽.
var _playing := true

func _ready() -> void:
    # _ready 是场景进入树后调用的初始化入口.
    # 初始化顺序很重要: 先设置窗口, 再读取角色组, 创建 UI, 连接信号, 最后加载动画.
    _apply_test_window_flags()
    _sync_root_size()
    # 如果用户拖拽调整窗口大小, 重新让根 Control 铺满窗口.
    get_viewport().size_changed.connect(_sync_root_size)
    # 通过 ConfigCharacter 读取角色配置, 再结合资源目录筛选可用的四角色组.
    _character_groups = _load_available_character_groups()
    # 根据可用角色组生成下拉框.
    _build_character_selector()
    # 创建四个预览槽, 分别显示同组的四个颜色变体.
    _create_preview_slots()
    # 根据测试页固定武器类型列表生成武器下拉框; 角色配置加载期已经确保每个角色都具备这些武器类型.
    _build_weapon_selector()
    # 根据 ACTIONS 生成动作按钮.
    _build_action_buttons()
    # 根据方向九宫格生成方向按钮.
    _build_direction_buttons()
    # 连接 UI 信号. 从这里开始, 用户操作会触发回调.
    _connect_controls()
    if _available_group_ids.is_empty() or _available_weapons.is_empty():
        # 没有可用角色组或固定武器类型列表时, 前面的 UI 已经给出提示, 这里停止加载.
        return
    # 加载当前角色组四个变体的图集和已换算 anchor_position 的帧配置.
    _load_group_data()
    # 把当前动作和方向应用到四个播放器.
    _apply_animation()

func _input(event: InputEvent) -> void:
    # 角色页支持键盘快捷键: 左右切方向, 上下切动作.
    if _handle_shortcut_key(event):
        # 标记事件已处理, 避免继续传给其他 UI 节点造成重复响应.
        get_viewport().set_input_as_handled()

func _apply_test_window_flags() -> void:
    # 这个测试页要看清楚 UI 和辅助线, 所以关闭透明背景.
    get_viewport().transparent_bg = false
    # 设置深色背景, 让浅色或彩色 frame 更容易观察.
    RenderingServer.set_default_clear_color(Color(0.12, 0.12, 0.14, 1.0))

    var window := get_window()
    # 下面这些设置只影响测试窗口, 不代表桌宠主窗口行为.
    window.transparent = false
    window.borderless = false
    window.always_on_top = false
    window.unresizable = false
    # 禁用 Godot 的内容缩放, 让像素资源按预期大小显示.
    window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
    window.content_scale_size = TEST_WINDOW_SIZE
    window.size = TEST_WINDOW_SIZE
    # DisplayServer 是 Godot 操作原生窗口的接口.
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)
    DisplayServer.window_set_size(TEST_WINDOW_SIZE)
    # 给窗口一个固定初始位置, 方便每次运行时找到测试页.
    DisplayServer.window_set_position(Vector2i(100, 80))

func _sync_root_size() -> void:
    # custom_minimum_size 告诉布局系统: 这个测试页至少需要这么大.
    custom_minimum_size = Vector2(TEST_WINDOW_SIZE)
    # 让根 Control 铺满窗口, 避免窗口变化后 UI 只占左上角一小块.
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_character_selector() -> void:
    # 重新构建下拉框前先清空旧选项, 防止重复添加.
    _character_select.clear()
    # 角色组列表会根据 _character_groups 重新计算.
    _available_group_ids.clear()
    for group_id in _character_groups.keys():
        _available_group_ids.append(int(group_id))
    # 排序后下拉框顺序稳定, 每次打开都一致.
    _available_group_ids.sort()

    if _available_group_ids.is_empty():
        # 没有完整四角色组时禁用角色和武器类型选择, 并显示明确提示.
        _character_select.disabled = true
        _weapon_select.disabled = true
        _title_label.text = "没有找到资源完整的四角色组"
        return

    # selected_index 记录默认要选中的下拉框索引.
    var selected_index := 0
    for index in range(_available_group_ids.size()):
        var group_id := _available_group_ids[index]
        # 下拉框显示组 ID 和组内四个角色 ID, 方便确认当前预览的是哪组资源.
        # Array[int] 中的 int 表示该角色组内的 character_id.
        var character_ids: Array[int] = _copy_character_ids(_character_groups[group_id])
        _character_select.add_item(_format_group_label(group_id, character_ids))
        if group_id == DEFAULT_GROUP_ID:
            # 如果默认角色组存在, 默认选它; 否则保留第一个可用组.
            selected_index = index

    _current_group_id = _available_group_ids[selected_index]
    # 拷贝一份角色 ID 数组, 避免后续误改 _character_groups 里的原始列表.
    _current_character_ids = _copy_character_ids(_character_groups[_current_group_id])
    _character_select.select(selected_index)
    _update_title()

func _build_weapon_selector() -> void:
    # 角色组变化后, 武器类型列表也要重新生成.
    _weapon_select.clear()
    _available_weapons.clear()
    for weapon in WEAPON_TYPES:
        _available_weapons.append(str(weapon))
    if _available_weapons.is_empty():
        _weapon_select.disabled = true
        _title_label.text = "没有配置角色武器类型列表"
        return

    var selected_index := 0
    for index in range(_available_weapons.size()):
        var weapon := _available_weapons[index]
        _weapon_select.add_item(weapon)
        if weapon == "unarmed":
            # 优先选择空手武器类型, 因为它通常是最基础, 最容易验证的动作集.
            selected_index = index

    _current_weapon = _available_weapons[selected_index]
    _weapon_select.disabled = false
    _weapon_select.select(selected_index)
    _update_title()

func _build_action_buttons() -> void:
    # false 表示按钮按下后不能再被取消到没有任何按钮选中的状态.
    _action_group.allow_unpress = false
    # 记录按钮引用前先清空映射, 避免旧引用残留.
    _action_buttons.clear()
    for action in ACTIONS:
        # 每个动作名创建一个按钮, 不需要在 .tscn 里手工摆所有动作.
        var button := Button.new()
        button.text = action
        # toggle_mode 让普通 Button 具备选中/未选中状态.
        button.toggle_mode = true
        # 关闭焦点, 避免键盘快捷键时按钮焦点干扰观察.
        button.focus_mode = Control.FOCUS_NONE
        # 加入同一个 ButtonGroup 后, 动作按钮变成互斥选择.
        button.button_group = _action_group
        button.custom_minimum_size = Vector2(104.0, 30.0)
        # bind(action) 会把动作名额外传给回调, 回调才能知道用户点了哪个动作.
        button.toggled.connect(_on_action_toggled.bind(action))
        _action_grid.add_child(button)
        _action_buttons[action] = button
        if action == _current_action:
            # 初始化默认按钮状态. no_signal 表示只改按钮外观, 不立刻触发回调.
            button.set_pressed_no_signal(true)

func _build_direction_buttons() -> void:
    _direction_group.allow_unpress = false
    _direction_buttons.clear()
    # 用 3 x 3 布局摆方向按钮, 中间留空, 更接近方向键的直觉.
    var direction_layout := [
        ["upleft", "up", "upright"],
        ["left", "", "right"],
        ["downleft", "down", "downright"],
    ]

    for row in direction_layout:
        for direction in row:
            if direction.is_empty():
                # 空字符串代表九宫格中心占位, 这样 left/right 不会挤在一起.
                var spacer := Control.new()
                spacer.custom_minimum_size = Vector2(86.0, 30.0)
                _direction_grid.add_child(spacer)
                continue

            # 方向按钮的创建方式和动作按钮一致, 只是尺寸稍窄.
            var button := Button.new()
            button.text = direction
            button.toggle_mode = true
            button.focus_mode = Control.FOCUS_NONE
            button.button_group = _direction_group
            button.custom_minimum_size = Vector2(86.0, 30.0)
            button.toggled.connect(_on_direction_toggled.bind(direction))
            _direction_grid.add_child(button)
            _direction_buttons[direction] = button
            if direction == _current_direction:
                button.set_pressed_no_signal(true)

func _connect_controls() -> void:
    # 角色组下拉框选择变化后, 重新加载四个角色变体.
    _character_select.item_selected.connect(_on_character_group_selected)
    # 武器类型下拉框选择变化后, 用同一武器类型重新生成四个角色的动画数据.
    _weapon_select.item_selected.connect(_on_weapon_selected)
    # 播放按钮是 toggle button, 所以使用 toggled 信号读取 pressed 状态.
    _play_button.toggled.connect(_on_play_toggled)
    # bind(-1) 和 bind(1) 把按钮变成上一帧/下一帧.
    _prev_button.pressed.connect(_step_frame.bind(-1))
    _next_button.pressed.connect(_step_frame.bind(1))
    # 循环和辅助线都是开关, 直接把勾选状态同步给所有播放器.
    _loop_check.toggled.connect(_on_loop_toggled)
    _guides_check.toggled.connect(_on_guides_toggled)

func _create_preview_slots() -> void:
    # 重新创建预览槽前先清理旧节点, 防止重复显示.
    for child in _preview_grid.get_children():
        child.queue_free()
    _preview_slots.clear()
    # 四个角色按 2 x 2 排列.
    _preview_grid.columns = 2

    for index in range(GROUP_SIZE):
        # 每个 PanelContainer 是一个角色变体的预览卡片.
        var panel := PanelContainer.new()
        panel.custom_minimum_size = Vector2(PREVIEW_CELL.x + 24.0, PREVIEW_CELL.y + 36.0)
        _preview_grid.add_child(panel)

        # 垂直布局: 标题和子视口. 帧信息文本已移除, 只保留画面和辅助线观察.
        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 6)
        panel.add_child(box)

        # 标题显示角色 ID, 加载前先显示通用文字.
        var title := Label.new()
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        title.text = "角色"
        box.add_child(title)

        # SubViewportContainer 用来把 Node2D 播放器嵌入 Control UI.
        var viewport_container := SubViewportContainer.new()
        viewport_container.custom_minimum_size = Vector2(PREVIEW_CELL)
        viewport_container.stretch = true
        box.add_child(viewport_container)

        # 每个角色变体使用独立 SubViewport, 互不影响绘制和坐标.
        var viewport := SubViewport.new()
        viewport.transparent_bg = true
        # 预览视口不单独处理输入, 输入仍由主测试页处理.
        viewport.handle_input_locally = false
        viewport.size = PREVIEW_CELL
        viewport_container.add_child(viewport)

        # root 的位置就是预览槽中的固定角色锚点, 不再根据当前动作帧内容反推显示范围.
        var root := Node2D.new()
        viewport.add_child(root)

        # CharacterFramePlayer 接收角色帧序列, 并通过底层 FramePlayer 对齐动画锚点.
        var player := CharacterFramePlayer.new()
        player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        root.add_child(player)

        # Dictionary 让每个槽位的节点和状态放在一起, 后面循环更新更方便.
        _preview_slots.append({
            "character_id": 0,
            "title": title,
            "panel": panel,
            "root": root,
            "player": player,
        })

func _load_available_character_groups() -> Dictionary[int, Array]:
    # 先找到所有资源完整的角色 ID.
    var ids := _load_available_character_ids()
    # 再按组 ID 收集. 例如 1000011/1000012/1000013/1000014 都属于 100001.
    # Dictionary[int, Array] 的 key int 是角色组 ID, value 中的 Array 元素是 character_id.
    var ids_by_group: Dictionary[int, Array] = {}
    for character_id in ids:
        var group_id := int(float(character_id) / 10.0)
        if not ids_by_group.has(group_id):
            # Array[int] 中的 int 表示当前组内的 character_id.
            var group_ids: Array[int] = []
            ids_by_group[group_id] = group_ids
        ids_by_group[group_id].append(character_id)

    # 只保留完整四颜色变体的组.
    # Dictionary[int, Array] 的 key int 是完整角色组 ID, value 中的 Array 元素是 character_id.
    var groups: Dictionary[int, Array] = {}
    for group_id in ids_by_group.keys():
        # Array[int] 中的 int 表示同一角色组内的 character_id.
        var character_ids: Array[int] = ids_by_group[group_id]
        character_ids.sort()
        if _has_complete_color_group(character_ids):
            groups[group_id] = character_ids

    return groups

func _load_available_character_ids() -> Array[int]:
    # 返回值只包含资源完整的角色, 这样测试页不会展示无法播放的角色.
    # Array[int] 中的 int 表示 character_id.
    var ids: Array[int] = []
    var character_config: ConfigCharacter = GCfgMgr.character_config
    for character_id in character_config.get_ids():
        if character_id <= 0 or not _has_character_entry(character_config, character_id):
            continue

        # 只有 ConfigCharacter.Entry 已挂载已合成帧表时才加入列表; `.tpsheet` offset 已在加载阶段换算为 anchor_position.
        ids.append(character_id)

    # 排序后角色组和下拉框顺序稳定.
    ids.sort()
    return ids

func _has_character_entry(character_config: ConfigCharacter, character_id: int) -> bool:
    # 可播放资源完整性已经由 ConfigCharacter.assemble() 断言, 测试页不再维护第二套判断规则.
    return character_config.get_by_id(character_id) != null

func _has_complete_color_group(character_ids: Array[int]) -> bool:
    # Array[int] 中的 int 表示同一角色组内的 character_id.
    # 角色组必须刚好有四个颜色变体.
    if character_ids.size() != GROUP_SIZE:
        return false

    for index in range(GROUP_SIZE):
        # 编号最后一位必须按 1, 2, 3, 4 排列, 这样才能确认是完整颜色组.
        if int(character_ids[index]) % 10 != index + 1:
            return false

    return true

func _load_group_data() -> void:
    # 当前角色组或武器类型变化后先刷新标题.
    _update_title()
    for index in range(_preview_slots.size()):
        var slot := _preview_slots[index]
        if index >= _current_character_ids.size():
            # 理论上完整组有四个角色, 这里保留保护逻辑, 防止数据异常时空槽显示旧内容.
            _set_slot_visible(slot, false)
            continue

        var character_id := _current_character_ids[index]
        # 从 slot 字典中取出这个槽位对应的 UI 节点和播放器.
        var title := slot["title"] as Label
        var root := slot["root"] as Node2D
        var player := slot["player"] as CharacterFramePlayer

        _set_slot_visible(slot, true)
        title.text = str(character_id)
        # 更新槽位状态. 现在每格不再显示帧信息, 只保留内部状态供同步播放使用.
        slot["character_id"] = character_id
        # 切换角色组或武器时销毁旧播放器, 后续 _apply_animation 会按当前动作和方向创建新画面.
        root.remove_child(player)
        player.queue_free()
        player = CharacterFramePlayer.new()
        player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        root.add_child(player)
        slot["player"] = player
        _sync_player_guides(player)
        root.position = PREVIEW_ANCHOR_POSITION
        _preview_slots[index] = slot

func _apply_animation() -> void:
    var direction_value := _direction_from_key(_current_direction)
    assert(direction_value != GPB.AssetDirection.AssetDirection_Unknow, "角色偏移测试方向未知: %s" % _current_direction)
    var weapon_value := _weapon_type_from_key(_current_weapon)
    assert(weapon_value != GPB.CharacterWeaponType.CharacterWeaponType_Unknow, "角色偏移测试武器类型未知: %s" % _current_weapon)
    var action_value := _character_action_from_key(_current_action)
    assert(action_value != GPB.CharacterAction.CharacterAction_Unknow, "角色偏移测试动作未知: %s" % _current_action)

    # 四个预览槽使用同一个 direction/weapon/action key, 保证颜色变体同步切换动作和方向.
    for index in range(_preview_slots.size()):
        var slot := _preview_slots[index]
        var character_id := int(slot.get("character_id", 0))
        if character_id <= 0:
            continue

        var character_entry := GCfgMgr.character_config.get_by_id(character_id)
        assert(character_entry != null, "角色偏移测试角色配置不存在: character:%d" % character_id)
        var play_info := character_entry.get_play_info(direction_value, weapon_value, action_value)

        var root := slot["root"] as Node2D
        var player := slot["player"] as CharacterFramePlayer
        player.play(
            character_entry.atlas,
            character_entry.frame_by_id,
            play_info.ids,
            Constants.ANIMATION_DEFAULT_SPEED,
            Constants.ANIMATION_DEFAULT_LOOP
        )
        root.position = PREVIEW_ANCHOR_POSITION
        player.position = Vector2.ZERO
        _sync_player_guides(player)
        _sync_player_loop(player)
        _sync_player_playing(player)
        _preview_slots[index] = slot

func _set_slot_visible(slot: Dictionary, slot_visible: bool) -> void:
    # 预览槽是否显示由最外层 PanelContainer 控制.
    var panel := slot["panel"] as PanelContainer
    panel.visible = slot_visible

func _on_character_group_selected(index: int) -> void:
    # 下拉框传入的是选项索引, 不是角色组 ID, 所以先做范围检查.
    if index < 0 or index >= _available_group_ids.size():
        return

    var group_id := _available_group_ids[index]
    if group_id == _current_group_id:
        # 选中的仍是当前角色组时不重复加载资源.
        return

    _current_group_id = group_id
    # 切换角色组后, 四个角色 ID, 武器类型下拉框和动画数据都需要更新.
    _current_character_ids = _copy_character_ids(_character_groups[_current_group_id])
    _build_weapon_selector()
    _load_group_data()
    _apply_animation()

func _on_weapon_selected(index: int) -> void:
    # 下拉框传入的是选项索引, 不是武器类型名, 所以先做范围检查.
    if index < 0 or index >= _available_weapons.size():
        return

    var weapon := _available_weapons[index]
    if weapon == _current_weapon:
        # 选中的仍是当前武器类型时不重复加载资源.
        return

    _current_weapon = weapon
    # 武器类型变化后, character.yaml 中对应的帧列表会变化, 所以要重建四个槽位的播放数据.
    _load_group_data()
    _apply_animation()

func _on_action_toggled(pressed: bool, action: String) -> void:
    if not pressed:
        # ButtonGroup 切换时, 旧按钮也会发出 pressed=false, 这里忽略取消选中的那次信号.
        return

    _select_action(action)

func _on_direction_toggled(pressed: bool, direction: String) -> void:
    if not pressed:
        return

    _select_direction(direction)

func _on_play_toggled(pressed: bool) -> void:
    # pressed=true 表示按钮处于播放状态, pressed=false 表示暂停.
    _playing = pressed
    _play_button.text = "暂停" if _playing else "播放"
    for slot in _preview_slots:
        # 四个预览槽同步播放或暂停.
        var player := slot["player"] as CharacterFramePlayer
        _sync_player_playing(player)

func _on_loop_toggled(_pressed: bool) -> void:
    for slot in _preview_slots:
        # 循环只影响播到最后一帧后的行为, 不会立刻重置当前帧.
        var player := slot["player"] as CharacterFramePlayer
        _sync_player_loop(player)

func _on_guides_toggled(_pressed: bool) -> void:
    for slot in _preview_slots:
        # 辅助线由底层 FramePlayer 的 _draw 绘制, 包括锚点横线, 锚点竖线和当前帧矩形.
        var player := slot["player"] as CharacterFramePlayer
        _sync_player_guides(player)

func _sync_player_playing(player: FramePlayer) -> void:
    if _playing:
        player.start()
    else:
        player.pause()

func _sync_player_loop(player: FramePlayer) -> void:
    if _loop_check.button_pressed:
        player.enable_loop()
    else:
        player.disable_loop()

func _sync_player_guides(player: FramePlayer) -> void:
    if _guides_check.button_pressed:
        player.enable_guides()
    else:
        player.disable_guides()

func _step_frame(delta_frames: int) -> void:
    # 手动逐帧时先把播放按钮改成未按下, 避免自动播放继续推进帧.
    _play_button.set_pressed_no_signal(false)
    _on_play_toggled(false)
    for slot in _preview_slots:
        # delta_frames 为 -1 表示上一帧, 1 表示下一帧.
        var player := slot["player"] as CharacterFramePlayer
        player.step_frame(delta_frames)

func _handle_shortcut_key(event: InputEvent) -> bool:
    # _input 可能收到鼠标, 手柄等事件. 这里先尝试转成键盘事件.
    var key_event := event as InputEventKey
    if key_event == null or not key_event.pressed or key_event.echo:
        # echo 是按住键时系统自动重复产生的事件, 这里忽略它, 避免切换过快.
        return false

    match key_event.keycode:
        KEY_LEFT:
            # 左右键按 DIRECTION_SHORTCUT_ORDER 切方向.
            _select_direction_by_delta(-1)
            return true
        KEY_RIGHT:
            _select_direction_by_delta(1)
            return true
        KEY_UP:
            # 上下键按 ACTIONS 顺序切动作.
            _select_action_by_delta(-1)
            return true
        KEY_DOWN:
            _select_action_by_delta(1)
            return true

    return false

func _select_action_by_delta(delta_actions: int) -> void:
    # 找到当前动作在 ACTIONS 中的位置.
    var current_index := ACTIONS.find(_current_action)
    if current_index < 0:
        # 理论上不会发生, 这里兜底回到第一个动作.
        current_index = 0

    # posmod 可以处理负数, 所以从第一个动作向上切会绕到最后一个动作.
    var next_index := posmod(current_index + delta_actions, ACTIONS.size())
    _select_action(str(ACTIONS[next_index]))

func _select_direction_by_delta(delta_directions: int) -> void:
    # 找到当前方向在快捷键顺序中的位置.
    var current_index := DIRECTION_SHORTCUT_ORDER.find(_current_direction)
    if current_index < 0:
        current_index = 0

    # posmod 可以处理负数, 所以方向切换可以循环.
    var next_index := posmod(current_index + delta_directions, DIRECTION_SHORTCUT_ORDER.size())
    _select_direction(str(DIRECTION_SHORTCUT_ORDER[next_index]))

func _select_action(action: String) -> void:
    if _current_action == action:
        # 如果只是同步按钮状态, 不需要重新播放动画.
        _sync_action_button()
        return

    _current_action = action
    # 键盘快捷键不会自动改变 ButtonGroup 外观, 所以要手动同步按钮状态.
    _sync_action_button()
    _apply_animation()

func _select_direction(direction: String) -> void:
    if _current_direction == direction:
        _sync_direction_button()
        return

    _current_direction = direction
    # 键盘快捷键不会自动改变 ButtonGroup 外观, 所以要手动同步按钮状态.
    _sync_direction_button()
    _apply_animation()

func _sync_action_button() -> void:
    # 遍历动作按钮映射, 让当前动作对应的按钮显示为按下.
    for action in _action_buttons.keys():
        var button := _action_buttons[action] as Button
        # set_pressed_no_signal 避免同步外观时再次触发 _on_action_toggled.
        button.set_pressed_no_signal(str(action) == _current_action)

func _sync_direction_button() -> void:
    # 遍历方向按钮映射, 让当前方向对应的按钮显示为按下.
    for direction in _direction_buttons.keys():
        var button := _direction_buttons[direction] as Button
        button.set_pressed_no_signal(str(direction) == _current_direction)

func _direction_from_key(key: String) -> int:
    match key:
        "up":
            return GPB.AssetDirection.AssetDirection_Up
        "upright":
            return GPB.AssetDirection.AssetDirection_UpRight
        "right":
            return GPB.AssetDirection.AssetDirection_Right
        "downright":
            return GPB.AssetDirection.AssetDirection_DownRight
        "down":
            return GPB.AssetDirection.AssetDirection_Down
        "downleft":
            return GPB.AssetDirection.AssetDirection_DownLeft
        "left":
            return GPB.AssetDirection.AssetDirection_Left
        "upleft":
            return GPB.AssetDirection.AssetDirection_UpLeft
        _:
            return GPB.AssetDirection.AssetDirection_Unknow

func _weapon_type_from_key(key: String) -> int:
    match key:
        "unarmed":
            return GPB.CharacterWeaponType.CharacterWeaponType_Unarmed
        "axe":
            return GPB.CharacterWeaponType.CharacterWeaponType_Axe
        "bow":
            return GPB.CharacterWeaponType.CharacterWeaponType_Bow
        "spear":
            return GPB.CharacterWeaponType.CharacterWeaponType_Spear
        "stick":
            return GPB.CharacterWeaponType.CharacterWeaponType_Stick
        _:
            return GPB.CharacterWeaponType.CharacterWeaponType_Unknow

func _character_action_from_key(key: String) -> int:
    match key:
        "attack":
            return GPB.CharacterAction.CharacterAction_Attack
        "wave":
            return GPB.CharacterAction.CharacterAction_Wave
        "faint":
            return GPB.CharacterAction.CharacterAction_Faint
        "hurt":
            return GPB.CharacterAction.CharacterAction_Hurt
        "defense":
            return GPB.CharacterAction.CharacterAction_Defense
        "sad":
            return GPB.CharacterAction.CharacterAction_Sad
        "angry":
            return GPB.CharacterAction.CharacterAction_Angry
        "sit":
            return GPB.CharacterAction.CharacterAction_Sit
        "stand":
            return GPB.CharacterAction.CharacterAction_Stand
        "throw":
            return GPB.CharacterAction.CharacterAction_Throw
        "nod":
            return GPB.CharacterAction.CharacterAction_Nod
        "walk":
            return GPB.CharacterAction.CharacterAction_Walk
        "happy":
            return GPB.CharacterAction.CharacterAction_Happy
        _:
            return GPB.CharacterAction.CharacterAction_Unknow

func _update_title() -> void:
    # 标题显示当前角色组和武器类型, 帮助确认当前四个槽位使用的是哪套动作配置.
    _title_label.text = "%d %s 角色组偏移播放测试" % [_current_group_id, _current_weapon]

func _copy_character_ids(raw_ids: Array[int]) -> Array[int]:
    # _character_groups 中的值是普通 Array, 这里转换成 Array[int], 让后续类型更明确.
    # Array[int] 中的 int 表示 character_id.
    var ids: Array[int] = []
    for character_id in raw_ids:
        ids.append(int(character_id))
    return ids

func _format_group_label(group_id: int, character_ids: Array[int]) -> String:
    # character_ids 的 Array[int] 中, int 表示 character_id.
    # 下拉框文字格式: "100001: 1000011/1000012/1000013/1000014".
    return "%d: %s" % [group_id, _format_character_ids(character_ids)]

func _format_character_ids(character_ids: Array[int]) -> String:
    # Array[int] 中的 int 表示 character_id.
    # 把角色 ID 列表拼成 slash 分隔的字符串, 方便在 UI 中紧凑显示.
    var text := ""
    for index in range(character_ids.size()):
        if index > 0:
            text += "/"
        text += str(character_ids[index])
    return text
