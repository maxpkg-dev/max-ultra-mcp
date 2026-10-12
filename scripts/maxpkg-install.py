# Run package-owned migration without importing an older loaded client module.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import importlib.util
from pathlib import Path
import sys
import types
from pymxs import runtime as rt

def _max_ultra_complete_installation():
    root = Path(__file__).resolve().parent.parent
    package_name = "_max_ultra_install"
    package = types.ModuleType(package_name)
    package.__path__ = [str(root / "python/max_ultra")]
    sys.modules[package_name] = package
    try:
        spec = importlib.util.spec_from_file_location(package_name + ".installation", str(root / "python/max_ultra/installation.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        report = module.complete_installation(root, str(rt.getDir(rt.Name("temp"))))
        if report["preserved"]:
            print("Max Ultra MCP: preserved modified legacy assets: " + ", ".join(report["preserved"]))
    finally:
        for key in list(sys.modules):
            if key == package_name or key.startswith(package_name + "."):
                del sys.modules[key]


_max_ultra_complete_installation()
del _max_ultra_complete_installation
