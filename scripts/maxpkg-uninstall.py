# Invoke the retained ownership-verified external cleanup before package removal.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import os
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
anchor = sys.modules.get("_max_ultra_session")
if anchor and getattr(anchor, "client", None):
    anchor.client.close(reload=True)
helper = root / "scripts/maxpkg-uninstall.ps1"
host = Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
completed = subprocess.run([str(host), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(helper), "-PackageRoot", str(root)], cwd=str(helper.parent), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
if completed.returncode:
    raise RuntimeError("Max Ultra MCP uninstall cleanup failed: " + completed.stderr.decode("utf-8", errors="replace"))
