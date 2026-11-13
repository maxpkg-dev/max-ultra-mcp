# Unified Skills window: built-in, installed and community cards plus one reusable details window.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import html
import json
import os
import re
import time
import uuid
from pathlib import Path
from types import SimpleNamespace

from . import themes
from .qt import QtWidgets, QtCore, QtGui, Qt
from .widgets import Window, LoadingOverlay, configure_close_icon, action, donate_action, icon, DESTRUCTIVE_STYLE, PillProgressBar, SEARCH_STYLE
from .dialogs import ResponsiveSkillBrowser, SkillsMenu, SkillHelpWindow
from .wire import decode

CATALOG_URL = "https://maxpkg-dev.github.io/max-ultra-mcp-community-skills/"
LOCAL_FIELDS = ("id", "name", "title", "description", "displayDescription", "author", "version", "source", "displaySource", "state", "error", "website", "email", "revision")
CATEGORIES = (("community", "Community"), ("builtin", "Built-in"))
INSTALL_STYLE = "QToolButton { background:@ready_background; color:@status_button_text; border-color:@community_border; } QToolButton:hover { background:@community_hover; border-color:@community_hover_border; } QToolButton:disabled { background:@community_disabled_background; color:@community_disabled_text; border-color:@border; }"
LINK_STYLE = "QToolButton { background:transparent; border:none; padding:0; min-height:0; color:@support_link; } QToolButton:hover { background:transparent; color:@selected_text; } QToolButton:focus { border:none; color:@selected_text; } QToolButton:disabled { color:@disabled_text; }"
CHIP_STYLE = "QToolButton { background:transparent; border:1px solid @field_border; border-radius:11px; padding:2px %PADDING%; min-height:18px; color:@muted_text; } QToolButton:hover { background:@button_hover; border-color:@accent; color:@text; } QToolButton:checked { background:@selection_background; border-color:@active_border; color:@selected_text; } QToolButton:focus { border-color:@focus_border; }"
CARD_STYLE = "QFrame#skillCard { background:@community_card_background; border:1px solid @field_border; border-radius:7px; } QFrame#skillCard QLabel { background:transparent; color:@field_text; }"
AVAILABLE_CARD_STYLE = "QFrame#skillCard { background:transparent; border:1px dashed @border; border-radius:7px; } QFrame#skillCard QLabel { background:transparent; color:@muted_text; }"
MUTED_STYLE = "QLabel { color:@muted_text; background:transparent; }"
BADGE_ROLES = {
    "plain": ("@recessed_background", "@field_border", "@field_text"),
    "builtin": ("@selection_background", "@selection_background", "@selected_text"),
    "installed": ("@ready_background", "@community_border", "@status_button_text"),
    "available": ("", "@field_border", "@muted_text"),
    "attention": ("@issue_background", "@issue_background", "@status_button_text"),
}


def newer_version(candidate, current):
    pattern = r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    first, second = re.fullmatch(pattern, candidate or ''), re.fullmatch(pattern, current or '')
    if first is None or second is None:
        return False
    return tuple(int(part) for part in first.groups()) > tuple(int(part) for part in second.groups())


def user_skills_root():
    default = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / ".local/share"))) / "3DGROUND/MaxUltraMCP/user-skills"
    return Path(os.environ.get("MAX_ULTRA_MCP_SKILLS_ROOT") or default)


def read_local_skills(root):
    """Read bundled and imported skill metadata straight from disk for the first paint.

    The helper's validated list replaces this a moment later; unreadable entries are skipped here.
    """
    def text(value):
        return value if isinstance(value, str) else ""

    skills = []
    try:
        folders = sorted(entry for entry in (Path(root) / "skills").iterdir() if entry.is_dir() and re.fullmatch(r"[a-z0-9][a-z0-9-]*", entry.name))
    except OSError:
        folders = []
    for folder in folders:
        try:
            header = re.match(r"﻿?---\r?\n(.*?)\r?\n---", (folder / "SKILL.md").read_text(encoding="utf-8"), re.S)
            if header is None:
                continue
            fields = {}
            for line in header.group(1).splitlines():
                field = re.match(r"(name|description|author):[ \t]*(.+)$", line)
                if field:
                    value = field.group(2).strip()
                    if value.startswith('"'):
                        value = json.loads(value)
                    elif value.startswith("'"):
                        value = value[1:-1].replace("''", "'")
                    fields[field.group(1)] = text(value)
            manifest = folder / "skill.json"
            display = json.loads(manifest.read_text(encoding="utf-8-sig")) if manifest.is_file() else {}
            if not isinstance(display, dict):
                display = {}
        except (OSError, ValueError):
            continue
        skills.append({"id": "bundled/" + folder.name, "name": fields.get("name", folder.name), "title": text(display.get("title")), "description": fields.get("description", ""),
                       "displayDescription": text(display.get("description")), "author": text(display.get("author")) or fields.get("author", ""), "version": text(display.get("version")),
                       "source": "Built-in", "displaySource": text(display.get("source")), "state": "Read only", "error": "",
                       "website": text(display.get("website")), "email": text(display.get("email")), "revision": ""})
    try:
        registry = json.loads((user_skills_root() / "registry.json").read_text(encoding="utf-8-sig"))
        records = registry.get("skills", []) if isinstance(registry, dict) else []
    except (OSError, ValueError):
        records = []
    for record in records if isinstance(records, list) else []:
        if not isinstance(record, dict) or not re.fullmatch(r"[0-9a-fA-F-]{36}", text(record.get("id"))):
            continue
        skill = {field: text(record.get(field)) for field in LOCAL_FIELDS}
        skill.update(id="user/" + record["id"], source="Custom")
        skills.append(skill)
    return skills


METADATA_BLOCK = '<table data-skill-metadata="true" border="1" cellspacing="0" cellpadding="12" width="100%" style="border:1px solid @preview_border;"><tr><td><div class="eyebrow">{}</div><h1>{}</h1><p>{}</p></td></tr></table><br>'
TEXT_DOCUMENTS = (".md", ".txt", ".json", ".csv")
IMAGE_DOCUMENTS = (".png", ".jpg", ".jpeg", ".webp")


def render_markdown(text, relative="SKILL.md"):
    """Render a skill document to passive HTML with Qt itself, so opening it needs no helper process.

    Raw HTML in the source is not interpreted, and the browser that shows the result loads no resources.
    """
    header = re.match(r"﻿?---\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|$)", text, re.S)
    block = ""
    if header is not None:
        fields = dict(re.findall(r"^(name|description):[ \t]*(.+)$", header.group(1), re.M))
        text = text[header.end():]
        block = METADATA_BLOCK.format("SKILL", html.escape(fields.get("name", "").strip().strip("\"'")), html.escape(fields.get("description", "").strip().strip("\"'")))
    elif relative != "SKILL.md":
        block = METADATA_BLOCK.format("REFERENCE", html.escape(relative), "")
    document = QtGui.QTextDocument()
    document.setMarkdown(text, QtGui.QTextDocument.MarkdownDialectGitHub | QtGui.QTextDocument.MarkdownNoHTML)
    rendered = document.toHtml()
    # Qt's Markdown import embeds blue foregrounds in anchor spans; keep palette tokens so themes apply.
    rendered = re.sub(r'<a\b[^>]*>.*?</a>', lambda match: re.sub(r'color\s*:\s*[^;"\']+', 'color:@support_link', match.group(), flags=re.I), rendered, flags=re.I | re.S)
    return re.sub(r"(<body\b[^>]*>)", lambda match: match.group(1) + block, rendered, count=1, flags=re.I) if block else rendered


def read_skill_document(root, local, relative):
    """Read one instruction file of a built-in or installed skill; returns (ok, message, html)."""
    from pathlib import PurePosixPath
    folder = skill_folder(root, local)
    parts = PurePosixPath(relative).parts
    unsafe = not parts or PurePosixPath(relative).is_absolute() or any(part in ("..", ".") or ":" in part or "\\" in part for part in parts)
    if folder is None or unsafe:
        return False, "This document is not part of the skill.", ""
    try:
        target = folder.joinpath(*parts)
        target.resolve().relative_to(folder.resolve())
        if not target.is_file():
            return False, "The document is no longer available. Refresh the list.", ""
        suffix = target.suffix.lower()
        if suffix in IMAGE_DOCUMENTS:
            return True, "", "<p>Image asset: {}</p><p>This image is available to the agent through max_skill_read.</p>".format(html.escape(relative))
        if suffix not in TEXT_DOCUMENTS or target.stat().st_size > 1024 * 1024:
            return False, "This file cannot be shown here. Use Open Folder to inspect it.", ""
        text = target.read_text(encoding="utf-8-sig")
    except (OSError, ValueError):
        return False, "The document could not be read. Refresh the list and try again.", ""
    if suffix == ".md":
        return True, "", render_markdown(text, relative)
    return True, "", METADATA_BLOCK.format("FILE", html.escape(relative), "") + "<pre>{}</pre>".format(html.escape(text))


def skill_folder(root, local):
    identifier, source = local.get("id", ""), local.get("source", "")
    if source == "Built-in" and re.fullmatch(r"bundled/[a-z0-9][a-z0-9-]*", identifier):
        return Path(root) / "skills" / identifier.split("/", 1)[1]
    if source == "Custom" and re.fullmatch(r"user/[0-9a-fA-F-]{36}", identifier):
        return user_skills_root() / "packages" / identifier.split("/", 1)[1]
    return None


def link_button(label, callback, name=None):
    button = QtWidgets.QToolButton()
    button.setText(label)
    button.setToolButtonStyle(Qt.ToolButtonTextOnly)
    button.setAccessibleName(name or label)
    button.setCursor(Qt.PointingHandCursor)
    themes.set_style(button, LINK_STYLE)
    font = button.font()
    font.setUnderline(True)
    button.setFont(font)
    button.clicked.connect(callback)
    return button


class MetadataBadge(QtWidgets.QLabel):
    """Single-line capsule; a value wider than its card is elided and kept in the tooltip."""
    def __init__(self, value, label, role="plain", parent=None):
        # Created inside its final parent: reparenting a styled widget repolishes it and slows a full grid.
        super().__init__(value, parent)
        self.role = role
        self.setTextFormat(Qt.PlainText)
        self.setAccessibleName(label + ": " + value)
        self.setToolTip(value)
        self.setWordWrap(False)
        self.setMinimumWidth(0)
        self.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        themes.set_style(self, "QLabel { font-size:8pt; background:transparent; border:none; padding:0; }")
        self.ensurePolished()

    def sizeHint(self):
        metrics = self.fontMetrics()
        return QtCore.QSize(metrics.horizontalAdvance(self.text()) + 20, metrics.height() + 4)

    def minimumSizeHint(self):
        metrics = self.fontMetrics()
        return QtCore.QSize(metrics.horizontalAdvance('...') + 20, metrics.height() + 4)

    def paintEvent(self, event):
        # Paint the capsule once: fractional QSS radii vary between Qt styles.
        background, border, foreground = BADGE_ROLES[self.role]
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        capsule = QtCore.QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        painter.setPen(QtGui.QPen(QtGui.QColor(themes.style(border)), 1))
        painter.setBrush(QtGui.QColor(themes.style(background)) if background else Qt.NoBrush)
        painter.drawRoundedRect(capsule, capsule.height() / 2, capsule.height() / 2)
        painter.setPen(QtGui.QColor(themes.style(foreground)))
        painter.setFont(self.font())
        caption = self.fontMetrics().elidedText(self.text(), Qt.ElideRight, max(0, self.width() - 16))
        painter.drawText(self.rect(), Qt.AlignCenter, caption)


class BadgeFlow(QtWidgets.QWidget):
    """Wraps badges onto further lines instead of widening a narrow card."""
    GAP = 6

    def __init__(self, item, parent=None):
        super().__init__(parent)
        self.badges = item_badges(item, self)
        policy = QtWidgets.QSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Minimum)
        policy.setHeightForWidth(True)
        self.setSizePolicy(policy)

    def arrange(self, width, apply):
        x = y = row = 0
        for badge in self.badges:
            size = badge.sizeHint()
            badge_width = min(size.width(), max(1, width))
            if x and x + badge_width > width:
                x, y, row = 0, y + row + self.GAP, 0
            if apply:
                badge.setGeometry(x, y, badge_width, size.height())
            x += badge_width + self.GAP
            row = max(row, size.height())
        return y + row

    def hasHeightForWidth(self):
        return True

    def heightForWidth(self, width):
        return self.arrange(width, False)

    def sizeHint(self):
        return QtCore.QSize(240, self.arrange(240, False))

    def minimumSizeHint(self):
        return QtCore.QSize(0, self.arrange(100000, False))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.arrange(self.width(), True)


class ClampLabel(QtWidgets.QWidget):
    """Plain text limited to a fixed number of lines so cards in a row stay equal."""
    def __init__(self, text, lines=3, role="@field_text", style="font-size:10pt;"):
        super().__init__()
        self.full_text = " ".join(str(text).split())
        self.lines = lines
        self.role = role
        self.setToolTip(self.full_text)
        self.setAccessibleName(self.full_text)
        self.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Fixed)
        themes.set_style(self, style)
        self.ensurePolished()

    def sizeHint(self):
        return QtCore.QSize(240, self.fontMetrics().lineSpacing() * self.lines)

    def minimumSizeHint(self):
        return QtCore.QSize(0, self.fontMetrics().lineSpacing() * self.lines)

    def paintEvent(self, event):
        painter = QtGui.QPainter(self)
        painter.setPen(QtGui.QColor(themes.style(self.role)))
        painter.setFont(self.font())
        metrics = self.fontMetrics()
        layout = QtGui.QTextLayout(self.full_text, self.font())
        layout.beginLayout()
        rows = []
        while len(rows) < self.lines:
            line = layout.createLine()
            if not line.isValid():
                break
            line.setLineWidth(max(1, self.width()))
            line.setPosition(QtCore.QPointF(0, len(rows) * metrics.lineSpacing()))
            rows.append((line.textStart(), line.textLength()))
        layout.endLayout()
        for index, (start, length) in enumerate(rows):
            top = index * metrics.lineSpacing()
            if index == self.lines - 1 and start + length < len(self.full_text):
                remainder = metrics.elidedText(self.full_text[start:], Qt.ElideRight, max(1, self.width()))
                painter.drawText(QtCore.QRect(0, top, self.width(), metrics.lineSpacing()), Qt.AlignLeft | Qt.AlignVCenter, remainder)
            else:
                layout.lineAt(index).draw(painter, QtCore.QPointF(0, 0))


class Spinner(QtWidgets.QWidget):
    """Small rotating arc for background catalog loading; it never blocks the window."""
    def __init__(self):
        super().__init__()
        self.angle = 0
        self.setFixedSize(16, 16)
        self.setAccessibleName("Loading")
        self.timer = QtCore.QTimer(self)
        self.timer.setInterval(40)
        self.timer.timeout.connect(self.advance)
        self.hide()

    def advance(self):
        self.angle = (self.angle + 12) % 360
        self.update()

    def showEvent(self, event):
        super().showEvent(event)
        self.timer.start()

    def hideEvent(self, event):
        self.timer.stop()
        super().hideEvent(event)

    def paintEvent(self, event):
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        ring = QtCore.QRectF(2, 2, 12, 12)
        track = QtGui.QColor(themes.style("@text"))
        track.setAlpha(65)
        painter.setPen(QtGui.QPen(track, 2))
        painter.drawEllipse(ring)
        pen = QtGui.QPen(QtGui.QColor(themes.style("@accent")), 2)
        pen.setCapStyle(Qt.RoundCap)
        painter.setPen(pen)
        painter.drawArc(ring, -self.angle * 16, 100 * 16)


class StatusBanner(QtWidgets.QFrame):
    """Closable strip for the progress or result of a skill operation, colored by its kind."""
    KINDS = ("info", "success", "warning", "error")
    STYLE = "QFrame#skillsBanner { background:@log_%s_background; border:1px solid @log_%s; border-radius:6px; } QFrame#skillsBanner QLabel { background:transparent; color:@text; }"

    def __init__(self, root):
        super().__init__()
        self.setObjectName("skillsBanner")
        self.kind = "info"
        row = QtWidgets.QHBoxLayout(self)
        row.setContentsMargins(12, 6, 6, 6)
        row.setSpacing(10)
        self.label = QtWidgets.QLabel()
        self.label.setTextFormat(Qt.PlainText)
        self.label.setWordWrap(True)
        self.label.setMinimumWidth(0)
        self.label.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        row.addWidget(self.label, 1)
        self.close_button = action(root, "close", "Dismiss", self.hide)
        self.close_button.setToolButtonStyle(Qt.ToolButtonIconOnly)
        self.close_button.setMinimumSize(0, 0)
        self.close_button.setFixedSize(20, 20)
        configure_close_icon(self.close_button, root)
        themes.set_style(self.close_button, "QToolButton { min-height:0; padding:0; border:none; border-radius:3px; background:transparent; } QToolButton:hover { background:@button_hover; }")
        row.addWidget(self.close_button, 0, Qt.AlignTop)
        self.hide()

    def text(self):
        return self.label.text()

    def show_message(self, message, kind="info"):
        self.kind = kind if kind in self.KINDS else "info"
        themes.set_style(self, self.STYLE % (self.kind, self.kind))
        self.label.setText(message)
        self.setAccessibleName(message)
        self.setVisible(bool(message))


class FilterChip(QtWidgets.QToolButton):
    """Checkable filter pill; its counter appears only once the list is known."""
    def __init__(self, label):
        super().__init__()
        self.label = label
        self.count = None
        self.setCheckable(True)
        self.setToolButtonStyle(Qt.ToolButtonTextOnly)
        self.setCursor(Qt.PointingHandCursor)
        self.set_compact(False)
        self.set_count(None)

    def set_count(self, count):
        self.count = count
        caption = self.label if count is None else "{} {}".format(self.label, count)
        self.setText(caption)
        self.setToolTip(caption)
        self.setAccessibleName(caption)

    def set_compact(self, compact):
        themes.set_style(self, CHIP_STYLE.replace("%PADDING%", "7px" if compact else "12px"))


class SkillCard(QtWidgets.QFrame):
    ACTION_HEIGHT = 34

    def __init__(self, owner, item, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.item = item
        self.setObjectName("skillCard")
        buttons = owner.card_buttons[item["kind"]]
        available = item["kind"] == "community"
        themes.set_style(self, AVAILABLE_CARD_STYLE if available else CARD_STYLE)
        self.install_button = self.delete_button = None
        self.details_button = link_button("View details", lambda checked=False, selected=item: owner.show_details(selected), "View details for " + item["title"])
        layout = QtWidgets.QVBoxLayout(self)
        layout.setContentsMargins(14, 12, 14, 12)
        layout.setSpacing(8)
        title = QtWidgets.QLabel(item["title"])
        title.setTextFormat(Qt.PlainText)
        title.setWordWrap(True)
        title.setMinimumWidth(0)
        title.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        font = title.font()
        font.setBold(True)
        font.setPointSizeF(font.pointSizeF() + 1)
        title.setFont(font)
        layout.addWidget(title)
        layout.addWidget(BadgeFlow(item, self))
        layout.addWidget(ClampLabel(item["description"], 3, "@muted_text" if available else "@field_text"))
        if item.get("notice"):
            notice = QtWidgets.QLabel(item["notice"])
            notice.setTextFormat(Qt.PlainText)
            notice.setWordWrap(True)
            notice.setMinimumWidth(0)
            notice.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
            themes.set_style(notice, "QLabel { font-size:9pt; color:@log_warning; background:transparent; }")
            layout.addWidget(notice)
        layout.addStretch(1)
        actions = QtWidgets.QHBoxLayout()
        actions.setSpacing(12)
        # A built-in card has only the link here; the strut keeps it as tall as a card with a button.
        actions.addStrut(self.ACTION_HEIGHT)
        if available:
            self.install_button = action(owner.client.root, "download", "Install", lambda checked=False, selected=item: owner.install(selected))
            themes.set_style(self.install_button, INSTALL_STYLE)
            buttons.append(self.install_button)
            actions.addWidget(self.install_button)
        actions.addWidget(self.details_button)
        actions.addStretch()
        if item["kind"] == "installed":
            self.delete_button = action(owner.client.root, "trash-2", "Delete Skill", lambda checked=False, selected=item: owner.delete_skill(selected))
            self.delete_button.setToolButtonStyle(Qt.ToolButtonIconOnly)
            themes.set_style(self.delete_button, DESTRUCTIVE_STYLE)
            buttons.append(self.delete_button)
            actions.addWidget(self.delete_button)
        layout.addLayout(actions)
        self.setContextMenuPolicy(Qt.CustomContextMenu)
        self.customContextMenuRequested.connect(lambda position: owner.show_card_menu(self, position))

    def height_for(self, width):
        height = self.heightForWidth(width)
        return max(height if height > 0 else self.sizeHint().height(), self.minimumSizeHint().height())


def item_badges(item, parent=None):
    label, role = {"builtin": ("Built-in", "builtin"), "installed": ("Installed", "installed"), "community": ("Not installed", "available")}[item["kind"]]
    if item["kind"] == "installed" and item["local"].get("state") != "ready":
        label, role = "Needs attention", "attention"
    badges = [MetadataBadge(label, "Status", role, parent)]
    for value, name in ((item["author"], "Author"), (item["version"], "Version")):
        if value:
            badges.append(MetadataBadge(value, name, "plain", parent))
    return badges


class CardGrid(QtWidgets.QWidget):
    """Responsive grid: as many equal columns as fit, every row as tall as its tallest card."""
    MINIMUM_CARD = 280
    GAP = 10
    MAXIMUM_COLUMNS = 4

    def __init__(self):
        super().__init__()
        self.cards = []
        self.columns = 1
        self.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Fixed)
        self.setFixedHeight(0)

    def set_cards(self, cards):
        """Replace the cards; each new card was created with this grid as its parent."""
        for card in self.cards:
            card.hide()
            card.deleteLater()
        self.cards = cards
        for card in cards:
            card.show()

    def arrange(self):
        visible = [card for card in self.cards if not card.isHidden()]
        if not visible:
            self.setFixedHeight(0)
            return
        width = max(1, self.width())
        self.columns = max(1, min(self.MAXIMUM_COLUMNS, (width + self.GAP) // (self.MINIMUM_CARD + self.GAP)))
        card_width = (width - self.GAP * (self.columns - 1)) // self.columns
        top = 0
        for start in range(0, len(visible), self.columns):
            row = visible[start:start + self.columns]
            height = max(card.height_for(card_width) for card in row)
            for index, card in enumerate(row):
                card.setGeometry(index * (card_width + self.GAP), top, card_width, height)
            top += height + self.GAP
        self.setFixedHeight(top - self.GAP)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if event.size().width() != event.oldSize().width():
            self.arrange()


class SectionHeader(QtWidgets.QWidget):
    def __init__(self, title):
        super().__init__()
        row = QtWidgets.QHBoxLayout(self)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)
        self.title = QtWidgets.QLabel(title)
        font = self.title.font()
        font.setBold(True)
        self.title.setFont(font)
        row.addWidget(self.title)
        self.note = QtWidgets.QLabel()
        themes.set_style(self.note, MUTED_STYLE)
        row.addWidget(self.note)
        self.spinner = Spinner()
        row.addWidget(self.spinner)
        line = QtWidgets.QFrame()
        line.setFixedHeight(1)
        themes.set_style(line, "background:@border; border:none;")
        row.addWidget(line, 1)


class SkillDetailsWindow(Window):
    """One reusable window: opening another skill replaces its content instead of adding a window."""
    def __init__(self, client, parent):
        super().__init__(client.root, "Skill Details", parent)
        self.client = client
        self.resize(820, 760)
        self.setMinimumSize(320, 300)
        self.item = None
        self.history = []
        self.current_document = None
        self._restore_scroll = 0
        self.title = QtWidgets.QLabel()
        self.title.setTextFormat(Qt.PlainText)
        self.title.setWordWrap(True)
        self.title.setMinimumWidth(0)
        font = self.title.font()
        font.setBold(True)
        font.setPointSizeF(font.pointSizeF() + 3)
        self.title.setFont(font)
        self.outer.addWidget(self.title)
        self.badge_row = QtWidgets.QVBoxLayout()
        self.badge_row.setContentsMargins(0, 0, 0, 0)
        self.badges = None
        self.outer.addLayout(self.badge_row)
        self.summary = QtWidgets.QLabel()
        self.summary.setTextFormat(Qt.PlainText)
        self.summary.setWordWrap(True)
        self.summary.setMinimumWidth(0)
        self.outer.addWidget(self.summary)
        self.information = QtWidgets.QLabel()
        self.information.setTextFormat(Qt.RichText)
        self.information.setWordWrap(True)
        self.information.setMinimumWidth(0)
        self.information.setOpenExternalLinks(False)
        self.information.linkActivated.connect(self.open_link)
        self.outer.addWidget(self.information)
        navigation = QtWidgets.QHBoxLayout()
        self.back_button = action(client.root, "arrow-left", "Back", self.back)
        navigation.addWidget(self.back_button)
        navigation.addStretch()
        self.outer.addLayout(navigation)
        self.preview = ResponsiveSkillBrowser()
        self.preview.setOpenLinks(False)
        self.preview.setOpenExternalLinks(False)
        self.preview.anchorClicked.connect(self.navigate)
        self.outer.addWidget(self.preview, 1)
        # The shared rotating loader covers only the document while an online description is fetched.
        self.loading_overlay = LoadingOverlay(self.preview)
        self.loading_overlay.setAccessibleName("Loading the online description")
        self.preview.installEventFilter(self)
        # Shown instead of the document when the online description cannot be loaded.
        self.filler = QtWidgets.QWidget()
        self.filler.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Expanding)
        center = QtWidgets.QVBoxLayout(self.filler)
        center.addStretch(1)
        self.fallback = QtWidgets.QLabel()
        self.fallback.setTextFormat(Qt.PlainText)
        self.fallback.setWordWrap(True)
        self.fallback.setAlignment(Qt.AlignHCenter)
        themes.set_style(self.fallback, MUTED_STYLE)
        center.addWidget(self.fallback)
        self.fallback_button = action(client.root, "globe", "Open Online Page", self.open_online)
        center.addWidget(self.fallback_button, 0, Qt.AlignHCenter)
        center.addStretch(1)
        self.outer.addWidget(self.filler, 1)
        self.pages = {}
        self.page_request = None
        self.page_address = ""
        self.note = QtWidgets.QLabel()
        self.note.setTextFormat(Qt.PlainText)
        self.note.setWordWrap(True)
        self.note.setMinimumWidth(0)
        themes.set_style(self.note, MUTED_STYLE)
        self.outer.addWidget(self.note)
        controls = QtWidgets.QHBoxLayout()
        self.folder_button = action(client.root, "folder-open", "Open Folder", self.open_folder)
        self.online_button = action(client.root, "globe", "Open Online Page", self.open_online)
        controls.addWidget(self.folder_button)
        controls.addWidget(self.online_button)
        controls.addStretch()
        controls.addWidget(action(client.root, "close", "Close", self.close))
        self.outer.addLayout(controls)
        self.update_navigation()

    def owner(self):
        return self.client.dialogs.get("skills")

    def set_loading(self, loading):
        self.loading_overlay.setGeometry(self.preview.rect())
        self.loading_overlay.setVisible(loading)
        if loading:
            self.loading_overlay.raise_()

    def eventFilter(self, watched, event):
        if watched is getattr(self, "preview", None) and event.type() == QtCore.QEvent.Resize:
            self.loading_overlay.setGeometry(self.preview.rect())
        return super().eventFilter(watched, event)

    def set_badges(self, badges):
        if self.badges is not None:
            self.badge_row.removeWidget(self.badges)
            self.badges.hide()
            self.badges.setParent(None)
            self.badges.deleteLater()
        self.badges = BadgeFlow(badges, self) if badges else None
        if self.badges is not None:
            self.badge_row.addWidget(self.badges)

    def show_item(self, item):
        self.item = item
        self.history = []
        self.current_document = None
        self._restore_scroll = 0
        local, catalog = item.get("local"), item.get("catalog")
        self.title.setText(item["title"])
        self.set_badges(item)
        self.summary.setText(item["description"])
        self.summary.setVisible(local is None)
        lines = []
        if local is not None:
            kind = "Built-in" if item["kind"] == "builtin" else "Custom"
            status = local.get("state") or "Not specified"
            lines.append("<b>Source:</b> {} &nbsp; <b>Type:</b> {} &nbsp; <b>Status:</b> {}".format(html.escape(local.get("displaySource") or kind), kind, html.escape(status)))
            if local.get("error"):
                lines.append(html.escape(local["error"]))
            from urllib.parse import quote
            contacts = []
            if local.get("website"):
                contacts.append('<b>Website:</b> <a href="{0}" style="color:@support_link">{0}</a>'.format(html.escape(local["website"], quote=True)))
            if local.get("email"):
                contacts.append('<b>Email:</b> <a href="mailto:{}" style="color:@support_link">{}</a>'.format(quote(local["email"], safe=""), html.escape(local["email"])))
            if contacts:
                lines.append(" &nbsp; ".join(contacts))
        else:
            lines.append("<b>Source:</b> Community Skills &nbsp; <b>Status:</b> Not installed")
        if item.get("notice"):
            lines.append(html.escape(item["notice"]))
        themes.set_label(self.information, "<br>".join(lines))
        self.information.show()
        self.folder_button.setVisible(local is not None)
        self.online_button.setVisible(catalog is not None)
        self.preview.clear()
        self.preview.show()
        self.filler.hide()
        self.set_loading(False)
        self.page_request = None
        self.page_address = ""
        self.note.setText("")
        if local is not None:
            self.open_document(local["id"], "SKILL.md")
        elif catalog is not None:
            self.open_page(catalog)
        self.update_navigation()

    # A skill that is not installed has no local files: its published description is shown instead.
    def open_page(self, catalog):
        key = (catalog.get("id", ""), catalog.get("version", ""))
        self.page_request = key
        if key in self.pages:
            self.show_page(self.pages[key])
        elif re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", key[0]) and self.client.page_operation(key[0]):
            self.set_loading(True)
        else:
            self.page_failed(key[0], "")

    def apply_page(self, identifier, helper):
        if self.page_request is None or identifier != self.page_request[0]:
            return  # An answer for a skill that is no longer shown.
        parser = helper.snapshot
        text = decode(parser.get("result", "text", fallback="")) if parser is not None and parser.get("result", "ok", fallback="false") == "true" else ""
        if not text.strip():
            self.page_failed(identifier, decode(parser.get("result", "message", fallback="")) if parser is not None else "")
            return
        self.pages[self.page_request] = text
        self.show_page(text)

    def show_page(self, text):
        self.set_loading(False)
        # The window already shows the title and description; generator comments are not content.
        text = re.sub(r"<!--.*?-->", "", text, flags=re.S).lstrip()
        text = re.sub(r"\A#[ \t]+[^\n]*\n+", "", text, count=1)
        self.page_address = "{}docs/skills/{}.md".format(CATALOG_URL, self.page_request[0])
        self.summary.hide()
        self.filler.hide()
        self.preview.show()
        self.preview.setHtml(render_markdown(text, "SKILL.md"))
        self.preview.verticalScrollBar().setValue(0)
        self.note.setText("Install this skill to read its full instructions here.")

    def page_failed(self, identifier, message):
        if self.page_request is None or identifier != self.page_request[0]:
            return
        self.set_loading(False)
        self.preview.hide()
        self.summary.show()
        # The helper's catalog wording mentions actions this window does not have, so one plain sentence is shown.
        self.fallback.setText("The online description could not be loaded. Check your connection, or open the online page to read about this skill.")
        self.filler.show()
        self.note.setText("")

    def show_report(self, content):
        self.item = None
        self.history = []
        self.current_document = None
        self.title.setText("Import Report")
        self.set_badges(None)
        self.summary.hide()
        self.information.hide()
        self.folder_button.hide()
        self.online_button.hide()
        self.filler.hide()
        self.set_loading(False)
        self.page_request = None
        self.page_address = ""
        self.preview.show()
        self.preview.setHtml(content)
        self.note.setText("")
        self.update_navigation()

    def update_navigation(self):
        self.back_button.setVisible(bool(self.history))

    def open_document(self, identifier, relative):
        if self.current_document:
            self.history.append((self.current_document, self.preview.verticalScrollBar().value()))
        self._restore_scroll = 0
        self.current_document = (identifier, relative)
        self.update_navigation()
        self.request()

    def request(self):
        # The file is on this disk, so it is read and rendered here at once; no helper process and no waiting.
        local = self.item.get("local") if self.item else None
        if local is not None and self.current_document and self.current_document[0] == local.get("id"):
            self.apply_document(*read_skill_document(self.client.root, local, self.current_document[1]))

    def back(self):
        if self.history:
            self.current_document, self._restore_scroll = self.history.pop()
            self.update_navigation()
            self.request()

    def apply_document(self, ok, message, content):
        if not ok:
            self.note.setText(message or "The skill could not be read. Refresh the list and try again.")
            return
        self.preview.setHtml(content)
        self.preview.verticalScrollBar().setValue(self._restore_scroll)
        self.note.setText(message)

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
            owner = self.owner()
            if owner is not None:
                owner.help(url.path() == "submit")
        elif url.scheme() in ("https", "http"):
            QtGui.QDesktopServices.openUrl(url)
        elif self.page_address and not url.scheme():
            # A relative link of the online description opens in the browser, and only inside the catalog site.
            target = QtCore.QUrl(self.page_address).resolved(url)
            if target.toString().startswith(CATALOG_URL):
                QtGui.QDesktopServices.openUrl(target)
        elif self.current_document and not url.scheme():
            from posixpath import normpath, dirname, join
            relative = normpath(join(dirname(self.current_document[1]), url.path()))
            if relative != ".." and not relative.startswith(("../", "/")):
                self.open_document(self.current_document[0], relative)

    def open_link(self, address):
        url = QtCore.QUrl(address)
        if url.scheme() in ("https", "mailto"):
            QtGui.QDesktopServices.openUrl(url)

    def open_folder(self):
        local = self.item.get("local") if self.item else None
        folder = skill_folder(self.client.root, local) if local else None
        if folder is None or not folder.is_dir():
            self.note.setText("The skill folder is no longer available. Refresh the list.")
        elif not QtGui.QDesktopServices.openUrl(QtCore.QUrl.fromLocalFile(str(folder.resolve()))):
            self.note.setText("Could not open the skill folder.")

    def open_online(self):
        catalog = self.item.get("catalog") if self.item else None
        if catalog is not None and re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", catalog.get("id", "")):
            QtGui.QDesktopServices.openUrl(QtCore.QUrl("{}docs/skills/{}.html".format(CATALOG_URL, catalog["id"])))


class SkillsWindow(Window):
    COMPACT_WIDTH = 720
    LONG_OPERATIONS = ("community-install", "community-sync")
    CATALOG_FRESH_SECONDS = 600

    def __init__(self, client, parent):
        super().__init__(client.root, "Skills", parent)
        self.client = client
        self.resize(1180, 820)
        self.setMinimumSize(360, 300)
        self.local = []
        self.community = None
        self.catalog_loading = False
        self.catalog_error = ""
        self.catalog_checked = 0
        self.busy = False
        self._busy_state = (False, "")
        self.queue = []
        self.card_buttons = {"builtin": [], "installed": [], "community": []}
        self.displayed = None
        self.stale = set()
        self.operation_started = None
        self.compact = None
        # Community is always the starting filter; the choice is deliberately not remembered.
        self.category = "community"

        main = self.outer
        top = QtWidgets.QHBoxLayout()
        self.search = QtWidgets.QLineEdit()
        themes.set_style(self.search, SEARCH_STYLE)
        self.search.setPlaceholderText("Search skills, descriptions or authors")
        self.search.setClearButtonEnabled(True)
        self.search.textChanged.connect(self.apply_filter)
        top.addWidget(self.search, 1)
        self.import_folder_button = action(client.root, "folder-open", "Import Folder", self.import_folder)
        self.import_zips_button = action(client.root, "file-archive", "Import ZIPs", self.import_zips)
        self.refresh_button = action(client.root, "refresh-cw", "Refresh", self.refresh)
        self.refresh_button.setToolButtonStyle(Qt.ToolButtonIconOnly)
        for button in (self.import_folder_button, self.import_zips_button, self.refresh_button):
            top.addWidget(button)
        main.addLayout(top)
        chips = QtWidgets.QHBoxLayout()
        chips.setSpacing(6)
        self.navigation = {}
        self.navigation_group = QtWidgets.QButtonGroup(self)
        self.navigation_group.setExclusive(True)
        for key, label in CATEGORIES:
            chip = FilterChip(label)
            chip.setChecked(key == self.category)
            chip.clicked.connect(lambda checked=False, selected=key: self.set_category(selected))
            self.navigation_group.addButton(chip)
            self.navigation[key] = chip
            chips.addWidget(chip)
        chips.addStretch()
        main.addLayout(chips)
        self.status = StatusBanner(client.root)
        main.addWidget(self.status)
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
        progress_row = QtWidgets.QHBoxLayout()
        progress_row.addWidget(self.progress, 1)
        progress_row.addWidget(self.elapsed)
        main.addLayout(progress_row)
        self.progress.hide()
        self.elapsed.hide()

        self.scroll = QtWidgets.QScrollArea()
        self.scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        self.scroll.setWidgetResizable(True)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        # A permanent track keeps the column count stable while cards reflow.
        self.scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOn)
        content = QtWidgets.QWidget()
        self.content_layout = QtWidgets.QVBoxLayout(content)
        self.content_layout.setContentsMargins(0, 0, 8, 0)
        self.content_layout.setSpacing(CardGrid.GAP)
        self.sections = {}
        for key, title in (("installed", "Installed"), ("community", "Not installed"), ("builtin", "Built-in")):
            section = SimpleNamespace(header=SectionHeader(title), hint=QtWidgets.QLabel(), retry=None, hint_row=QtWidgets.QWidget(), grid=CardGrid())
            section.hint.setTextFormat(Qt.PlainText)
            section.hint.setWordWrap(True)
            section.hint.setMinimumWidth(0)
            themes.set_style(section.hint, MUTED_STYLE)
            row = QtWidgets.QHBoxLayout(section.hint_row)
            row.setContentsMargins(0, 0, 0, 0)
            row.addWidget(section.hint, 1)
            if key == "community":
                section.retry = link_button("Retry", self.load_catalog, "Retry loading the community catalog")
                row.addWidget(section.retry)
            for widget in (section.header, section.hint_row, section.grid):
                self.content_layout.addWidget(widget)
            self.sections[key] = section
        self.empty = QtWidgets.QLabel("No skills match your search.")
        themes.set_style(self.empty, MUTED_STYLE)
        self.content_layout.addWidget(self.empty)
        self.content_layout.addStretch(1)
        self.scroll.setWidget(content)
        main.addWidget(self.scroll, 1)
        footer = QtWidgets.QHBoxLayout()
        footer.setSpacing(16)
        online = lambda checked=False: QtGui.QDesktopServices.openUrl(QtCore.QUrl(CATALOG_URL))
        # Text links when they fit; the same three actions as icons in a narrow window.
        self.footer_links, self.footer_buttons = [], []
        for symbol, label, callback in (("circle-question-mark", "How to Create and Import Skills", lambda checked=False: self.help(False)),
                                        ("send", "Submit Your Skill", lambda checked=False: self.help(True)), ("globe", "Open Online Catalog", online)):
            link = link_button(label, callback)
            button = action(client.root, symbol, label, callback)
            button.setToolButtonStyle(Qt.ToolButtonIconOnly)
            self.footer_links.append(link)
            self.footer_buttons.append(button)
            footer.addWidget(link)
            footer.addWidget(button)
        footer.addStretch()
        self.donate_button = donate_action(client.root, client.donate)
        footer.addWidget(self.donate_button)
        main.addLayout(footer)
        self.load_cache()
        # Built-in and installed skills are on this disk, so they are shown without waiting for a helper.
        self.local = read_local_skills(client.root)
        self.rebuild()

    # The saved catalog makes Community visible at once; fresh data replaces it in the background.
    def cache_path(self):
        directory = getattr(self.client, "state_directory", None)
        return Path(directory) / "skills-cache.json" if directory else None

    def load_cache(self):
        location = self.cache_path()
        try:
            document = json.loads(location.read_text(encoding="utf-8")) if location else {}
        except (OSError, ValueError):
            return
        community = document.get("community") if isinstance(document, dict) else None
        if isinstance(community, list) and all(isinstance(entry, dict) and isinstance(entry.get("name"), str) and isinstance(entry.get("id"), str) for entry in community):
            self.community = community
            checked = document.get("checked")
            self.catalog_checked = checked if isinstance(checked, (int, float)) and checked <= time.time() else 0

    def save_cache(self):
        location = self.cache_path()
        if location is None:
            return
        try:
            temporary = location.with_name(location.name + "." + uuid.uuid4().hex + ".tmp")
            temporary.write_text(json.dumps({"community": self.community, "checked": self.catalog_checked}), encoding="utf-8")
            os.replace(str(temporary), str(location))
        except OSError:
            pass

    # Operations
    def present(self):
        """Called whenever the window is opened: start on Community with current local skills at once."""
        self.navigation["community"].setChecked(True)
        self.set_category("community")
        self.set_status("")
        self.reload_local()
        # A catalog checked a few minutes ago is not requested again on every opening; Refresh always asks.
        if self.community is None or time.time() - self.catalog_checked > self.CATALOG_FRESH_SECONDS:
            # Ask after the window has painted, so starting that helper never delays it.
            QtCore.QTimer.singleShot(0, self.load_catalog)

    def reload_local(self):
        # Local skills are read straight from disk; no helper process is involved, so this is immediate.
        self.local = read_local_skills(self.client.root)
        self.refresh_cards()

    def refresh(self):
        self.reload_local()
        self.load_catalog()

    def load_catalog(self):
        if self.client.catalog_operation():
            self.catalog_loading = True
            self.catalog_error = ""
            self.apply_filter()

    def run(self, operation, arguments=None, status="", temporary=None):
        """Start an operation now, or keep it for the moment the running helper finishes."""
        if self.client.skills_operation(operation, arguments):
            helper = getattr(self.client, "skills_helper", None)
            if temporary and helper is not None:
                helper.temporary_files.extend(temporary)
            if status:
                self.set_status(status)
            self.set_busy(True)
            return True
        if operation == "community-sync":
            self.queue = [entry for entry in self.queue if entry[0] != operation]
        self.queue.append((operation, arguments, status, temporary))
        return False

    def operation_finished(self):
        if self.queue:
            operation, arguments, status, temporary = self.queue.pop(0)
            self.run(operation, arguments, status, temporary)

    def operation_failed(self, message):
        self.set_status(message, "error")

    def set_status(self, message, kind="info"):
        self.status.show_message(message, kind)

    @staticmethod
    def result_kind(succeeded, message):
        if not succeeded:
            return "error"
        return "warning" if re.search(r"incomplete|Not updated|, [1-9]\d* failed", message) else "success"

    def set_busy(self, busy):
        operation = getattr(self.client, "skills_operation_name", "") if busy else ""
        if (busy, operation) == self._busy_state:
            return
        self._busy_state = (busy, operation)
        self.busy = busy
        long_running = busy and operation in self.LONG_OPERATIONS
        if long_running and self.operation_started is None:
            self.progress.setRange(0, 0)
            self.operation_started = time.monotonic()
            self.elapsed.setText("0 s")
            self.elapsed_timer.start()
        elif not long_running:
            self.elapsed_timer.stop()
            self.operation_started = None
        self.progress.setVisible(long_running)
        self.elapsed.setVisible(long_running)
        self.update_buttons()

    def update_buttons(self):
        for button in [self.refresh_button, self.import_folder_button, self.import_zips_button] + [button for group in self.card_buttons.values() for button in group]:
            button.setEnabled(not self.busy)

    def update_elapsed(self):
        if self.operation_started is not None:
            self.elapsed.setText("{} s".format(max(0, int(time.monotonic() - self.operation_started))))

    def show_progress(self, state):
        if not isinstance(state, dict) or self.operation_started is None:
            return
        phase = state.get('phase')
        received, total = state.get('bytes', 0), state.get('total')
        if phase == 'download' and isinstance(received, int) and received >= 0:
            if isinstance(total, int) and 0 < total <= 50 * 1024 * 1024:
                self.progress.setRange(0, total)
                self.progress.setValue(min(received, total))
                self.set_status('Downloading: {:,} / {:,} bytes ({}%)'.format(received, total, min(received * 100 // total, 100)))
            else:
                self.progress.setRange(0, 0)
                self.set_status('Downloading: {:,} bytes'.format(received))
        elif phase in ('catalog', 'verify', 'install'):
            self.progress.setRange(0, 0)
            self.set_status({'catalog': 'Checking the community catalog...', 'verify': 'Verifying archive checksum and contents...', 'install': 'Installing skill and registering clients...'}[phase])

    def apply_result(self, helper):
        operation = getattr(self.client, "skills_operation_name", "")
        parser = helper.snapshot
        if parser is None:
            self.operation_failed("Skills helper did not return a result.")
            return
        succeeded = parser.get("result", "ok", fallback="false") == "true"
        message = decode(parser.get("result", "message", fallback=""))
        changed = False
        if parser.get("result", "haslist", fallback="false") == "true":
            self.local = [{field: decode(parser.get("skill" + str(index), field, fallback="")) for field in LOCAL_FIELDS} for index in range(parser.getint("result", "count", fallback=0))]
            changed = True
        if parser.has_option("result", "community"):
            try:
                self.community = json.loads(decode(parser.get("result", "community")))
                self.catalog_error = ""
                self.catalog_checked = time.time()
                changed = True
            except ValueError:
                pass
        if changed:
            self.save_cache()
            self.refresh_cards()
        document = Path(str(helper.result) + ".html")
        if operation in ("add-folder", "add-zips") and document.exists() and (not succeeded or re.search(r", [1-9]\d* failed\.$", message)):
            self.client.show_dialog("skill_details", SkillDetailsWindow).show_report(document.read_text(encoding="utf-8-sig"))
        if operation != "list":
            self.set_status(message, self.result_kind(succeeded, message))

    def apply_catalog(self, helper):
        parser = helper.snapshot
        if parser is None or parser.get("result", "ok", fallback="false") != "true" or not parser.has_option("result", "community"):
            self.catalog_failed(decode(parser.get("result", "message", fallback="")) if parser else "")
            return
        try:
            self.community = json.loads(decode(parser.get("result", "community")))
        except ValueError:
            self.catalog_failed("The catalog response could not be read.")
            return
        self.catalog_loading = False
        self.catalog_error = ""
        self.catalog_checked = time.time()
        self.save_cache()
        self.refresh_cards()
        # A newer catalog version replaces an installed community copy without a click.
        if any(self.updatable(entry) for entry in self.community):
            self.run("community-sync", None, "Updating installed community skills...")

    def catalog_failed(self, message):
        self.catalog_loading = False
        self.catalog_error = message or "The community catalog could not be loaded. Retry, or use Open Online Catalog to download and import a skill manually."
        if self.community:
            self.catalog_error += " The saved list is shown."
        self.apply_filter()

    def installed_copy(self, entry):
        return next((skill for skill in self.local if skill["source"] == "Custom" and skill["name"] == entry.get("name")), None)

    def owned(self, entry, local):
        return local["displaySource"] == "Community Skills" and local["title"] == entry.get("title") and local["author"] == entry.get("author")

    def updatable(self, entry):
        local = self.installed_copy(entry)
        return local is not None and local["state"] == "ready" and self.owned(entry, local) and newer_version(entry.get("version"), local["version"])

    # Cards
    def items(self):
        catalog = {entry.get("name"): entry for entry in self.community or []}
        groups = {"builtin": [], "installed": [], "community": []}
        for skill in self.local:
            kind = "builtin" if skill["source"] == "Built-in" else "installed"
            entry = catalog.get(skill["name"]) if kind == "installed" else None
            notice = ""
            if entry is not None and newer_version(entry.get("version"), skill["version"]):
                notice = "Version {} is available in Community.".format(entry["version"])
                if not self.owned(entry, skill):
                    notice += " Your local copy is not overwritten."
            if kind == "installed" and skill["state"] != "ready" and skill["error"]:
                notice = skill["error"]
            groups[kind].append(self.item(kind, skill["title"] or skill["name"], skill["author"], skill["version"], skill["displayDescription"] or skill["description"], skill, entry, notice))
        installed = {skill["name"] for skill in self.local if skill["source"] == "Custom"}
        for entry in self.community or []:
            if entry.get("name") not in installed:
                groups["community"].append(self.item("community", entry.get("title", ""), entry.get("author", ""), entry.get("version", ""), entry.get("description", ""), None, entry, ""))
        for group in groups.values():
            group.sort(key=lambda item: item["title"].casefold())
        return groups

    def item(self, kind, title, author, version, description, local, catalog, notice):
        return {"kind": kind, "title": title, "author": author, "version": version, "description": description, "local": local, "catalog": catalog, "notice": notice,
                "search": " ".join((title, author, description)).lower()}

    def signature(self):
        """What the cards display; an answer that changes nothing here must not rebuild them."""
        shown = [[skill[field] for field in LOCAL_FIELDS if field != "revision"] for skill in self.local]
        return json.dumps([shown, self.community], sort_keys=True)

    def refresh_cards(self):
        if self.signature() == self.displayed:
            self.apply_filter()
        else:
            self.rebuild()

    def rebuild(self):
        position = self.scroll.verticalScrollBar().value()
        self.displayed = self.signature()
        self.groups = self.items()
        self.counts = {key: len(self.groups[key]) for key in self.groups}
        # Cards are built per section when it is first shown, so opening never pays for the hidden filter.
        self.stale = set(self.sections)
        # A counter appears only once its list is known, never as a misleading zero.
        self.navigation["builtin"].set_count(self.counts["builtin"])
        self.navigation["community"].set_count(self.counts["installed"] + self.counts["community"] if self.community is not None else None)
        self.apply_filter()
        QtCore.QTimer.singleShot(0, lambda: self.scroll.verticalScrollBar().setValue(position))

    def ensure_cards(self, key):
        if key in self.stale:
            self.stale.discard(key)
            self.card_buttons[key] = []
            grid = self.sections[key].grid
            grid.set_cards([SkillCard(self, item, grid) for item in self.groups[key]])
            self.update_buttons()
        return self.sections[key].grid.cards

    def set_category(self, category):
        self.category = category
        self.apply_filter()
        self.scroll.verticalScrollBar().setValue(0)

    def section_hint(self, key):
        if key == "builtin":
            return ""
        if key == "installed":
            return "" if self.counts["installed"] else "No skills are installed yet. Install one below, or use Import Folder or Import ZIPs."
        if self.catalog_error:
            return self.catalog_error
        if self.community is None:
            return "Loading the community catalog..."
        return "" if self.counts["community"] else "Every published community skill is already installed."

    def apply_filter(self):
        query = self.search.text().strip().lower()
        matches = 0
        for key, section in self.sections.items():
            # Community holds installed skills first, then the ones that are not installed. A search looks everywhere.
            selected = bool(query) or (key == "builtin") == (self.category == "builtin")
            shown = 0
            for card in self.ensure_cards(key) if selected else section.grid.cards:
                visible = selected and (not query or query in card.item["search"])
                card.setVisible(visible)
                shown += 1 if visible else 0
            section.grid.arrange()
            hint = self.section_hint(key) if selected and not query else ""
            section.hint.setText(hint)
            section.hint_row.setVisible(bool(hint))
            if section.retry is not None:
                section.retry.setVisible(bool(self.catalog_error) and not self.catalog_loading)
            # The Built-in chip already names its only group; its heading appears just in search results.
            section.header.setVisible(selected and (shown > 0 or bool(hint)) and (key != "builtin" or bool(query)))
            section.grid.setVisible(shown > 0)
            matches += shown
            known = key != "community" or self.community is not None
            section.header.note.setText(str(shown if query else self.counts[key]) if known else "")
            if key == "community":
                section.header.spinner.setVisible(self.catalog_loading)
        self.empty.setVisible(bool(query) and matches == 0)

    def fit_layout(self):
        compact = self.width() < self.COMPACT_WIDTH
        for button in (self.import_folder_button, self.import_zips_button):
            button.setToolButtonStyle(Qt.ToolButtonIconOnly if compact else Qt.ToolButtonTextBesideIcon)
        for link, button in zip(self.footer_links, self.footer_buttons):
            link.setVisible(not compact)
            button.setVisible(compact)
        for chip in self.navigation.values():
            chip.set_compact(compact)
        self.compact = compact

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if (self.width() < self.COMPACT_WIDTH) != self.compact:
            self.fit_layout()

    def showEvent(self, event):
        super().showEvent(event)
        self.fit_layout()

    # Card actions
    def install(self, item):
        entry = item["catalog"]
        self.run("community-install", ["-SkillId", entry["id"], "-Source", entry["version"], "-Revision", entry["sha256"]], "Downloading, verifying and importing " + item["title"] + "...")

    def delete_skill(self, item):
        local = item.get("local")
        if self.busy or local is None or local["source"] != "Custom":
            return
        if QtWidgets.QMessageBox.question(self, "Delete skill", "Delete this imported skill and its owned discovery adapters?") == QtWidgets.QMessageBox.Yes:
            self.run("delete", ["-SkillId", local["id"]], "Deleting " + item["title"] + "...")

    def show_details(self, item):
        self.client.show_dialog("skill_details", SkillDetailsWindow).show_item(item)

    def open_skill_folder(self, item):
        folder = skill_folder(self.client.root, item["local"])
        if folder is None or not folder.is_dir():
            self.set_status("The skill folder is no longer available. Refresh the list.", "warning")
        elif not QtGui.QDesktopServices.openUrl(QtCore.QUrl.fromLocalFile(str(folder.resolve()))):
            self.set_status("Could not open the skill folder.", "warning")

    def card_menu(self, item):
        menu = SkillsMenu(self)
        details = menu.addAction(icon(self.client.root, "book-open"), "View details")
        details.setIconVisibleInMenu(True)
        details.triggered.connect(lambda: self.show_details(item))
        if item["local"] is not None:
            folder = menu.addAction(icon(self.client.root, "folder-open"), "Open folder")
            folder.setIconVisibleInMenu(True)
            folder.triggered.connect(lambda: self.open_skill_folder(item))
        if item["kind"] == "installed":
            menu.addSeparator()
            delete = menu.addAction(icon(self.client.root, "trash-2"), "Delete")
            delete.setProperty("destructive", True)
            delete.setIconVisibleInMenu(True)
            delete.setEnabled(not self.busy)
            delete.triggered.connect(lambda: self.delete_skill(item))
        return menu

    def show_card_menu(self, card, position):
        # A refresh may replace the card while QMenu runs its nested event loop.
        item, target = card.item, card.mapToGlobal(position)
        menu = self.card_menu(item)
        try:
            menu.exec_(target)
        finally:
            menu.deleteLater()

    def import_folder(self):
        folder = QtWidgets.QFileDialog.getExistingDirectory(self, "Import instruction-only skill")
        if folder:
            self.run("add-folder", ["-Source", folder], "Importing skill...")

    def import_zips(self):
        files, _ = QtWidgets.QFileDialog.getOpenFileNames(self, "Import instruction-only skills", "", "ZIP (*.zip)")
        if files:
            selection = self.client.state_directory / ("zip-selection-" + uuid.uuid4().hex + ".txt")
            selection.write_text("\n".join(files), encoding="utf-8")
            self.run("add-zips", ["-Source", str(selection)], "Importing skills...", [selection])

    def help(self, submit):
        self.client.show_dialog("skill_help_submit" if submit else "skill_help_create",
                                lambda client, parent: SkillHelpWindow(client, parent, submit=submit))
