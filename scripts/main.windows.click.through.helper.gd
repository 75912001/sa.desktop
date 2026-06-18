class_name WindowsClickThroughHelper
extends RefCounted

# 这个 helper 是 Windows 专用的小程序, 用来设置原生窗口样式.
# Godot 自带的鼠标穿透 flag 在某些 Windows 场景下不够稳定, 所以优先用 native helper.
const RESOURCE_HELPER_PATH := "res://native/windows_click_through_helper.exe"

# 切换指定窗口的点击穿透状态.
# 返回 `true` 表示 native helper 已成功启动.
func set_click_through(window_id: int, enabled: bool) -> bool:
    assert(OS.get_name() == "Windows", "Windows 点击穿透 helper 只支持 Windows.")
    # `OS.create_process()` 只能启动真实磁盘文件, 所以 helper 必须作为外置 exe 存在.
    var helper_path := ProjectSettings.globalize_path(RESOURCE_HELPER_PATH)
    assert(FileAccess.file_exists(helper_path), "Windows 点击穿透 helper 不存在.")

    # Godot 的 window_id 需要转换为 Windows HWND, helper 才能调用 Win32 API.
    var hwnd := int(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window_id))
    assert(hwnd != 0, "Windows 点击穿透 helper 无法获取窗口 HWND.")

    # 参数 1/0 表示开启或关闭穿透. 这里不等待进程结束, 避免阻塞 Godot 主循环.
    var pid := OS.create_process(helper_path, [str(hwnd), "1" if enabled else "0"], false)
    assert(pid > 0, "Windows 点击穿透 helper 启动失败, pid=%d." % pid)

    return true
