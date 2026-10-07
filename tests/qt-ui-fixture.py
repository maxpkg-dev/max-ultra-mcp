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
from max_ultra.qt import QtWidgets, QtCore, Qt, max_parent
from max_ultra.journal import Journal
from max_ultra.widgets import Panel, MiniPanel, bounded_window_position


def run():
    application = QtWidgets.QApplication.instance()
    if application is None:
        raise RuntimeError("This fixture runs inside 3ds Max")
    output = ROOT / "dist" / "qt-fixture"
    output.mkdir(parents=True, exist_ok=True)
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
            for width, height in [(640, 480), (320, 240)]:
                panel.resize(width, height)
                application.processEvents()
                assert panel.width() == width and panel.height() == height
                assert panel.log.viewport().height() >= 24
                assert not bool(panel.windowFlags() & Qt.WindowStaysOnTopHint)
                for button in panel.buttons:
                    assert button.width() >= 32
                    assert not button.icon().isNull()
                    assert panel.rect().contains(button.mapTo(panel, QtCore.QPoint(button.width() - 1, button.height() - 1)))
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
            return "Qt fixture passed: sizes, SVG, colors, 100k history, search, scroll preservation, paged memory and non-topmost ownership"
        finally:
            panel.close()
            mini.close()
            panel.deleteLater()
            mini.deleteLater()
            application.processEvents()
            journal.close()


print(run())
