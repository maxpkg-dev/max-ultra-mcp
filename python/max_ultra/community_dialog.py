# Native community catalog; network and validated imports run in the owned helper.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import json
from .qt import QtWidgets, QtCore, QtGui, Qt
from .widgets import Window, action
from .wire import decode
from . import themes

CATALOG_URL = "https://maxpkg-dev.github.io/max-ultra-mcp-community-skills/"


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
        self.search.setPlaceholderText("Search skills, descriptions or authors")
        self.search.textChanged.connect(self.filter_cards)
        self.outer.addWidget(self.search)
        self.status = QtWidgets.QLabel("Loading community catalog...")
        self.status.setWordWrap(True)
        self.status.setTextFormat(Qt.PlainText)
        self.outer.addWidget(self.status)
        self.progress = QtWidgets.QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setTextVisible(False)
        self.progress.setFixedHeight(6)
        self.outer.addWidget(self.progress)
        self.scroll = QtWidgets.QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.content = QtWidgets.QWidget()
        self.cards = QtWidgets.QVBoxLayout(self.content)
        self.cards.setContentsMargins(8, 8, 8, 8)
        self.cards.setSpacing(12)
        self.cards.addStretch()
        self.scroll.setWidget(self.content)
        self.outer.addWidget(self.scroll, 1)
        controls = QtWidgets.QHBoxLayout()
        self.retry = action(client.root, "refresh-cw", "Refresh", self.refresh)
        controls.addWidget(self.retry)
        controls.addStretch()
        controls.addWidget(action(client.root, "globe", "Open online catalog", lambda: QtGui.QDesktopServices.openUrl(QtCore.QUrl(CATALOG_URL))))
        self.outer.addLayout(controls)

    def refresh(self):
        if self.client.skills_operation("community-list"):
            self.status.setText("Loading community catalog...")

    def set_busy(self, busy):
        self.busy = busy
        self.progress.setVisible(busy)
        self.retry.setEnabled(not busy)
        for button, available in self.install_buttons:
            button.setEnabled(not busy and available)

    def show_error(self, message):
        self.status.setText(message + "\nUse Refresh to retry, or Open online catalog for manual download and import.")
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
            for text, title in ((entry["title"], True), (entry["author"] + "  |  " + entry["version"], False), (entry["description"], False)):
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
            state = entry.get("installState", "available")
            if state == "available":
                button = action(self.client.root, "download", "Install", lambda checked=False, selected=entry: self.install(selected))
            elif state == "installed":
                button = action(self.client.root, "check", "Installed", lambda: None)
            else:
                notice = QtWidgets.QLabel("The installed copy needs attention. Inspect it in Custom." if state == "needs-attention" else "Another version is installed. Your local copy will not be overwritten.")
                notice.setWordWrap(True)
                layout.addWidget(notice)
                button = action(self.client.root, "folder-open", "Manage installed", self.manage_installed)
            layout.addWidget(button, 0, Qt.AlignLeft)
            self.install_buttons.append((button, state != "installed"))
            self.cards.insertWidget(self.cards.count() - 1, card)
            self.card_widgets.append((card, " ".join(entry[field] for field in ("title", "author", "description")).lower()))
        self.filter_cards()
        self.set_busy(self.busy)

    def filter_cards(self):
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
