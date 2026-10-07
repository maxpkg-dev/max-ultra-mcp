# Responsive Qt windows, accessible SVG actions, and paged activity history.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from collections import OrderedDict
from html import escape
from pathlib import Path
import random

from .qt import QtCore, QtGui, QtWidgets, QtSvg, Qt

COLORS = {"info": "#8ed0e0", "system": "#bea5ff", "success": "#78e196", "warning": "#ffc350", "error": "#ff7d7d", "support": "#efa35c", "debug": "#bebe8c"}
DONATE_STYLE = "QToolButton { background:#a35d2c; border-color:#d38d50; } QToolButton:hover { background:#b56b34; }"
STYLE = """
QWidget { background: #242320; color: #e8e3da; font-family: 'Segoe UI'; font-size: 11pt; }
QDialog { border: 1px solid #514b42; }
QToolButton, QPushButton { background: #302e29; border: 1px solid #514b42; border-radius: 4px; padding: 4px; min-height: 20px; }
QToolButton:hover, QPushButton:hover { background: #41382d; border-color: #dc9b57; }
QToolButton:focus, QPushButton:focus, QLineEdit:focus { border: 1px solid #e3a363; }
QToolButton:disabled, QPushButton:disabled { color: #81796e; border-color: #39352f; }
QLineEdit, QPlainTextEdit, QTextBrowser, QTableView, QTreeWidget, QListWidget, QComboBox { background: #1c1c1a; border: 1px solid #49453e; padding: 3px; selection-background-color: #705137; }
QTreeWidget::item { padding: 3px; }
QTreeWidget::item:selected { background: #705137; color: #fff0dc; }
QTreeWidget::item:selected { background: #705137; color: #fff0dc; }
QHeaderView::section { background: #302e29; padding: 4px; border: none; }
QTableView::item:selected, QListWidget::item:selected { background: #705137; color: #fff0df; }
QTableView#activityJournal { background: #302f2b; border: 1px solid #5a554b; }
QScrollBar:vertical { width: 13px; background: #242320; }
QScrollBar::handle:vertical { background: #615647; min-height: 22px; border-radius: 4px; }
QProgressBar { border: 1px solid #514b42; height: 8px; text-align: center; }
QProgressBar::chunk { background: #dc9b57; }
QTabWidget::pane { border: 1px solid #60574a; top: -1px; background: #292823; }
QTabBar::tab { padding: 8px 12px; margin-right: 4px; margin-top: 3px; border: 1px solid #4b463e; border-bottom: 1px solid #60574a; border-top-left-radius: 4px; border-top-right-radius: 4px; background: #1e1e1b; color: #b8b0a3; }
QTabBar::tab:selected { color: #efb577; background: #35312a; border: 1px solid #8e7455; border-bottom-color: #35312a; margin-top: 0; padding-top: 11px; }
QTabBar::tab:hover { color: #fff0dc; }
QToolTip { color: #eee8de; background: #39342c; border: 1px solid #8e7455; }
"""


class PromotionLink(QtWidgets.QLabel):
    PROMOTIONS = (
        ("Discover useful 3ds Max tools on maxpkg.dev.", "Tools on maxpkg.dev", "https://maxpkg.dev"),
        ("Clean up unwanted scene data with Prune Scene.", "Explore Prune Scene", "https://maxpkg.dev/catalog/prune-scene"),
        ("Prepare models and assets for delivery with Model Packer.", "Explore Model Packer", "https://maxpkg.dev/catalog/model-packer"),
        ("Find practical 3ds Max scripts on 3dground.net.", "Scripts on 3dground.net", "https://3dground.net"),
    )

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumWidth(0)
        self.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        self.setTextFormat(Qt.RichText)
        self.setOpenExternalLinks(False)
        self.linkActivated.connect(lambda url: QtGui.QDesktopServices.openUrl(QtCore.QUrl(url)))
        self._remaining = []
        self._current = None
        self.timer = QtCore.QTimer(self)
        self.timer.setInterval(30000)
        self.timer.timeout.connect(self.rotate)
        self.rotate()

    def rotate(self):
        if not self._remaining:
            self._remaining = list(self.PROMOTIONS)
            random.shuffle(self._remaining)
            if self._remaining[-1] == self._current:
                self._remaining[0], self._remaining[-1] = self._remaining[-1], self._remaining[0]
        self._current = self._remaining.pop()
        self.update_text()

    def update_text(self):
        full, short, url = self._current
        metrics = self.fontMetrics()
        available = max(0, self.contentsRect().width() - 2)
        label = full if metrics.horizontalAdvance(full) <= available else short
        label = metrics.elidedText(label, Qt.ElideRight, available)
        self.setText('<a href="{}" style="color:#efa35c">{}</a>'.format(escape(url, quote=True), escape(label)))
        self.setToolTip(full + "\n" + url)
        self.setAccessibleName(full)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.update_text()

    def showEvent(self, event):
        super().showEvent(event)
        self.update_text()
        self.timer.start()

    def hideEvent(self, event):
        self.timer.stop()
        super().hideEvent(event)


def icon(root, name):
    return QtGui.QIcon(str(Path(root) / "assets" / "icons" / (name + ".svg")))


class ActionButton(QtWidgets.QToolButton):
    def paintEvent(self, event):
        # Max's proxy style can offset tool-button icons. Center the shared SVG
        # canvas ourselves while letting Qt draw the styled border/background.
        option = QtWidgets.QStyleOptionToolButton()
        self.initStyleOption(option)
        # PySide2 exposes option.icon as a borrowed value; copy it before clearing
        # the style option or the SVG disappears along with the borrowed icon.
        glyph = QtGui.QIcon(self.icon())
        option.icon = QtGui.QIcon()
        option.text = ""
        painter = QtWidgets.QStylePainter(self)
        painter.drawComplexControl(QtWidgets.QStyle.CC_ToolButton, option)
        close_svg = getattr(self, "close_svg", None)
        if close_svg is not None:
            # Render the original Lucide vector directly at the device DPI. This
            # avoids cached tiny icon pixmaps and keeps both diagonals centered.
            edge = min(14, self.width() - 4, self.height() - 4)
            painter.setRenderHint(QtGui.QPainter.Antialiasing)
            painter.setOpacity(1.0 if self.isEnabled() else 0.45)
            close_svg.render(painter, QtCore.QRectF((self.width() - edge) / 2.0,
                                                  (self.height() - edge) / 2.0, edge, edge))
            return
        edge = min(self.iconSize().width(), max(0, self.height() - 4))
        caption = self.text() if self.toolButtonStyle() != Qt.ToolButtonIconOnly else ""
        if self.toolButtonStyle() == Qt.ToolButtonTextUnderIcon:
            metrics = self.fontMetrics()
            caption = metrics.elidedText(caption, Qt.ElideRight, self.width() - 16)
            top = max(4, (self.height() - edge - metrics.height() - 10) // 2)
            glyph.paint(painter, QtCore.QRect((self.width() - edge) // 2, top, edge, edge), Qt.AlignCenter, QtGui.QIcon.Normal if self.isEnabled() else QtGui.QIcon.Disabled)
            painter.setPen(option.palette.color(QtGui.QPalette.Active if self.isEnabled() else QtGui.QPalette.Disabled, QtGui.QPalette.ButtonText))
            painter.drawText(QtCore.QRect(8, top + edge + 10, self.width() - 16, metrics.height()), Qt.AlignCenter, caption)
            return
        gap = 5 if caption else 0
        available = max(0, self.width() - 12 - edge - gap)
        caption = self.fontMetrics().elidedText(caption, Qt.ElideRight, available)
        total = edge + gap + self.fontMetrics().horizontalAdvance(caption)
        x = max(0 if not caption else 2, (self.width() - total) // 2)
        rectangle = QtCore.QRect(x, (self.height() - edge) // 2, edge, edge)
        glyph.paint(painter, rectangle, Qt.AlignCenter, QtGui.QIcon.Normal if self.isEnabled() else QtGui.QIcon.Disabled)
        if caption:
            group = QtGui.QPalette.Active if self.isEnabled() else QtGui.QPalette.Disabled
            painter.setPen(option.palette.color(group, QtGui.QPalette.ButtonText))
            painter.setFont(self.font())
            painter.drawText(QtCore.QRect(x + edge + gap, 0, max(0, self.width() - x - edge - gap - 3), self.height()), Qt.AlignLeft | Qt.AlignVCenter, caption)


def action(root, name, label, callback, parent=None):
    button = ActionButton(parent)
    button.setIcon(icon(root, name))
    button.setIconSize(QtCore.QSize(20, 20))
    button.setText(label)
    button.setToolTip(label)
    button.setAccessibleName(label)
    button.setMinimumSize(32, 32)
    button.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
    button.clicked.connect(callback)
    return button


def donate_action(root, callback):
    button = action(root, "heart", "Donate", callback)
    button.setStyleSheet(DONATE_STYLE)
    return button


def configure_close_icon(button, root):
    previous = getattr(button, "close_svg", None)
    if previous is not None:
        previous.deleteLater()
    button.close_svg = QtSvg.QSvgRenderer(str(Path(root) / "assets/icons/close.svg"), button)
    button.setIconSize(QtCore.QSize(14, 14))
    button.update()


class Window(QtWidgets.QDialog):
    def __init__(self, root, title, parent):
        super().__init__(parent, Qt.Tool | Qt.FramelessWindowHint)
        self.setWindowTitle(title)
        self.setStyleSheet(STYLE)
        self.setSizeGripEnabled(True)
        self.setAttribute(Qt.WA_DeleteOnClose, False)
        self._drag = None
        self.outer = QtWidgets.QVBoxLayout(self)
        self.outer.setContentsMargins(8, 6, 8, 6)
        self.outer.setSpacing(6)
        self.header = QtWidgets.QWidget()
        heading = QtWidgets.QHBoxLayout(self.header)
        heading.setContentsMargins(0, 0, 0, 0)
        self.caption = QtWidgets.QLabel(title)
        self.caption.setMinimumWidth(0)
        self.caption.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        self.caption.setStyleSheet("font-size: 12pt; font-weight: 600; color: #efb577")
        self.caption.setToolTip(title)
        heading.addWidget(self.caption, 1)
        self.close_button = action(root, "close", "Close", self.close)
        self.close_button.setToolButtonStyle(Qt.ToolButtonIconOnly)
        self.close_button.setMinimumSize(0, 0)
        self.close_button.setFixedSize(18, 18)
        configure_close_icon(self.close_button, root)
        self.close_button.setStyleSheet("QToolButton { min-height:0; padding:0; border-radius:2px; }")
        heading.addWidget(self.close_button)
        self.outer.addWidget(self.header)
        self.header.installEventFilter(self)
        self.caption.installEventFilter(self)

    def eventFilter(self, watched, event):
        if watched in (self.header, self.caption):
            if event.type() == QtCore.QEvent.MouseButtonPress and event.button() == Qt.LeftButton:
                self._drag = event.globalPos() - self.frameGeometry().topLeft()
                return True
            if event.type() == QtCore.QEvent.MouseMove and self._drag is not None:
                self.move(event.globalPos() - self._drag)
                return True
            if event.type() == QtCore.QEvent.MouseButtonRelease:
                self._drag = None
        return super().eventFilter(watched, event)

    def nativeEvent(self, event_type, message):
        # Native hit testing retains edge/corner resize with custom title chrome.
        import ctypes
        from ctypes import wintypes
        native = wintypes.MSG.from_address(int(message))
        if native.message == 0x84 and self.minimumSize() != self.maximumSize():
            x = ctypes.c_short(native.lParam & 0xffff).value
            y = ctypes.c_short((native.lParam >> 16) & 0xffff).value
            rect = wintypes.RECT()
            ctypes.windll.user32.GetWindowRect(wintypes.HWND(int(self.winId())), ctypes.byref(rect))
            edge = max(5, int(5 * self.devicePixelRatioF()))
            left, right = x < rect.left + edge, x >= rect.right - edge
            top, bottom = y < rect.top + edge, y >= rect.bottom - edge
            code = (13 if left else 14 if right else 12) if top else (16 if left else 17 if right else 15) if bottom else 10 if left else 11 if right else 0
            if code:
                return True, code
        return super().nativeEvent(event_type, message)


class JournalModel(QtCore.QAbstractTableModel):
    def __init__(self, journal, parent=None):
        super().__init__(parent)
        self.journal = journal
        self.search, self.category = "", ""
        self.pages = OrderedDict()
        self.total = journal.count()

    def rowCount(self, parent=QtCore.QModelIndex()):
        return 0 if parent.isValid() else self.total

    def columnCount(self, parent=QtCore.QModelIndex()):
        return 1

    def record(self, row):
        page = row // 256
        if page not in self.pages:
            self.pages[page] = self.journal.page(page * 256, 256, self.search, self.category)
            while len(self.pages) > 8:
                self.pages.popitem(last=False)
        self.pages.move_to_end(page)
        records = self.pages[page]
        return records[row % 256] if row % 256 < len(records) else None

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid() or not 0 <= index.row() < self.total:
            return None
        record = self.record(index.row())
        if record is None:
            return None
        if role in (Qt.DisplayRole, Qt.ToolTipRole, Qt.AccessibleTextRole):
            return "{}  [{}]  {}".format(record[1][11:19], record[2].upper(), record[3])
        if role == Qt.ForegroundRole:
            return QtGui.QColor(COLORS.get(record[2], COLORS["info"]))
        return None

    def refresh(self, search=None, category=None):
        changed = search is not None or category is not None
        if search is not None:
            self.search = search
        if category is not None:
            self.category = category
        total = self.journal.count(self.search, self.category)
        if changed or total < self.total:
            self.beginResetModel()
            self.pages.clear()
            self.total = total
            self.endResetModel()
        elif total > self.total:
            self.beginInsertRows(QtCore.QModelIndex(), self.total, total - 1)
            self.pages.clear()
            self.total = total
            self.endInsertRows()


class JournalDelegate(QtWidgets.QStyledItemDelegate):
    def paint(self, painter, option, index):
        record = index.model().record(index.row())
        if record is None:
            return
        painter.save()
        painter.setClipRect(option.rect)
        if option.state & QtWidgets.QStyle.State_Selected:
            painter.fillRect(option.rect, QtGui.QColor("#493b2c"))
        color = QtGui.QColor(COLORS.get(record[2], COLORS["info"]))
        font = QtGui.QFont("Consolas", 11)
        painter.setFont(font)
        metrics = QtGui.QFontMetrics(font)
        rect = option.rect.adjusted(5, 0, -4, 0)
        baseline = rect.top() + (rect.height() + metrics.ascent() - metrics.descent()) // 2
        timestamp = record[1][11:19]
        painter.setPen(color)
        font.setBold(True)
        font.setItalic(True)
        painter.setFont(font)
        painter.drawText(rect.left(), baseline, timestamp)
        x = rect.left() + metrics.horizontalAdvance(timestamp) + 10
        font.setItalic(False)
        painter.setFont(font)
        badge = "[ {} ]".format(record[2].lower())
        badge_width = QtGui.QFontMetrics(font).horizontalAdvance(badge) + 8
        badge_rect = QtCore.QRect(x, rect.top() + 2, badge_width, rect.height() - 4)
        painter.fillRect(badge_rect, color)
        painter.setPen(QtGui.QColor("#29232c"))
        painter.drawText(badge_rect, Qt.AlignCenter, badge)
        x += badge_width + 8
        font.setBold(False)
        painter.setFont(font)
        painter.setPen(color)
        content = "> " + record[3].replace("\n", "  ")
        painter.drawText(x, baseline, metrics.elidedText(content, Qt.ElideRight, max(0, rect.right() - x)))
        painter.restore()


class Panel(Window):
    def __init__(self, client, parent):
        super().__init__(client.root, "3DGROUND - Max Ultra MCP " + client.version, parent)
        self.client = client
        self.setMinimumSize(320, 240)
        self.resize(640, 480)
        self.outer.setSpacing(6)
        self.ai = action(client.root, "settings", "Setup AI Client", client.show_onboarding)
        self.ai.setFocusPolicy(Qt.StrongFocus)
        self.setFocusProxy(self.ai)
        self.ai.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Fixed)
        self.ai.setMinimumWidth(100)
        self.ai_refresh = action(client.root, "refresh-cw", "Refresh AI client status", client.refresh_agents)
        self.ai_refresh.setToolButtonStyle(Qt.ToolButtonIconOnly)
        self.hide_button = action(client.root, "panel-top-close", "Hide panel", client.hide_panel)
        top_row = QtWidgets.QHBoxLayout()
        top_row.setSpacing(8)
        top_row.addWidget(self.ai, 1)
        top_row.addWidget(self.ai_refresh)
        top_row.addSpacing(12)
        top_row.addWidget(self.hide_button)
        self.outer.addLayout(top_row)
        status_row = QtWidgets.QHBoxLayout()
        self.scene_label = QtWidgets.QLabel()
        self.scene_label.setMinimumWidth(0)
        self.scene_label.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        self.scene_label.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        status_row.addWidget(self.scene_label, 1)
        self.outer.addLayout(status_row)
        self.filters = QtWidgets.QWidget()
        filters = QtWidgets.QHBoxLayout(self.filters)
        filters.setContentsMargins(0, 0, 0, 0)
        self.search = QtWidgets.QLineEdit()
        self.search.setPlaceholderText("Search complete session history")
        self.search.setAccessibleName("Search complete session history")
        self.categories = QtWidgets.QComboBox()
        self.categories.addItems(["All"] + list(COLORS))
        filters.addWidget(self.search, 1)
        filters.addWidget(self.categories)
        self.outer.addWidget(self.filters)
        self.filters.hide()
        self.model = JournalModel(client.journal, self)
        self.log = QtWidgets.QTableView()
        self.log.setObjectName("activityJournal")
        self.log.setMinimumHeight(24)
        self.log.setModel(self.model)
        self.log.setItemDelegate(JournalDelegate(self.log))
        self.log.setAccessibleName("Complete session activity journal")
        self.log.horizontalHeader().hide()
        self.log.verticalHeader().hide()
        self.log.horizontalHeader().setStretchLastSection(True)
        row_height = max(22, QtGui.QFontMetrics(QtGui.QFont("Consolas", 11)).height() + 4)
        self.log.verticalHeader().setMinimumSectionSize(row_height)
        self.log.verticalHeader().setDefaultSectionSize(row_height)
        self.log.setWordWrap(False)
        self.log.setShowGrid(False)
        self.log.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.log.setSelectionMode(QtWidgets.QAbstractItemView.ExtendedSelection)
        self.log.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.log.doubleClicked.connect(self.show_message)
        self.outer.addWidget(self.log, 1)
        self.storage_error = QtWidgets.QLabel()
        self.storage_error.setWordWrap(True)
        self.storage_error.setStyleSheet("color: #e48a82")
        self.storage_error.hide()
        self.outer.addWidget(self.storage_error)
        self.latest = QtWidgets.QPushButton("Go to latest")
        self.latest.clicked.connect(self.go_latest)
        self.latest.hide()
        self.outer.addWidget(self.latest)
        self.actions = QtWidgets.QHBoxLayout()
        self.buttons = []
        for symbol, title, callback in [("plug-zap", "Reconnect", client.reconnect), ("power", "Stop / Exit", client.close), ("skills", "Skills", client.show_skills), ("settings", "Settings", client.show_settings)]:
            if title == "Skills":
                self.actions.addStretch(1)
            button = action(client.root, symbol, title, callback)
            self.buttons.append(button)
            self.actions.addWidget(button)
        self.actions.setSpacing(8)
        self.outer.addLayout(self.actions)
        footer = QtWidgets.QHBoxLayout()
        self.support = PromotionLink()
        footer.addWidget(self.support, 1)
        self.donate_button = donate_action(client.root, client.donate)
        footer.addWidget(self.donate_button)
        self.outer.addLayout(footer)
        self.search_timer = QtCore.QTimer(self)
        self.search_timer.setSingleShot(True)
        self.search_timer.setInterval(250)
        self.search_timer.timeout.connect(lambda: self.model.refresh(search=self.search.text(), category="" if self.categories.currentIndex() == 0 else self.categories.currentText()))
        self.search.textChanged.connect(lambda: self.search_timer.start())
        self.categories.currentIndexChanged.connect(lambda: self.search_timer.start())
        shortcut_type = getattr(QtGui, "QShortcut", None) or QtWidgets.QShortcut
        self.copy_shortcut = shortcut_type(QtGui.QKeySequence.Copy, self.log)
        self.copy_shortcut.activated.connect(self.copy_selected)
        self.search_shortcut = shortcut_type(QtGui.QKeySequence("Ctrl+F"), self)
        self.search_shortcut.activated.connect(self.show_search)
        self.export_shortcut = shortcut_type(QtGui.QKeySequence("Ctrl+E"), self)
        self.export_shortcut.activated.connect(self.export)
        self.log.setContextMenuPolicy(Qt.CustomContextMenu)
        self.log.customContextMenuRequested.connect(self.journal_menu)
        self._unread = 0
        self.update_ai()
        self.ai.setFocus(Qt.OtherFocusReason)

    def show_search(self):
        self.filters.show()
        self.search.setFocus()

    def journal_menu(self, position):
        menu = QtWidgets.QMenu(self)
        for symbol, label, callback in [("search", "Search / filter (Ctrl+F)", self.show_search), ("copy", "Copy selected (Ctrl+C)", self.copy_selected), ("download", "Export (Ctrl+E)", self.export), ("expand", "Go to latest", self.go_latest)]:
            item = menu.addAction(icon(self.client.root, symbol), label)
            item.triggered.connect(callback)
        menu.exec_(self.log.viewport().mapToGlobal(position))

    def update_ai(self):
        label, state = self.client.ai_status()
        self.ai.setText(label if self.width() >= 520 else "Setup AI Client")
        self.ai.setToolTip(label + " — open AI Client Setup")
        background = {"ready": "#356b43", "issue": "#864f3b", "checking": "#685735"}.get(state, "#805f35")
        self.ai.setStyleSheet("QToolButton { background:" + background + "; border-color:" + background + "; color:#fff3dc; } QToolButton:hover { border-color:#efb577; }")
        self.ai_refresh.setEnabled(self.client.integration is None)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, "buttons"):
            required = sum(button.fontMetrics().horizontalAdvance(button.text()) + 48 for button in self.buttons) + 42
            compact = self.width() < required
            for button in self.buttons:
                button.setToolButtonStyle(Qt.ToolButtonIconOnly if compact else Qt.ToolButtonTextBesideIcon)
            self.hide_button.setToolButtonStyle(Qt.ToolButtonIconOnly if self.width() < 520 else Qt.ToolButtonTextBesideIcon)
            self.donate_button.setToolButtonStyle(Qt.ToolButtonIconOnly if self.width() < 400 else Qt.ToolButtonTextBesideIcon)
            self.update_ai()

    def refresh(self):
        scrollbar = self.log.verticalScrollBar()
        following = scrollbar.value() >= scrollbar.maximum() - 1
        previous = self.model.total
        self.model.refresh()
        if following:
            self.go_latest()
        elif self.model.total > previous:
            self._unread += self.model.total - previous
            self.latest.setText("{} new messages - go to latest".format(self._unread))
            self.latest.show()
        self.scene_label.setText(getattr(self.client, "scene_context", ""))
        self.scene_label.setToolTip(getattr(self.client, "scene_context", ""))
        self.update_ai()

    def go_latest(self):
        self.log.scrollToBottom()
        self._unread = 0
        self.latest.hide()

    def show_message(self, index):
        dialog = Window(self.client.root, "Activity message", self)
        layout = QtWidgets.QPlainTextEdit()
        layout.setReadOnly(True)
        layout.setPlainText(self.model.data(index))
        dialog.outer.addWidget(layout)
        dialog.resize(560, 300)
        self._message = dialog
        dialog.show()

    def copy_selected(self):
        indexes = sorted(self.log.selectionModel().selectedRows(), key=lambda entry: entry.row())
        QtWidgets.QApplication.clipboard().setText("\n".join(self.model.data(index) for index in indexes))

    def export(self):
        destination, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Export session journal", "activity.txt", "Text (*.txt)")
        if destination:
            try:
                search, category = self.model.search, self.model.category
                self.client.tasks.submit(lambda: self.client.journal.export(destination, search, category), lambda result: self.client.log("success", "Journal exported"), lambda error: self.client.storage_failure(str(error)))
            except Exception as error:
                self.client.storage_failure(str(error))

    def closeEvent(self, event):
        if not self.client.disposed:
            self.client.close()
        event.accept()


def bounded_window_position(position, size, areas, anchor=None):
    if not areas:
        return position
    target = anchor if anchor is not None else position + QtCore.QPoint(size.width() // 2, size.height() // 2)

    def distance(area):
        x = max(area.left(), min(target.x(), area.right()))
        y = max(area.top(), min(target.y(), area.bottom()))
        return (target.x() - x) ** 2 + (target.y() - y) ** 2

    area = min(areas, key=distance)
    return QtCore.QPoint(max(area.left(), min(position.x(), area.right() - size.width() + 1)),
                        max(area.top(), min(position.y(), area.bottom() - size.height() + 1)))


class MiniPanel(Window):
    def __init__(self, client, parent):
        super().__init__(client.root, "Max Ultra MCP", parent)
        self.setSizeGripEnabled(False)
        self.setFixedSize(180, 32)
        self.header.hide()
        self.outer.removeWidget(self.header)
        self.outer.setContentsMargins(3, 2, 3, 2)
        self.outer.setSpacing(0)
        row = QtWidgets.QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(2)
        self.button = action(client.root, "expand", "Max Ultra MCP", client.show_panel)
        self.button.setToolTip("Expand MCP Server — drag to move")
        self.button.setMinimumSize(0, 0)
        self.button.setIconSize(QtCore.QSize(14, 14))
        self.button.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Fixed)
        self.close_button.setParent(self)
        self.close_button.setMinimumSize(0, 0)
        self.close_button.setFixedSize(22, 24)
        compact_style = "QToolButton { font-size:10pt; min-height:0; padding:2px; border:none; background:transparent; } QToolButton:hover { background:#41382d; }"
        self.button.setStyleSheet(compact_style)
        self.close_button.setStyleSheet(compact_style)
        row.addWidget(self.button, 1)
        row.addWidget(self.close_button)
        self.outer.addLayout(row)
        self.button.installEventFilter(self)
        self._press = None
        self._moving = False
        self.client = client
        self.install_screen_constraints()
        self.update_status("warning", "Starting local MCP server...")

    def update_status(self, state, message):
        self.button.setToolTip(message + " — click to expand; drag to move")
        if state == getattr(self, "_status_color", None):
            return
        self._status_color = state
        background, border, hover = {
            "ready": ("#356b42", "#78a780", "#427e50"),
            "error": ("#873c38", "#d17a70", "#a04842"),
            "warning": ("#945b27", "#dc9b57", "#aa6b30"),
        }.get(state, ("#945b27", "#dc9b57", "#aa6b30"))
        self.setObjectName("miniStatus")
        self.setStyleSheet(STYLE + "\nQDialog#miniStatus { background:" + background + "; border:1px solid " + border + "; }")
        style = "QToolButton { color:#fff3dc; font-size:10pt; min-height:0; padding:2px; border:none; background:transparent; } QToolButton:hover { background:" + hover + "; }"
        self.button.setStyleSheet(style)
        self.close_button.setStyleSheet(style)

    def install_screen_constraints(self):
        if getattr(self, "_screen_constraints", False):
            return
        self._screen_constraints = True
        application = QtWidgets.QApplication.instance()
        application.screenAdded.connect(self.watch_screen)
        application.screenRemoved.connect(self.confine_to_screen)
        for screen in application.screens():
            self.watch_screen(screen)

    def watch_screen(self, screen):
        screen.availableGeometryChanged.connect(self.confine_to_screen)
        self.confine_to_screen()

    def confine_to_screen(self, *args, position=None, anchor=None):
        if getattr(self, "_confining", False):
            return
        point = self.pos() if position is None else position
        areas = [screen.availableGeometry() for screen in QtWidgets.QApplication.screens()]
        bounded = bounded_window_position(point, self.frameGeometry().size(), areas, anchor)
        if bounded != self.pos():
            self._confining = True
            try:
                self.move(bounded)
            finally:
                self._confining = False

    def moveEvent(self, event):
        super().moveEvent(event)
        if self.isVisible():
            self.confine_to_screen()

    def showEvent(self, event):
        super().showEvent(event)
        self.confine_to_screen()

    def eventFilter(self, watched, event):
        if watched is getattr(self, "button", None):
            if event.type() == QtCore.QEvent.MouseButtonPress and event.button() == Qt.LeftButton:
                self._press = event.globalPos()
                self._drag = event.globalPos() - self.frameGeometry().topLeft()
                self._moving = False
            elif event.type() == QtCore.QEvent.MouseMove and self._press is not None:
                self._moving = self._moving or (event.globalPos() - self._press).manhattanLength() >= QtWidgets.QApplication.startDragDistance()
                if self._moving:
                    self.confine_to_screen(position=event.globalPos() - self._drag, anchor=event.globalPos())
                    return True
            elif event.type() == QtCore.QEvent.MouseButtonRelease:
                self._press = None
                if self._moving:
                    self.button.setDown(False)
                    self._moving = False
                    return True
        return super().eventFilter(watched, event)

    def closeEvent(self, event):
        if not self.client.disposed:
            self.client.show_panel()
        event.accept()
