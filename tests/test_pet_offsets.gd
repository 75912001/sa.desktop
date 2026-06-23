extends Control

# 这个测试用于手动观察同类型宠物合并后的锚点对齐效果.
# 宠物 ID 按百位分组, 例如 4000101 到 4000106 会被归为 40001 组并同屏显示.
# 页面上的动作, 方向, 播放, 帧步进, 循环和辅助线控制都会同步作用到当前组的所有宠物.
#
# Godot 学习提示:
# - 这个脚本继承 Control, 因为测试页本质是一个工具 UI, 不是桌宠运行时的透明小窗口.
# - UI 骨架在 test_pet_offsets.tscn 中声明, 预览格中的 PanelContainer, Label, Node2D 和 PetFramePlayer 由代码动态创建.
# - PetFramePlayer 是 Node2D, 负责接收宠物播放数据; 底层 FramePlayer 按图集 region 直接绘制当前帧.
# - AssetsConfig 先准备同 ID 帧表, ConfigPet.load() 读取 pet.yaml, ConfigPet.assemble() 挂载帧表引用, ConfigPet.get_by_id() 按需懒加载图集, 预览卡片把播放器放到固定锚点后再把帧序列交给 PetFramePlayer.
# - 阅读时建议从 _ready() 开始, 再看 _load_pet_groups(), _create_preview() 和 _apply_animation_to_all(), 这几段覆盖了测试页的核心流程.

# PetFramePlayer 是实际接收宠物帧序列的播放器脚本.
# 这里用 preload 提前加载脚本资源, 后续可以通过 PetFramePlayerScript.new() 动态创建多个播放器实例.
const PetFramePlayerScript := preload("res://scripts/animation/pet.player.gd")

# 默认宠物 ID 只用于推导默认分组.
# 4000101 / 100 = 40001, 所以测试页默认打开 40001 这一组同类宠物.
const DEFAULT_PET_ID := 4000101
# 测试窗口尺寸. 这个页面需要同时放下多只宠物和控制按钮, 所以使用比桌宠主窗口更大的普通窗口.
const TEST_WINDOW_SIZE := Vector2i(1180, 820)
# 单个宠物预览区域大小. 它决定每个 Panel 里可裁剪显示的动画范围.
const PREVIEW_CELL := Vector2i(260, 220)
# 预览格里的固定锚点位置.
# FramePlayer 的局部原点就是动画锚点, 所以所有宠物都放到同一个父坐标, 便于观察帧内锚点是否稳定.
const PREVIEW_ANCHOR_POSITION := Vector2(130.0, 132.0)
# 宠物分组规则. 4000101 到 4000199 都会归到 40001 组, 用来观察相同类型或相近编号宠物.
const GROUP_DIVISOR := 100
const GROUP_DIVISOR_FLOAT := 100.0
# 宠物测试页的 UI 仍显示动作和方向字符串, 但动画构建前会转换为运行期枚举.
const ACTIONS := ["attack", "faint", "hurt", "defense", "stand", "walk", "attackShort"]
const DIRECTIONS := ["down", "downleft", "left", "upleft", "up", "upright", "right", "downright"]
# @onready 表示等 .tscn 中的节点实例化完成后再读取.
# 百分号语法会按 unique_name_in_owner 查找节点, 需要场景里对应节点设置 unique_name_in_owner = true.
# 循环开关会同步到所有 PetFramePlayer, 控制动画到末帧后是否回到首帧.
@onready var _loop_check: CheckBox = %LoopCheck
# 标题 Label, 显示当前同类组和组内宠物 ID 范围.
@onready var _title_label: Label = %Title
# 同类组下拉框. 每个选项是一组资源完整的宠物, 例如 "40001 (4000101-4000106)".
@onready var _pet_select: OptionButton = %PetSelect
# 播放/暂停按钮. 它是 toggle button, pressed=true 表示播放中.
@onready var _play_button: Button = %PlayButton
# 上一帧按钮, 用于暂停后同步查看所有宠物的前一帧.
@onready var _prev_button: Button = %PrevButton
# 下一帧按钮, 用于暂停后同步查看所有宠物的后一帧.
@onready var _next_button: Button = %NextButton
# 动作上翻按钮. 点击后按公共动作顺序向前切一个动作, 并同步全部宠物.
@onready var _action_prev_button: Button = %ActionPrevButton
# 动作下翻按钮. 点击后按公共动作顺序向后切一个动作.
@onready var _action_next_button: Button = %ActionNextButton
# 方向左切按钮. 点击后按公共方向顺序向前切一个方向.
@onready var _direction_prev_button: Button = %DirectionPrevButton
# 方向右切按钮. 点击后按公共方向顺序向后切一个方向.
@onready var _direction_next_button: Button = %DirectionNextButton
# 辅助线开关. 开启后播放器会画出锚点辅助线和当前帧矩形, 用于观察锚点是否稳定.
@onready var _guides_check: CheckBox = %GuidesCheck
# 动作按钮容器. 按钮由代码根据公共动作顺序动态创建, 不需要在 .tscn 里手工摆每个动作.
@onready var _action_grid: GridContainer = %ActionGrid
# 方向按钮容器. 按钮按九宫格布局动态创建, 中间用空 Control 占位.
@onready var _direction_grid: GridContainer = %DirectionGrid
# 宠物预览网格. 当前组的每只宠物都会创建一个 Panel 放进这里.
@onready var _preview_grid: GridContainer = %PreviewGrid
# 底部信息标签. 显示当前分组, 动作, 方向或加载失败原因.
@onready var _info_label: Label = %InfoLabel

# ButtonGroup 让动作按钮具备单选效果, 同一时间只显示一个动作被选中.
var _action_group := ButtonGroup.new()
# 方向按钮也使用单选组, 避免 UI 同时显示多个方向.
var _direction_group := ButtonGroup.new()
# 动作名到按钮节点的映射. 键盘/上下按钮切动作时, 需要用它反向同步按钮外观.
var _action_buttons: Dictionary[String, Button] = {}
# 方向名到按钮节点的映射. 左右按钮或键盘切方向时, 需要用它同步按钮外观.
var _direction_buttons: Dictionary[String, Button] = {}
# 已发现的宠物分组. key 是分组号, value 是该组内资源完整的宠物 ID 数组.
# Dictionary[int, Array] 的 key int 是同类分组号, value 中的 Array 元素是 pet_id.
var _pet_groups: Dictionary[int, Array] = {}
# 分组号列表. 单独保存排序后的 key, 方便 OptionButton 的 index 和分组号互相转换.
# Array[int] 中的 int 表示同类分组号.
var _group_keys: Array[int] = []
# 当前分组号. 初始值由 DEFAULT_PET_ID 通过 GROUP_DIVISOR 推导.
var _current_group_key := floori(DEFAULT_PET_ID / GROUP_DIVISOR_FLOAT)
# 当前分组内实际要显示的宠物 ID.
# Array[int] 中的 int 表示 pet_id.
var _current_pet_ids: Array[int] = []
# 当前创建出来的预览数据列表.
# 每个 Dictionary 保存 pet_id, panel, root, player, pet_entry 和 animation_name.
var _pet_previews: Array[Dictionary] = []
# 当前动作名. 会和 _current_direction 转换为 ConfigPet.PlayInfo 查询 key.
var _current_action := "stand"
# 当前方向名.
var _current_direction := "down"
# 全局播放状态. 所有宠物播放器都使用同一个播放/暂停状态.
var _playing := true

func _ready() -> void:
    # _ready 是 Control 进入场景树后执行的初始化入口.
    # 初始化顺序很重要: 先设置测试窗口, 再读取资源分组, 创建按钮, 连接信号, 最后加载并播放当前分组.
    _apply_test_window_flags()
    _sync_root_size()
    # 当用户拖拽改变测试窗口大小时, 重新让根 Control 铺满窗口.
    get_viewport().size_changed.connect(_sync_root_size)
    # 通过 ConfigPet 读取宠物配置, 再结合 assets/pet 中的资源完整性按编号归组.
    _pet_groups = _load_pet_groups()
    # 根据可用分组生成顶部下拉框.
    _build_pet_selector()
    # 根据固定动作列表生成动作单选按钮.
    _build_action_buttons()
    # 根据八方向列表生成方向九宫格按钮.
    _build_direction_buttons()
    # 连接按钮和下拉框信号. 从这里开始 UI 操作会进入对应回调.
    _connect_controls()
    if _group_keys.is_empty():
        # 没有可用宠物分组时停止后续加载, UI 会保持错误提示.
        return
    # 创建当前分组内每只宠物的预览 Panel 和播放器.
    _load_group_data()
    # 把默认动作和方向应用到全部播放器.
    _apply_animation_to_all()

func _unhandled_key_input(event: InputEvent) -> void:
    # _unhandled_key_input 只处理没有被按钮/下拉框消费掉的键盘事件.
    # 这里用于提供键盘快捷键: 左右切方向, 上下切动作.
    if not (event is InputEventKey):
        return

    var key_event := event as InputEventKey
    if not key_event.pressed or key_event.echo:
        # echo 是长按键盘时系统自动重复产生的事件, 忽略它可以避免动作切换过快.
        return

    match key_event.keycode:
        KEY_LEFT:
            _step_direction(-1)
        KEY_RIGHT:
            _step_direction(1)
        KEY_UP:
            _step_action(-1)
        KEY_DOWN:
            _step_action(1)

func _apply_test_window_flags() -> void:
    # 偏移测试页需要完整 UI 和深色背景, 因此关闭透明背景, 不沿用桌宠主窗口的透明小窗口行为.
    get_viewport().transparent_bg = false
    # RenderingServer 的默认清屏色会影响没有被控件覆盖的区域.
    RenderingServer.set_default_clear_color(Color(0.12, 0.12, 0.14, 1.0))

    var window := get_window()
    # 下面这些是 Godot Window 属性, 作用于当前测试窗口.
    # transparent=false, borderless=false 让它成为普通可观察窗口; always_on_top=false 避免遮挡其它调试工具.
    window.transparent = false
    window.borderless = false
    window.always_on_top = false
    window.unresizable = false
    # 禁用内容缩放, 让像素风资源按实际像素和整数坐标显示, 便于观察锚点是否稳定.
    window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
    window.content_scale_size = TEST_WINDOW_SIZE
    window.size = TEST_WINDOW_SIZE
    # DisplayServer 是 Godot 操作原生窗口的底层入口.
    # 这里显式设置窗口模式和 flags, 可以覆盖项目主窗口为桌宠做过的透明/无边框配置.
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)
    DisplayServer.window_set_size(TEST_WINDOW_SIZE)
    # 给测试窗口固定初始位置, 方便重复运行时快速找到窗口.
    DisplayServer.window_set_position(Vector2i(80, 80))

func _sync_root_size() -> void:
    # custom_minimum_size 告诉布局系统这个测试页至少需要多大.
    custom_minimum_size = Vector2(TEST_WINDOW_SIZE)
    # PRESET_FULL_RECT 会把 Control 的 anchor 拉满父窗口, 避免窗口变大后 UI 仍停在左上角.
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_action_buttons() -> void:
    # allow_unpress=false 表示按钮组里必须始终有一个按钮保持选中.
    _action_group.allow_unpress = false
    for action in ACTIONS:
        # 动作按钮用代码生成, 这样公共动作顺序变化时不需要同步手工改场景节点.
        var button := Button.new()
        button.text = action
        # toggle_mode 让普通 Button 具备按下/未按下状态.
        button.toggle_mode = true
        # 测试页主要靠方向键切动作方向, 关闭按钮焦点可以减少键盘焦点框干扰.
        button.focus_mode = Control.FOCUS_NONE
        # 加入同一个 ButtonGroup 后, Godot 会自动保证这些动作按钮互斥.
        button.button_group = _action_group
        button.custom_minimum_size = Vector2(104.0, 30.0)
        # bind(action) 会把当前循环里的动作名附加到信号参数后面.
        button.toggled.connect(_on_action_toggled.bind(action))
        _action_grid.add_child(button)
        _action_buttons[action] = button
        if action == _current_action:
            # 初始化默认选中按钮. no_signal 避免创建 UI 时立即触发播放逻辑.
            button.set_pressed_no_signal(true)

func _build_direction_buttons() -> void:
    _direction_group.allow_unpress = false
    # 方向按钮按 3 x 3 九宫格摆放, 中间空出来, 更接近方向键的空间关系.
    var direction_layout := [
        ["upleft", "up", "upright"],
        ["left", "", "right"],
        ["downleft", "down", "downright"],
    ]

    for row in direction_layout:
        for direction in row:
            if direction.is_empty():
                # 空字符串代表九宫格中心占位, 用 Control 保持布局尺寸.
                var spacer := Control.new()
                spacer.custom_minimum_size = Vector2(86.0, 30.0)
                _direction_grid.add_child(spacer)
                continue

            # 每个方向按钮和动作按钮一样使用 toggle + ButtonGroup 的单选模式.
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
    # OptionButton.item_selected 传入的是选项 index, 回调里需要再映射到实际分组号.
    _pet_select.item_selected.connect(_on_group_selected)
    # 播放按钮是 toggle button, 使用 toggled 信号可以直接拿到 pressed 状态.
    _play_button.toggled.connect(_on_play_toggled)
    # bind(-1) 和 bind(1) 把两个按钮复用到同一个逐帧函数.
    _prev_button.pressed.connect(_step_frame.bind(-1))
    _next_button.pressed.connect(_step_frame.bind(1))
    # 上下按钮控制动作, 左右按钮控制方向, 和键盘方向键语义保持一致.
    _action_prev_button.pressed.connect(_step_action.bind(-1))
    _action_next_button.pressed.connect(_step_action.bind(1))
    _direction_prev_button.pressed.connect(_step_direction.bind(-1))
    _direction_next_button.pressed.connect(_step_direction.bind(1))
    # 循环和辅助线都是全局开关, 回调里会同步给每一个播放器.
    _loop_check.toggled.connect(_on_loop_toggled)
    _guides_check.toggled.connect(_on_guides_toggled)

func _load_pet_groups() -> Dictionary[int, Array]:
    # 返回结构: {40001: [4000101, 4000102, ...], 40002: [...]}.
    # ConfigPet.assemble() 已经在启动阶段断言每个宠物都具备可播放帧表, 这里只确认 ID 存在.
    # Dictionary[int, Array] 的 key int 是同类分组号, value 中的 Array 元素是 pet_id.
    var groups: Dictionary[int, Array] = {}
    var pet_config: ConfigPet = GCfgMgr.pet_config
    for pet_id in pet_config.get_ids():
        if pet_id <= 0 or not _has_pet_entry(pet_config, pet_id):
            continue

        var group_key := floori(pet_id / GROUP_DIVISOR_FLOAT)
        if not groups.has(group_key):
            # Array[int] 中的 int 表示当前分组内的 pet_id.
            var group_ids: Array[int] = []
            groups[group_key] = group_ids
        groups[group_key].append(pet_id)

    for group_key in groups.keys():
        # 同组内排序后, 预览顺序稳定, 也方便肉眼比较相邻编号宠物.
        # Array[int] 中的 int 表示同组内资源完整的 pet_id.
        var ids: Array[int] = groups[group_key]
        ids.sort()

    return groups

func _has_pet_entry(pet_config: ConfigPet, pet_id: int) -> bool:
    # 可播放资源完整性已经由 ConfigPet.assemble() 断言, 测试页扫描分组时只查 ID, 不触发图集懒加载.
    return pet_config.has_id(pet_id)

func _build_pet_selector() -> void:
    # 重建下拉框前先清空旧数据, 这样重新加载或未来扩展刷新时不会重复追加.
    _pet_select.clear()
    _group_keys.clear()
    if _pet_groups.is_empty():
        # 没有任何可用分组时禁用下拉框, 并在标题和信息区给出明确提示.
        _pet_select.disabled = true
        _title_label.text = "同类宠物偏移播放测试"
        _info_label.text = "没有找到资源完整的宠物"
        return

    for group_key in _pet_groups.keys():
        _group_keys.append(int(group_key))
    # 排序后 OptionButton 顺序稳定.
    _group_keys.sort()

    # 默认选择由 DEFAULT_PET_ID 推导出来的组; 如果该组不存在, 就保留第一个可用组.
    var selected_index := 0
    for index in range(_group_keys.size()):
        var group_key := _group_keys[index]
        # Array[int] 中的 int 表示当前下拉项对应分组内的 pet_id.
        var ids: Array[int] = _pet_groups[group_key]
        # 显示格式如 "40001 (4000101-4000106)", 便于确认当前对比的是哪一类宠物.
        _pet_select.add_item("%d (%s)" % [group_key, _format_id_range(ids)])
        if group_key == _current_group_key:
            selected_index = index

    _current_group_key = _group_keys[selected_index]
    _current_pet_ids = _typed_id_array(_pet_groups[_current_group_key])
    _pet_select.select(selected_index)
    _update_title()

func _typed_id_array(raw_ids: Array) -> Array[int]:
    # Dictionary 里取出的 Array 默认是弱类型数组.
    # 这里复制成 Array[int], 后续函数签名和 IDE 提示会更明确.
    # Array[int] 中的 int 表示 pet_id.
    var ids: Array[int] = []
    for id_value in raw_ids:
        ids.append(int(id_value))
    return ids

func _format_id_range(ids: Array) -> String:
    # 下拉框和标题只需要展示 ID 范围.
    # 同组只有一个宠物时直接显示单个 ID, 多个时显示首尾范围.
    if ids.is_empty():
        return ""
    if ids.size() == 1:
        return str(ids[0])
    return "%s-%s" % [str(ids[0]), str(ids[ids.size() - 1])]

func _load_group_data() -> void:
    # 切换分组后, 旧预览节点不再对应当前宠物, 需要全部清理后重建.
    _clear_previews()
    _update_title()

    for pet_id in _current_pet_ids:
        # 每个宠物创建一个独立预览字典和 Panel.
        var preview: Dictionary = _create_preview(pet_id)
        _pet_previews.append(preview)
        _preview_grid.add_child(preview["panel"])

    if _pet_previews.is_empty():
        _info_label.text = "加载失败: group=%d" % _current_group_key

func _create_preview(pet_id: int) -> Dictionary:
    # PanelContainer 是单个宠物预览卡片的最外层节点, 用于让每个宠物有清晰边界.
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(PREVIEW_CELL)
    panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

    # 纵向布局: 上方宠物 ID, 中间动画预览区域.
    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 6)
    panel.add_child(vbox)

    # 标题显示宠物 ID. 如果加载失败, 后面会改成 "加载失败" 文案.
    var title := Label.new()
    title.text = str(pet_id)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title)

    # 预览区域使用 Control, 通过 clip_contents 裁剪超出范围的绘制内容.
    # 这里没有使用 SubViewport, 因为同屏宠物数量较多, 直接在 Control 下面放 Node2D 更轻量.
    var preview_area := Control.new()
    preview_area.custom_minimum_size = Vector2(PREVIEW_CELL)
    preview_area.clip_contents = true
    vbox.add_child(preview_area)

    # root 是播放器的 Node2D 父容器.
    # 它的位置就是预览格中的固定动画锚点, 不再根据当前动画帧内容反推显示范围.
    var root := Node2D.new()
    preview_area.add_child(root)

    # 每只宠物一个 PetFramePlayer, 播放器之间互不共享帧状态.
    var player: PetFramePlayer = PetFramePlayerScript.new()
    player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    root.add_child(player)

    var pet_entry := GCfgMgr.pet_config.get_by_id(pet_id)
    if pet_entry == null:
        # 返回的预览字典仍保留 panel/player 等节点, 这样上层逻辑不用额外处理 null Panel.
        title.text = "%d 加载失败" % pet_id
        return {
            "pet_id": pet_id,
            "panel": panel,
            "root": root,
            "player": player,
            "pet_entry": null,
            "animation_name": "",
        }

    # 所有宠物共用同一个预览锚点, 这样动作或方向切换时不会因为内容范围不同而移动播放器.
    root.position = PREVIEW_ANCHOR_POSITION
    player.position = Vector2.ZERO
    # 新创建播放器时同步当前 UI 开关, 避免切组后循环/辅助线状态丢失.
    _sync_player_loop(player)
    _sync_player_playing(player)
    _sync_player_guides(player)

    return {
        "pet_id": pet_id,
        "panel": panel,
        "root": root,
        "player": player,
        "pet_entry": pet_entry,
        "animation_name": "",
    }

func _clear_previews() -> void:
    # 预览 Panel 是运行时动态创建的节点, 切组时必须 queue_free, 避免旧节点残留在 UI 上.
    for preview in _pet_previews:
        var panel: Node = preview.get("panel", null)
        if panel != null and is_instance_valid(panel):
            panel.queue_free()
    _pet_previews.clear()

func _apply_animation_to_all() -> void:
    # 当前测试页的核心同步逻辑: 所有宠物都尝试播放同一个动作和方向帧表.
    for preview in _pet_previews:
        var pet_entry := preview.get("pet_entry", null) as ConfigPet.Entry
        if pet_entry == null:
            continue

        var player: PetFramePlayer = preview.get("player", null)
        if player == null:
            continue

        var requested_action := _pet_action_from_key(_current_action)
        var requested_direction := _direction_from_key(_current_direction)
        var requested_animation := "%s_%s" % [_current_action, _current_direction]
        var play_info := _get_pet_play_info(pet_entry, requested_direction, requested_action)
        if play_info == null:
            # 配置里缺少某个动作/方向时回退到 stand_down.
            # 这样测试页仍然有画面, 同时也能从视觉上发现该宠物缺少目标动画.
            requested_action = GPB.PetAction.PetAction_Stand
            requested_direction = GPB.AssetDirection.AssetDirection_Down
            requested_animation = "stand_down"
            play_info = _get_pet_play_info(pet_entry, requested_direction, requested_action)
            assert(play_info != null, "宠物偏移测试缺少兜底动画: pet=%d" % int(preview.get("pet_id", 0)))

        # 记录实际播放动画名, 后续如果需要显示每只宠物状态可直接读取.
        preview["animation_name"] = requested_animation
        var play_speed := Constants.ANIMATION_DEFAULT_SPEED
        if requested_action == GPB.PetAction.PetAction_Walk:
            play_speed = Constants.ANIMATION_WALK_SPEED
        player.play(
            pet_entry.atlas,
            pet_entry.frame_by_id,
            play_info.ids,
            play_speed,
            _loop_check.button_pressed
        )
        player.position = Vector2.ZERO
        # 每次切动作/方向后都重新同步全局开关, 避免新帧序列重置内部播放状态后和 UI 不一致.
        _sync_player_loop(player)
        _sync_player_playing(player)
        _sync_player_guides(player)

func _on_action_toggled(pressed: bool, action: String) -> void:
    if not pressed:
        # ButtonGroup 切换时旧按钮会发出 pressed=false, 这里只处理新按钮 pressed=true 的那次信号.
        return

    # 动作按钮直接改变当前动作, 并让所有宠物重新播放对应动画.
    _current_action = action
    _apply_animation_to_all()

func _on_direction_toggled(pressed: bool, direction: String) -> void:
    if not pressed:
        return

    # 方向按钮直接改变当前方向, 并让所有宠物重新播放对应动画.
    _current_direction = direction
    _apply_animation_to_all()

func _on_group_selected(index: int) -> void:
    # OptionButton 给的是选项索引, 需要先检查范围, 再映射到 _group_keys 中的分组号.
    if index < 0 or index >= _group_keys.size():
        return

    var group_key := _group_keys[index]
    if group_key == _current_group_key:
        # 选择未变化时不重复重建预览节点.
        return

    # 切换分组后, 当前宠物列表, 预览节点和动画都需要刷新.
    _current_group_key = group_key
    _current_pet_ids = _typed_id_array(_pet_groups[_current_group_key])
    _load_group_data()
    _apply_animation_to_all()

func _on_play_toggled(pressed: bool) -> void:
    # 播放按钮的 pressed 状态就是全局播放状态.
    _playing = pressed
    _play_button.text = "暂停" if _playing else "播放"
    for preview in _pet_previews:
        # 所有宠物同步播放或暂停.
        var player: PetFramePlayer = preview.get("player", null)
        if player != null:
            _sync_player_playing(player)

func _on_loop_toggled(_pressed: bool) -> void:
    # 循环开关影响每个播放器到末帧后的行为, 不会立即改变当前帧.
    for preview in _pet_previews:
        var player: PetFramePlayer = preview.get("player", null)
        if player != null:
            _sync_player_loop(player)

func _on_guides_toggled(_pressed: bool) -> void:
    # 辅助线由底层 FramePlayer._draw 绘制, 包括锚点横线, 锚点竖线和当前 frame region 边框.
    for preview in _pet_previews:
        var player: PetFramePlayer = preview.get("player", null)
        if player != null:
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
    # 手动逐帧时先暂停, 否则自动播放会马上把帧推进走, 不利于比较锚点位置.
    _play_button.set_pressed_no_signal(false)
    _on_play_toggled(false)
    for preview in _pet_previews:
        # delta_frames=-1 表示上一帧, 1 表示下一帧. 所有宠物同步步进.
        var player: PetFramePlayer = preview.get("player", null)
        if player != null:
            player.step_frame(delta_frames)

func _step_action(delta: int) -> void:
    # 上下按钮和键盘上下键都走这里.
    # posmod 允许从第一个动作继续向上切时绕到最后一个动作.
    var action_order := ACTIONS
    if action_order.is_empty():
        return

    var index := action_order.find(_current_action)
    if index < 0:
        index = 0
    var next_index := posmod(index + delta, action_order.size())
    _set_action(action_order[next_index])

func _step_direction(delta: int) -> void:
    # 左右按钮和键盘左右键都走这里.
    # DIRECTIONS 的顺序就是循环切换方向的顺序.
    var index := DIRECTIONS.find(_current_direction)
    if index < 0:
        index = 0
    var next_index := posmod(index + delta, DIRECTIONS.size())
    _set_direction(DIRECTIONS[next_index])

func _set_action(action: String) -> void:
    # 这个函数用于非鼠标点击场景, 例如键盘或动作上下按钮.
    # 它需要同时更新内部状态, 按钮外观和全部播放器.
    _current_action = action
    for action_id in _action_buttons.keys():
        var button: Button = _action_buttons[action_id]
        # set_pressed_no_signal 只改按钮状态, 不再次触发 _on_action_toggled, 避免重复应用动画.
        button.set_pressed_no_signal(action_id == action)
    _apply_animation_to_all()

func _set_direction(direction: String) -> void:
    # 和 _set_action 类似, 这里负责同步方向状态和方向按钮外观.
    _current_direction = direction
    for direction_id in _direction_buttons.keys():
        var button: Button = _direction_buttons[direction_id]
        button.set_pressed_no_signal(direction_id == direction)
    _apply_animation_to_all()

func _get_pet_play_info(pet_entry: ConfigPet.Entry, direction: int, action: int) -> ConfigPet.PlayInfo:
    if direction == GPB.AssetDirection.AssetDirection_Unknow or action == GPB.PetAction.PetAction_Unknow:
        return null

    var play_key := Vector2i(direction, action)
    if not pet_entry.direction_action_frames.has(play_key):
        return null

    return pet_entry.get_play_info(direction, action)

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

func _pet_action_from_key(key: String) -> int:
    match key:
        "attack":
            return GPB.PetAction.PetAction_Attack
        "faint":
            return GPB.PetAction.PetAction_Faint
        "hurt":
            return GPB.PetAction.PetAction_Hurt
        "defense":
            return GPB.PetAction.PetAction_Defense
        "stand":
            return GPB.PetAction.PetAction_Stand
        "walk":
            return GPB.PetAction.PetAction_Walk
        "attackShort":
            return GPB.PetAction.PetAction_AttackShort
        _:
            return GPB.PetAction.PetAction_Unknow

func _update_title() -> void:
    # 标题显示当前同类组和宠物 ID 范围, 方便截图或录屏时判断正在比较哪组资源.
    _title_label.text = "同类宠物偏移播放测试: %d (%s)" % [
        _current_group_key,
        _format_id_range(_current_pet_ids),
    ]
