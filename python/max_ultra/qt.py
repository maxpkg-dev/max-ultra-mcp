# Compatibility imports using the Qt application supplied by 3ds Max.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

try:
    from PySide6 import QtCore, QtGui, QtWidgets, QtSvg
except ImportError:
    from PySide2 import QtCore, QtGui, QtWidgets, QtSvg

Qt = QtCore.Qt
_keyboard_guard = None


def enable_window_shadow(widget):
    """Ask Windows to draw the native shadow outside our custom window frame."""
    import sys
    if sys.platform != "win32":
        return False
    import ctypes
    from ctypes import wintypes

    class Margins(ctypes.Structure):
        _fields_ = [(edge, ctypes.c_int) for edge in ("left", "right", "top", "bottom")]

    try:
        dwm = ctypes.WinDLL("dwmapi")
        dwm.DwmSetWindowAttribute.argtypes = [wintypes.HWND, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD]
        dwm.DwmSetWindowAttribute.restype = ctypes.c_long
        dwm.DwmExtendFrameIntoClientArea.argtypes = [wintypes.HWND, ctypes.POINTER(Margins)]
        dwm.DwmExtendFrameIntoClientArea.restype = ctypes.c_long
        handle = wintypes.HWND(int(widget.winId()))
        # DWMWA_NCRENDERING_POLICY / DWMNCRP_ENABLED. Keep the opaque Qt
        # content and existing hit testing; only a one-pixel frame is extended.
        policy = ctypes.c_int(2)
        if dwm.DwmSetWindowAttribute(handle, 2, ctypes.byref(policy), ctypes.sizeof(policy)) < 0:
            return False
        return dwm.DwmExtendFrameIntoClientArea(handle, ctypes.byref(Margins(1, 1, 1, 1))) >= 0
    except (OSError, AttributeError):
        # Cosmetic only: remote sessions or disabled composition must not
        # prevent a window from opening.
        return False


def max_parent():
    import qtmax
    return qtmax.GetQMaxMainWindow()


def protect_keyboard(widget):
    global _keyboard_guard
    import qtmax
    native = getattr(qtmax, "DisableMaxAcceleratorsOnFocus", None)
    if native:
        native(widget, True)
        return
    if _keyboard_guard is None:
        _keyboard_guard = KeyboardGuard(QtWidgets.QApplication.instance())
    _keyboard_guard.add(widget)


class KeyboardGuard(QtCore.QObject):
    """Max 2022 compatibility for the qtmax helper added in later releases."""
    def __init__(self, application):
        super().__init__(application)
        self.windows = []
        self.previous = None
        application.focusChanged.connect(self.changed)

    def add(self, widget):
        import weakref
        self.windows.append(weakref.ref(widget))
        widget.destroyed.connect(lambda: self.changed(None, QtWidgets.QApplication.focusWidget()))

    def changed(self, old, current):
        from pymxs import runtime as rt
        owns_focus = False
        retained = []
        for reference in self.windows:
            window = reference()
            if window is not None:
                try:
                    owns_focus = owns_focus or (current is not None and (current == window or window.isAncestorOf(current)))
                    retained.append(reference)
                except RuntimeError:
                    pass
        self.windows = retained
        if owns_focus and self.previous is None:
            self.previous = bool(rt.enableAccelerators)
            rt.enableAccelerators = False
        elif not owns_focus and self.previous is not None:
            rt.enableAccelerators = self.previous
            self.previous = None


def release_keyboard():
    global _keyboard_guard
    if _keyboard_guard is not None:
        _keyboard_guard.windows = []
        _keyboard_guard.changed(None, None)
        QtWidgets.QApplication.instance().focusChanged.disconnect(_keyboard_guard.changed)
        _keyboard_guard.deleteLater()
        _keyboard_guard = None
