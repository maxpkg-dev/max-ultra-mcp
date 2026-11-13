# Qt settings, AI onboarding, skill help and shared passive skill browsers.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import html
import json
import re
import time

from . import themes
from .qt import QtWidgets, QtCore, QtGui, Qt
from .widgets import Window, JoinedTabBar, ActionButton, action, icon, copy_action, donate_action, COLORS, PillProgressBar, ThemedComboBox, RoundedTextEdit

CLIENTS = [("openai", "Codex", "InstallOpenAI", "https://chatgpt.com/download/"), ("claudeCode", "Claude Code", "InstallClaudeCode", "https://claude.ai/download"), ("antigravity", "Antigravity", "InstallAntigravity", "https://antigravity.google/download")]
TEST_PROMPT = (
    "Use Max Ultra MCP to list connected 3ds Max instances. If exactly one is connected, select it and report its version, "
    "connection health, scene summary and capabilities. If none are connected, tell me to start "
    "01_START_MAX_ULTRA_MCP_FIRST.ms in 3ds Max. If several are connected, list them and ask which one to use. "
    "Do not create, modify, save or render anything.\n"
    "\n"
    "If Max Ultra MCP tools are not available in this conversation, do not guess or simulate any result. "
    "This usually means I am in an ordinary chat, which cannot reach local MCP servers on this computer. "
    "Tell me that I need to switch modes and explain how:\n"
    "- ChatGPT desktop app: switch to Codex mode on this Windows computer, then send this prompt again in a new Codex conversation.\n"
    "- Claude desktop app: open the Code tab and start a Local session on this Windows computer, then send this prompt again. "
    "Chat, Cowork, Cloud and WSL sessions cannot reach Max Ultra MCP.\n"
    "- If you cannot tell which app this is, show both instructions.\n"
    "If I am already in Codex or a Claude Code Local session and the tools are still missing, tell me to restart or reconnect "
    "the AI client and click Refresh Status in AI Client Setup in 3ds Max."
)


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
        self._rendering_html = True
        try:
            self._render_html(content)
        finally:
            self._rendering_html = False
            if getattr(self, '_reflow_pending', False):
                QtCore.QTimer.singleShot(0, self._reflow_document)

    def _render_html(self, content):
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
        if getattr(self, '_rendering_html', False):
            self._reflow_pending = True
            return
        self._reflow_document((anchor, anchor_y, selection))

    def _reflow_document(self, saved=None):
        if getattr(self, '_rendering_html', False):
            self._reflow_pending = True
            return
        self._reflow_pending = False
        if saved is None:
            anchor = self.cursorForPosition(QtCore.QPoint(0, 0))
            anchor_y = self.cursorRect(anchor).top()
            selection = self.textCursor()
        else:
            anchor, anchor_y, selection = saved
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


class AboutWindow(Window):
    def __init__(self, client, parent):
        super().__init__(client.root, "About", parent)
        self.setMinimumWidth(320)
        about = self.outer
        about.setContentsMargins(0, 0, 0, 0)
        about.setSpacing(0)
        self.header.setContentsMargins(8, 6, 8, 6)
        self.header.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Fixed)
        content = QtWidgets.QVBoxLayout()
        content.setContentsMargins(24, 18, 24, 18)
        content.setSpacing(12)
        hero_panel = QtWidgets.QWidget()
        hero_panel.setObjectName('aboutHero')
        themes.set_style(hero_panel, 'QWidget#aboutHero { background:@button_background; } QLabel { background:transparent; }')
        hero = QtWidgets.QHBoxLayout(hero_panel)
        hero.setContentsMargins(24, 18, 24, 18)
        hero_panel.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Fixed)
        hero.setSpacing(12)
        logo = QtWidgets.QLabel()
        ratio = self.devicePixelRatioF()
        logo_path = client.root / 'icons/icon.svg'
        if not logo_path.is_file():
            logo_path = client.root / 'maxpkg-icon.svg'
        pixmap = QtGui.QIcon(str(logo_path)).pixmap(round(60 * ratio), round(60 * ratio))
        pixmap.setDevicePixelRatio(ratio)
        logo.setPixmap(pixmap)
        hero.addWidget(logo)
        title = QtWidgets.QLabel('Max Ultra MCP')
        themes.set_style(title, 'font-size:20pt; font-weight:600; color:@heading_text;')
        heading = QtWidgets.QVBoxLayout()
        heading.setSpacing(0)
        heading.setAlignment(Qt.AlignVCenter)
        heading.addWidget(title)
        subtitle = QtWidgets.QLabel('AI-powered tools for 3ds Max')
        themes.set_style(subtitle, 'font-size:10pt; color:@muted_text;')
        heading.addWidget(subtitle)
        hero.addLayout(heading, 1)
        about.addWidget(hero_panel)
        separator = QtWidgets.QFrame()
        separator.setFixedHeight(2)
        themes.set_style(separator, 'background:@accent; border:none;')
        about.addWidget(separator)
        body = QtWidgets.QWidget()
        body.setLayout(content)
        themes.set_style(body, 'QLabel, QToolButton { font-size:10pt; }')
        about.addWidget(body)
        description = QtWidgets.QLabel('Connect AI workflows to Autodesk 3ds Max.\nScene inspection, modeling and automation.')
        description.setWordWrap(True)
        content.addWidget(description)
        details = QtWidgets.QFormLayout()
        details.setHorizontalSpacing(20)
        details.setVerticalSpacing(10)
        for name, text in [('Version', client.version), ('Developer', 'Lukianenko Vasyl'), ('Project', '3DGROUND - Max Ultra MCP')]:
            label = QtWidgets.QLabel(text)
            label.setWordWrap(True)
            details.addRow(name, label)
        content.addLayout(details)
        links = QtWidgets.QHBoxLayout()
        links.setSpacing(16)
        content.addLayout(links)
        for address in ["3dground.net", "maxpkg.dev"]:
            link = QtWidgets.QLabel()
            themes.set_label(link, '<a href="https://' + address + '" style="color:@support_link">' + address + '</a>')
            link.setOpenExternalLinks(True)
            links.addWidget(link)
        links.addStretch()
        content.addStretch()
        buttons = QtWidgets.QHBoxLayout()
        buttons.addWidget(donate_action(client.root, client.donate))
        buttons.addStretch()
        buttons.addWidget(action(client.root, "close", "Close", self.close))
        content.addSpacing(36)
        content.addLayout(buttons)
        self.adjustSize()
        self.resize(460, self.height())


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
        for title in ["Appearance", "Autostart", "Server console", "Updates", "AI client integration"]:
            group = QtWidgets.QGroupBox(title)
            themes.set_style(group, "QGroupBox { border:1px solid @group_border; border-radius:3px; margin-top:12px; padding:12px 10px 8px; } QGroupBox::title { subcontrol-origin:margin; subcontrol-position:top left; left:10px; padding:0 5px; color:@heading_text; }")
            groups[title] = QtWidgets.QVBoxLayout(group)
            layout.addWidget(group)
        self.theme_picker = ThemedComboBox(client.root)
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
        for group, label, section, key, default in [("Appearance", "Highlight Log Backgrounds", "settings", "highlightLogBackgrounds", True), ("Autostart", "Autostart with 3ds Max", "settings", "autostart", False), ("Server console", "Show server console when starting", "settings", "showServerConsole", False), ("Updates", "Check and install updates automatically", "updates", "automatic", True)]:
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
        self.check_updates = action(client.root, "refresh-cw", "Check Now", client.check_updates)
        update_row.addWidget(self.check_updates)
        groups["Updates"].addLayout(update_row)
        groups["AI client integration"].addWidget(action(client.root, "settings", "Open AI Client Setup...", self.open_ai_setup))
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
            self.client.panel.preview_base_opacity(True)
        else:
            self.save_opacity()

    def eventFilter(self, watched, event):
        if watched is getattr(self, 'opacity_slider', None):
            if event.type() == QtCore.QEvent.MouseButtonPress and event.button() == Qt.LeftButton:
                self._opacity_dragging = True
                self.client.panel.preview_base_opacity(True)
            elif event.type() == QtCore.QEvent.MouseButtonRelease and event.button() == Qt.LeftButton:
                self._opacity_dragging = False
                self.save_opacity()
        return super().eventFilter(watched, event)

    def save_opacity(self):
        self.client.set_panel_opacity(self.opacity_slider.value(), persist=True)
        self.client.panel.preview_base_opacity(False)
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
        state = getattr(self.client, "update_state", "")
        role = "text" if busy else ("log_success" if state == "current" else
                "log_error" if state == "error" else "log_warning" if state else "text")
        themes.set_style(self.update_status_label, "color:@" + role + ";")


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
        setup_layout.setContentsMargins(8, 6, 8, 6)
        setup_layout.setSpacing(6)
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
        self.refresh = action(client.root, "refresh-cw", "Refresh Status", client.refresh_agents)
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
            layout.setContentsMargins(8, 6, 8, 6)
            layout.setSpacing(6)
            box = RoundedTextEdit(content)
            box.setReadOnly(True)
            layout.addWidget(box)
            copy_button = copy_action(client.root, "Copy", content)
            layout.addWidget(copy_button)
            self.tabs.addTab(page, title)
        manual = QtWidgets.QWidget()
        manual_layout = QtWidgets.QVBoxLayout(manual)
        manual_layout.setContentsMargins(8, 6, 8, 6)
        manual_layout.setSpacing(6)
        explanation = QtWidgets.QLabel("For clients configured manually, use these STDIO values. Automatic setup is available on the Setup tab.")
        explanation.setWordWrap(True)
        manual_layout.addWidget(explanation)
        self.manual_fields = []
        self._manual_text = None
        for label in ("Command", "Arguments (one per line)", "Environment"):
            field_group = QtWidgets.QVBoxLayout()
            field_group.setSpacing(4)
            field_group.addWidget(QtWidgets.QLabel(label))
            field = RoundedTextEdit()
            field.setReadOnly(True)
            field.setAccessibleName(label)
            themes.set_style(field, "font-family:Consolas; font-size:11pt;")
            field.ensurePolished()
            lines = 1 if label == "Command" else 2
            field.setFixedHeight(field.fontMetrics().lineSpacing() * lines + 20)
            field_group.addWidget(field)
            manual_layout.addLayout(field_group)
            self.manual_fields.append(field)
        self.runtime_status = QtWidgets.QLabel()
        self.runtime_status.setWordWrap(True)
        manual_layout.addWidget(self.runtime_status)
        manual_layout.addStretch()
        manual_controls = QtWidgets.QHBoxLayout()
        manual_controls.setSpacing(8)
        manual_controls.addWidget(action(client.root, "refresh-cw", "Refresh Status", client.refresh_agents))
        manual_controls.addStretch()
        manual_controls.addWidget(copy_action(client.root, "Copy JSON Configuration", client.manual_setup))
        manual_layout.addLayout(manual_controls)
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
        runtime_ready = parser is not None and parser.get("runtime", "ready", fallback="false").lower() == "true"
        themes.set_style(self.runtime_status, "color:" + (COLORS["success"] if runtime_ready else COLORS["error"]))
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
            status_text = {"configured": "MCP Ready", "not_configured": "Not connected", "restart_required": "Restart required", "cli_missing": "CLI not installed", "desktop_missing": "Desktop app not installed", "check_failed": "Check failed — refresh status", "runtime_missing": "Runtime unavailable", "unknown": "Refresh Status", "checking": "Checking..."}.get(state, state.replace("_", " "))
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
                "Install the app yourself, then Refresh Status and Connect separately. "
                "Cancel installation stops the helper but does not undo installed files."
            ).format(label, installer_url)
            reply = QtWidgets.QMessageBox.question(self, "Install " + label, confirmation)
            if reply == QtWidgets.QMessageBox.Yes:
                self.client.start_integration("InstallCli", identifier, ["-" + switch, "-ConfirmCliInstall"])
        elif state == "desktop_missing" or (identifier == "antigravity" and state == "cli_missing"):
            QtGui.QDesktopServices.openUrl(QtCore.QUrl(url))
            self.client.integration_message = "Install the desktop app, click Refresh Status, then Connect on the same client card."
            self.update_status()
        elif state in ("not_configured", "restart_required", "configured"):
            self.client.start_integration("Install", identifier, ["-" + switch])
        else:
            self.client.refresh_agents()


class SkillHelpWindow(Window):
    def __init__(self, client, parent, submit=False):
        title = "Submit Your Skill" if submit else "How to Create and Import Skills"
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
        self.text = RoundedTextEdit(self.copy_text)
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
