#include <stdint.h>
#include <stdlib.h>
#include <wchar.h>
#include <windows.h>
#include <shellapi.h>

static int set_click_through(HWND hwnd, int enabled) {
    if (hwnd == NULL || !IsWindow(hwnd)) {
        return 2;
    }

    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (style == 0 && GetLastError() != 0) {
        return 3;
    }

    style |= WS_EX_LAYERED;
    style |= WS_EX_TOOLWINDOW;
    style &= ~WS_EX_APPWINDOW;

    if (enabled) {
        style |= WS_EX_TRANSPARENT;
    } else {
        style &= ~WS_EX_TRANSPARENT;
    }

    SetLastError(0);
    if (SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style) == 0 && GetLastError() != 0) {
        return 4;
    }

    SetWindowPos(
        hwnd,
        HWND_TOPMOST,
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_ASYNCWINDOWPOS
    );

    return 0;
}

static int set_maximize_enabled(HWND hwnd, int enabled) {
    if (hwnd == NULL || !IsWindow(hwnd)) {
        return 2;
    }

    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if (style == 0 && GetLastError() != 0) {
        return 3;
    }

    if (enabled) {
        style |= WS_MAXIMIZEBOX;
    } else {
        style &= ~WS_MAXIMIZEBOX;
    }

    SetLastError(0);
    if (SetWindowLongPtrW(hwnd, GWL_STYLE, style) == 0 && GetLastError() != 0) {
        return 4;
    }

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

    return 0;
}

static int run_command(int argc, wchar_t **argv) {
    if (argc == 3) {
        uintptr_t hwnd_value = (uintptr_t)wcstoull(argv[1], NULL, 0);
        int enabled = _wtoi(argv[2]) != 0;
        return set_click_through((HWND)hwnd_value, enabled);
    }

    if (argc != 4) {
        return 1;
    }

    uintptr_t hwnd_value = (uintptr_t)wcstoull(argv[2], NULL, 0);
    int enabled = _wtoi(argv[3]) != 0;
    if (wcscmp(argv[1], L"click_through") == 0) {
        return set_click_through((HWND)hwnd_value, enabled);
    }
    if (wcscmp(argv[1], L"maximize") == 0) {
        return set_maximize_enabled((HWND)hwnd_value, enabled);
    }

    return 5;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous_instance, PWSTR command_line, int show_command) {
    (void)instance;
    (void)previous_instance;
    (void)command_line;
    (void)show_command;

    int argc = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv == NULL) {
        return 6;
    }

    int result = run_command(argc, argv);
    LocalFree(argv);
    return result;
}
