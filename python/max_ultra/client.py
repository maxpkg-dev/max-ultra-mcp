# Main-thread controller for the Python client; Node remains the MCP server.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from collections import deque
import json
import os
from pathlib import Path
import time
import uuid
import datetime
import sys

from .qt import QtCore, QtWidgets, QtGui, max_parent, protect_keyboard, release_keyboard
from . import themes
from .widgets import Panel, MiniPanel
from .dialogs import SettingsWindow, Onboarding, SkillsWindow, CLIENTS
from .settings import Settings, read_ini
from .journal import Journal
from .max_api import MaxApi
from .processes import process_started, launch_helper
from .transport import Transport
from .helpers import Helper
from .wire import encode, decode
from .tasks import BackgroundTasks
from .updates import verify_package, staged_version


class Client:
    def __init__(self, root, launch_count=1, restart=False):
        self.disposed = False
        self.dialogs = {}
        self.transport = self.timer = self.journal = None
        self.tasks = BackgroundTasks()
        self.integration = self.skills_helper = self.update_helper = None
        try:
            self.initialize(root, launch_count, restart)
        except Exception:
            self.close(reload=True)
            raise

    def initialize(self, root, launch_count, restart):
        from pymxs import runtime as rt
        self.root = Path(root).resolve()
        self.rt = rt
        self.launch_count = launch_count
        self.disposed = False
        self.in_tick = False
        self.status = "Starting local MCP server..."
        self.connection_state = "starting"
        self.support_reminder_count = 0
        self.support_reminder_due = None
        self.state_directory = Path(str(rt.getDir(rt.Name("userScripts")))) / "MaxUltraMCP"
        self.state_directory.mkdir(parents=True, exist_ok=True)
        self.settings = Settings(self.state_directory / "panel-ui.ini")
        theme_error = None
        try:
            themes.select(self.settings.get("appearance", "theme", "graphite"))
        except (OSError, ValueError) as error:
            theme_error = str(error)
        if themes.current == "max":
            themes.read_max_colors(self.rt)
        self.update_applying = False
        self.automatic_update_suppressed = False
        self.update_message = self.settings.get("updates", "lastStatus")
        self.sync_autostart()
        manifest = self.root / "manifest.ini"
        versions = read_ini(manifest if manifest.exists() else self.root / "version.ini")
        self.version = versions.get("package", "version", fallback="") or versions.get("MaxUltraMCP", "Version", fallback="development")
        self.started_at, ticks = process_started()
        year = int(rt.maxVersion()[7])
        self.instance_id = "max-{}-pid-{}-{}".format(year, os.getpid(), ticks)
        journal_directory = Path(os.environ["LOCALAPPDATA"]) / "3DGROUND/MaxUltraMCP/runtime/journals"
        journal_directory.mkdir(parents=True, exist_ok=True)
        self.journal = Journal(journal_directory / (self.instance_id + ".sqlite3"))
        self.api = MaxApi(self.root, self.instance_id, self.log)
        self.layer_scene_epoch = uuid.uuid4().hex
        self.port = int(os.environ.get("MAX_ULTRA_MCP_PORT", "47635"))
        if not 1 <= self.port <= 65535:
            raise ValueError("Invalid MCP port")
        if os.environ.get("MAX_ULTRA_MCP_HOST", "127.0.0.1") != "127.0.0.1":
            raise ValueError("Max Ultra MCP requires the 127.0.0.1 loopback endpoint")
        self.hello = "\t".join(["HELLO", "1", encode(self.instance_id), str(os.getpid()), encode(year), encode(str(rt.maxVersion())), encode(self.started_at)])
        self.transport = None
        self.pending = deque()
        self.cancelled = set()
        self.integration = self.skills_helper = self.update_helper = None
        self.integration_result = None
        self.integration_message = "Refresh status to detect AI clients."
        self.integration_client = ""
        self.integration_action = ""
        self.integration_automatic = False
        self.integration_failed = False
        self.integration_steps = []
        self.integration_stage_count = 0
        self.dialogs = {}
        parent = max_parent()
        self.panel = Panel(self, parent)
        self.mini = MiniPanel(self, parent)
        protect_keyboard(self.panel)
        protect_keyboard(self.mini)
        self.restore_geometry(self.panel, "panel", (640, 480))
        self.restore_geometry(self.mini, "restoreBubble", (180, 32))
        if self.settings.boolean("panel", "hidden"):
            self.mini.show()
        else:
            self.panel.show()
        self.timer = QtCore.QTimer(self.panel)
        self.timer.setInterval(50)
        self.timer.timeout.connect(self.tick)
        self.timer.start()
        self.last_status = 0
        self.automatic_due = time.monotonic() + 2
        self.reconnect_pending = False
        self.start_transport(restart=restart)
        self.log("system", "Initializing Max Ultra MCP services")
        if theme_error:
            self.log("error", "Could not load saved color theme: " + theme_error)
        if self.update_message:
            self.log("error" if self.update_message.startswith("Update could not complete:") else "info", self.update_message)
        QtWidgets.QApplication.instance().aboutToQuit.connect(self.close)
        callback_id = rt.Name("MaxUltraMcpPythonLifecycle")
        rt.callbacks.removeScripts(id=callback_id)
        for event in ("systemPreReset", "systemPreNew", "filePreOpen"):
            rt.callbacks.addScript(rt.Name(event), self.invalidate_scene, id=callback_id, persistent=False)
        rt.callbacks.addScript(rt.Name("preSystemShutdown"), self.close, id=callback_id, persistent=False)

    def resume_pending_update(self):
        package = self.settings.get("updates", "pendingPackage")
        if package and not self.disposed:
            try:
                version = self.settings.get("updates", "pendingVersion") or staged_version(package)
                self.stage_update_package(package, version)
            except Exception as error:
                self.update_failed(error)

    def invalidate_scene(self):
        self.layer_scene_epoch = uuid.uuid4().hex

    def storage_failure(self, message):
        if hasattr(self, "panel"):
            self.panel.storage_error.setText("Local history/settings could not be saved: " + message)
            self.panel.storage_error.show()

    def log(self, category, message):
        try:
            self.journal.append(str(category), str(message))
        except Exception as error:
            self.storage_failure(str(error))

    def save_setting(self, section, values):
        try:
            self.settings.set_many(section, values)
            return True
        except OSError as error:
            self.storage_failure(str(error))
            return False

    def poll_support_reminder(self, now):
        if self.support_reminder_due is None or now < self.support_reminder_due:
            return
        self.log("support", "Max Ultra MCP is maintained independently in personal time. Without community support, continued development may not be sustainable. If it helps your work, please use Donate to support it.")
        self.support_reminder_count += 1
        delays = (60, 600, 3600)
        self.support_reminder_due = now + delays[self.support_reminder_count] if self.support_reminder_count < len(delays) else None

    def restore_geometry(self, window, section, default):
        width = max(window.minimumWidth(), self.settings.integer(section, "width", default[0]))
        height = max(window.minimumHeight(), self.settings.integer(section, "height", default[1]))
        width, height = min(width, window.maximumWidth()), min(height, window.maximumHeight())
        screen = QtWidgets.QApplication.primaryScreen().availableGeometry()
        x = self.settings.integer(section, "x", screen.x() + 60)
        y = self.settings.integer(section, "y", screen.y() + 80)
        rectangle = QtCore.QRect(x, y, width, height)
        for candidate in QtWidgets.QApplication.screens():
            if candidate.availableGeometry().contains(rectangle.topLeft()):
                screen = candidate.availableGeometry()
                break
        width, height = min(width, screen.width()), min(height, screen.height())
        x = max(screen.left(), min(x, screen.right() - width + 1))
        y = max(screen.top(), min(y, screen.bottom() - height + 1))
        window.setGeometry(x, y, width, height)

    def save_geometry(self):
        for window, section in ((self.panel, "panel"), (self.mini, "restoreBubble")):
            rectangle = window.normalGeometry() if window.isMinimized() else window.geometry()
            self.save_setting(section, {"x": rectangle.x(), "y": rectangle.y(), "width": rectangle.width(), "height": rectangle.height()})

    def show_panel(self):
        self.save_geometry()
        self.mini.hide()
        self.panel.showNormal()
        self.panel.ai.setFocus(QtCore.Qt.OtherFocusReason)
        self.save_setting("panel", {"hidden": False})
        return True

    def hide_panel(self):
        self.save_geometry()
        self.mini.update_status(*self.mini_status())
        self.mini.show()
        self.panel.hide()
        self.save_setting("panel", {"hidden": True})
        return True

    def start_transport(self, restart=False, allow_launch=True):
        self.transport = Transport(self.root, self.state_directory, self.port, self.hello, restart, allow_launch, self.settings.boolean("settings", "showServerConsole"))
        self.transport.start()

    def reconnect(self):
        if self.disposed or self.reconnect_pending:
            return
        self.status = "Reconnecting..."
        self.connection_state = "reconnecting"
        self.transport.stop()
        self.pending.clear()
        self.cancelled.clear()
        self.reconnect_pending = True

    def send_status(self):
        scene = self.api.scene_status()
        self.scene_context = "PID {} | Scene {} | Objects {} | Selection {}".format(os.getpid(), scene[0] or "Untitled", scene[2], scene[3])
        self.transport.outbound.put("\t".join(["STATUS", encode(scene[0]), str(scene[1]).lower(), str(scene[2]), str(scene[3]), encode(scene[4])]))

    def process_request(self, fields):
        identifier = fields[1]
        try:
            if len(fields) > 5 and time.time() * 1000 >= int(fields[5]):
                raise TimeoutError("REQUEST_EXPIRED: request expired before main-thread execution")
            if identifier in self.cancelled:
                self.cancelled.discard(identifier)
                raise RuntimeError("Request cancelled before main-thread execution")
            action = fields[2]
            payload = decode(fields[3]) if len(fields) > 3 else ""
            label = decode(fields[4]) if len(fields) > 4 else ""
            if action == "logs":
                rows = self.journal.tail(30)
                response = json.dumps({"action": "logs", "available": True, "source": "Max Ultra MCP panel", "content": "\n".join("{} [{}] {}".format(row[1], row[2], row[3]) for row in rows), "entryCount": len(rows), "maximumEntries": 30})
                success = True
            elif action == "panel":
                if payload in ("show", "restore"):
                    self.show_panel()
                elif payload == "hide":
                    self.hide_panel()
                elif payload == "minimize":
                    self.panel.showMinimized()
                else:
                    raise ValueError("Unsupported panel action")
                success, response = True, json.dumps({"action": "panel", "ok": True, "requestedAction": payload, "state": payload, "mainThread": True})
            else:
                success, response = self.api.request(action, payload, label)
            self.transport.outbound.put("RESPONSE\t{}\t{}\t{}".format(identifier, "ok" if success else "error", encode(response)))
        except Exception as error:
            self.transport.outbound.put("RESPONSE\t{}\terror\t{}".format(identifier, encode(str(error))))

    def tick(self):
        if self.disposed or self.in_tick:
            return
        self.in_tick = True
        try:
            if self.reconnect_pending and not self.transport.thread.is_alive():
                self.reconnect_pending = False
                self.start_transport(allow_launch=False)
            for _ in range(16):
                line = self.transport.inbound.pop()
                if line is None:
                    break
                fields = line.split("\t")
                if fields[0] == "EVENT":
                    message = decode(fields[2])
                    if fields[1] == "connected":
                        self.connection_state = "connected"
                        if self.support_reminder_due is None and self.support_reminder_count == 0:
                            self.support_reminder_due = time.monotonic() + 60
                        self.status = "Server 127.0.0.1:{}".format(self.transport.port)
                        self.port = self.transport.port
                        self.log("success", message)
                    elif fields[1] == "port_changed":
                        self.port = int(message)
                        self.log("warning", "Using fallback endpoint; MCP host setting MAX_ULTRA_MCP_PORT=" + message)
                    else:
                        self.log(fields[1], message)
                elif fields[0] == "REQUEST":
                    if len(self.pending) >= 64 or sum(len("\t".join(entry)) for entry in self.pending) + len(line) > 8388608:
                        raise BufferError("Main-thread request queue limit reached")
                    self.pending.append(fields)
                elif fields[0] == "CANCEL" and len(fields) > 1:
                    if len(self.cancelled) >= 64:
                        self.cancelled.clear()
                    self.cancelled.add(fields[1])
                elif fields[0] == "STOP":
                    self.transport.stop()
                    self.pending.clear()
                    self.status = "Instance registration replaced"
                    self.connection_state = "stopped"
            # Drain transport frames before execution so queued cancellation is observed.
            if self.transport.error:
                self.connection_state = "error"
                self.status = self.transport.error
                self.log("error", self.status)
                self.transport.error = None
                self.pending.clear()
            if self.pending and self.transport.inbound.empty() and self.transport.connection is not None and not self.reconnect_pending and not self.transport.stop_event.is_set():
                self.process_request(self.pending.popleft())
            now = time.monotonic()
            self.poll_support_reminder(now)
            if now - self.last_status > 1:
                if themes.current == "max" and themes.read_max_colors(self.rt):
                    self.apply_theme()
                if self.transport.connection is not None:
                    self.send_status()
                self.panel.refresh()
                self.mini.update_status(*self.mini_status())
                self.last_status = now
            if self.automatic_due and now >= self.automatic_due:
                self.automatic_due = 0
                self.start_integration("Status", automatic=True)
                if not self.automatic_update_suppressed and (self.launch_count - 1) % 3 == 0 and self.settings.boolean("updates", "automatic", True):
                    self.check_updates()
            self.poll_helpers()
            self.tasks.poll()
        except Exception as error:
            self.log("error", str(error))
            self.status = str(error)
            self.connection_state = "error"
            self.transport.stop()
            self.pending.clear()
            self.mini.update_status(*self.mini_status())
        finally:
            self.in_tick = False

    def mini_status(self):
        state = getattr(self, "connection_state", "starting")
        if state == "error":
            return "error", self.status
        if state != "connected" or self.transport.connection is None or self.reconnect_pending:
            return "warning", self.status
        label, ai_state = self.ai_status()
        if self.integration_failed and self.integration is None:
            return "error", label
        return ("ready" if ai_state == "ready" else "warning"), self.status + " | " + label

    def show_dialog(self, key, kind):
        dialog = self.dialogs.get(key)
        if dialog is None:
            dialog = kind(self, self.panel if key == "settings" else self.panel.parentWidget())
            protect_keyboard(dialog)
            self.dialogs[key] = dialog
        dialog.show()
        dialog.raise_()
        dialog.activateWindow()
        return dialog

    def show_onboarding(self):
        self.show_dialog("onboarding", Onboarding)

    def show_settings(self):
        self.show_dialog("settings", SettingsWindow)

    def set_theme(self, identifier):
        try:
            document = themes.load(identifier)
        except (OSError, ValueError) as error:
            self.log("error", "Could not load color theme: " + str(error))
            return False
        if identifier not in themes.THEMES or not self.save_setting("appearance", {"theme": identifier}):
            return False
        themes.select(identifier, document)
        if identifier == "max":
            themes.read_max_colors(self.rt)
        self.apply_theme()
        return True

    def apply_theme(self):
        # Use the controller's actual objects, including hidden dialogs. Qt's
        # top-level enumeration can return base wrappers after module reloads.
        themes.apply_all([self.panel, self.mini] + list(self.dialogs.values()))

    def show_skills(self):
        self.show_dialog("skills", SkillsWindow)
        self.skills_operation("list")

    def manual_setup(self):
        parser = self.integration_result
        node = str(self.root / "runtime/win-x64/node.exe")
        server = str(self.root / "core/server.js")
        environment = {"MAX_ULTRA_MCP_TOOL_PROFILE": "archviz"}
        if parser is not None:
            node = parser.get("runtime", "command", fallback="") or node
            server = parser.get("runtime", "server", fallback="") or server
            for line in parser.get("runtime", "environment", fallback="").splitlines():
                key, separator, value = line.partition("=")
                if separator and key.strip():
                    environment[key.strip()] = value
        environment["MAX_ULTRA_MCP_PORT"] = str(self.port)
        return json.dumps({"mcpServers": {"max-ultra-mcp": {"command": node, "args": [server, "--stdio"], "env": environment}}}, indent=2)

    def client_state(self, identifier):
        if self.integration_failed:
            return "check_failed"
        if self.integration_result is None:
            return "checking" if self.integration else "unknown"
        state = self.integration_result.get(identifier, "state", fallback="check_failed")
        if state == "configured":
            return state
        if state in ("not_configured", "restart_required") and self.integration_result.get(identifier, "desktopstate", fallback="") == "missing":
            return "desktop_missing"
        return state

    def ai_status(self):
        if self.integration:
            return "Checking AI clients...", "checking"
        if self.integration_failed:
            return "Setup AI Client | check failed", "issue"
        states = [self.client_state(identifier) for identifier, _, _, _ in CLIENTS]
        if any(state in ("check_failed", "runtime_missing", "runtime_check_failed", "install_failed", "desktop_check_failed") for state in states):
            return "Setup AI Client | needs attention", "issue"
        if "restart_required" in states:
            return "Setup AI Client | restart required", "issue"
        ready = [label for identifier, label, _, _ in CLIENTS if self.client_state(identifier) == "configured"]
        if ready:
            return " / ".join(ready) + " | MCP ready", "ready"
        return "Setup AI Client", "setup"

    def start_integration(self, operation, identifier="", switches=None, automatic=False):
        if self.integration or self.disposed:
            return
        self.integration_action = operation
        self.integration_client = identifier
        self.integration_automatic = automatic
        self.integration_failed = False
        self.integration_steps = []
        self.integration_stage_count = 0
        self.integration_message = "{}: {}".format(identifier or "AI clients", operation)
        self.integration_step(self.integration_message)
        self.integration = Helper(self.root, self.state_directory, "agent-integration.ps1", ["-Action", operation, "-Port", str(self.port)] + (switches or []), timeout=660 if operation == "InstallCli" else 120 if operation == "Install" else 75)

    def refresh_agents(self):
        self.start_integration("Status")

    def cancel_integration(self):
        if self.integration:
            self.integration.cancel()
            self.integration_message = "Cancellation requested; waiting for the installer to finish stopping."
            self.integration_step(self.integration_message, "warning")

    def integration_step(self, message, kind="info"):
        message = " ".join(str(message).splitlines())
        self.integration_steps.append((datetime.datetime.now().strftime("%H:%M:%S"), kind, message))

    def skills_operation(self, operation, arguments=None):
        if self.skills_helper or self.disposed:
            return False
        self.skills_helper = Helper(self.root, self.state_directory, "skills-manager.ps1", ["-Action", operation] + (arguments or []) + ["-Background", "28,28,26", "-Foreground", "232,227,218", "-ButtonBackground", "48,46,41", "-ButtonHover", "65,56,45"], timeout=120)
        if "skills" in self.dialogs:
            self.dialogs["skills"].set_busy(True)
        return True

    def check_updates(self):
        if self.update_helper or self.disposed or self.update_applying:
            return
        self.update_helper = Helper(self.root, self.state_directory, "update-manager.ps1", ["-Action", "CheckAndStage", "-ProjectRoot", str(self.root)], "-ResultFile", 300)
        self.log("info", "Checking for updates")

    def poll_helpers(self):
        for name in ("integration", "skills_helper", "update_helper"):
            helper = getattr(self, name)
            if helper is None:
                continue
            try:
                code = helper.poll()
                if name == "integration" and helper.snapshot:
                    self.integration_result = helper.snapshot
                    message = helper.snapshot.get("operation", "message", fallback="")
                    if message:
                        self.integration_message = message
                    stages = helper.snapshot.get("operation", "stages", fallback="").split("|")
                    kinds = helper.snapshot.get("operation", "stagekinds", fallback="").split("|")
                    for index in range(self.integration_stage_count, len(stages)):
                        if stages[index]:
                            self.integration_step(stages[index], kinds[index] if index < len(kinds) else "info")
                    self.integration_stage_count = len(stages) if stages != [""] else 0
                if code is None:
                    continue
                if name == "integration":
                    self.integration_failed = code != 0 or helper.snapshot is None or helper.cancelled
                    if helper.snapshot is not None:
                        self.integration_failed = self.integration_failed or helper.snapshot.get("operation", "state", fallback="failed") == "failed"
                        if self.integration_client:
                            state = helper.snapshot.get(self.integration_client, "state", fallback="check_failed")
                            self.integration_failed = self.integration_failed or state in ("install_failed", "check_failed", "runtime_check_failed", "runtime_missing")
                    if self.integration_failed:
                        self.integration_message = "Cancelled" if helper.cancelled else "AI setup failed. Refresh status before retrying."
                        self.log("warning" if helper.cancelled else "error", self.integration_message)
                        self.integration_step(self.integration_message, "warning" if helper.cancelled else "error")
                    else:
                        self.log("success", "AI client operation completed; registration does not imply a live chat connection")
                        self.integration_step(self.integration_message, "success")
                        if self.integration_action == "InstallCli" and self.integration_client:
                            record = next(entry for entry in CLIENTS if entry[0] == self.integration_client)
                            if helper.snapshot.get(self.integration_client, "desktopstate", fallback="") != "installed":
                                QtGui.QDesktopServices.openUrl(QtCore.QUrl(record[3]))
                            self.integration_message = "CLI verified. Install the desktop app if needed, then Refresh status and Connect on the same card."
                        states = [self.client_state(entry[0]) for entry in CLIENTS]
                        conclusive = {"configured", "not_configured", "restart_required", "cli_missing", "runtime_missing", "desktop_missing"}
                        if self.integration_automatic and all(state in conclusive for state in states) and "configured" not in states:
                            self.show_onboarding()
                elif name == "skills_helper":
                    if "skills" in self.dialogs:
                        self.dialogs["skills"].apply_result(helper)
                else:
                    if code != 0 or helper.snapshot is None:
                        raise RuntimeError("Update check failed")
                    state = helper.snapshot.get("update", "state", fallback="error")
                    message = helper.snapshot.get("update", "message", fallback="Update result unavailable")
                    self.update_message = message
                    self.log("success" if state in ("ready", "current") else "warning", message)
                    if state == "ready":
                        self.stage_update(helper.snapshot)
                helper.cleanup()
                setattr(self, name, None)
            except Exception as error:
                self.log("error", str(error))
                if name == "update_helper":
                    self.update_message = str(error)
                helper.dispose()
                if name == "integration":
                    self.integration_failed = True
                    self.integration_message = str(error)
                    self.integration_step(str(error), "error")
                setattr(self, name, None)
        if "onboarding" in self.dialogs:
            self.dialogs["onboarding"].update_status()
        if "skills" in self.dialogs:
            self.dialogs["skills"].set_busy(self.skills_helper is not None)
        if "settings" in self.dialogs:
            self.dialogs["settings"].update_status()

    def stage_update(self, result):
        package = result.get("update", "packagepath")
        version = result.get("update", "latestversion")
        self.stage_update_package(package, version)

    def update_failed(self, error):
        self.update_applying = False
        self.update_message = "Update could not complete: " + str(error)
        self.save_setting("updates", {"lastStatus": self.update_message})
        if not self.disposed:
            self.log("error", self.update_message)

    def stage_update_package(self, package, version):
        if self.update_applying or self.disposed:
            return
        self.update_applying = True
        self.update_message = "Verifying staged update " + version
        def verified(filename):
            if self.disposed:
                return
            if self.save_setting("updates", {"pendingPackage": str(filename), "pendingVersion": version}):
                QtCore.QTimer.singleShot(0, self.apply_update)
            else:
                self.update_failed("Could not save the pending update")
        try:
            self.tasks.submit(lambda: verify_package(package, self.state_directory / "updates", version), verified, self.update_failed)
        except Exception as error:
            self.update_failed(error)

    def apply_update(self):
        package = self.settings.get("updates", "pendingPackage")
        if not package or self.disposed:
            return
        version = self.settings.get("updates", "pendingVersion")
        self.close(reload=True)
        deadline = time.monotonic() + 15
        def install_when_stopped():
            if self.transport.thread.is_alive():
                if time.monotonic() > deadline:
                    self.recover_update("Transport did not stop. Update remains pending.")
                else:
                    QtCore.QTimer.singleShot(50, install_when_stopped)
                return
            self.install_update(package, version)
        QtCore.QTimer.singleShot(0, install_when_stopped)

    def install_update(self, package, version):
        try:
            self.rt.fileIn(package, quiet=True)
            installed = read_ini(self.root / "manifest.ini").get("package", "version", fallback="")
            if installed != version:
                raise RuntimeError("Installation was cancelled or the installed version was not updated. The staged package remains available for retry.")
            self.settings.set_many("updates", {"pendingPackage": "", "pendingVersion": "", "lastStatus": "Installed version " + version})
            self.rt.fileIn(str(self.root / "01_START_MAX_ULTRA_MCP_FIRST.ms"), quiet=True)
        except Exception as error:
            self.recover_update(error)

    def recover_update(self, error):
        self.update_failed(error)
        # Reopen the surviving installation once, without retrying the same
        # failed installer recursively. A later explicit launch retries it.
        anchor = sys.modules.get("_max_ultra_session")
        if anchor is not None:
            anchor.skip_pending_once = True
        try:
            self.rt.fileIn(str(self.root / "01_START_MAX_ULTRA_MCP_FIRST.ms"), quiet=True)
        except Exception as restart_error:
            if anchor is not None:
                anchor.skip_pending_once = False
            QtWidgets.QMessageBox.critical(None, "Max Ultra MCP update", self.update_message + "\nCould not restart: " + str(restart_error))

    def autostart_file(self):
        return Path(str(self.rt.getDir(self.rt.Name("userStartupScripts")))) / "3DGROUND-Max-Ultra-MCP-Autostart.ms"

    def sync_autostart(self):
        enabled = self.autostart_file().is_file()
        if self.settings.boolean("settings", "autostart") != enabled:
            self.save_setting("settings", {"autostart": enabled})
        return enabled

    def set_autostart(self, enabled):
        destination = self.autostart_file()
        if enabled:
            script = str(self.root / "01_START_MAX_ULTRA_MCP_FIRST.ms").replace('"', '\\"')
            destination.write_text('-- Max Ultra MCP owned startup entry.\nfileIn @"' + script + '" quiet: true\n', encoding="utf-8")
        elif destination.exists():
            destination.unlink()
        self.save_setting("settings", {"autostart": enabled})

    def donate(self):
        QtGui.QDesktopServices.openUrl(QtCore.QUrl("https://store.payproglobal.com/checkout?products[1][id]=137366"))

    def close(self, reload=False):
        if self.disposed:
            return
        if hasattr(self, "panel") and hasattr(self, "mini"):
            self.save_geometry()
        self.disposed = True
        self.tasks.close()
        release_keyboard()
        if hasattr(self, "rt"):
            self.rt.callbacks.removeScripts(id=self.rt.Name("MaxUltraMcpPythonLifecycle"))
        try:
            QtWidgets.QApplication.instance().aboutToQuit.disconnect(self.close)
        except (RuntimeError, TypeError):
            pass
        if self.timer:
            self.timer.stop()
        if self.transport:
            self.transport.stop()
        for helper in (self.integration, self.skills_helper, self.update_helper):
            if helper:
                helper.dispose()
        for dialog in list(self.dialogs.values()) + [getattr(self, "mini", None), getattr(self, "panel", None)]:
            if dialog is None:
                continue
            dialog.hide()
            dialog.deleteLater()
        if self.journal:
            self.journal.close()
        if not reload and self.transport:
            ownership = self.state_directory / "ownership" / ("max-ultra-mcp-owned-{}.json".format(self.port))
            launch_helper(self.root, "stop-owned-server.ps1", ["-OwnershipFile", str(ownership), "-Port", str(self.port), "-OwnerToken", self.transport.owner_token, "-ClosingMaxPid", str(os.getpid())])
