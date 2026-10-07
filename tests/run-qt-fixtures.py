# Dedicated-process Qt acceptance runner; never used in an existing user Max process.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import json
import os
from pathlib import Path
import runpy
import sys
import traceback

if os.environ.get("MAX_ULTRA_QT_TEST_PROCESS") != "1":
    raise RuntimeError("This runner requires a dedicated test process")

from pymxs import runtime as rt
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from max_ultra.qt import QtCore, QtWidgets


def run():
    result = {"year": int(rt.maxVersion()[7]), "qt": QtCore.qVersion(), "python": sys.version.split()[0], "ok": False}
    try:
        result["dpi"] = QtWidgets.QApplication.primaryScreen().logicalDotsPerInch()
        result["devicePixelRatio"] = QtWidgets.QApplication.primaryScreen().devicePixelRatio()
        result["requestedScale"] = os.environ.get("MAX_ULTRA_QT_SCALE", "1")
        assert abs(result["devicePixelRatio"] - float(result["requestedScale"])) < 0.05
        for name in ("qt-svg-fixture.py", "qt-dialog-fixture.py", "qt-ui-fixture.py", "python-client-fixture.py"):
            runpy.run_path(str(ROOT / "tests" / name), run_name="__main__")
        result["ok"] = True
    except Exception:
        result["error"] = traceback.format_exc()
    finally:
        output = ROOT / "dist/qt-fixture"
        output.mkdir(parents=True, exist_ok=True)
        (output / ("acceptance-{}-{}.json".format(result["year"], result.get("requestedScale", "1")))).write_text(json.dumps(result, indent=2), encoding="utf-8")
        rt.quitMax(noPrompt=True)


QtCore.QTimer.singleShot(1000, run)
