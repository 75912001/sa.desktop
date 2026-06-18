extends Node

# GTray 是托盘流程的全局协调入口.
# 它不创建业务页面, 只处理托盘初始化、账号登录完成后的页面跳转和系统选项变化.
# 这个脚本作为 Autoload 常驻, 生命周期早于 MainWindow; 因此它不能在 `_ready()` 里直接访问主场景节点.
# MainWindow 完成窗口控制器创建并注册到 GMainWindow 后, 才会显式调用 initialize() 接上真实窗口和托盘节点.
# 这样做可以让托盘流程成为全局能力, 同时避免把窗口 DisplayServer 操作散落到多个业务脚本中.
var tray_controller: TrayController = null

# `_ready()` 当前不做初始化.
# 此时主场景可能还没有进入树, 所以这里不初始化托盘图标、不读取 MainWindow 子节点.
func _ready() -> void:
    pass

# 初始化托盘系统.
# initialize() 不接收主窗口参数, 只从 GMainWindow.main_window 读取真实主窗口实例.
# TrayController 仍然是 main.window.tscn 的节点, WindowController 仍由 MainWindow 持有.
# 调用顺序必须在 MainWindow._ready() 创建 WindowController 之后, 否则托盘按钮无法控制真实 OS 窗口.
func initialize() -> void:
    assert(GMainWindow.main_window != null and is_instance_valid(GMainWindow.main_window), "GTray 缺少有效 MainWindow, 无法初始化托盘.")
    assert(GMainWindow.main_window.window_controller != null and is_instance_valid(GMainWindow.main_window.window_controller), "GTray 缺少有效 WindowController, 无法初始化托盘.")

    tray_controller = GMainWindow.main_window.get_node_or_null("TrayController") as TrayController
    assert(tray_controller != null, "GTray 未找到 MainWindow/TrayController, 无法初始化托盘.")

    _apply_window_config(GMainWindow.main_window.window_controller)
    tray_controller.initialize(GMainWindow.main_window.window_controller)
    if not tray_controller.account_login_completed.is_connected(_on_account_login_completed):
        tray_controller.account_login_completed.connect(_on_account_login_completed)
    if not tray_controller.debug_border_changed.is_connected(_on_debug_border_changed):
        tray_controller.debug_border_changed.connect(_on_debug_border_changed)

# 启动时把托盘配置应用到真实窗口.
# GTrayConfig 负责读取配置, WindowController 只负责执行窗口操作.
# 顺序上先缩放和移动, 再设置透明度和穿透; 如果配置要求启动隐藏, 最后再隐藏窗口.
# 这样可以保证用户通过托盘显示窗口时, 看到的是已经恢复到上次配置的窗口状态.
func _apply_window_config(window_controller: WindowController) -> void:
    window_controller.set_scale(GTrayConfig.get_window_scale())
    window_controller.set_position(GTrayConfig.get_window_position())
    window_controller.set_opacity(GTrayConfig.get_window_opacity())
    window_controller.set_click_through(GTrayConfig.get_window_click_through())
    if GTrayConfig.get_window_hidden():
        window_controller.hide_window()

# 托盘账号页登录成功后进入游戏页面.
# GRecord 已经在选项窗口里创建了运行期内存记录, 因此这里直接进入游戏页.
# GTray 负责“登录完成后切哪个页面”这个流程决策, OptionsDialogController 只负责发出登录完成信号.
func _on_account_login_completed() -> void:
    assert(GRecord.record != null, "登录完成后缺少运行期账号记录.")
    assert(GMainWindow.main_window != null and is_instance_valid(GMainWindow.main_window), "GTray 缺少有效 MainWindow, 无法进入游戏页面.")

    GMainWindow.main_window.switch_scene(Constants.GAME_SCENE)

# 系统选项页勾选或取消调试边框后, 只通知主场景重绘.
# 调试边框状态已经由 OptionsDialogController 写入 config/tray.yaml, 这里不重复写配置.
func _on_debug_border_changed(_enabled: bool) -> void:
    assert(GMainWindow.main_window != null and is_instance_valid(GMainWindow.main_window), "GTray 缺少有效 MainWindow, 无法刷新调试边框.")

    GMainWindow.main_window.queue_redraw()
