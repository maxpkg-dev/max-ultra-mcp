# Reload the in-Max Python client after the previous lifecycle has stopped.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import sys
import time
import types
import importlib
import importlib.util

from pymxs import runtime as rt

ROOT = Path(__file__).resolve().parent.parent
PYTHON_ROOT = str(ROOT / "python")
while PYTHON_ROOT in sys.path:
    sys.path.remove(PYTHON_ROOT)
sys.path.insert(0, PYTHON_ROOT)
sys.dont_write_bytecode = True

# This one process-local anchor survives package replacement and module reload.
anchor = sys.modules.setdefault("_max_ultra_session", types.ModuleType("_max_ultra_session"))
if not getattr(anchor, "loading", False):
    anchor.loading = True
    previous = getattr(anchor, "client", None)
    launch_count = getattr(anchor, "launch_count", 0) + 1
    from max_ultra.qt import QtCore, QtWidgets
    started = time.monotonic()

    def finish_reload():
        try:
            if previous and (previous.in_tick or previous.transport.thread.is_alive()):
                # A reload invoked through MCP must send its final reply before
                # closing that connection; never replay it in the new lifecycle.
                reply_pending = previous.transport.connection is not None and not previous.transport.outbound.empty()
                if not previous.in_tick and not previous.disposed and not reply_pending and time.monotonic() - started >= 0.15:
                    previous.close(reload=True)
                if time.monotonic() - started > 15:
                    raise TimeoutError("Previous transport did not stop; retry after it finishes")
                QtCore.QTimer.singleShot(50, finish_reload)
                return
            # The 1.4.7 facade may still own a pending main-thread request.
            legacy = rt.MaxUltraMcpActiveClient if rt.globalVars.isGlobal(rt.Name("MaxUltraMcpActiveClient")) else None
            if legacy is not None:
                if rt.isProperty(legacy, rt.Name("prepareReload")) and not legacy.prepareReload():
                    if time.monotonic() - started > 15:
                        raise TimeoutError("Previous MaxScript client is still busy")
                    QtCore.QTimer.singleShot(50, finish_reload)
                    return
                legacy.disposeForReload()
                rt.MaxUltraMcpActiveClient = rt.undefined
            for module_name in list(sys.modules):
                if module_name == "max_ultra" or module_name.startswith("max_ultra."):
                    del sys.modules[module_name]
            # Another installed copy may also be on sys.path. Bind this launch
            # to its own package explicitly, including all relative imports.
            importlib.invalidate_caches()
            package_root = ROOT / "python/max_ultra"
            spec = importlib.util.spec_from_file_location("max_ultra", str(package_root / "__init__.py"), submodule_search_locations=[str(package_root)])
            package = importlib.util.module_from_spec(spec)
            sys.modules["max_ultra"] = package
            spec.loader.exec_module(package)
            from max_ultra.client import Client
            anchor.client = Client(ROOT, launch_count, restart=previous is not None or legacy is not None)
            anchor.launch_count = launch_count
            anchor.loading = False
            skip_pending = getattr(anchor, "skip_pending_once", False)
            anchor.skip_pending_once = False
            if skip_pending:
                anchor.client.automatic_update_suppressed = True
            else:
                anchor.client.resume_pending_update()
        except Exception as error:
            anchor.loading = False
            QtWidgets.QMessageBox.critical(None, "Max Ultra MCP startup", str(error))

    def wait_for_installation():
        global started
        try:
            # Source launches have no installed manifest. Check before importing
            # package code: an older client may still occupy sys.modules.
            ready = True
            if (ROOT / "manifest.ini").is_file():
                install_package_name = "_max_ultra_boot_install"
                install_package = types.ModuleType(install_package_name)
                install_package.__path__ = [str(ROOT / "python/max_ultra")]
                sys.modules[install_package_name] = install_package
                try:
                    spec = importlib.util.spec_from_file_location(install_package_name + ".installation", str(ROOT / "python/max_ultra/installation.py"))
                    module = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(module)
                    ready = module.installation_ready(ROOT, str(rt.getDir(rt.Name("temp"))))
                finally:
                    for key in list(sys.modules):
                        if key == install_package_name or key.startswith(install_package_name + "."):
                            del sys.modules[key]
            if not ready:
                if time.monotonic() - started > 300:
                    raise TimeoutError("Confirm installation in the MaxPkg installer, then launch Max Ultra MCP again.")
                QtCore.QTimer.singleShot(250, wait_for_installation)
                return
            if not (ROOT / "01_START_MAX_ULTRA_MCP_FIRST.ms").is_file():
                raise RuntimeError("Installation was cancelled. Reinstall the complete MZP package.")
            started = time.monotonic()
            finish_reload()
        except Exception as error:
            anchor.loading = False
            QtWidgets.QMessageBox.critical(None, "Max Ultra MCP installation", str(error))

    QtCore.QTimer.singleShot(0, wait_for_installation)
