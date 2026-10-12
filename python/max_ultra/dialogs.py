# Qt settings, AI onboarding and passive skills management windows.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import html
import json
import os
import re
import time

from . import themes
from .qt import QtWidgets, QtCore, QtGui, Qt
from .widgets import Window, LoadingOverlay, JoinedTabBar, TabHeading, ActionButton, action, icon, copy_action, donate_action, COLORS, DESTRUCTIVE_STYLE, PillProgressBar
from .wire import decode

CLIENTS = [("openai", "Codex", "InstallOpenAI", "https://chatgpt.com/download/"), ("claudeCode", "Claude Code", "InstallClaudeCode", "https://claude.ai/download"), ("antigravity", "Antigravity", "InstallAntigravity", "https://antigravity.google/download")]
TEST_PROMPT = "Use Max Ultra MCP to list connected 3ds Max instances. If exactly one is connected, select it and report its version, connection health, scene summary and capabilities. Do not create, modify, save or render anything."


class PassiveBrowser(QtWidgets.QTextBrowser):
    def clear(self):
        self._theme_html = None
        super().clear()

    def setHtml(self, content):
        self._theme_html = content
        super().setHtml(themes.html(content))

    def loadResource(self, resource_type, url):
        # Imported documents cannot fetch network or local resources implicitly.
        return QtCore.QByteArray()


class ResponsiveSkillBrowser(PassiveBrowser):
    def __init__(self):
        super().__init__()
        self._text_points = 11
        self._document_padding = 16
        self.setLineWrapMode(QtWidgets.QTextEdit.WidgetWidth)
        themes.set_style(self, "QTextBrowser { padding:0; background:@field_background; color:@field_text; }")

    def document_menu(self, position):
        menu = SkillsMenu(self)
        root = Path(__file__).resolve().parents[2]
        copy = menu.addAction(icon(root, 'copy'), 'Copy')
        copy.setShortcut(QtGui.QKeySequence.Copy)
        copy.setEnabled(self.textCursor().hasSelection())
        copy.triggered.connect(self.copy)
        link = self.anchorAt(position)
        copy_link = menu.addAction(icon(root, 'link-2'), 'Copy Link Location')
        copy_link.setEnabled(bool(link))
        copy_link.triggered.connect(lambda: QtWidgets.QApplication.clipboard().setText(link))
        menu.addSeparator()
        select_all = menu.addAction(icon(root, 'square-dashed'), 'Select All')
        select_all.setShortcut(QtGui.QKeySequence.SelectAll)
        select_all.setEnabled(not self.document().isEmpty())
        select_all.triggered.connect(self.selectAll)
        for item in (copy, copy_link, select_all):
            item.setIconVisibleInMenu(True)
            item.setShortcutVisibleInContextMenu(True)
        return menu

    def contextMenuEvent(self, event):
        position = event.pos()
        if event.reason() == QtGui.QContextMenuEvent.Keyboard:
            position = self.cursorRect().center()
        menu = self.document_menu(position)
        try:
            menu.exec_(self.viewport().mapToGlobal(position))
        finally:
            menu.deleteLater()

    def setHtml(self, content):
        self._theme_html = content
        points = self._text_points
        rules = "html,body,p,li,td,th,pre,code { font-size:%spt; color:@field_text; }" % points
        for level, ratio in enumerate((1.8, 1.5, 1.3, 1.15, 1.05, 1), 1):
            rules += "h%d { font-size:%.2fpt; }" % (level, points * ratio)
        rules += ".eyebrow { font-size:%.2fpt; }" % (points * 0.8)
        style = "<style>" + rules + "</style>"
        # QTextDocument does not consistently override earlier fixed pixel
        # heading sizes with a later stylesheet. Keep the source untouched and
        # remove only those size declarations from the rendered CSS.
        content = re.sub(r'(<style\b[^>]*>)(.*?)(</style\s*>)',
                         lambda match: match.group(1) + re.sub(r'\bbody\s*\{[^}]*\}', 'body{margin:0;padding:0}', re.sub(r'font-size\s*:[^;}]+;?', '', match.group(2), flags=re.I), flags=re.I) + match.group(3),
                         content, flags=re.I | re.S)
        # Inline font sizes otherwise override the responsive document rules.
        # Restrict normalization to style attributes, preserving prose/code.
        content = re.sub(r'\bstyle\s*=\s*([\"\'])(.*?)\1',
                         lambda match: 'style=' + match.group(1) + re.sub(
                             r'font-size\s*:[^;}]+;?', '', match.group(2), flags=re.I
                         ) + match.group(1), content, flags=re.I | re.S)
        # Web CSS centers the document with auto margins; Qt imports those as
        # fixed margins on every paragraph, squeezing the narrow viewport.
        content = re.sub(r'\.document\s*\{[^}]*\}', '.document{margin:0;padding:0}', content, flags=re.I)
        if re.search(r'</head\s*>', content, re.I):
            rendered = re.sub(r'</head\s*>', lambda match: style + match.group(), content, count=1, flags=re.I)
        else:
            rendered = style + content
        QtWidgets.QTextBrowser.setHtml(self, themes.html(rendered))
        # Qt retains the HTML heading size adjustment even alongside an
        # explicit point size; it otherwise wins during actual font rendering.
        formats = []
        block = self.document().begin()
        while block.isValid():
            iterator = block.begin()
            while not iterator.atEnd():
                fragment = iterator.fragment()
                formatting = fragment.charFormat()
                if formatting.hasProperty(QtGui.QTextFormat.FontPointSize) and formatting.hasProperty(QtGui.QTextFormat.FontSizeAdjustment):
                    formatting.clearProperty(QtGui.QTextFormat.FontSizeAdjustment)
                    formats.append((fragment.position(), fragment.length(), formatting))
                iterator += 1
            block = block.next()
        for position, length, formatting in formats:
            cursor = QtGui.QTextCursor(self.document())
            cursor.setPosition(position)
            cursor.setPosition(position + length, QtGui.QTextCursor.KeepAnchor)
            cursor.setCharFormat(formatting)
        self.document().setDocumentMargin(self._document_padding)
        if 'data-skill-metadata="true"' in content:
            # Keep the existing introductory block's outline independent of
            # generic HTML table/cell rules and QTextDocument CSS precedence.
            table = next((frame for frame in self.document().rootFrame().childFrames() if isinstance(frame, QtGui.QTextTable)), None)
            if table is not None:
                formatting = table.format()
                formatting.setBorder(1)
                formatting.setBorderStyle(QtGui.QTextFrameFormat.BorderStyle_Solid)
                formatting.setBorderBrush(QtGui.QColor(themes.style('@preview_border')))
                formatting.setCellPadding(4)
                formatting.setCellSpacing(0)
                table.setFormat(formatting)
                cell = table.cellAt(0, 0)
                cell_format = cell.format().toTableCellFormat()
                cell_format.setPadding(4)
                cell_format.setBorder(1)
                cell_format.setBorderStyle(QtGui.QTextFrameFormat.BorderStyle_Solid)
                cell_format.setBorderBrush(QtGui.QColor(themes.style('@preview_border')))
                cell.setFormat(cell_format)
        # The helper's browser CSS contains em-based block spacing intended for
        # a web engine. Bound it here so small QTextBrowser views stay readable.
        block = self.document().begin()
        while block.isValid():
            formatting = block.blockFormat()
            formatting.setTopMargin(min(formatting.topMargin(), points * 0.6))
            formatting.setBottomMargin(min(formatting.bottomMargin(), points * 0.6))
            cursor = QtGui.QTextCursor(block)
            cursor.setBlockFormat(formatting)
            block = block.next()

    def resizeEvent(self, event):
        anchor = self.cursorForPosition(QtCore.QPoint(0, 0))
        anchor_y = self.cursorRect(anchor).top()
        selection = self.textCursor()
        super().resizeEvent(event)
        width = self.window().width()
        points = 8 if width < 420 else 9 if width < 600 else 10 if width < 900 else 32 if width >= 3600 else 28 if width >= 3000 else 24 if width >= 2400 else 20 if width >= 1800 else 16 if width >= 1280 else 14 if width > 1250 else 11
        padding = max(16, min(40, round(16 + (self.viewport().width() - 360) / 100)))
        if points == self._text_points and padding == self._document_padding:
            return
        self._text_points = points
        self._document_padding = padding
        content = getattr(self, '_theme_html', None)
        if content is not None:
            anchor_position = anchor.position()
            selected_position, selected_anchor = selection.position(), selection.anchor()
            self.setHtml(content)
            limit = self.document().characterCount() - 1
            selection = self.textCursor()
            selection.setPosition(min(selected_anchor, limit))
            selection.setPosition(min(selected_position, limit), QtGui.QTextCursor.KeepAnchor)
            self.setTextCursor(selection)
            anchor = self.textCursor()
            anchor.setPosition(min(anchor_position, limit))
            scrollbar = self.verticalScrollBar()
            scrollbar.setValue(scrollbar.value() + self.cursorRect(anchor).top() - anchor_y)


class InlineHelpBrowser(PassiveBrowser):
    def __init__(self):
        super().__init__()
        self.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        themes.set_style(self, "QTextBrowser { border:none; padding:0; background:transparent; }")
        self.document().documentLayout().documentSizeChanged.connect(self.fit_height)

    def setMarkdown(self, content):
        super().setMarkdown(content)
        # Qt's Markdown import embeds blue foregrounds in anchor spans.
        # Store palette tokens so already-open help follows theme changes.
        rendered = re.sub(r'<a\b[^>]*>.*?</a>',
                          lambda match: re.sub(r'color\s*:\s*[^;"\']+', 'color:@support_link', match.group(), flags=re.I),
                          self.toHtml(), flags=re.I | re.S)
        self.setHtml(rendered)

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
        for title in ["Appearance", "Autostart", "Server console", "Updates", "AI client integration", "About"]:
            group = QtWidgets.QGroupBox(title)
            themes.set_style(group, "QGroupBox { border:1px solid @group_border; border-radius:3px; margin-top:12px; padding:12px 10px 8px; } QGroupBox::title { subcontrol-origin:margin; subcontrol-position:top left; left:10px; padding:0 5px; color:@heading_text; }")
            groups[title] = QtWidgets.QVBoxLayout(group)
            layout.addWidget(group)
        self.theme_picker = QtWidgets.QComboBox()
        self.theme_picker.setAccessibleName("Color theme")
        for identifier, (label, _) in themes.THEMES.items():
            self.theme_picker.addItem(label, identifier)
        self.theme_picker.setCurrentIndex(self.theme_picker.findData(themes.current))
        self.theme_picker.currentIndexChanged.connect(self.change_theme)
        groups["Appearance"].addWidget(self.theme_picker)
        opacity_row = QtWidgets.QHBoxLayout()
        opacity_row.addWidget(QtWidgets.QLabel("Main window opacity"))
        self.opacity_value = QtWidgets.QLabel()
        opacity_row.addStretch()
        opacity_row.addWidget(self.opacity_value)
        groups["Appearance"].addLayout(opacity_row)
        self.opacity_slider = QtWidgets.QSlider(Qt.Horizontal)
        self.opacity_slider.setRange(20, 100)
        self.opacity_slider.setValue(getattr(client, "panel_opacity", 100))
        self.opacity_slider.setAccessibleName("Main window opacity, 20 to 100 percent")
        self.opacity_slider.setCursor(Qt.PointingHandCursor)
        self.opacity_value.setText("{}%".format(self.opacity_slider.value()))
        self._opacity_dragging = False
        self._opacity_dirty = False
        self.opacity_slider.installEventFilter(self)
        self.opacity_slider.valueChanged.connect(self.change_opacity)
        groups["Appearance"].addWidget(self.opacity_slider)
        check_icon = (client.root / "assets/icons/check.svg").as_posix()
        for group, label, section, key, default in [("Autostart", "Autostart with 3ds Max", "settings", "autostart", False), ("Server console", "Show server console when starting", "settings", "showServerConsole", False), ("Updates", "Check and install updates automatically", "updates", "automatic", True)]:
            checkbox = QtWidgets.QCheckBox(label)
            checkbox.setMinimumHeight(30)
            themes.set_style(checkbox, 'QCheckBox { color:@text; spacing:9px; } '
                'QCheckBox::indicator { width:20px; height:20px; border:1px solid @checkbox_border; border-radius:3px; background:@recessed_background; } '
                'QCheckBox::indicator:checked { background:@donate_background; border-color:@support_link; image:url("' + check_icon + '"); } '
                'QCheckBox::indicator:hover { border-color:@checkbox_hover_border; } '
                'QCheckBox:focus { color:@selected_text; }')
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
        about = groups["About"]
        about.setSpacing(0)
        details = QtWidgets.QVBoxLayout()
        details.setSpacing(4)
        about.addLayout(details)
        for text in ["3DGROUND - Max Ultra MCP", client.version, "Lukianenko Vasyl"]:
            label = QtWidgets.QLabel(text)
            label.setWordWrap(True)
            label.setAlignment(Qt.AlignCenter)
            details.addWidget(label)
        about.addSpacing(8)
        links = QtWidgets.QVBoxLayout()
        links.setSpacing(4)
        about.addLayout(links)
        for address in ["3dground.net", "maxpkg.dev"]:
            link = QtWidgets.QLabel()
            themes.set_label(link, '<a href="https://' + address + '" style="color:@support_link">' + address + '</a>')
            link.setAlignment(Qt.AlignCenter)
            link.setOpenExternalLinks(True)
            links.addWidget(link)
        about.addSpacing(16)
        about.addWidget(donate_action(client.root, client.donate), 0, Qt.AlignHCenter)
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

    def showEvent(self, event):
        super().showEvent(event)
        self.set_settings_dimming(True)

    def hideEvent(self, event):
        self._opacity_dragging = False
        if self._opacity_dirty:
            self.save_opacity()
        self.set_settings_dimming(False)
        super().hideEvent(event)

    def change_opacity(self, value):
        self.opacity_value.setText("{}%".format(value))
        self.client.set_panel_opacity(value)
        self._opacity_dirty = True
        if self._opacity_dragging:
            self.client.panel.setWindowOpacity(self.client.panel_opacity / 100.0)
        else:
            self.save_opacity()

    def eventFilter(self, watched, event):
        if watched is getattr(self, 'opacity_slider', None):
            if event.type() == QtCore.QEvent.MouseButtonPress and event.button() == Qt.LeftButton:
                self._opacity_dragging = True
                self.client.panel.setWindowOpacity(self.client.panel_opacity / 100.0)
            elif event.type() == QtCore.QEvent.MouseButtonRelease and event.button() == Qt.LeftButton:
                self._opacity_dragging = False
                self.save_opacity()
        return super().eventFilter(watched, event)

    def save_opacity(self):
        self.client.set_panel_opacity(self.opacity_slider.value(), persist=True)
        self._opacity_dirty = False

    def change_theme(self, index):
        if not self.client.set_theme(self.theme_picker.itemData(index)):
            self.theme_picker.blockSignals(True)
            self.theme_picker.setCurrentIndex(self.theme_picker.findData(themes.current))
            self.theme_picker.blockSignals(False)

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
        self.tabs.setTabBar(JoinedTabBar())
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
        self.detail.setObjectName("setupJournal")
        self.detail.setReadOnly(True)
        themes.set_style(self.detail, "QTextBrowser { font-family:Consolas; font-size:11pt; }")
        self.detail.setMinimumHeight(90)
        self.detail.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Expanding)
        setup_layout.addWidget(self.detail, 1)
        self.progress = PillProgressBar()
        self.progress.setTextVisible(False)
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
            copy_button = copy_action(client.root, "Copy", content)
            layout.addWidget(copy_button)
            self.tabs.addTab(page, title)
        manual = QtWidgets.QWidget()
        manual_layout = QtWidgets.QVBoxLayout(manual)
        manual_layout.setContentsMargins(12, 12, 12, 12)
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
            themes.set_style(field, "font-family:Consolas; font-size:11pt;")
            field.setMaximumHeight(70)
            manual_layout.addWidget(field)
            self.manual_fields.append(field)
        self.runtime_status = QtWidgets.QLabel()
        self.runtime_status.setWordWrap(True)
        manual_layout.addWidget(self.runtime_status)
        manual_layout.addWidget(action(client.root, "refresh-cw", "Refresh status", client.refresh_agents))
        manual_layout.addStretch()
        manual_layout.addWidget(copy_action(client.root, "Copy JSON configuration", client.manual_setup))
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
            themes.set_style(status_label, "color:" + ("@disabled_text" if busy else COLORS["success"] if state == "configured" else COLORS["error"] if state in ("check_failed", "install_failed", "runtime_check_failed") else COLORS["warning"]))
            button.setText(title)
            button.setToolTip(title)
            button.setEnabled(not busy and state in ("configured", "cli_missing", "desktop_missing", "not_configured", "restart_required"))
        blocks = ['<p>{}</p>'.format(html.escape(self.client.integration_message))]
        for stamp, kind, message in self.client.integration_steps:
            blocks.append('<div style="color:{}">{} &gt; {}</div>'.format(COLORS.get(kind, COLORS["info"]), stamp, html.escape(message)))
        parser = self.client.integration_result
        if parser is not None and not busy:
            for identifier, label, _, _ in CLIENTS:
                blocks.append('<p style="margin-top:18px; margin-bottom:6px; font-size:14pt; font-weight:700">{}</p><p style="margin-top:0; margin-bottom:0">{}<br>{}</p>'.format(label, html.escape(parser.get(identifier, "detail", fallback="")), html.escape(parser.get(identifier, "desktopinstructions", fallback=""))))
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
        themes.set_style(page, "background:@field_background;")
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
        themes.set_style(content, "QFrame#helpCodeBlock { background:@journal_background; border:1px solid @group_border; border-radius:4px; } QFrame#helpCodeBlock QLabel { background:transparent; }")
        layout = QtWidgets.QVBoxLayout(content)
        layout.setContentsMargins(10, 8, 10, 10)
        heading = QtWidgets.QHBoxLayout()
        heading.addWidget(QtWidgets.QLabel("Mail template" if submit else "Skill creation prompt"))
        heading.addStretch()
        self.copy_label = "Copy Template" if submit else "Copy Prompt"
        self.copy_button = copy_action(client.root, self.copy_label, lambda: self.copy_text)
        heading.addWidget(self.copy_button)
        layout.addLayout(heading)
        self.text = QtWidgets.QPlainTextEdit(self.copy_text)
        self.text.setReadOnly(True)
        themes.set_style(self.text, "font-family:Consolas; font-size:11pt;")
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

    def open_link(self, url):
        if url.scheme() in ("https", "http", "mailto"):
            QtGui.QDesktopServices.openUrl(url)


class SkillsMenu(QtWidgets.QMenu):
    """Native menu interaction with one shared icon/text layout for every row."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WA_TranslucentBackground)
        themes.set_style(self, "QMenu { background:@window_background; border:1px solid @border; border-radius:8px; padding:6px; } QMenu::item { padding:8px 20px 8px 42px; min-width:130px; border-radius:5px; } QMenu::item:selected { background:@selection_background; } QMenu::separator { height:1px; background:@border; margin:6px 8px; }")

    def resizeEvent(self, event):
        super().resizeEvent(event)
        outline = QtGui.QPainterPath()
        outline.addRoundedRect(QtCore.QRectF(self.rect()), 8, 8)
        self.setMask(QtGui.QRegion(outline.toFillPolygon().toPolygon()))

    def paintEvent(self, event):
        super().paintEvent(event)
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        for item in self.actions():
            if item.isSeparator():
                continue
            rectangle = self.actionGeometry(item)
            selected = item == self.activeAction() and item.isEnabled()
            painter.fillRect(rectangle, QtGui.QColor(themes.style('@window_background')))
            if selected:
                painter.setPen(Qt.NoPen)
                painter.setBrush(QtGui.QColor(themes.style('@selection_background')))
                painter.drawRoundedRect(QtCore.QRectF(rectangle), 5, 5)
            role = '@log_error' if item.property('destructive') else '@selected_text' if selected else '@text'
            color = QtGui.QColor(themes.style(role if item.isEnabled() else '@disabled_text'))
            ratio = self.devicePixelRatioF()
            pixmap = item.icon().pixmap(round(20 * ratio), round(20 * ratio))
            tint = QtGui.QPainter(pixmap)
            tint.setCompositionMode(QtGui.QPainter.CompositionMode_SourceIn)
            tint.fillRect(pixmap.rect(), color)
            tint.end()
            pixmap.setDevicePixelRatio(ratio)
            painter.drawPixmap(rectangle.left() + 12, rectangle.center().y() - 10, pixmap)
            painter.setPen(color)
            shortcut = item.shortcut().toString(QtGui.QKeySequence.NativeText)
            reserved = self.fontMetrics().horizontalAdvance(shortcut) + 28 if shortcut else 0
            painter.drawText(rectangle.adjusted(42, 0, -20 - reserved, 0), Qt.AlignLeft | Qt.AlignVCenter, item.text())
            if shortcut:
                painter.drawText(rectangle.adjusted(42, 0, -20, 0), Qt.AlignRight | Qt.AlignVCenter, shortcut)


class SkillTableItem(QtWidgets.QTreeWidgetItem):
    def __lt__(self, other):
        column = self.treeWidget().sortColumn()
        if column == 3:
            return (self.data(3, Qt.UserRole) or '') < (other.data(3, Qt.UserRole) or '')
        return self.text(column).casefold() < other.text(column).casefold()


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
        self.source = JoinedTabBar()
        self.source.addTab("Built-in")
        self.source.addTab("Custom")
        self.source.setExpanding(False)
        category = client.settings.get("skills", "category", "builtin")
        self.source.setCurrentIndex(1 if category == "custom" else 0)
        self.source.currentChanged.connect(self.filter_rows)
        tab_heading = TabHeading(self.source)
        heading = QtWidgets.QHBoxLayout(tab_heading)
        heading.setContentsMargins(0, 0, 0, 0)
        heading.addWidget(self.source)
        heading.addStretch()
        self.refresh_button = action(client.root, "refresh-cw", "Refresh", lambda: client.skills_operation("list"))
        self.buttons.append(self.refresh_button)
        heading.addWidget(self.refresh_button)
        self.outer.addWidget(tab_heading)
        self.splitter = QtWidgets.QSplitter(Qt.Vertical)
        self.list = QtWidgets.QTreeWidget()
        self.list.setColumnCount(4)
        self.list.setHeaderLabels(["Name", "Description", "Author", "Date"])
        self.list.setSortingEnabled(True)
        self.list.header().setSectionsClickable(True)
        self.list.header().setSortIndicatorShown(True)
        self.list.sortByColumn(0, Qt.AscendingOrder)
        self.list.setColumnWidth(2, 150)
        self.list.setColumnWidth(3, 135)
        self.list.setRootIsDecorated(False)
        self.list.setUniformRowHeights(True)
        self.list.setMinimumHeight(72)
        self.list.setColumnWidth(0, 230)
        self.list.header().setStretchLastSection(False)
        self.list.header().setSectionResizeMode(1, QtWidgets.QHeaderView.Stretch)
        self.list.currentItemChanged.connect(self.read_selected)
        self.list.viewport().installEventFilter(self)
        self.list.setContextMenuPolicy(Qt.CustomContextMenu)
        self.list.customContextMenuRequested.connect(self.show_skill_menu)
        self.preview = ResponsiveSkillBrowser()
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
        self.import_controls = controls
        for symbol, title, callback in [("download", "Discover Community Skills", self.show_community), ("folder-open", "Import Folder", self.import_folder), ("file-archive", "Import ZIPs", self.import_zips), ("trash-2", "Delete", self.delete_selected)]:
            if title == "Delete":
                controls.addStretch()
            button = action(client.root, symbol, title, callback)
            if title == "Delete":
                themes.set_style(button, DESTRUCTIVE_STYLE)
            if title == "Discover Community Skills":
                themes.set_style(button, "QToolButton { background:@ready_background; border-color:@community_border; color:@status_button_text; } QToolButton:hover { background:@community_hover; border-color:@community_hover_border; } QToolButton:disabled { background:@community_disabled_background; color:@community_disabled_text; border-color:@border; }")
            self.buttons.append(button)
            controls.addWidget(button)
            if title == "Discover Community Skills":
                controls.addSpacing(14)
        self.delete_button = button
        self.outer.addLayout(controls)
        self.status = QtWidgets.QLabel()
        self.status.setWordWrap(True)
        self.outer.addWidget(self.status)
        self.controls = QtWidgets.QHBoxLayout()
        for symbol, title, callback in [("circle-question-mark", "How to create and import skills", lambda: self.help("CUSTOM_SKILLS.html")), ("circle-question-mark", "Submit Your Skill", lambda: self.help("SUBMIT_SKILL.html")), ("heart", "Donate", client.donate)]:
            if title == "Donate":
                self.controls.addStretch()
            button = donate_action(client.root, callback) if title == "Donate" else action(client.root, symbol, title, callback)
            if title != "Donate":
                button.elidable_caption = True
                button.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Fixed)
            self.buttons.append(button)
            self.controls.addWidget(button)
        self.donate_button = button
        self.donate_button.installEventFilter(self)
        self.outer.addLayout(self.controls)
        self.loading_overlay = LoadingOverlay(self)
        self.update_actions()

    def show_community(self):
        from .community_dialog import CommunityWindow
        self.client.show_dialog("community", CommunityWindow).refresh()

    def eventFilter(self, watched, event):
        if watched is self.list.viewport() and event.type() == QtCore.QEvent.MouseButtonPress and event.button() == Qt.RightButton:
            # Leave selection and preview untouched; the context-menu event
            # resolves its target directly from the pointer position.
            return True
        if watched is getattr(self, "donate_button", None) and event.type() == QtCore.QEvent.Resize:
            self.delete_button.setFixedWidth(watched.width())
        return super().eventFilter(watched, event)

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
        if hasattr(self, 'donate_button'):
            self.fit_button_rows()

    def fit_button_rows(self):
        if getattr(self, '_fitting_buttons', False):
            return
        self._fitting_buttons = True
        try:
            available = self.width() - self.outer.contentsMargins().left() - self.outer.contentsMargins().right()
            for row, priorities in ((self.controls, ('Donate',)),
                                    (self.import_controls, ('Import Folder', 'Import ZIPs', 'Delete'))):
                visible = [row.itemAt(i).widget() for i in range(row.count()) if row.itemAt(i).widget() is not None and not row.itemAt(i).widget().isHidden()]
                for button in visible:
                    if row is self.controls and button is not self.donate_button:
                        button.setMaximumWidth(16777215)
                    button.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
                def required_width():
                    widths = sum(button.sizeHint().width() for button in visible)
                    if self.delete_button in visible:
                        widths += self.donate_button.sizeHint().width() - self.delete_button.sizeHint().width()
                    gaps = sum(row.itemAt(i).spacerItem().sizeHint().width() for i in range(row.count()) if row.itemAt(i).spacerItem() is not None)
                    return widths + gaps + max(0, len(visible) - 1) * max(0, row.spacing())
                for title in priorities:
                    if required_width() <= available:
                        break
                    button = next((item for item in visible if item.text() == title), None)
                    if button is not None:
                        button.setToolButtonStyle(Qt.ToolButtonIconOnly)
                        if row is self.import_controls and title == 'Import Folder':
                            for sibling in visible:
                                if sibling.text() == 'Import ZIPs':
                                    sibling.setToolButtonStyle(Qt.ToolButtonIconOnly)
                if row is self.controls:
                    help_buttons = [button for button in visible if button is not self.donate_button]
                    widths = [button.sizeHint().width() for button in help_buttons]
                    excess = max(0, required_width() - available)
                    minimums = [button.iconSize().width() + button.fontMetrics().horizontalAdvance('...') + 24 for button in help_buttons]
                    while excess > 0 and any(width > minimum for width, minimum in zip(widths, minimums)):
                        index = max(range(len(widths)), key=lambda i: widths[i] - minimums[i])
                        widths[index] -= 1
                        excess -= 1
                    for button, width in zip(help_buttons, widths):
                        button.setMinimumWidth(minimums[help_buttons.index(button)])
                        button.setMaximumWidth(width)
                elif self.delete_button in visible:
                    # Its width follows Donate, so choose the caption using that
                    # actual constraint before Qt paints the first resized frame.
                    self.delete_button.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
                    if self.delete_button.sizeHint().width() > self.donate_button.sizeHint().width():
                        self.delete_button.setToolButtonStyle(Qt.ToolButtonIconOnly)
        finally:
            self._fitting_buttons = False

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, "loading_overlay"):
            self.position_loading_overlay()
        if hasattr(self, "donate_button"):
            self.fit_button_rows()

    def position_loading_overlay(self):
        top = self.header.geometry().bottom() + 1
        self.loading_overlay.setGeometry(1, top, max(0, self.width() - 2), max(0, self.height() - top - 1))

    def set_busy(self, busy):
        self.busy = busy
        self.list.setEnabled(not busy)
        self.source.setEnabled(not busy)
        self.preview.setEnabled(not busy)
        for button in self.buttons:
            button.setEnabled(not busy)
        self.update_actions()
        self.position_loading_overlay()
        self.loading_overlay.setVisible(busy)
        if busy:
            self.loading_overlay.raise_()

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

    def skill_folder(self, entry):
        identifier, source = entry.data(0, Qt.UserRole)
        if source == "Built-in" and re.fullmatch(r"bundled/[a-z0-9][a-z0-9-]*", identifier):
            return self.client.root / "skills" / identifier.split("/", 1)[1]
        if source == "Custom" and re.fullmatch(r"user/[0-9a-fA-F-]{36}", identifier):
            default = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / ".local/share"))) / "3DGROUND/MaxUltraMCP/user-skills"
            return Path(os.environ.get("MAX_ULTRA_MCP_SKILLS_ROOT") or default) / "packages" / identifier.split("/", 1)[1]
        return None

    def open_skill_folder(self, entry):
        folder = self.skill_folder(entry)
        if folder is None or not folder.is_dir():
            self.status.setText("The skill folder is no longer available. Refresh the list.")
        elif not QtGui.QDesktopServices.openUrl(QtCore.QUrl.fromLocalFile(str(folder.resolve()))):
            self.status.setText("Could not open the skill folder.")

    def skill_menu(self, entry):
        # The helper may refresh the tree while QMenu runs its nested event loop.
        entry = entry.clone()
        menu = SkillsMenu(self)
        about = menu.addAction(icon(self.client.root, "circle-question-mark"), "About")
        about.setIconVisibleInMenu(True)
        about.triggered.connect(lambda: self.show_skill_about(entry))
        open_folder = menu.addAction(icon(self.client.root, "folder-open"), "Open folder")
        open_folder.setIconVisibleInMenu(True)
        open_folder.triggered.connect(lambda: self.open_skill_folder(entry))
        if entry.data(0, Qt.UserRole)[1] == "Custom":
            menu.addSeparator()
            delete = menu.addAction(icon(self.client.root, "trash-2"), "Delete")
            delete.setProperty("destructive", True)
            delete.setIconVisibleInMenu(True)
            delete.setEnabled(not self.busy)
            delete.triggered.connect(lambda: self.delete_skill(entry))
        return menu

    def show_skill_about(self, entry):
        dialog = Window(self.client.root, "About skill", self)
        dialog.resize(520, 420)
        details = entry.data(0, Qt.UserRole + 1) or {}
        information = PassiveBrowser()
        information.setOpenExternalLinks(False)
        information.setOpenLinks(False)
        information.anchorClicked.connect(lambda url: QtGui.QDesktopServices.openUrl(url) if url.scheme() in ('https', 'mailto') else None)
        content = "<h2>{}</h2><p>{}</p><p><b>Author:</b> {}<br><b>Version:</b> {}<br><b>Source:</b> {}<br><b>Type:</b> {}<br><b>Status:</b> {}</p>".format(
            html.escape(entry.text(0)), html.escape(entry.text(1)),
            html.escape(details.get("author") or "Not specified"),
            html.escape(details.get("version") or "Not specified"),
            html.escape(details.get("displaySource") or entry.data(0, Qt.UserRole)[1]),
            html.escape(entry.data(0, Qt.UserRole)[1]), html.escape(details.get("state") or "Not specified"))
        from urllib.parse import quote
        contacts = []
        if details.get('website'):
            contacts.append('<b>Website:</b> <a href="{0}" style="color:@support_link">{0}</a>'.format(html.escape(details['website'], quote=True)))
        if details.get('email'):
            contacts.append('<b>Email:</b> <a href="mailto:{}" style="color:@support_link">{}</a>'.format(quote(details['email'], safe=''), html.escape(details['email'])))
        if contacts:
            content += '<p>' + '<br>'.join(contacts) + '</p>'
        information.setHtml(content)
        information.moveCursor(QtGui.QTextCursor.Start)
        dialog.setMinimumSize(320, 240)
        dialog.outer.addWidget(information, 1)
        dialog.outer.addWidget(action(self.client.root, "close", "Close", dialog.accept))
        information.document().setTextWidth(480)
        target_height = max(420, int(information.document().size().height()) + 115)
        screen = self.screen() if hasattr(self, "screen") else QtWidgets.QApplication.primaryScreen()
        dialog.resize(520, min(target_height, max(300, screen.availableGeometry().height() - 80)))
        try:
            dialog.exec_()
        finally:
            dialog.deleteLater()

    def show_skill_menu(self, position):
        entry = self.list.itemAt(position)
        if entry is None:
            return
        menu = self.skill_menu(entry)
        try:
            menu.exec_(self.list.viewport().mapToGlobal(position))
        finally:
            menu.deleteLater()

    def delete_selected(self):
        self.delete_skill(self.list.currentItem())

    def delete_skill(self, current):
        if current and not self.busy and current.data(0, Qt.UserRole)[1] == "Custom":
            identifier = current.data(0, Qt.UserRole)[0]
            if QtWidgets.QMessageBox.question(self, "Delete skill", "Delete this imported skill and its owned discovery adapters?") == QtWidgets.QMessageBox.Yes:
                self.client.skills_operation("delete", ["-SkillId", identifier])

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
            self.list.setSortingEnabled(False)
            self.list.clear()
            for index in range(parser.getint("result", "count", fallback=0)):
                section = "skill" + str(index)
                from .community_dialog import display_date
                values = [decode(parser.get(section, field, fallback="")) for field in ("name", "description", "author", "publishedAt")]
                values[3] = display_date(values[3]) or 'Not specified'
                values[0] = decode(parser.get(section, "title", fallback="")) or values[0]
                values[1] = decode(parser.get(section, "displayDescription", fallback="")) or values[1]
                entry = SkillTableItem(values)
                raw_date = decode(parser.get(section, 'publishedAt', fallback=''))
                entry.setData(3, Qt.UserRole, raw_date[:10] if display_date(raw_date) else '')
                for column, value in enumerate(values):
                    entry.setToolTip(column, value)
                entry.setData(0, Qt.UserRole, (decode(parser.get(section, "id")), decode(parser.get(section, "source"))))
                entry.setData(0, Qt.UserRole + 1, {field: decode(parser.get(section, field, fallback="")) for field in ("author", "state", "version", "displaySource", "website", "email")})
                self.list.addTopLevelItem(entry)
            self.list.setSortingEnabled(True)
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
            r'<table data-skill-metadata="true" border="1" cellspacing="0" cellpadding="12" width="100%" style="border:1px solid @preview_border;"><tr><td>\1</td></tr></table><br>',
            content, count=1, flags=re.DOTALL)
        self.preview.setHtml(content)
        self.preview.verticalScrollBar().setValue(getattr(self, "_restore_scroll", 0))
