#include <stdint.h>
#include <stdlib.h>
#include <wchar.h>
#include <windows.h>
#include <shellapi.h>

/* Windows 原生窗口样式 helper, 由 Godot 侧通过 OS.create_process() 启动. */

/* 设置窗口点击穿透状态. enabled 为 0 表示关闭, 非 0 表示开启. */
static int set_click_through(HWND hwnd, int enabled) {
    if (hwnd == NULL || !IsWindow(hwnd)) {
        /* 返回 2: hwnd 为空, 或 hwnd 不是当前系统中的有效窗口句柄. */
        return 2;
    }

    /*
     * 读取扩展窗口样式.
     * GWL_EXSTYLE 保存 WS_EX_* 样式位; 如果真实样式值为 0, 必须结合 GetLastError() 判断是否失败.
     */
    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (style == 0 && GetLastError() != 0) {
        /* 返回 3: GetWindowLongPtrW() 读取 GWL_EXSTYLE 失败. */
        return 3;
    }

    /* WS_EX_LAYERED 让窗口按 layered window 参与桌面合成, 透明桌宠窗口需要它. */
    style |= WS_EX_LAYERED;

    /* WS_EX_TOOLWINDOW 通常不显示任务栏按钮, WS_EX_APPWINDOW 通常强制显示任务栏按钮. */
    style |= WS_EX_TOOLWINDOW;
    style &= ~WS_EX_APPWINDOW;

    /* WS_EX_TRANSPARENT 让鼠标命中穿过当前窗口, 落到后面的窗口. */
    if (enabled) {
        style |= WS_EX_TRANSPARENT;
    } else {
        /* 移除 WS_EX_TRANSPARENT 后, 当前窗口恢复可被鼠标命中. */
        style &= ~WS_EX_TRANSPARENT;
    }

    /* 写回扩展窗口样式. 返回值为 0 时仍需结合 GetLastError() 区分失败和旧样式值为 0. */
    SetLastError(0);
    if (SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style) == 0 && GetLastError() != 0) {
        /* 返回 4: SetWindowLongPtrW() 写回 GWL_EXSTYLE 失败. */
        return 4;
    }

    /*
     * 这里不移动, 不缩放窗口, 只保持置顶并刷新 frame.
     * HWND_TOPMOST 保持主桌宠窗口置顶.
     * SWP_FRAMECHANGED 通知系统刷新非客户区和扩展样式缓存.
     * SWP_ASYNCWINDOWPOS 避免跨线程窗口所有者时同步等待.
     * 当前函数不把 SetWindowPos() 失败映射为退出码, 因为窗口样式已经写入;
     * 若后续需要严格感知置顶刷新失败, 应新增独立返回码.
     */
    SetWindowPos(
        hwnd,
        HWND_TOPMOST,
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_ASYNCWINDOWPOS
    );

    /* 返回 0: 点击穿透相关扩展样式写入成功. */
    return 0;
}

/* 设置窗口标题栏最大化按钮是否可用. enabled 为 0 表示关闭, 非 0 表示开启. */
static int set_maximize_enabled(HWND hwnd, int enabled) {
    if (hwnd == NULL || !IsWindow(hwnd)) {
        /* 返回 2: hwnd 为空, 或 hwnd 不是当前系统中的有效窗口句柄. */
        return 2;
    }

    /*
     * 读取普通窗口样式.
     * GWL_STYLE 保存 WS_* 样式位; 如果真实样式值为 0, 必须结合 GetLastError() 判断是否失败.
     */
    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if (style == 0 && GetLastError() != 0) {
        /* 返回 3: GetWindowLongPtrW() 读取 GWL_STYLE 失败. */
        return 3;
    }

    /* WS_MAXIMIZEBOX 控制标题栏最大化按钮是否可用. */
    if (enabled) {
        style |= WS_MAXIMIZEBOX;
    } else {
        /* 移除 WS_MAXIMIZEBOX 后, Windows 标题栏最大化按钮会被禁用. */
        style &= ~WS_MAXIMIZEBOX;
    }

    /* 写回普通窗口样式. 返回值为 0 时仍需结合 GetLastError() 区分失败和旧样式值为 0. */
    SetLastError(0);
    if (SetWindowLongPtrW(hwnd, GWL_STYLE, style) == 0 && GetLastError() != 0) {
        /* 返回 4: SetWindowLongPtrW() 写回 GWL_STYLE 失败. */
        return 4;
    }

    /*
     * 只刷新窗口 frame, 不改变位置, 尺寸和 Z 序.
     * HWND 参数在 SWP_NOZORDER 下会被忽略, 因此这里传 NULL.
     * SWP_FRAMECHANGED 和 DrawMenuBar() 用于刷新标题栏按钮状态.
     */
    SetWindowPos(
        hwnd,
        NULL,
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_ASYNCWINDOWPOS
    );
    DrawMenuBar(hwnd);

    /* 返回 0: 最大化按钮相关普通样式写入成功. */
    return 0;
}

/* 解析命令行参数并分发到具体窗口样式操作. argc 包含 exe 自身路径. */
static int run_command(int argc, wchar_t **argv) {
    if (argc == 3) {
        /*
         * 兼容旧格式: <exe> <hwnd> <enabled>, 固定执行 click_through.
         * hwnd 按 uintptr_t 解析; 32 位构建范围为 0..UINT32_MAX, 64 位构建范围为 0..UINT64_MAX.
         * base=0 支持十进制, 0x 前缀十六进制和 C 运行库支持的前缀格式.
         */
        uintptr_t hwnd_value = (uintptr_t)wcstoull(argv[1], NULL, 0);

        /* enabled 通过 _wtoi() 解析; 0 或解析失败表示关闭, 任何非 0 值表示开启. */
        int enabled = _wtoi(argv[2]) != 0;
        return set_click_through((HWND)hwnd_value, enabled);
    }

    if (argc != 4) {
        /* 返回 1: 参数数量不是旧格式 argc==3, 也不是显式命令格式 argc==4. */
        return 1;
    }

    /*
     * 显式命令格式: <exe> <command> <hwnd> <enabled>.
     * 当前实现不额外校验字符串是否完整解析; 非法 hwnd 字符串通常会得到 0,
     * 随后由 set_* 函数通过 NULL/IsWindow() 返回 2.
     */
    uintptr_t hwnd_value = (uintptr_t)wcstoull(argv[2], NULL, 0);

    /* enabled 通过 _wtoi() 解析; 0 或解析失败表示关闭, 任何非 0 值表示开启. */
    int enabled = _wtoi(argv[3]) != 0;

    /* click_through 返回 0, 2, 3 或 4, 含义见 set_click_through() 内对应 return. */
    if (wcscmp(argv[1], L"click_through") == 0) {
        return set_click_through((HWND)hwnd_value, enabled);
    }

    /* maximize 返回 0, 2, 3 或 4, 含义见 set_maximize_enabled() 内对应 return. */
    if (wcscmp(argv[1], L"maximize") == 0) {
        return set_maximize_enabled((HWND)hwnd_value, enabled);
    }

    /* 返回 5: 显式命令格式中的命令名未知. */
    return 5;
}

/* Windows GUI 程序入口. 使用 wWinMain 构建 Windows 子系统程序时不会弹出控制台窗口. */
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous_instance, PWSTR command_line, int show_command) {
    (void)instance;
    (void)previous_instance;
    (void)command_line;
    (void)show_command;

    int argc = 0;

    /* CommandLineToArgvW() 按 Windows 命令行规则拆分宽字符参数, 返回的 argv 必须用 LocalFree() 释放. */
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv == NULL) {
        /* 返回 6: CommandLineToArgvW() 解析命令行失败. */
        return 6;
    }

    /* result 取值为 0..6, 直接作为进程退出码返回给操作系统. */
    int result = run_command(argc, argv);
    LocalFree(argv);
    return result;
}
