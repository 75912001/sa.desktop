#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

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

int main(int argc, char **argv) {
    if (argc != 3) {
        return 1;
    }

    uintptr_t hwnd_value = (uintptr_t)strtoull(argv[1], NULL, 0);
    int enabled = atoi(argv[2]) != 0;
    return set_click_through((HWND)hwnd_value, enabled);
}
