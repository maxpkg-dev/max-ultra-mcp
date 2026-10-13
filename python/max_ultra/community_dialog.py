# Native community catalog; network and validated imports run in the owned helper.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import json
import time
from datetime import datetime
from .qt import QtWidgets, QtCore, QtGui, Qt
from .widgets import Window, action, DESTRUCTIVE_STYLE, PillProgressBar, SEARCH_STYLE
from .wire import decode
from . import themes

CATALOG_URL = "https://maxpkg-dev.github.io/max-ultra-mcp-community-skills/"


def display_date(value):
    try:
        parsed = datetime.strptime(value[:10], '%Y-%m-%d')
        month = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')[parsed.month - 1]
        return '{} {}, {}'.format(parsed.day, month, parsed.year)
    except (ValueError, TypeError):
        return ''


class MetadataBadge(QtWidgets.QLabel):
    def __init__(self, value, label):
        super().__init__(value)
        self._full_text = value
        self.setTextFormat(Qt.PlainText)
        self.setAccessibleName(label + ": " + value)
        self.setToolTip(value)
        self.setWordWrap(False)
        self.setMinimumWidth(0)
        self.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        self.update_style()
        self.ensurePolished()
        self.setFixedHeight(self.fontMetrics().height() + 4)
        self.setFixedWidth(self.fontMetrics().horizontalAdvance(value) + 20)

    def update_style(self):
        themes.set_style(self, "QLabel { font-size:8pt; color:@field_text; background:transparent; border:none; padding:0; }")

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.update()

    def paintEvent(self, event):
        # Paint the capsule once: fractional QSS radii vary between Qt styles.
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        capsule = QtCore.QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        painter.setPen(QtGui.QPen(QtGui.QColor(themes.style('@field_border')), 1))
        painter.setBrush(QtGui.QColor(themes.style('@recessed_background')))
        painter.drawRoundedRect(capsule, capsule.height() / 2, capsule.height() / 2)
        painter.setPen(QtGui.QColor(themes.style('@field_text')))
        painter.setFont(self.font())
        painter.drawText(self.rect(), Qt.AlignCenter, self.text())

    def changeEvent(self, event):
        super().changeEvent(event)
        if event.type() == QtCore.QEvent.FontChange and hasattr(self, '_full_text'):
            self.setFixedWidth(self.fontMetrics().horizontalAdvance(self._full_text) + 20)
            self.setFixedHeight(self.fontMetrics().height() + 4)


class MetadataRow(QtWidgets.QWidget):
    def __init__(self, author, version, date=''):
        super().__init__()
        self.setObjectName('skillMetadataRow')
        themes.set_style(self, 'QWidget#skillMetadataRow { background:transparent; border:none; }')
        self.row = QtWidgets.QBoxLayout(QtWidgets.QBoxLayout.LeftToRight, self)
        self.row.setContentsMargins(0, 0, 0, 0)
        self.row.setSpacing(6)
        self.row.setSizeConstraint(QtWidgets.QLayout.SetNoConstraint)
        self.author = MetadataBadge(author, 'Author')
        self.version = MetadataBadge(version, 'Version')
        self.row.addWidget(self.author, 0, Qt.AlignLeft)
        version_row = QtWidgets.QWidget()
        version_row.setObjectName('skillVersionRow')
        themes.set_style(version_row, 'QWidget#skillVersionRow { background:transparent; border:none; }')
        version_layout = QtWidgets.QHBoxLayout(version_row)
        version_layout.setContentsMargins(0, 0, 0, 0)
        version_layout.setSpacing(8)
        version_layout.addWidget(self.version)
        self.date = MetadataBadge(display_date(date) or 'Not specified', 'Publication date')
        version_layout.addWidget(self.date)
        self.version_row = version_row
        self.row.addWidget(version_row, 0, Qt.AlignLeft)
        self.row.addStretch()

    def minimumSizeHint(self):
        return QtCore.QSize(max(self.author.width(), self.version_row.sizeHint().width()), self.author.height())

    def resizeEvent(self, event):
        super().resizeEvent(event)
        vertical = self.width() < self.author.width() + self.version_row.sizeHint().width() + 6
        self.row.setDirection(QtWidgets.QBoxLayout.TopToBottom if vertical else QtWidgets.QBoxLayout.LeftToRight)


class CommunityWindow(Window):
    def __init__(self, client, parent):
        super().__init__(client.root, "Community Skills", parent)
        self.client = client
        self.resize(760, 640)
        self.setMinimumSize(320, 300)
        self.entries = []
        self.install_buttons = []
        self.busy = False
        self.search = QtWidgets.QLineEdit()
        themes.set_style(self.search, SEARCH_STYLE)
        self.search.setPlaceholderText("Search skills, descriptions or authors")
        self.search.textChanged.connect(self.filter_cards)
        self.outer.addWidget(self.search)
        self.status = QtWidgets.QLabel("Loading community catalog...")
        self.status.setWordWrap(True)
        self.status.setTextFormat(Qt.PlainText)
        self.outer.addWidget(self.status)
        self.progress = PillProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setTextVisible(False)
        self.elapsed = QtWidgets.QLabel("0 s")
        self.elapsed.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.elapsed.setMinimumWidth(48)
        self.elapsed.setToolTip("Elapsed time for the current operation")
        self.elapsed.setAccessibleName("Elapsed operation time")
        self.elapsed_timer = QtCore.QTimer(self)
        self.elapsed_timer.setInterval(250)
        self.elapsed_timer.timeout.connect(self.update_elapsed)
        self.operation_started = None
        progress_row = QtWidgets.QHBoxLayout()
        progress_row.addWidget(self.progress, 1)
        progress_row.addWidget(self.elapsed)
        self.outer.addLayout(progress_row)
        self.progress.hide()
        self.elapsed.hide()
        self.scroll = QtWidgets.QScrollArea()
        self.scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        self.scroll.setWidgetResizable(True)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.content = QtWidgets.QWidget()
        self.cards = QtWidgets.QVBoxLayout(self.content)
        self.cards.setContentsMargins(0, 0, 0, 0)
        self.cards.setSpacing(12)
        self.cards.addStretch()
        self.scroll.setWidget(self.content)
        self.outer.addWidget(self.scroll, 1)
        controls = QtWidgets.QHBoxLayout()
        self.retry = action(client.root, "refresh-cw", "Refresh", self.refresh)
        controls.addWidget(self.retry)
        controls.addStretch()
        controls.addWidget(action(client.root, "globe", "Open Online Catalog", lambda: QtGui.QDesktopServices.openUrl(QtCore.QUrl(CATALOG_URL))))
        self.outer.addLayout(controls)

    def refresh(self):
        if self.client.skills_operation("community-list"):
            self.status.setText("Loading community catalog...")

    def set_busy(self, busy):
        if busy and not self.busy:
            self.progress.setRange(0, 0)
            self.operation_started = time.monotonic()
            self.elapsed.setText("0 s")
            self.elapsed_timer.start()
        elif not busy:
            self.elapsed_timer.stop()
            self.operation_started = None
        self.busy = busy
        self.progress.setVisible(busy)
        self.elapsed.setVisible(busy)
        self.retry.setEnabled(not busy)
        for button, available in self.install_buttons:
            button.setEnabled(not busy and available)

    def update_elapsed(self):
        if self.busy and self.operation_started is not None:
            self.elapsed.setText("{} s".format(max(0, int(time.monotonic() - self.operation_started))))

    def show_progress(self, state):
        if not isinstance(state, dict) or not self.busy:
            return
        phase = state.get('phase')
        received, total = state.get('bytes', 0), state.get('total')
        if phase == 'download' and isinstance(received, int) and received >= 0:
            if isinstance(total, int) and 0 < total <= 50 * 1024 * 1024:
                self.progress.setRange(0, total)
                self.progress.setValue(min(received, total))
                self.status.setText('Downloading: {:,} / {:,} bytes ({}%)'.format(received, total, min(received * 100 // total, 100)))
            else:
                self.progress.setRange(0, 0)
                self.status.setText('Downloading: {:,} bytes'.format(received))
        elif phase in ('catalog', 'verify', 'install'):
            self.progress.setRange(0, 0)
            self.status.setText({'catalog': 'Loading community catalog...', 'verify': 'Verifying archive checksum and contents...', 'install': 'Installing skill and registering clients...'}[phase])

    def show_error(self, message):
        self.status.setText(message + "\nUse Refresh to retry, or Open Online Catalog for manual download and import.")
        self.set_busy(False)

    def apply_result(self, helper):
        parser = helper.snapshot
        if parser is None or parser.get("result", "ok", fallback="false") != "true":
            self.show_error(decode(parser.get("result", "message", fallback="")) if parser else "The catalog helper did not return a result.")
            return
        try:
            self.entries = json.loads(decode(parser.get("result", "community")))
        except (ValueError, KeyError):
            self.show_error("The catalog response could not be read.")
            return
        self.status.setText(decode(parser.get("result", "message", fallback="")))
        self.render_cards()

    def render_cards(self):
        while self.cards.count() > 1:
            widget = self.cards.takeAt(0).widget()
            widget.hide()
            widget.deleteLater()
        self.install_buttons = []
        self.card_widgets = []
        for entry in self.entries:
            card = QtWidgets.QGroupBox()
            card.setObjectName("communitySkillCard")
            themes.set_style(card, "QGroupBox#communitySkillCard { background:@community_card_background; border:1px solid @field_border; border-radius:7px; margin:0; } QGroupBox#communitySkillCard QLabel { background:transparent; color:@field_text; }")
            layout = QtWidgets.QVBoxLayout(card)
            layout.setContentsMargins(14, 12, 14, 12)
            layout.setSpacing(8)
            for text, title in ((entry["title"], True), (entry["description"], False)):
                label = QtWidgets.QLabel(text)
                label.setTextFormat(Qt.PlainText)
                label.setWordWrap(True)
                label.setMinimumWidth(0)
                label.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
                if title:
                    font = label.font()
                    font.setBold(True)
                    font.setPointSizeF(font.pointSizeF() + 2)
                    label.setFont(font)
                layout.addWidget(label)
                if title:
                    layout.addWidget(MetadataRow(entry['author'], entry['version'], entry.get('publishedAt', '')))
            state = entry.get("installState", "available")
            if state == "available":
                button = action(self.client.root, "download", "Install", lambda checked=False, selected=entry: self.install(selected))
                themes.set_style(button, "QToolButton { background:@ready_background; color:@status_button_text; border-color:@community_border; } QToolButton:hover { background:@community_hover; border-color:@community_hover_border; } QToolButton:disabled { background:@community_disabled_background; color:@community_disabled_text; border-color:@border; }")
            elif state == "installed":
                button = action(self.client.root, "check", "Installed", lambda: None)
            else:
                notice = QtWidgets.QLabel("The installed copy needs attention. Inspect it in Custom." if state == "needs-attention" else "Another version is installed. Your local copy will not be overwritten.")
                notice.setWordWrap(True)
                layout.addWidget(notice)
                button = action(self.client.root, "folder-open", "Manage Installed", self.manage_installed)
            self.install_buttons.append((button, state != "installed"))
            actions = QtWidgets.QHBoxLayout()
            actions.addWidget(button)
            actions.addSpacing(max(6, actions.spacing()))
            details = QtWidgets.QLabel()
            themes.set_label(details, '<a href="{}docs/skills/{}.html" style="color:@support_link">View details</a>'.format(CATALOG_URL, entry['id']))
            details.setOpenExternalLinks(True)
            details.setCursor(Qt.PointingHandCursor)
            details.setAccessibleName('View details for ' + entry['title'])
            actions.addWidget(details)
            actions.addStretch()
            if entry.get("installedId", "").startswith("user/"):
                delete_button = action(self.client.root, "trash-2", "Delete Installed Skill", lambda checked=False, selected=entry: self.delete_installed(selected))
                delete_button.setToolButtonStyle(Qt.ToolButtonIconOnly)
                themes.set_style(delete_button, DESTRUCTIVE_STYLE)
                actions.addWidget(delete_button)
                self.install_buttons.append((delete_button, True))
            layout.addLayout(actions)
            self.cards.insertWidget(self.cards.count() - 1, card)
            self.card_widgets.append((card, " ".join(entry[field] for field in ("title", "author", "description")).lower()))
        self.filter_cards()
        self.set_busy(self.busy)

    def sync_installed(self, parser):
        if parser is None or parser.get("result", "haslist", fallback="false") != "true":
            return
        installed = [{field: decode(parser.get("skill" + str(index), field, fallback="")) for field in ("id", "name", "title", "author", "displaySource", "source", "revision", "version", "state")} for index in range(parser.getint("result", "count", fallback=0))]
        for entry in self.entries:
            matched = next((item for item in installed if item['name'] == entry['name']), None)
            entry['installState'] = 'available' if matched is None else 'different-version' if matched['version'] != entry['version'] else 'installed' if matched['state'] == 'ready' else 'needs-attention'
            owned = next((item for item in installed if item['source'] == 'Custom' and item['id'].startswith('user/') and item['name'] == entry['name'] and item['displaySource'] == 'Community Skills' and item['title'] == entry['title'] and item['author'] == entry['author']), None)
            entry['installedId'] = owned['id'] if owned else ''
            entry['installedRevision'] = owned['revision'] if owned else ''
        self.render_cards()

    def filter_cards(self):
        # Full single-line author names establish a finite minimum width;
        # the validated feed bounds author length to 256 characters.
        badge_widths = [badge.width() for card, _ in getattr(self, 'card_widgets', []) for badge in card.findChildren(MetadataBadge)]
        self.setMinimumWidth(max([320] + [width + 80 for width in badge_widths]))
        query = self.search.text().strip().lower()
        for card, text in getattr(self, "card_widgets", []):
            card.setVisible(not query or query in text)

    def install(self, entry):
        if self.client.skills_operation("community-install", ["-SkillId", entry["id"], "-Source", entry["version"], "-Revision", entry["sha256"]]):
            self.status.setText("Downloading, verifying and importing " + entry["title"] + "...")

    def manage_installed(self):
        self.client.show_skills()
        self.client.dialogs["skills"].source.setCurrentIndex(1)
        QtWidgets.QMessageBox.information(self, "Installed skill", "Inspect and back up your installed skill using Open folder in Custom. To replace it, explicitly delete that copy, then return here and Refresh. Installation never overwrites your local work.")

    def delete_installed(self, entry):
        if self.busy or not entry.get("installedId", "").startswith("user/"):
            return
        if QtWidgets.QMessageBox.question(self, "Delete skill", "Delete this imported skill and its owned discovery adapters?") == QtWidgets.QMessageBox.Yes:
            if self.client.skills_operation("community-delete", ["-SkillId", entry["installedId"], "-Source", entry["id"], "-Revision", entry["installedRevision"]]):
                self.status.setText("Deleting " + entry["title"] + "...")
