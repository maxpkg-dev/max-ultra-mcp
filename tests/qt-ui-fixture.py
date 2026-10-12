# Synthetic Qt UI fixture; never reads or modifies scene objects or client setup.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import sys
import tempfile
import types
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from max_ultra.qt import QtWidgets, QtCore, QtGui, Qt, max_parent
from max_ultra.journal import Journal
from max_ultra.widgets import Panel, MiniPanel, OverflowLabel, bounded_window_position


def run():
    application = QtWidgets.QApplication.instance()
    if application is None:
        raise RuntimeError("This fixture runs inside 3ds Max")
    output = ROOT / "dist" / "qt-fixture"
    output.mkdir(parents=True, exist_ok=True)
    context = OverflowLabel()
    try:
        context.resize(180, 28)
        message = "PID 22022 | Scene ExampleScene.max | Objects 100 | Selection 0"
        context.setText(message)
        context.show()
        application.processEvents()
        assert context._timer.isActive() and context._limit > 0
        deadline = time.monotonic() + 1.7
        while time.monotonic() < deadline:
            application.processEvents()
            time.sleep(0.01)
        assert context._offset > 0
        offset = context._offset
        context.setText(message)
        assert context._offset == offset  # Repeated scene polls must not reset motion.
        context.hide()
        assert not context._timer.isActive()
        context.resize(1200, 28)
        context.show()
        application.processEvents()
        assert context._offset == 0 and not context._timer.isActive()
        assert context.text() == message and context.toolTip() == message
    finally:
        context.close()
        context.deleteLater()
    with tempfile.TemporaryDirectory(prefix="max-ultra-qt-fixture-") as folder:
        journal = Journal(Path(folder) / "journal.sqlite3")
        for category, message in [("system", "Initializing Max Ultra MCP services"), ("success", "Connected to the example server"), ("info", "Read scene summary completed in 12 ms"), ("warning", "Example warning with detailed diagnostic information"), ("error", "Example operation failed; inspect details")]:
            journal.append(category, message)
        callback = lambda *args: None
        client = types.SimpleNamespace(root=ROOT, version="Qt preview", journal=journal, status="Server 127.0.0.1:47635", disposed=True, integration=None, ai_status=lambda: ("ChatGPT / Codex | MCP ready", "ready"), refresh_agents=callback, donate=callback, show_onboarding=callback, reconnect=callback, close=callback, show_skills=callback, show_settings=callback, hide_panel=callback, show_panel=callback, storage_failure=lambda message: None)
        panel = Panel(client, max_parent())
        mini = MiniPanel(client, max_parent())
        try:
            for state, color in [('ready', '#356b42'), ('error', '#873c38'), ('warning', '#945b27')]:
                mini.update_status(state, 'Synthetic status')
                assert color in mini.styleSheet()
                assert 'Synthetic status' in mini.button.toolTip()
            size = QtCore.QSize(180, 32)
            areas = [QtCore.QRect(0, 0, 1920, 1040), QtCore.QRect(-1280, 40, 1280, 984)]
            assert bounded_window_position(QtCore.QPoint(1900, 1060), size, areas) == QtCore.QPoint(1740, 1008)
            assert bounded_window_position(QtCore.QPoint(-1500, -100), size, areas) == QtCore.QPoint(-1280, 40)
            assert bounded_window_position(QtCore.QPoint(-100, 500), size, areas, QtCore.QPoint(-10, 500)) == QtCore.QPoint(-180, 500)
            mini.show()
            available = mini.screen().availableGeometry()
            mini.move(available.right() + 100, available.bottom() + 100)
            application.processEvents()
            assert any(screen.availableGeometry().contains(mini.frameGeometry()) for screen in application.screens())
            mini.hide()
            panel.show()
            panel.refresh()
            normal_small_log_height = None
            for width, height in [(640, 480), (480, 360), (320, 240), (280, 240), (240, 180), (1024, 600), (1025, 600), (1280, 720), (1799, 720), (1800, 800), (1920, 900), (1799, 720), (1024, 600), (280, 240), (640, 480)]:
                panel.resize(width, height)
                application.processEvents()
                assert panel.width() == width and panel.height() == height
                assert panel.ai.height() == panel.ai_refresh.height() == panel.hide_button.height()
                assert panel.log.viewport().height() >= 24
                assert not panel.log.mask().contains(QtCore.QPoint(0, 0))
                assert panel.log.mask().contains(panel.log.rect().center())
                expected_points = 18 if width >= 1800 else 14 if width > 1024 else {1024: 11, 640: 11, 480: 10, 320: 8, 280: 8, 240: 8}[width]
                assert panel.log.itemDelegate().journal_font().pointSize() == expected_points
                metrics = QtGui.QFontMetrics(panel.log.itemDelegate().journal_font())
                assert panel.log.verticalHeader().defaultSectionSize() == metrics.height() + {8: 1, 9: 2, 10: 3, 11: 4, 14: 6, 18: 8}[expected_points]
                assert panel.ai.iconSize().width() == (34 if width >= 1800 else 26 if width > 1024 else 14 if width < 350 else 20)
                assert panel.ai.font().pointSize() == (18 if width >= 1800 else 14 if width > 1024 else 9 if width < 350 else 11)
                assert panel.caption.font().pointSize() == (20 if width >= 1800 else 16 if width > 1024 else 9 if width < 350 else 12)
                assert panel.support.font().pointSize() == (18 if width >= 1800 else 14 if width > 1024 else 8 if width < 350 else 11)
                scroll_width = 7 if width < 350 else 9 if width < 520 else 21 if width >= 1800 else 17 if width > 1024 else 13
                assert panel.log.verticalScrollBar().sizeHint().width() == scroll_width
                assert panel.log.horizontalScrollBar().sizeHint().height() == scroll_width
                assert not bool(panel.windowFlags() & Qt.WindowStaysOnTopHint)
                for button in panel.buttons:
                    assert button.width() >= (24 if width < 350 else 32)
                    if width < 350:
                        assert button.height() == 24, (width, button.text(), button.height(), button.minimumHeight(), button.maximumHeight())
                    assert not button.icon().isNull()
                    assert panel.rect().contains(button.mapTo(panel, QtCore.QPoint(button.width() - 1, button.height() - 1)))
                if width == 320:
                    normal_small_log_height = panel.log.viewport().height()
                if width == 280:
                    assert panel.log.viewport().height() >= normal_small_log_height
                panel.grab().save(str(output / ("panel-{}x{}.png".format(width, height))))
            assert panel.model.total == 5
            panel.model.refresh(search="diagnostic")
            assert panel.model.total == 1
            panel.model.refresh(search="")
            assert panel.model.total == 5
            assert not bool(mini.windowFlags() & Qt.WindowStaysOnTopHint)
            # Populate disk storage, not the view; GUI memory must remain paged.
            with journal._db:
                journal._db.executemany("INSERT INTO entries(stamp,category,message) VALUES (?,?,?)", (("2026-01-01T12:00:00", "system", "Synthetic history {}".format(index)) for index in range(100000)))
            opening = Panel(client, max_parent())
            try:
                opening.show()
                journal.append('info', 'Asynchronous initial wrapped message ' * 20)
                opening.refresh()
                for _ in range(12):
                    application.processEvents()
                bar = opening.log.verticalScrollBar()
                assert bar.value() == bar.maximum(), 'First opening must settle at the latest message'
                opening.log.cancel_latest()
                bar.setValue(bar.maximum() // 2)
                application.processEvents()
                position = bar.value()
                opening.hide()
                opening.show()
                opening.refresh()
                for _ in range(8):
                    application.processEvents()
                assert bar.value() == position, 'Restoring an existing panel must preserve manual reading'
            finally:
                opening.close()
                opening.deleteLater()
            for width in (240, 349, 350, 351):
                panel.resize(width, 480)
                application.processEvents()
                assert panel._ultra_compact == (width < 350)
                assert panel.ai.height() == 24 if width < 350 else panel.ai.height() >= 32
                assert panel.ai.iconSize().width() == (14 if width < 350 else 20)
                assert panel.log.itemDelegate().point_size == (8 if width < 350 else 9)
                assert panel.log.height() > 200
            panel.resize(640, 480)
            panel.refresh()
            application.processEvents()
            panel.log.verticalScrollBar().setValue(50000)
            application.processEvents()
            scroll_position = panel.log.verticalScrollBar().value()
            journal.append("success", "New synthetic event while reading history")
            panel.refresh()
            application.processEvents()
            assert panel.log.verticalScrollBar().value() == scroll_position
            assert panel.latest.isVisible() and panel._unread == 1
            started = time.perf_counter()
            panel.model.refresh(search="Synthetic history 99999")
            assert panel.model.total == 1
            assert "99999" in panel.model.data(panel.model.index(0, 0))
            assert time.perf_counter() - started < 2, "Full-history search stalled"
            panel.model.refresh(search="")
            for row in range(0, 100000, 1024):
                panel.model.record(row)
            assert len(panel.model.pages) <= 8
            panel.go_latest()
            assert not panel.latest.isVisible()
            journal.append('info', 'Latest wrapped message ' * 70)
            panel.refresh()
            for _ in range(8):
                application.processEvents()
            assert panel.log.verticalScrollBar().value() == panel.log.verticalScrollBar().maximum()
            newest = panel.model.index(panel.model.total - 1, 0)
            assert panel.log.visualRect(newest).bottom() <= panel.log.viewport().height()
            assert not panel.log._jump_pending
            journal.append('support', 'Please use Donate to support development.')
            panel.model.refresh()
            index = panel.model.index(panel.model.total - 1, 0)
            delegate = panel.log.itemDelegate()
            option = QtWidgets.QStyleOptionViewItem()
            option.rect = QtCore.QRect(0, 0, 290, 26)
            link = delegate.donate_rect(option.rect, panel.model.record(index.row()))
            assert option.rect.contains(link) and link.width() > 20
            clicked = []
            delegate.donateActivated.connect(lambda: clicked.append(True))
            event = QtGui.QMouseEvent(QtCore.QEvent.MouseButtonRelease, QtCore.QPointF(link.center()), Qt.LeftButton, Qt.NoButton, Qt.NoModifier)
            assert delegate.editorEvent(event, panel.model, option, index)
            assert clicked == [True]
            return "Qt fixture passed: sizes, SVG, colors, 100k history, search, scroll preservation, paged memory and non-topmost ownership"
        finally:
            panel.close()
            mini.close()
            panel.deleteLater()
            mini.deleteLater()
            application.processEvents()
            journal.close()


print(run())
