# Responsive Qt windows, accessible SVG actions, and paged activity history.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from collections import OrderedDict
from html import escape
from pathlib import Path
import random
import weakref

from . import themes
from .qt import QtCore, QtGui, QtWidgets, QtSvg, Qt, enable_window_shadow

COLORS = {"info": "@log_info", "system": "@log_system", "success": "@log_success", "warning": "@log_warning", "error": "@log_error", "support": "@support_link", "debug": "@log_debug"}
DONATE_STYLE = "QToolButton { background:@donate_background; border-color:@donate_border; } QToolButton:hover { background:@donate_hover; }"
DESTRUCTIVE_STYLE = "QToolButton { background:@delete_background; color:@delete_text; border-color:@delete_border; } QToolButton:hover { background:@delete_hover; border-color:@delete_border; } QToolButton:pressed { background:@delete_pressed; border-color:@delete_border; } QToolButton:disabled { background:@button_background; color:@disabled_text; border-color:@border; }"
STYLE = """
QWidget { background: @window_background; color: @text; font-family: 'Segoe UI'; font-size: 11pt; }
QDialog { border: 1px solid @border; }
QToolButton, QPushButton { background: @button_background; border: 1px solid @border; border-radius: 4px; padding: 4px; min-height: 20px; }
QToolButton:hover, QPushButton:hover { background: @button_hover; border-color: @accent; }
QToolButton:focus, QPushButton:focus, QLineEdit:focus { border: 1px solid @focus_border; }
QToolButton:disabled, QPushButton:disabled { color: @disabled_text; border-color: @disabled_border; }
QLineEdit, QPlainTextEdit, QTextBrowser, QTableView, QTreeWidget, QListWidget, QComboBox { background: @field_background; border: 1px solid @field_border; padding: 3px; selection-background-color: @selection_background; }
QTreeWidget::item { padding: 3px; }
QTreeWidget::item:selected { background: @selection_background; color: @selected_text; }
QTreeWidget::item:selected { background: @selection_background; color: @selected_text; }
QHeaderView::section { background: @button_background; padding: 4px; border: none; }
QTableView::item:selected, QListWidget::item:selected { background: @selection_background; color: @list_selected_text; }
QTableView#activityJournal { background: @journal_background; border: 1px solid @journal_border; border-radius: 8px; }
QTextBrowser#setupJournal { border-radius:5px; }
QScrollBar:vertical { width:13px; background:@recessed_background; border:none; border-radius:6px; margin:0; }
QScrollBar:horizontal { height:13px; background:@recessed_background; border:none; border-radius:6px; margin:0; }
QScrollBar::handle:vertical { background:@scrollbar_thumb; min-height:24px; border-radius:4px; margin:2px; }
QScrollBar::handle:horizontal { background:@scrollbar_thumb; min-width:24px; border-radius:4px; margin:2px; }
QScrollBar::handle:hover { background:@scrollbar_hover; }
QScrollBar::handle:pressed { background:@text; }
QScrollBar::add-page, QScrollBar::sub-page { background:none; border:none; }
QScrollBar::add-line, QScrollBar::sub-line { background:none; border:none; width:0; height:0; }
QScrollBar::up-arrow, QScrollBar::down-arrow, QScrollBar::left-arrow, QScrollBar::right-arrow { image:none; width:0; height:0; }
QWidget#qt_scrollarea_vcontainer, QWidget#qt_scrollarea_hcontainer { background:transparent; border:none; }
QAbstractScrollArea::corner { background:transparent; border:none; }
QProgressBar { background:@recessed_background; border:1px solid @border; border-radius:6px; min-height:10px; max-height:10px; padding:0; text-align:center; }
QProgressBar::chunk { background:@accent; border-radius:5px; }
QMessageBox QPushButton { min-width:76px; min-height:24px; padding:6px 12px; margin-left:5px; margin-right:5px; }
QTabWidget::pane { border: 1px solid @active_border; border-radius: 5px; top: -1px; background: @tab_pane_background; }
QTabBar::tab { padding: 8px 12px; margin-right: 4px; margin-top: 3px; border: 1px solid @tab_border; border-bottom: 1px solid @active_border; border-top-left-radius: 4px; border-top-right-radius: 4px; background: @tab_background; color: @muted_text; }
QTabBar::tab:selected { color: @heading_text; background: @active_tab_background; border: 1px solid @active_border; border-bottom-color: @active_tab_background; margin-top: 0; padding-top: 11px; }
QTabBar::tab:hover { color: @selected_text; }
QToolTip { color: @tooltip_text; background: @tooltip_background; border: 1px solid @active_border; }
QToolButton[ultraCompact="true"], QPushButton[ultraCompact="true"] { font-size:9pt; min-height:0; padding:1px; border-radius:3px; }
QToolButton[largeControls="true"], QPushButton[largeControls="true"] { font-size:14pt; padding:6px; }
QLineEdit[largeControls="true"], QComboBox[largeControls="true"] { font-size:14pt; padding:5px; }
QScrollBar[largeControls="true"]:vertical { width:17px; }
QScrollBar[largeControls="true"]:horizontal { height:17px; }
QToolButton[extraLargeControls="true"], QPushButton[extraLargeControls="true"] { font-size:18pt; padding:8px; }
QLineEdit[extraLargeControls="true"], QComboBox[extraLargeControls="true"] { font-size:18pt; padding:7px; }
QScrollBar[extraLargeControls="true"]:vertical { width:21px; }
QScrollBar[extraLargeControls="true"]:horizontal { height:21px; }
QScrollBar[scrollDensity="compact"]:vertical { width:9px; border-radius:4px; }
QScrollBar[scrollDensity="compact"]:horizontal { height:9px; border-radius:4px; }
QScrollBar[scrollDensity="tiny"]:vertical { width:7px; border-radius:3px; }
QScrollBar[scrollDensity="tiny"]:horizontal { height:7px; border-radius:3px; }
QScrollBar[scrollDensity="compact"]::handle, QScrollBar[scrollDensity="tiny"]::handle { margin:1px; border-radius:2px; }
QSlider::groove:horizontal { height:6px; background:@recessed_background; border-radius:3px; }
QSlider::sub-page:horizontal { background:@accent; border-radius:3px; }
QSlider::handle:horizontal { width:14px; margin:-5px 0; background:@text; border:1px solid @active_border; border-radius:7px; }
"""


class OverflowLabel(QtWidgets.QLabel):
    """Scroll overflowing context without restarting on identical status polls."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTextFormat(Qt.PlainText)
        self._offset = 0.0
        self._limit = 0
        self._pause = 1200
        self._clock = QtCore.QElapsedTimer()
        self._timer = QtCore.QTimer(self)
        self._timer.setInterval(40)
        self._timer.timeout.connect(self.advance)

    def setText(self, text):
        if text == self.text():
            return
        super().setText(text)
        self.setToolTip(text)
        self.reset_scroll()

    def reset_scroll(self):
        self._offset = 0.0
        self._pause = 1200
        self._limit = max(0, self.fontMetrics().horizontalAdvance(self.text()) - self.contentsRect().width())
        self._timer.stop()
        if self._limit and self.isVisible():
            self._clock.start()
            self._timer.start()
        self.update()

    def advance(self):
        elapsed = min(100, self._clock.restart())
        if self._pause > 0:
            self._pause -= elapsed
            return
        if self._offset >= self._limit:
            self._offset = 0.0
            self._pause = 1200
        else:
            self._offset = min(self._limit, self._offset + elapsed * 0.025)
            if self._offset >= self._limit:
                self._pause = 1200
        self.update()

    def paintEvent(self, event):
        if not self._limit:
            return super().paintEvent(event)
        painter = QtGui.QPainter(self)
        painter.setClipRect(self.contentsRect())
        painter.setPen(self.palette().color(QtGui.QPalette.WindowText))
        rectangle = self.contentsRect().adjusted(-int(self._offset), 0, self._limit, 0)
        painter.drawText(rectangle, Qt.AlignLeft | Qt.AlignVCenter | Qt.TextSingleLine, self.text())

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.reset_scroll()

    def changeEvent(self, event):
        super().changeEvent(event)
        if event.type() == QtCore.QEvent.FontChange and hasattr(self, "_timer"):
            self.reset_scroll()

    def showEvent(self, event):
        super().showEvent(event)
        self.reset_scroll()

    def hideEvent(self, event):
        self._timer.stop()
        super().hideEvent(event)


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
        themes.set_label(self, '<a href="{}" style="color:@support_link">{}</a>'.format(escape(url, quote=True), escape(label)))
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


class PillProgressBar(QtWidgets.QProgressBar):
    """One clipped, antialiased track and fill for both Qt bindings."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self._phase = 0
        self._animation = QtCore.QTimer(self)
        self._animation.setInterval(40)
        self._animation.timeout.connect(self.advance)
        self.setFixedHeight(12)

    def setFixedHeight(self, height):
        # QSS min/max dimensions override QWidget constraints during polish.
        themes.set_style(self, "QProgressBar { background:transparent; border:none; padding:0; min-height:%dpx; max-height:%dpx; }" % (height, height))
        super().setFixedHeight(height)

    def sync_animation(self):
        if self.isVisible() and self.minimum() == self.maximum() == 0:
            self._animation.start()
        else:
            self._animation.stop()
        self.update()

    def setRange(self, minimum, maximum):
        super().setRange(minimum, maximum)
        self.sync_animation()

    def setMinimum(self, value):
        super().setMinimum(value)
        self.sync_animation()

    def setMaximum(self, value):
        super().setMaximum(value)
        self.sync_animation()

    def showEvent(self, event):
        super().showEvent(event)
        self.sync_animation()

    def hideEvent(self, event):
        self._animation.stop()
        super().hideEvent(event)

    def advance(self):
        self._phase = (self._phase + 1) % 80
        self.update()

    def paintEvent(self, event):
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing)
        track = QtCore.QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        painter.setPen(QtGui.QPen(QtGui.QColor(themes.style('@border')), 1))
        painter.setBrush(QtGui.QColor(themes.style('@recessed_background')))
        painter.drawRoundedRect(track, track.height() / 2, track.height() / 2)
        inner = track.adjusted(0.5, 0.5, -0.5, -0.5)
        if inner.width() <= 0 or inner.height() <= 0:
            return
        clip = QtGui.QPainterPath()
        clip.addRoundedRect(inner, inner.height() / 2, inner.height() / 2)
        painter.setClipPath(clip)
        fill = QtCore.QRectF(inner)
        if self.minimum() == self.maximum() == 0:
            fill.setWidth(max(inner.height(), inner.width() * 0.28))
            offset = 1 - abs(self._phase / 40.0 - 1)
            fill.moveLeft(inner.left() + (inner.width() - fill.width()) * offset)
        else:
            fraction = max(0, min(1, (self.value() - self.minimum()) / max(1, self.maximum() - self.minimum())))
            fill.setWidth(inner.width() * fraction)
        if self.invertedAppearance() != (self.layoutDirection() == Qt.RightToLeft):
            fill.moveRight(inner.right() - (fill.left() - inner.left()))
        painter.setPen(Qt.NoPen)
        painter.setBrush(QtGui.QColor(themes.style('@accent' if self.isEnabled() else '@disabled_text')))
        radius = min(fill.height(), fill.width()) / 2
        painter.drawRoundedRect(fill, radius, radius)
        if self.isTextVisible() and self.maximum() != self.minimum():
            painter.setPen(QtGui.QColor(themes.style('@field_text')))
            painter.drawText(self.rect(), Qt.AlignCenter, self.text())


def icon(root, name):
    return QtGui.QIcon(str(Path(root) / "assets" / "icons" / (name + ".svg")))


class ActionButton(QtWidgets.QToolButton):
    def minimumSizeHint(self):
        size = super().minimumSizeHint()
        if getattr(self, 'elidable_caption', False):
            size.setWidth(self.iconSize().width() + self.fontMetrics().horizontalAdvance('...') + 24)
        return size

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setCursor(Qt.PointingHandCursor if self.isEnabled() else Qt.ArrowCursor)

    def changeEvent(self, event):
        super().changeEvent(event)
        if event.type() == QtCore.QEvent.EnabledChange:
            self.setCursor(Qt.PointingHandCursor if self.isEnabled() else Qt.ArrowCursor)

    def sizeHint(self):
        size = super().sizeHint()
        if self.toolButtonStyle() == Qt.ToolButtonIconOnly:
            # Point-sized fonts can grow independently of logical icon pixels
            # under Max's high-DPI settings. Reserve the same content height as
            # a labelled action, including the current style's padding/border.
            option = QtWidgets.QStyleOptionToolButton()
            self.initStyleOption(option)
            content = QtCore.QSize(self.iconSize().width(), max(self.iconSize().height(), self.fontMetrics().height()))
            styled = self.style().sizeFromContents(QtWidgets.QStyle.CT_ToolButton, option, content, self)
            edge = max(size.width(), size.height(), styled.height())
            return QtCore.QSize(edge, edge)
        return size

    def paint_glyph(self, painter, glyph, rectangle, renderer=None):
        mode = QtGui.QIcon.Normal if self.isEnabled() else QtGui.QIcon.Disabled
        ratio = self.devicePixelRatioF()
        size = QtCore.QSize(max(1, round(rectangle.width() * ratio)), max(1, round(rectangle.height() * ratio)))
        if renderer is None:
            pixmap = glyph.pixmap(size, mode)
        else:
            pixmap = QtGui.QPixmap(size)
            pixmap.fill(Qt.transparent)
            vector_painter = QtGui.QPainter(pixmap)
            renderer.render(vector_painter, QtCore.QRectF(0, 0, size.width(), size.height()))
            vector_painter.end()
        if pixmap.isNull():
            return
        tint = QtGui.QPainter(pixmap)
        tint.setCompositionMode(QtGui.QPainter.CompositionMode_SourceIn)
        group = QtGui.QPalette.Active if self.isEnabled() else QtGui.QPalette.Disabled
        tint.fillRect(pixmap.rect(), self.palette().color(group, QtGui.QPalette.ButtonText))
        tint.end()
        pixmap.setDevicePixelRatio(ratio)
        painter.drawPixmap(rectangle, pixmap)

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
            self.paint_glyph(painter, glyph, QtCore.QRect((self.width() - edge) // 2, (self.height() - edge) // 2, edge, edge), close_svg)
            return
        edge = min(self.iconSize().width(), max(0, self.height() - 4))
        caption = self.text() if self.toolButtonStyle() != Qt.ToolButtonIconOnly else ""
        if self.toolButtonStyle() == Qt.ToolButtonTextUnderIcon:
            metrics = self.fontMetrics()
            caption = metrics.elidedText(caption, Qt.ElideRight, self.width() - 16)
            top = max(4, (self.height() - edge - metrics.height() - 10) // 2)
            self.paint_glyph(painter, glyph, QtCore.QRect((self.width() - edge) // 2, top, edge, edge))
            painter.setPen(option.palette.color(QtGui.QPalette.Active if self.isEnabled() else QtGui.QPalette.Disabled, QtGui.QPalette.ButtonText))
            painter.drawText(QtCore.QRect(8, top + edge + 10, self.width() - 16, metrics.height()), Qt.AlignCenter, caption)
            return
        gap = 5 if caption else 0
        available = max(0, self.width() - 12 - edge - gap)
        caption = self.fontMetrics().elidedText(caption, Qt.ElideRight, available)
        gap = 5 if caption else 0
        total = edge + gap + self.fontMetrics().horizontalAdvance(caption)
        x = max(0 if not caption else 2, (self.width() - total) // 2)
        rectangle = QtCore.QRect(x, (self.height() - edge) // 2, edge, edge)
        self.paint_glyph(painter, glyph, rectangle)
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
    themes.set_style(button, DONATE_STYLE)
    return button


def copy_action(root, label, text):
    """Copy the current value and give consistent, restartable feedback."""
    button = action(root, "copy", label, lambda: None)
    original_icon = QtGui.QIcon(button.icon())
    check_icon = icon(root, "check")
    timer = QtCore.QTimer(button)
    timer.setSingleShot(True)
    timer.setInterval(2000)

    def reset():
        button.setText(label)
        button.setAccessibleName(label)
        button.setIcon(original_icon)

    def copy():
        QtWidgets.QApplication.clipboard().setText(text() if callable(text) else text)
        button.setText("Copied")
        button.setAccessibleName("Copied")
        button.setIcon(check_icon)
        timer.start()

    timer.timeout.connect(reset)
    button.clicked.connect(copy)
    button.copy_reset = timer
    return button


def configure_close_icon(button, root):
    previous = getattr(button, "close_svg", None)
    if previous is not None:
        previous.deleteLater()
    button.close_svg = QtSvg.QSvgRenderer(str(Path(root) / "assets/icons/close.svg"), button)
    button.setIconSize(QtCore.QSize(14, 14))
    button.update()


class JoinedTabBar(QtWidgets.QTabBar):
    def __init__(self, parent=None):
        super().__init__(parent)
        # The native standalone tab-bar base adds a second frame in Max's style.
        # Our paintEvent supplies the shared baseline instead.
        self.setDrawBase(False)
        self.setMouseTracking(True)

    def mouseMoveEvent(self, event):
        index = self.tabAt(event.pos())
        self.setCursor(Qt.PointingHandCursor if index >= 0 and self.isTabEnabled(index) else Qt.ArrowCursor)
        super().mouseMoveEvent(event)

    def paintEvent(self, event):
        super().paintEvent(event)
        painter = QtGui.QPainter(self)
        painter.setPen(QtGui.QColor(themes.style('@active_border')))
        selected = self.tabRect(self.currentIndex())
        y = self.height() - 1
        # The 4 px trailing tab margin belongs to the continuous baseline too.
        if selected.isValid():
            painter.drawLine(0, y, selected.left(), y)
            painter.drawLine(selected.right() - 4, y, self.width() - 1, y)
        else:
            painter.drawLine(0, y, self.width() - 1, y)
        painter.end()


class TabHeading(QtWidgets.QWidget):
    """Continue a standalone tab bar's baseline across its adjacent controls."""
    def __init__(self, tabs):
        super().__init__()
        self.tabs = tabs

    def paintEvent(self, event):
        super().paintEvent(event)
        origin = self.tabs.mapTo(self, QtCore.QPoint(0, 0))
        painter = QtGui.QPainter(self)
        painter.setPen(QtGui.QColor(themes.style('@active_border')))
        y = origin.y() + self.tabs.height() - 1
        painter.drawLine(origin.x() + self.tabs.width(), y, self.width() - 1, y)
        painter.end()


class Window(QtWidgets.QDialog):
    _windows = weakref.WeakSet()
    _dimmed = weakref.WeakKeyDictionary()
    _opacity_owner = None

    def __init__(self, root, title, parent):
        super().__init__(parent, Qt.Tool | Qt.FramelessWindowHint)
        Window._windows.add(self)
        self.setWindowTitle(title)
        themes.set_style(self, STYLE)
        self.setSizeGripEnabled(True)
        self.setAttribute(Qt.WA_DeleteOnClose, False)
        self._drag = None
        self.outer = QtWidgets.QVBoxLayout(self)
        self.outer.setContentsMargins(8, 6, 8, 6)
        self.outer.setSpacing(6)
        self.header = QtWidgets.QWidget()
        self.header.setObjectName("windowHeader")
        heading = QtWidgets.QHBoxLayout(self.header)
        heading.setContentsMargins(0, 0, 0, 0)
        self.caption = QtWidgets.QLabel(title)
        self.caption.setMinimumWidth(0)
        self.caption.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        themes.set_style(self.caption, "font-size: 12pt; font-weight: 600; color: @heading_text; background:transparent")
        self.caption.setToolTip(title)
        heading.addWidget(self.caption, 1)
        self.close_button = action(root, "close", "Close", self.close)
        self.close_button.setToolButtonStyle(Qt.ToolButtonIconOnly)
        self.close_button.setMinimumSize(0, 0)
        self.close_button.setFixedSize(18, 18)
        configure_close_icon(self.close_button, root)
        themes.set_style(self.close_button, "QToolButton { min-height:0; padding:0; border-radius:2px; }")
        heading.addWidget(self.close_button)
        self.outer.addWidget(self.header)
        self.header.installEventFilter(self)
        self.caption.installEventFilter(self)

    def showEvent(self, event):
        super().showEvent(event)
        owner = Window._opacity_owner() if Window._opacity_owner else None
        if owner is not None and owner is not self:
            self.dim_for_settings()
        enable_window_shadow(self)
        for widget in self.findChildren(QtWidgets.QWidget):
            if isinstance(widget, (QtWidgets.QAbstractButton, QtWidgets.QComboBox)):
                widget.installEventFilter(self)
                widget.setCursor(Qt.PointingHandCursor if widget.isEnabled() else Qt.ArrowCursor)

    def dim_for_settings(self):
        if self not in Window._dimmed:
            Window._dimmed[self] = self.windowOpacity()
            self.setWindowOpacity(self.windowOpacity() * 0.5)

    def set_base_opacity(self, opacity):
        if self in Window._dimmed:
            Window._dimmed[self] = opacity
            self.setWindowOpacity(opacity * 0.5)
        else:
            self.setWindowOpacity(opacity)

    def set_settings_dimming(self, enabled):
        if enabled:
            Window._opacity_owner = weakref.ref(self)
            for window in list(Window._windows):
                try:
                    if window is not self and window.isVisible():
                        window.dim_for_settings()
                except RuntimeError:
                    # Qt may already have destroyed a deferred-delete wrapper.
                    continue
        else:
            owner = Window._opacity_owner() if Window._opacity_owner else None
            if owner is not self:
                return
            Window._opacity_owner = None
            for window, opacity in list(Window._dimmed.items()):
                try:
                    window.setWindowOpacity(opacity)
                except RuntimeError:
                    pass
            Window._dimmed.clear()

    def eventFilter(self, watched, event):
        if event.type() == QtCore.QEvent.EnabledChange and isinstance(watched, (QtWidgets.QAbstractButton, QtWidgets.QComboBox)):
            watched.setCursor(Qt.PointingHandCursor if watched.isEnabled() else Qt.ArrowCursor)
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
        if native.message == 0x031E:  # WM_DWMCOMPOSITIONCHANGED
            enable_window_shadow(self)
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


class LoadingOverlay(QtWidgets.QWidget):
    """Non-blocking loading veil; its parent retains the accessible title bar."""
    def __init__(self, parent):
        super().__init__(parent)
        self.setAttribute(Qt.WA_NoSystemBackground)
        self.setAccessibleName("Loading skills")
        self.setCursor(Qt.WaitCursor)
        self.angle = 0
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
        veil = QtGui.QColor(themes.style("@recessed_background"))
        veil.setAlpha(175)
        painter.fillRect(self.rect(), veil)
        center = self.rect().center()
        ring = QtCore.QRectF(center.x() - 22, center.y() - 22, 44, 44)
        track = QtGui.QColor(themes.style("@text"))
        track.setAlpha(65)
        painter.setPen(QtGui.QPen(track, 4))
        painter.drawEllipse(ring)
        pen = QtGui.QPen(QtGui.QColor(themes.style("@accent")), 4)
        pen.setCapStyle(Qt.RoundCap)
        painter.setPen(pen)
        painter.drawArc(ring, -self.angle * 16, 100 * 16)
        painter.end()


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
            return QtGui.QColor(themes.style(COLORS.get(record[2], COLORS["info"])))
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
    donateActivated = QtCore.Signal()
    point_size = 11

    def journal_font(self):
        return QtGui.QFont("Consolas", self.point_size)

    def wrapped_layout(self, record, width):
        font = self.journal_font()
        metrics = QtGui.QFontMetrics(font)
        font.setBold(True)
        prefix = 5 + metrics.horizontalAdvance(record[1][11:19]) + 10 + QtGui.QFontMetrics(font).horizontalAdvance("[ {} ]".format(record[2].lower())) + 16
        reserve = metrics.horizontalAdvance("Donate") + 24 if record[2] == "support" and "Donate" in record[3] else 4
        layout = QtGui.QTextLayout("> " + record[3].replace('\n', '\u2028'), self.journal_font())
        option = QtGui.QTextOption()
        option.setWrapMode(QtGui.QTextOption.WrapAtWordBoundaryOrAnywhere)
        layout.setTextOption(option)
        layout.beginLayout()
        height = 0
        while True:
            line = layout.createLine()
            if not line.isValid():
                break
            left = prefix if height == 0 else 5
            line.setLineWidth(max(1, width - left - reserve))
            line.setPosition(QtCore.QPointF(left, height))
            height += line.height()
        layout.endLayout()
        return layout, prefix, int(height + 4)

    def donate_rect(self, rect, record):
        if record is None or record[2] != "support" or "Donate" not in record[3]:
            return QtCore.QRect()
        metrics = QtGui.QFontMetrics(self.journal_font())
        width = metrics.horizontalAdvance("Donate") + 8
        return QtCore.QRect(rect.right() - width - 4, rect.top(), width, rect.height())

    def editorEvent(self, event, model, option, index):
        if event.type() == QtCore.QEvent.MouseButtonRelease and event.button() == Qt.LeftButton:
            if self.donate_rect(option.rect, model.record(index.row())).contains(event.pos()):
                self.donateActivated.emit()
                return True
        return super().editorEvent(event, model, option, index)

    def paint(self, painter, option, index):
        record = index.model().record(index.row())
        if record is None:
            return
        painter.save()
        painter.setClipRect(option.rect)
        if option.state & QtWidgets.QStyle.State_Selected:
            painter.fillRect(option.rect, QtGui.QColor(themes.style("@journal_selection")))
        color = QtGui.QColor(themes.style(COLORS.get(record[2], COLORS["info"])))
        font = self.journal_font()
        painter.setFont(font)
        metrics = QtGui.QFontMetrics(font)
        rect = option.rect.adjusted(5, 0, -4, 0)
        wrapped = self.parent().viewport().width() >= 600
        line_height = metrics.height() + 4 if wrapped else rect.height()
        baseline = rect.top() + (line_height + metrics.ascent() - metrics.descent()) // 2
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
        inset = 1 if self.point_size < 11 else 2
        badge_rect = QtCore.QRect(x, rect.top() + inset, badge_width, line_height - inset * 2)
        painter.fillRect(badge_rect, color)
        painter.setPen(QtGui.QColor(themes.style("@log_badge_text")))
        painter.drawText(badge_rect, Qt.AlignCenter, badge)
        x += badge_width + 8
        font.setBold(False)
        painter.setFont(font)
        painter.setPen(color)
        content = "> " + record[3].replace("\n", "  ")
        link_rect = self.donate_rect(option.rect, record)
        right = link_rect.left() - 8 if not link_rect.isNull() else rect.right()
        if wrapped:
            layout, prefix, height = self.wrapped_layout(record, option.rect.width())
            layout.draw(painter, QtCore.QPointF(option.rect.left(), rect.top() + 2))
        else:
            painter.drawText(x, baseline, metrics.elidedText(content, Qt.ElideRight, max(0, right - x)))
        if not link_rect.isNull():
            font.setUnderline(True)
            painter.setFont(font)
            painter.drawText(link_rect, Qt.AlignCenter, "Donate")
        painter.restore()


class JournalView(QtWidgets.QTableView):
    """Measure visible rows only, keeping large disk-backed histories responsive."""
    def __init__(self):
        super().__init__()
        self._layout_width = None
        self._layout_font = None
        self._sized_rows = set()
        self._jump_pending = False
        self._adjusting_scroll = False
        self._jump_timer = QtCore.QTimer(self)
        self._jump_timer.setSingleShot(True)
        self._jump_timer.timeout.connect(self.finish_latest)
        self.setMouseTracking(True)
        self._relayout = QtCore.QTimer(self)
        self._relayout.setSingleShot(True)
        self._relayout.timeout.connect(self.layout_visible_rows)
        self.verticalScrollBar().valueChanged.connect(self.scroll_changed)
        self.verticalScrollBar().sliderPressed.connect(self.cancel_latest)

    def cancel_latest(self):
        self._jump_pending = False
        self._jump_timer.stop()

    def scroll_changed(self, value):
        if self._jump_pending and not self._adjusting_scroll and value < self.verticalScrollBar().maximum():
            self.cancel_latest()
        self.schedule_rows()

    def wheelEvent(self, event):
        self.cancel_latest()
        super().wheelEvent(event)

    def keyPressEvent(self, event):
        self.cancel_latest()
        super().keyPressEvent(event)

    def request_latest(self):
        self._jump_pending = True
        self._adjusting_scroll = True
        self.scrollToBottom()
        self._adjusting_scroll = False
        self.schedule_rows()
        self._jump_timer.start(0)

    def finish_latest(self):
        if not self._jump_pending:
            return
        self._adjusting_scroll = True
        self.doItemsLayout()
        self.layout_visible_rows()
        self.doItemsLayout()
        self.scrollToBottom()
        self.verticalScrollBar().setValue(self.verticalScrollBar().maximum())
        self._adjusting_scroll = False
        # Row measurements can schedule a second geometry pass. Keep the
        # explicit jump alive until that pass has settled, not just one frame.
        if self._relayout.isActive():
            self._jump_timer.start(0)
        else:
            self._jump_pending = False

    def schedule_rows(self, *args):
        self._relayout.start(0)

    def mouseMoveEvent(self, event):
        super().mouseMoveEvent(event)
        index = self.indexAt(event.pos())
        link = QtCore.QRect()
        if index.isValid() and isinstance(self.itemDelegate(), JournalDelegate):
            link = self.itemDelegate().donate_rect(self.visualRect(index), self.model().record(index.row()))
        self.viewport().setCursor(Qt.PointingHandCursor if link.contains(event.pos()) else Qt.ArrowCursor)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        # A scroll area's viewport and scrollbar containers are child widgets:
        # stylesheet rounding alone does not clip their square backgrounds.
        outline = QtGui.QPainterPath()
        outline.addRoundedRect(QtCore.QRectF(self.rect()), 8, 8)
        self.setMask(QtGui.QRegion(outline.toFillPolygon().toPolygon()))
        self.schedule_rows()

    def layout_visible_rows(self):
        model, delegate = self.model(), self.itemDelegate()
        if model is None or not isinstance(delegate, JournalDelegate):
            return
        was_adjusting = self._adjusting_scroll
        self._adjusting_scroll = True
        width = self.viewport().width()
        bar = self.verticalScrollBar()
        following, position = self._jump_pending or bar.value() >= bar.maximum() - 1, bar.value()
        if (width, delegate.point_size) != (self._layout_width, self._layout_font):
            for row in self._sized_rows:
                self.setRowHeight(row, self.verticalHeader().defaultSectionSize())
            self._sized_rows.clear()
            self._layout_width, self._layout_font = width, delegate.point_size
        if width >= 600:
            first = max(0, self.rowAt(0))
            count = self.viewport().height() // max(1, self.verticalHeader().minimumSectionSize()) + 2
            # Include the last screen before following the bottom; no full-history scan.
            if following:
                first = max(0, model.rowCount() - count)
            for row in range(first, min(model.rowCount(), first + count)):
                record = model.record(row)
                if record is not None:
                    height = delegate.wrapped_layout(record, self.columnWidth(0))[2]
                    if self.rowHeight(row) != height:
                        self.setRowHeight(row, height)
                    self._sized_rows.add(row)
            if len(self._sized_rows) > 512:
                stale = {row for row in self._sized_rows if not first <= row < first + count}
                for row in stale:
                    self.setRowHeight(row, self.verticalHeader().defaultSectionSize())
                self._sized_rows.difference_update(stale)
        if following:
            self.scrollToBottom()
        else:
            bar.setValue(position)
        self._adjusting_scroll = was_adjusting


class Panel(Window):
    def __init__(self, client, parent):
        super().__init__(client.root, "3DGROUND - Max Ultra MCP " + client.version, parent)
        self.client = client
        self.setMinimumSize(240, 180)
        self.resize(640, 480)
        self.outer.setSpacing(6)
        self.ai = action(client.root, "settings", "Setup AI Client", client.show_onboarding)
        self.ai.setFocusPolicy(Qt.StrongFocus)
        self.ai.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Preferred)
        self.ai.setMinimumWidth(100)
        self.ai_refresh = action(client.root, "refresh-cw", "Refresh AI client status", client.refresh_agents)
        self.ai_refresh.setToolButtonStyle(Qt.ToolButtonIconOnly)
        self.hide_button = action(client.root, "panel-top-close", "Hide panel", client.hide_panel)
        for button in (self.ai_refresh, self.hide_button):
            button.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Preferred)
        top_row = QtWidgets.QHBoxLayout()
        self.top_row = top_row
        top_row.setSpacing(8)
        top_row.addWidget(self.ai, 1)
        top_row.addWidget(self.ai_refresh)
        top_row.addSpacing(12)
        top_row.addWidget(self.hide_button)
        self.outer.addLayout(top_row)
        status_row = QtWidgets.QHBoxLayout()
        self.scene_label = OverflowLabel()
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
        self.log = JournalView()
        self.log.setObjectName("activityJournal")
        self.log.setMinimumHeight(24)
        self.log.setModel(self.model)
        delegate = JournalDelegate(self.log)
        delegate.donateActivated.connect(client.donate)
        self.log.setItemDelegate(delegate)
        self.model.rowsInserted.connect(self.log.schedule_rows)
        self.model.modelReset.connect(self.log.schedule_rows)
        self.log.setAccessibleName("Complete session activity journal")
        self.log.horizontalHeader().hide()
        self.log.verticalHeader().hide()
        self.log.horizontalHeader().setStretchLastSection(True)
        self.update_journal_density()
        self.log.setWordWrap(False)
        self.log.setShowGrid(False)
        self.log.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.log.setSelectionMode(QtWidgets.QAbstractItemView.ExtendedSelection)
        self.log.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.log.doubleClicked.connect(self.show_message)
        self.outer.addWidget(self.log, 1)
        self.storage_error = QtWidgets.QLabel()
        self.storage_error.setWordWrap(True)
        themes.set_style(self.storage_error, "color: @storage_error")
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
        self.footer = footer
        self.support = PromotionLink()
        footer.addWidget(self.support, 1)
        self.donate_button = donate_action(client.root, client.donate)
        self.donate_button.setFocusPolicy(Qt.StrongFocus)
        self.setFocusProxy(self.donate_button)
        # If Refresh becomes disabled during a check, Qt advances focus here.
        self.setTabOrder(self.ai_refresh, self.donate_button)
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
        self._opened_once = False
        self.update_ai()
        self.donate_button.setFocus(Qt.OtherFocusReason)

    def showEvent(self, event):
        super().showEvent(event)
        if not self._opened_once:
            self._opened_once = True
            self.go_latest()

    def show_search(self):
        self.filters.show()
        self.search.setFocus()

    def journal_menu(self, position):
        menu = QtWidgets.QMenu(self)
        index = self.log.indexAt(position)
        record = self.model.record(index.row()) if index.isValid() else None
        if record and record[2] == "support" and "Donate" in record[3]:
            menu.addAction(icon(self.client.root, "heart"), "Donate", self.client.donate)
        for symbol, label, callback in [("search", "Search / filter (Ctrl+F)", self.show_search), ("copy", "Copy selected (Ctrl+C)", self.copy_selected), ("download", "Export (Ctrl+E)", self.export), ("expand", "Go to latest", self.go_latest)]:
            item = menu.addAction(icon(self.client.root, symbol), label)
            item.triggered.connect(callback)
        menu.exec_(self.log.viewport().mapToGlobal(position))

    def update_ai(self):
        label, state = self.client.ai_status()
        self.ai.setText(label if self.width() >= 520 else "Setup AI Client")
        self.ai.setToolTip(label + " — open AI Client Setup")
        background = {"ready": "@ready_background", "issue": "@issue_background", "checking": "@checking_background"}.get(state, "@setup_background")
        themes.set_style(self.ai, "QToolButton { background:" + background + "; border-color:" + background + "; color:@status_button_text; } QToolButton:hover { border-color:@heading_text; }")
        self.ai_refresh.setEnabled(self.client.integration is None)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, "buttons"):
            self.update_compact_layout()
            required = sum(button.fontMetrics().horizontalAdvance(button.text()) + 48 for button in self.buttons) + 42
            compact = self.width() < required
            for button in self.buttons:
                button.setToolButtonStyle(Qt.ToolButtonIconOnly if compact else Qt.ToolButtonTextBesideIcon)
            self.hide_button.setToolButtonStyle(Qt.ToolButtonIconOnly if self.width() < 520 else Qt.ToolButtonTextBesideIcon)
            self.donate_button.setToolButtonStyle(Qt.ToolButtonIconOnly if self.width() < 400 else Qt.ToolButtonTextBesideIcon)
            self.update_ai()
            self.update_journal_density()

    def update_compact_layout(self):
        tiny = self.width() < 350
        large = self.width() > 1250
        extra_large = self.width() >= 1800
        scroll_density = 'tiny' if tiny else 'compact' if self.width() < 520 else 'normal'
        for scrollbar in (self.log.verticalScrollBar(), self.log.horizontalScrollBar()):
            if scrollbar.property('scrollDensity') != scroll_density:
                scrollbar.setProperty('scrollDensity', scroll_density)
                scrollbar.style().unpolish(scrollbar)
                scrollbar.style().polish(scrollbar)
                scrollbar.updateGeometry()
        mode = 'tiny' if tiny else 'extra_large' if extra_large else 'large' if large else 'normal'
        if getattr(self, '_layout_mode', None) == mode:
            return
        self._layout_mode = mode
        self._ultra_compact = tiny
        self.outer.setContentsMargins(*((4, 3, 4, 3) if tiny else (16, 12, 16, 12) if extra_large else (12, 9, 12, 9) if large else (8, 6, 8, 6)))
        spacing = 3 if tiny else 12 if extra_large else 9 if large else 6
        action_spacing = 3 if tiny else 16 if extra_large else 12 if large else 8
        self.outer.setSpacing(spacing)
        self.header.layout().setSpacing(spacing)
        self.top_row.setSpacing(action_spacing)
        self.top_row.itemAt(2).spacerItem().changeSize(2 if tiny else 24 if extra_large else 18 if large else 12, 0)
        self.actions.setSpacing(action_spacing)
        self.footer.setSpacing(spacing)
        button_size = 24 if tiny else 56 if extra_large else 44 if large else 32
        for button in self.buttons + [self.ai, self.ai_refresh, self.hide_button, self.donate_button, self.latest]:
            button.setProperty('ultraCompact', tiny)
            button.setProperty('largeControls', large)
            button.setProperty('extraLargeControls', extra_large)
            button.style().unpolish(button)
            button.style().polish(button)
            button.setMinimumHeight(button_size)
            button.setMaximumHeight(24 if tiny else 16777215)
            if isinstance(button, QtWidgets.QToolButton):
                button.setMinimumWidth((80 if tiny else 180 if extra_large else 140 if large else 100) if button is self.ai else button_size)
                glyph_size = 14 if tiny else 34 if extra_large else 26 if large else 20
                button.setIconSize(QtCore.QSize(glyph_size, glyph_size))
        for control in (self.search, self.categories, self.log.verticalScrollBar(), self.log.horizontalScrollBar()):
            control.setProperty('largeControls', large)
            control.setProperty('extraLargeControls', extra_large)
            control.style().unpolish(control)
            control.style().polish(control)
            control.updateGeometry()
        close_size = 14 if tiny else 30 if extra_large else 24 if large else 18
        self.close_button.setFixedSize(close_size, close_size)
        close_glyph = 22 if extra_large else 18 if large else 14
        self.close_button.setIconSize(QtCore.QSize(close_glyph, close_glyph))
        themes.set_style(self.caption, 'font-size:{}pt; font-weight:600; color:@heading_text; background:transparent'.format(9 if tiny else 20 if extra_large else 16 if large else 12))
        for label in (self.scene_label, self.support, self.storage_error):
            themes.set_style(label, 'font-size:{}pt;'.format(8 if tiny else 18 if extra_large else 14 if large else 11) + ('color:@storage_error;' if label is self.storage_error else ''))
        self.support.update_text()
        self.top_row.invalidate()

    def update_journal_density(self):
        # Window dimensions are logical pixels; point sizes retain DPI scaling.
        point_size = 18 if self.width() >= 1800 else 14 if self.width() > 1250 else 8 if self.width() < 350 else 9 if self.width() < 420 or self.height() < 300 else 10 if self.width() < 520 or self.height() < 380 else 11
        delegate = self.log.itemDelegate()
        padding = {8: 1, 9: 2, 10: 3, 11: 4, 14: 6, 18: 8}[point_size]
        row_height = QtGui.QFontMetrics(QtGui.QFont("Consolas", point_size)).height() + padding
        header = self.log.verticalHeader()
        if delegate.point_size == point_size and header.defaultSectionSize() == row_height:
            return
        scrollbar = self.log.verticalScrollBar()
        following = scrollbar.value() >= scrollbar.maximum() - 1
        position = scrollbar.value()
        delegate.point_size = point_size
        header.setMinimumSectionSize(row_height)
        header.setDefaultSectionSize(row_height)
        if following:
            self.log.scrollToBottom()
        else:
            scrollbar.setValue(position)
        self.log.viewport().update()
        self.log.schedule_rows()

    def refresh(self):
        scrollbar = self.log.verticalScrollBar()
        following = self.log._jump_pending or scrollbar.value() >= scrollbar.maximum() - 1
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
        self._unread = 0
        self.latest.hide()
        self.log.request_latest()

    def show_message(self, index):
        dialog = Window(self.client.root, "Activity message", self)
        layout = QtWidgets.QPlainTextEdit()
        layout.setReadOnly(True)
        layout.setPlainText(self.model.data(index))
        dialog.outer.addWidget(layout)
        record = self.model.record(index.row())
        if record and record[2] == "support" and "Donate" in record[3]:
            dialog.outer.addWidget(donate_action(self.client.root, self.client.donate))
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
        self.setFixedSize(196, 32)
        self.header.hide()
        self.outer.removeWidget(self.header)
        self.outer.setContentsMargins(3, 2, 3, 2)
        self.outer.setSpacing(0)
        row = QtWidgets.QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(2)
        self.drag_grip = action(client.root, "grip-vertical", "Drag to move", lambda: None)
        self.drag_grip.setToolButtonStyle(Qt.ToolButtonIconOnly)
        self.drag_grip.setMinimumSize(0, 0)
        self.drag_grip.setFixedSize(14, 24)
        self.drag_grip.setIconSize(QtCore.QSize(14, 14))
        self.drag_grip.setFocusPolicy(Qt.NoFocus)
        self.button = action(client.root, "expand", "Max Ultra MCP", client.show_panel)
        self.button.setToolTip("Expand MCP Server — drag to move")
        self.button.setMinimumSize(0, 0)
        self.button.setIconSize(QtCore.QSize(14, 14))
        self.button.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Fixed)
        self.close_button.setParent(self)
        self.close_button.setMinimumSize(0, 0)
        self.close_button.setFixedSize(22, 24)
        compact_style = "QToolButton { font-size:10pt; min-height:0; padding:2px; border:none; background:transparent; } QToolButton:hover { background:@button_hover; }"
        themes.set_style(self.button, compact_style)
        themes.set_style(self.close_button, compact_style)
        row.addWidget(self.drag_grip)
        row.addWidget(self.button, 1)
        row.addWidget(self.close_button)
        self.outer.addLayout(row)
        self.button.installEventFilter(self)
        self.drag_grip.installEventFilter(self)
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
            "ready": ("@mini_ready_background", "@mini_ready_border", "@mini_ready_hover"),
            "error": ("@mini_error_background", "@mini_error_border", "@mini_error_hover"),
            "warning": ("@mini_warning_background", "@accent", "@mini_warning_hover"),
        }.get(state, ("@mini_warning_background", "@accent", "@mini_warning_hover"))
        self.setObjectName("miniStatus")
        themes.set_style(self, STYLE + "\nQDialog#miniStatus { background:" + background + "; border:1px solid " + border + "; }")
        style = "QToolButton { color:@status_button_text; font-size:10pt; min-height:0; padding:2px; border:none; background:transparent; } QToolButton:hover { background:" + hover + "; }"
        themes.set_style(self.button, style)
        themes.set_style(self.close_button, style)
        themes.set_style(self.drag_grip, style)

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
        self.drag_grip.setCursor(Qt.OpenHandCursor)
        self.confine_to_screen()

    def eventFilter(self, watched, event):
        if watched in (getattr(self, "button", None), getattr(self, "drag_grip", None)):
            if event.type() == QtCore.QEvent.MouseButtonPress and event.button() == Qt.LeftButton:
                self._press = event.globalPos()
                self._drag = event.globalPos() - self.frameGeometry().topLeft()
                self._moving = False
                if watched is self.drag_grip:
                    self.drag_grip.setCursor(Qt.ClosedHandCursor)
            elif event.type() == QtCore.QEvent.MouseMove and self._press is not None:
                self._moving = self._moving or (event.globalPos() - self._press).manhattanLength() >= QtWidgets.QApplication.startDragDistance()
                if self._moving:
                    self.confine_to_screen(position=event.globalPos() - self._drag, anchor=event.globalPos())
                    return True
            elif event.type() == QtCore.QEvent.MouseButtonRelease:
                self._press = None
                self.drag_grip.setCursor(Qt.OpenHandCursor)
                if self._moving:
                    watched.setDown(False)
                    self._moving = False
                    return True
        return super().eventFilter(watched, event)

    def closeEvent(self, event):
        if not self.client.disposed:
            self.client.show_panel()
        event.accept()
