# Main-thread-only adapters for Max scene operations and native ownership checks.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
import os
import threading
import sys


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def json_escape(content):
    return json.dumps(str(content), ensure_ascii=True)[1:-1]


def sha256(content):
    return hashlib.sha256(str(content).encode("utf-8")).hexdigest().upper()


def unicode_character(code):
    return chr(int(code))


def scene_epoch():
    anchor = sys.modules.get("_max_ultra_session")
    return anchor.client.layer_scene_epoch if anchor and getattr(anchor, "client", None) else ""


def owns_window(handle):
    user = ctypes.WinDLL("user32", use_last_error=True)
    user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    process = wintypes.DWORD()
    user.GetWindowThreadProcessId(wintypes.HWND(int(handle)), ctypes.byref(process))
    return process.value == os.getpid()


class MaxApi:
    def __init__(self, root, instance_id, log):
        from pymxs import runtime
        self.rt = runtime
        self.thread = threading.get_ident()
        self.operations = runtime.fileIn(str(root / "core/max-operations.ms"), quiet=True)
        self.operations.instanceId = instance_id
        self.operations.processId = os.getpid()
        self.operations.activityCallback = log

    def check_thread(self):
        if threading.get_ident() != self.thread:
            raise RuntimeError("Max API access is restricted to the main thread")

    def scene_status(self):
        self.check_thread()
        rt = self.rt
        return str(rt.maxFilePath) + str(rt.maxFileName), bool(rt.getSaveRequired()), len(rt.objects), len(rt.selection), str(rt.sliderTime)

    def request(self, action, payload, label):
        self.check_thread()
        ops = self.operations
        if action in ("health", "scene_summary", "smoke"):
            return True, str(ops.buildSceneSummaryJson(action))
        if action == "get_info":
            return True, str(ops.buildGetInfoJson())
        if action == "execute":
            ops.handleExecuteRequest("python", payload, label)
        elif action == "screenshot":
            ops.handleViewportScreenshot("python", payload)
        elif action == "ui_list":
            ops.handleUiListRequest("python", payload)
        elif action == "ui_invoke":
            ops.handleUiInvokeRequest("python", payload)
        else:
            return False, "Unsupported action: " + action
        return bool(ops.responseSuccess), str(ops.responseBody)
