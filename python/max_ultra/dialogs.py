# Qt settings, AI onboarding and passive skills management windows.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import html
import json
import re
import time

from .qt import QtWidgets, QtCore, QtGui, Qt
from .widgets import Window, ActionButton, action, donate_action, COLORS
from .wire import decode

CLIENTS = [("openai", "Codex", "InstallOpenAI", "https://chatgpt.com/download/"), ("claudeCode", "Claude Code", "InstallClaudeCode", "https://claude.ai/download"), ("antigravity", "Antigravity", "InstallAntigravity", "https://antigravity.google/download")]
TEST_PROMPT = "Use Max Ultra MCP to list connected 3ds Max instances. If exactly one is connected, select it and report its version, connection health, scene summary and capabilities. Do not create, modify, save or render anything."


class PassiveBrowser(QtWidgets.QTextBrowser):
    def loadResource(self, resource_type, url):
        # Imported documents cannot fetch network or local resources implicitly.
        return QtCore.QByteArray()


class InlineHelpBrowser(PassiveBrowser):
    def __init__(self):
        super().__init__()
        self.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setStyleSheet("QTextBrowser { border:none; padding:0; background:transparent; }")
        self.document().documentLayout().documentSizeChanged.connect(self.fit_height)

    def fit_height(self, *args):
        self.setFixedHeight(int(self.document().size().height()) + 10)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.fit_height()


class SettingsWindow(Window):
    def __init__(self, client, parent):
        super().__init__(client.root, "Settings", parent)
        self.setWindowModality(Qt.WindowModal)
        self.client = client
        client.sync_autostart()
        self.resize(540, 720)
        self.setMinimumSize(320, 260)
        content = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(content)
        layout.setSpacing(12)
        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(content)
        self.outer.addWidget(scroll)
        groups = {}
        for title in ["Autostart", "Server console", "Updates", "AI client integration", "About"]:
            group = QtWidgets.QGroupBox(title)
            group.setStyleSheet("QGroupBox { border:1px solid #62594c; border-radius:0; margin-top:12px; padding:12px 10px 8px; } QGroupBox::title { subcontrol-origin:margin; subcontrol-position:top left; left:10px; padding:0 5px; color:#efb577; }")
            groups[title] = QtWidgets.QVBoxLayout(group)
            layout.addWidget(group)
        check_icon = (client.root / "assets/icons/check.svg").as_posix()
        for group, label, section, key, default in [("Autostart", "Autostart with 3ds Max", "settings", "autostart", False), ("Server console", "Show server console when starting", "settings", "showServerConsole", False), ("Updates", "Check and install updates automatically", "updates", "automatic", True)]:
            checkbox = QtWidgets.QCheckBox(label)
            checkbox.setMinimumHeight(30)
            checkbox.setStyleSheet(
                'QCheckBox { color:#e8e3da; spacing:9px; } '
                'QCheckBox::indicator { width:20px; height:20px; border:1px solid #a29684; border-radius:3px; background:#191916; } '
                'QCheckBox::indicator:checked { background:#a35d2c; border-color:#efa35c; image:url("' + check_icon + '"); } '
                'QCheckBox::indicator:hover { border-color:#ffd09a; } '
                'QCheckBox:focus { color:#fff0dc; }')
            checkbox.setChecked(client.settings.boolean(section, key, default))
            if key == "autostart":
                checkbox.toggled.connect(client.set_autostart)
            else:
                checkbox.toggled.connect(lambda enabled, s=section, k=key: client.save_setting(s, {k: enabled}))
            groups[group].addWidget(checkbox)
        update_row = QtWidgets.QHBoxLayout()
        self.update_status_label = QtWidgets.QLabel()
        self.update_status_label.setWordWrap(True)
        update_row.addWidget(self.update_status_label, 1)
        self.check_updates = action(client.root, "refresh-cw", "Check now", client.check_updates)
        update_row.addWidget(self.check_updates)
        groups["Updates"].addLayout(update_row)
        groups["AI client integration"].addWidget(action(client.root, "settings", "Open AI client setup...", self.open_ai_setup))
        for text in ["3DGROUND - Max Ultra MCP", "Version " + client.version, "Lukianenko Vasyl"]:
            label = QtWidgets.QLabel(text)
            label.setWordWrap(True)
            label.setAlignment(Qt.AlignCenter)
            groups["About"].addWidget(label)
        for address in ["3dground.net", "maxpkg.dev"]:
            link = QtWidgets.QLabel('<a href="https://' + address + '" style="color:#efa35c">' + address + '</a>')
            link.setAlignment(Qt.AlignCenter)
            link.setOpenExternalLinks(True)
            groups["About"].addWidget(link)
        groups["About"].addWidget(donate_action(client.root, client.donate), 0, Qt.AlignHCenter)
        self.update_status()
        self.ensurePolished()
        layout.activate()
        margins = self.outer.contentsMargins()
        height = (layout.sizeHint().height() + self.header.sizeHint().height()
                  + margins.top() + margins.bottom() + self.outer.spacing()
                  + scroll.frameWidth() * 2 + 16)
        screen = self.screen()
        if screen is not None:
            height = min(height, screen.availableGeometry().height() - 40)
        self.resize(self.width(), max(self.minimumHeight(), height))

    def open_ai_setup(self):
        self.close()
        self.client.show_onboarding()

    def update_status(self):
        busy = self.client.update_helper is not None
        self.check_updates.setEnabled(not busy)
        self.update_status_label.setText("Checking for updates..." if busy else getattr(self.client, "update_message", "Check for available updates."))


class Onboarding(Window):
    def __init__(self, client, parent):
        super().__init__(client.root, "AI Client Setup", parent)
        self.client = client
        self.resize(670, 570)
        self.setMinimumSize(320, 320)
        self.tabs = QtWidgets.QTabWidget()
        self.outer.addWidget(self.tabs)
        setup = QtWidgets.QWidget()
        setup_layout = QtWidgets.QVBoxLayout(setup)
        self.cards = []
        self.card_panels = []
        self.card_statuses = []
        self.card_grid = QtWidgets.QGridLayout()
        setup_layout.addLayout(self.card_grid)
        for index, (identifier, label, switch, url) in enumerate(CLIENTS):
            card = QtWidgets.QWidget()
            card_layout = QtWidgets.QVBoxLayout(card)
            card_layout.setContentsMargins(5, 8, 5, 8)
            card_layout.setSpacing(8)
            button = ActionButton()
            button.setText(label)
            button.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
            logo = ("codex.svg", "claude.svg", "antigravity.svg")[index]
            button.setIcon(QtGui.QIcon(str(client.root / "assets/client-logos" / logo)))
            button.setIconSize(QtCore.QSize(56, 56))
            button.setMinimumHeight(116)
            button.setMinimumWidth(0)
            button.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Fixed)
            button.clicked.connect(lambda checked=False, client_id=identifier: self.activate_client(client_id))
            card_layout.addWidget(button)
            status = QtWidgets.QLabel("Checking...")
            status.setAlignment(Qt.AlignCenter)
            status.setWordWrap(True)
            card_layout.addWidget(status)
            self.card_grid.addWidget(card, index, 0)
            self.cards.append(button)
            self.card_panels.append(card)
            self.card_statuses.append(status)
        self.card_grid.setHorizontalSpacing(12)
        self.card_grid.setVerticalSpacing(10)
        self.detail = PassiveBrowser()
        self.detail.setReadOnly(True)
        self.detail.setStyleSheet("QTextBrowser { font-family:Consolas; font-size:11pt; }")
        self.detail.setMinimumHeight(90)
        self.detail.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Expanding)
        setup_layout.addWidget(self.detail, 1)
        self.progress = QtWidgets.QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.hide()
        self.elapsed = QtWidgets.QLabel("0 s")
        self.elapsed.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.elapsed.setMinimumWidth(48)
        self.elapsed.setToolTip("Elapsed time for the current operation")
        self.elapsed.setAccessibleName("Elapsed operation time")
        self.elapsed.hide()
        progress_row = QtWidgets.QHBoxLayout()
        progress_row.addWidget(self.progress, 1)
        progress_row.addWidget(self.elapsed)
        setup_layout.addLayout(progress_row)
        controls = QtWidgets.QHBoxLayout()
        self.refresh = action(client.root, "refresh-cw", "Refresh status", client.refresh_agents)
        self.cancel = QtWidgets.QPushButton("Cancel")
        self.cancel.clicked.connect(client.cancel_integration)
        controls.addWidget(self.refresh)
        controls.addWidget(self.cancel)
        setup_layout.addLayout(controls)
        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(setup)
        self.tabs.addTab(scroll, "Setup")
        for title, content in [("Test prompt", TEST_PROMPT)]:
            page = QtWidgets.QWidget()
            layout = QtWidgets.QVBoxLayout(page)
            box = QtWidgets.QPlainTextEdit(content)
            box.setReadOnly(True)
            layout.addWidget(box)
            copy_button = action(client.root, "copy", "Copy", lambda checked=False, text=content: QtWidgets.QApplication.clipboard().setText(text))
            layout.addWidget(copy_button)
            self.tabs.addTab(page, title)
        manual = QtWidgets.QWidget()
        manual_layout = QtWidgets.QVBoxLayout(manual)
        explanation = QtWidgets.QLabel("For clients configured manually, use these STDIO values. Automatic setup is available on the Setup tab.")
        explanation.setWordWrap(True)
        manual_layout.addWidget(explanation)
        self.manual_fields = []
        self._manual_text = None
        for label in ("Command", "Arguments (one per line)", "Environment"):
            manual_layout.addWidget(QtWidgets.QLabel(label))
            field = QtWidgets.QPlainTextEdit()
            field.setReadOnly(True)
            field.setAccessibleName(label)
            field.setStyleSheet("font-family:Consolas; font-size:11pt;")
            field.setMaximumHeight(70)
            manual_layout.addWidget(field)
            self.manual_fields.append(field)
        self.runtime_status = QtWidgets.QLabel()
        self.runtime_status.setWordWrap(True)
        manual_layout.addWidget(self.runtime_status)
        manual_layout.addWidget(action(client.root, "refresh-cw", "Refresh status", client.refresh_agents))
        manual_layout.addStretch()
        manual_layout.addWidget(action(client.root, "copy", "Copy JSON configuration", lambda: QtWidgets.QApplication.clipboard().setText(client.manual_setup())))
        manual_scroll = QtWidgets.QScrollArea()
        manual_scroll.setWidgetResizable(True)
        manual_scroll.setWidget(manual)
        self.tabs.addTab(manual_scroll, "Manual setup")
        self.update_status()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, "cards"):
            for index, card in enumerate(self.card_panels):
                self.card_grid.addWidget(card, 0 if self.width() >= 600 else index, index if self.width() >= 600 else 0)

    def update_status(self):
        config_text = self.client.manual_setup()
        if config_text != self._manual_text:
            config = json.loads(config_text)["mcpServers"]["max-ultra-mcp"]
            values = (config["command"], "\n".join(config["args"]), "\n".join(key + "=" + value for key, value in config["env"].items()))
            for field, value in zip(self.manual_fields, values):
                field.setPlainText(value)
            self._manual_text = config_text
        parser = self.client.integration_result
        self.runtime_status.setText("Runtime check: " + (parser.get("runtime", "detail", fallback="Runtime not checked.") if parser is not None else "Runtime not checked."))
        busy = self.client.integration is not None
        self.progress.setVisible(busy)
        self.elapsed.setVisible(busy)
        seconds = max(0, int(time.monotonic() - self.client.integration.started)) if busy else 0
        self.elapsed.setText("{} s".format(seconds))
        self.refresh.setEnabled(not busy)
        self.cancel.setEnabled(busy)
        for button, status_label, (identifier, label, switch, url) in zip(self.cards, self.card_statuses, CLIENTS):
            state = self.client.client_state(identifier)
            if state == "configured":
                title = label
            elif state == "cli_missing" and identifier != "antigravity":
                title = "Install " + label
            elif state == "desktop_missing" or (identifier == "antigravity" and state == "cli_missing"):
                title = "Download " + label
            elif state in ("not_configured", "restart_required"):
                title = "Connect to " + label
            else:
                title = label
            status_text = {"configured": "MCP ready", "not_configured": "Not connected", "restart_required": "Restart required", "cli_missing": "CLI not installed", "desktop_missing": "Desktop app not installed", "check_failed": "Check failed — refresh status", "runtime_missing": "Runtime unavailable", "unknown": "Refresh status", "checking": "Checking..."}.get(state, state.replace("_", " "))
            if busy:
                title = label
                active = not self.client.integration_client or self.client.integration_client == identifier
                status_text = ("Checking..." if self.client.integration_action == "Status" else "Setting up...") if active else "Waiting..."
            status_label.setText(status_text)
            status_label.setEnabled(not busy)
            status_label.setStyleSheet("color:" + ("#81796e" if busy else COLORS["success"] if state == "configured" else COLORS["error"] if state in ("check_failed", "install_failed", "runtime_check_failed") else COLORS["warning"]))
            button.setText(title)
            button.setToolTip(title)
            button.setEnabled(not busy and state in ("configured", "cli_missing", "desktop_missing", "not_configured", "restart_required"))
        blocks = ['<p>{}</p>'.format(html.escape(self.client.integration_message))]
        for stamp, kind, message in self.client.integration_steps:
            blocks.append('<div style="color:{}">{} &gt; {}</div>'.format(COLORS.get(kind, COLORS["info"]), stamp, html.escape(message)))
        parser = self.client.integration_result
        if parser is not None and not busy:
            for identifier, label, _, _ in CLIENTS:
                blocks.append("<p><b>{}</b><br>{}<br>{}</p>".format(label, html.escape(parser.get(identifier, "detail", fallback="")), html.escape(parser.get(identifier, "desktopinstructions", fallback=""))))
        content = "".join(blocks)
        if content != getattr(self, "_detail_html", None):
            scrollbar = self.detail.verticalScrollBar()
            previous = scrollbar.value()
            following = previous >= scrollbar.maximum() - 1
            self.detail.setHtml(content)
            scrollbar.setValue(scrollbar.maximum() if following else previous)
            self._detail_html = content

    def activate_client(self, identifier):
        record = next(row for row in CLIENTS if row[0] == identifier)
        _, label, switch, url = record
        state = self.client.client_state(identifier)
        if state == "cli_missing" and identifier != "antigravity":
            installer_url = "https://chatgpt.com/codex/install.ps1" if identifier == "openai" else "https://claude.ai/install.ps1"
            confirmation = (
                "Install the {} setup CLI for automatic connection?\n\n"
                "Existing apps are kept. You will chat and sign in in the desktop app; terminal chat is not required.\n\n"
                "PowerShell will download and run the official CLI installer:\n{}\n\n"
                "Internet access is required. The installer manages CLI files and may update user PATH. "
                "No separate Node.js install is needed.\n\n"
                "If the desktop app is missing, its official download page will open after CLI verification. "
                "Install the app yourself, then Refresh status and Connect separately. "
                "Cancel installation stops the helper but does not undo installed files."
            ).format(label, installer_url)
            reply = QtWidgets.QMessageBox.question(self, "Install " + label, confirmation)
            if reply == QtWidgets.QMessageBox.Yes:
                self.client.start_integration("InstallCli", identifier, ["-" + switch, "-ConfirmCliInstall"])
        elif state == "desktop_missing" or (identifier == "antigravity" and state == "cli_missing"):
            QtGui.QDesktopServices.openUrl(QtCore.QUrl(url))
            self.client.integration_message = "Install the desktop app, click Refresh status, then Connect on the same client card."
            self.update_status()
        elif state in ("not_configured", "restart_required", "configured"):
            self.client.start_integration("Install", identifier, ["-" + switch])
        else:
            self.client.refresh_agents()


class SkillHelpWindow(Window):
    def __init__(self, client, parent, submit=False):
        title = "Submit Your Skill" if submit else "How to create and import skills"
        super().__init__(client.root, title, parent)
        self.resize(940, 780)
        self.setMinimumSize(320, 300)
        guide = (client.root / "docs" / ("SUBMIT_SKILL.md" if submit else "CUSTOM_SKILLS.md")).read_text(encoding="utf-8-sig")
        if submit:
            match = re.search(r"```text\r?\n([\s\S]*?)\r?\n```", guide)
            if match is None:
                raise ValueError("The submission help is missing its mail template")
            self.copy_text = match.group(1)
            guide = guide.split("## Mail template", 1)[0]
        else:
            self.copy_text = (client.root / "docs/SKILL_CREATION_PROMPT.md").read_text(encoding="utf-8-sig")
        after = ""
        if not submit and "## Import and use" in guide:
            guide, after = guide.split("## Import and use", 1)
            after = "## Import and use" + after
        page = QtWidgets.QWidget()
        page.setStyleSheet("background:#1c1c1a;")
        page_layout = QtWidgets.QVBoxLayout(page)
        page_layout.setContentsMargins(14, 10, 14, 14)
        page_layout.setSpacing(14)
        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(page)
        self.outer.addWidget(scroll, 1)
        self.guide = InlineHelpBrowser()
        self.guide.setOpenLinks(False)
        self.guide.setOpenExternalLinks(False)
        self.guide.anchorClicked.connect(self.open_link)
        self.guide.setMarkdown(guide)
        page_layout.addWidget(self.guide)
        content = QtWidgets.QFrame()
        content.setObjectName("helpCodeBlock")
        content.setStyleSheet("QFrame#helpCodeBlock { background:#302f2b; border:1px solid #62594c; border-radius:4px; } QFrame#helpCodeBlock QLabel { background:transparent; }")
        layout = QtWidgets.QVBoxLayout(content)
        layout.setContentsMargins(10, 8, 10, 10)
        heading = QtWidgets.QHBoxLayout()
        heading.addWidget(QtWidgets.QLabel("Mail template" if submit else "Skill creation prompt"))
        heading.addStretch()
        self.copy_label = "Copy Template" if submit else "Copy Prompt"
        self.copy_button = action(client.root, "copy", self.copy_label, self.copy_content)
        self.copy_icon = QtGui.QIcon(self.copy_button.icon())
        self.copied_icon = QtGui.QIcon(str(client.root / "assets/icons/check.svg"))
        self.copy_reset = QtCore.QTimer(self)
        self.copy_reset.setSingleShot(True)
        self.copy_reset.setInterval(2000)
        self.copy_reset.timeout.connect(self.reset_copy_button)
        heading.addWidget(self.copy_button)
        layout.addLayout(heading)
        self.text = QtWidgets.QPlainTextEdit(self.copy_text)
        self.text.setReadOnly(True)
        self.text.setStyleSheet("font-family:Consolas; font-size:11pt;")
        self.text.setFixedHeight(180)
        layout.addWidget(self.text)
        page_layout.addWidget(content)
        if after:
            remainder = InlineHelpBrowser()
            remainder.setOpenLinks(False)
            remainder.setOpenExternalLinks(False)
            remainder.anchorClicked.connect(self.open_link)
            remainder.setMarkdown(after)
            page_layout.addWidget(remainder)
        page_layout.addStretch()

    def copy_content(self):
        QtWidgets.QApplication.clipboard().setText(self.copy_text)
        self.copy_button.setText("Copied")
        self.copy_button.setIcon(self.copied_icon)
        self.copy_reset.start()

    def reset_copy_button(self):
        self.copy_button.setText(self.copy_label)
        self.copy_button.setIcon(self.copy_icon)

    def open_link(self, url):
        if url.scheme() in ("https", "http", "mailto"):
            QtGui.QDesktopServices.openUrl(url)


class SkillsWindow(Window):
    def __init__(self, client, parent):
        super().__init__(client.root, "Skills", parent)
        self.client = client
        self.resize(1040, 860)
        self.setMinimumSize(320, 300)
        self.history = []
        self.current_document = None
        self.busy = False
        self.buttons = []
        self.source = QtWidgets.QTabBar()
        self.source.addTab("Built-in")
        self.source.addTab("Custom")
        self.source.setExpanding(False)
        category = client.settings.get("skills", "category", "builtin")
        self.source.setCurrentIndex(1 if category == "custom" else 0)
        self.source.currentChanged.connect(self.filter_rows)
        heading = QtWidgets.QHBoxLayout()
        heading.addWidget(self.source)
        heading.addStretch()
        self.refresh_button = action(client.root, "refresh-cw", "Refresh", lambda: client.skills_operation("list"))
        self.buttons.append(self.refresh_button)
        heading.addWidget(self.refresh_button)
        self.outer.addLayout(heading)
        self.splitter = QtWidgets.QSplitter(Qt.Vertical)
        self.list = QtWidgets.QTreeWidget()
        self.list.setColumnCount(2)
        self.list.setHeaderLabels(["Name", "Description"])
        self.list.setRootIsDecorated(False)
        self.list.setUniformRowHeights(True)
        self.list.setMinimumHeight(72)
        self.list.setColumnWidth(0, 230)
        self.list.header().setStretchLastSection(False)
        self.list.header().setSectionResizeMode(1, QtWidgets.QHeaderView.Stretch)
        self.list.currentItemChanged.connect(self.read_selected)
        self.preview = PassiveBrowser()
        self.preview.setOpenLinks(False)
        self.preview.setOpenExternalLinks(False)
        self.preview.anchorClicked.connect(self.navigate)
        self.splitter.addWidget(self.list)
        document = QtWidgets.QWidget()
        document_layout = QtWidgets.QVBoxLayout(document)
        document_layout.setContentsMargins(0, 0, 0, 0)
        navigation = QtWidgets.QHBoxLayout()
        self.back_button = action(client.root, "arrow-left", "Back", self.back)
        self.buttons.append(self.back_button)
        navigation.addWidget(self.back_button)
        navigation.addStretch()
        document_layout.addLayout(navigation)
        document_layout.addWidget(self.preview, 1)
        self.splitter.addWidget(document)
        self.splitter.setStretchFactor(0, 0)
        self.splitter.setStretchFactor(1, 1)
        self.splitter.setSizes([140, 540])
        self.outer.addWidget(self.splitter, 1)
        controls = QtWidgets.QHBoxLayout()
        for symbol, title, callback in [("folder-open", "Import Folder", self.import_folder), ("file-archive", "Import ZIPs", self.import_zips), ("trash-2", "Delete", self.delete_selected)]:
            button = action(client.root, symbol, title, callback)
            self.buttons.append(button)
            controls.addWidget(button)
        self.delete_button = button
        controls.addStretch()
        self.outer.addLayout(controls)
        self.status = QtWidgets.QLabel()
        self.status.setWordWrap(True)
        self.outer.addWidget(self.status)
        self.controls = QtWidgets.QHBoxLayout()
        for symbol, title, callback in [("book-open", "How to create and import skills", lambda: self.help("CUSTOM_SKILLS.html")), ("send", "Submit Your Skill", lambda: self.help("SUBMIT_SKILL.html")), ("globe", "Community Skills", lambda: QtGui.QDesktopServices.openUrl(QtCore.QUrl("https://maxpkg-dev.github.io/max-ultra-mcp-community-skills/"))), ("heart", "Donate", client.donate)]:
            if title == "Donate":
                self.controls.addStretch()
            button = donate_action(client.root, callback) if title == "Donate" else action(client.root, symbol, title, callback)
            self.buttons.append(button)
            self.controls.addWidget(button)
        self.outer.addLayout(self.controls)
        self.update_actions()

    def filter_rows(self):
        self.client.save_setting("skills", {"category": ("builtin", "custom")[self.source.currentIndex()]})
        for index in range(self.list.topLevelItemCount()):
            entry = self.list.topLevelItem(index)
            entry.setHidden(entry.data(0, Qt.UserRole)[1] != ("Built-in", "Custom")[self.source.currentIndex()])
        current = self.list.currentItem()
        if current and current.isHidden():
            self.list.setCurrentItem(None)
            self.preview.clear()
            self.current_document = None
            self.history = []
        self.update_actions()

    def update_actions(self):
        current = self.list.currentItem()
        custom = current is not None and not current.isHidden() and current.data(0, Qt.UserRole)[1] == "Custom"
        self.delete_button.setVisible(custom)
        self.delete_button.setEnabled(custom and not self.busy)
        self.back_button.setVisible(bool(self.history))
        self.back_button.setEnabled(bool(self.history) and not self.busy)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, "buttons"):
            for button in self.buttons:
                button.setToolButtonStyle(Qt.ToolButtonIconOnly if self.width() < 900 else Qt.ToolButtonTextBesideIcon)

    def set_busy(self, busy):
        self.busy = busy
        self.list.setEnabled(not busy)
        self.source.setEnabled(not busy)
        for button in self.buttons:
            button.setEnabled(not busy)
        self.update_actions()

    def read_selected(self, current, previous):
        if current:
            identifier = current.data(0, Qt.UserRole)[0]
            self.history = []
            self.current_document = None
            self.open_document(identifier, "SKILL.md")
        self.update_actions()

    def open_document(self, identifier, relative):
        if self.current_document:
            self.history.append((self.current_document, self.preview.verticalScrollBar().value()))
        self._restore_scroll = 0
        self.current_document = (identifier, relative)
        self.update_actions()
        self.client.skills_operation("read", ["-SkillId", identifier, "-RelativePath", relative])

    def navigate(self, url):
        if not url.scheme() and not url.path() and url.hasFragment():
            self.preview.scrollToAnchor(url.fragment())
        elif url.scheme() == "skill-nav" and url.path() == "back":
            self.back()
        elif url.scheme() == "skill-ref" and self.current_document:
            from urllib.parse import unquote
            from pathlib import PurePosixPath
            relative = unquote(url.toString().split(":", 1)[1])
            if not PurePosixPath(relative).is_absolute() and ".." not in PurePosixPath(relative).parts:
                self.open_document(self.current_document[0], relative)
        elif url.scheme() == "skill-help":
            self.help("SUBMIT_SKILL.html" if url.path() == "submit" else "CUSTOM_SKILLS.html")
        elif url.scheme() in ("https", "http"):
            QtGui.QDesktopServices.openUrl(url)
        elif self.current_document and not url.scheme():
            from posixpath import normpath, dirname, join
            relative = normpath(join(dirname(self.current_document[1]), url.path()))
            if relative != ".." and not relative.startswith(("../", "/")):
                self.open_document(self.current_document[0], relative)

    def back(self):
        if self.history:
            self.current_document, self._restore_scroll = self.history.pop()
            self.update_actions()
            self.client.skills_operation("read", ["-SkillId", self.current_document[0], "-RelativePath", self.current_document[1]])

    def import_folder(self):
        folder = QtWidgets.QFileDialog.getExistingDirectory(self, "Import instruction-only skill")
        if folder:
            self.client.skills_operation("add-folder", ["-Source", folder])

    def import_zips(self):
        files, _ = QtWidgets.QFileDialog.getOpenFileNames(self, "Import instruction-only skills", "", "ZIP (*.zip)")
        if files:
            import uuid
            selection = self.client.state_directory / ("zip-selection-" + uuid.uuid4().hex + ".txt")
            selection.write_text("\n".join(files), encoding="utf-8")
            if self.client.skills_operation("add-zips", ["-Source", str(selection)]):
                self.client.skills_helper.temporary_files.append(selection)
            else:
                selection.unlink()

    def delete_selected(self):
        current = self.list.currentItem()
        if current and current.data(0, Qt.UserRole)[1] == "Custom":
            if QtWidgets.QMessageBox.question(self, "Delete skill", "Delete this imported skill and its owned discovery adapters?") == QtWidgets.QMessageBox.Yes:
                self.client.skills_operation("delete", ["-SkillId", current.data(0, Qt.UserRole)[0]])

    def help(self, document):
        submit = document == "SUBMIT_SKILL.html"
        self.client.show_dialog("skill_help_submit" if submit else "skill_help_create",
                                lambda client, parent: SkillHelpWindow(client, parent, submit=submit))

    def apply_result(self, helper):
        parser = helper.snapshot
        if parser is None:
            self.status.setText("Skills helper did not return a result")
            return
        self.status.setText(decode(parser.get("result", "message", fallback="")))
        if parser.get("result", "haslist", fallback="false") == "true":
            self.list.blockSignals(True)
            self.list.clear()
            for index in range(parser.getint("result", "count", fallback=0)):
                section = "skill" + str(index)
                values = [decode(parser.get(section, field, fallback="")) for field in ("name", "description")]
                entry = QtWidgets.QTreeWidgetItem(values)
                for column, value in enumerate(values):
                    entry.setToolTip(column, value)
                entry.setData(0, Qt.UserRole, (decode(parser.get(section, "id")), decode(parser.get(section, "source"))))
                self.list.addTopLevelItem(entry)
            self.list.blockSignals(False)
            self.filter_rows()
        preview = Path(str(helper.result) + ".html")
        if preview.exists():
            self.set_preview_html(preview.read_text(encoding="utf-8-sig"))

    def set_preview_html(self, content):
        # The helper also serves the legacy browser, whose fixed HTML header has
        # two Back variants toggled through CSS. QTextBrowser cannot hide these.
        # Navigation in this window belongs to the native Qt toolbar instead.
        content = re.sub(r'<div class="skill-header" id="skill-header"[^>]*>.*?</div>',
                         "", content, count=1, flags=re.DOTALL)
        # QTextBrowser ignores borders on HTML divs; a one-cell table preserves
        # the original square metadata frame in both Qt 5 and Qt 6.
        content = re.sub(
            r'<div class="metadata">(<div class="eyebrow">.*?</div><h1>.*?</h1><p>.*?</p>)</div>',
            r'<table border="1" cellspacing="0" cellpadding="12" width="100%" style="border:1px solid #777066;"><tr><td>\1</td></tr></table><br>',
            content, count=1, flags=re.DOTALL)
        self.preview.setHtml(content)
        self.preview.verticalScrollBar().setValue(getattr(self, "_restore_scroll", 0))
