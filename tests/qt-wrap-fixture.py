# Check responsive journal wrapping without accessing a Max scene.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'python'))
from max_ultra.qt import QtWidgets, QtCore
from max_ultra.journal import Journal
from max_ultra.widgets import JournalView, JournalModel, JournalDelegate, STYLE

app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
with tempfile.TemporaryDirectory() as folder:
    journal = Journal(Path(folder) / 'journal.sqlite3')
    message = 'A long diagnostic message with meaningful details. ' * 12 + '\nSecond paragraph.'
    for index in range(1000):
        journal.append('info', message)
    view = JournalView()
    view.setStyleSheet(STYLE)
    view.setShowGrid(False)
    view.horizontalHeader().hide()
    view.verticalHeader().hide()
    model = JournalModel(journal, view)
    view.setModel(model)
    view.setItemDelegate(JournalDelegate(view))
    view.horizontalHeader().setStretchLastSection(True)
    view.verticalHeader().setMinimumSectionSize(22)
    view.verticalHeader().setDefaultSectionSize(22)
    view.show()
    for width in (700, 320, 1000):
        view.resize(width, 400)
        app.processEvents()
        view.layout_visible_rows()
        row = max(0, view.rowAt(0))
        assert (view.rowHeight(row) > 22) == (width >= 600), (width, row, view.rowHeight(row))
        if width >= 600:
            layout, prefix, height = view.itemDelegate().wrapped_layout(model.record(row), view.columnWidth(0))
            assert layout.lineCount() > 1
            assert layout.lineAt(0).position().x() == prefix
            assert layout.lineAt(1).position().x() == 5
            assert sum(layout.lineAt(i).textLength() for i in range(layout.lineCount())) == len('> ' + message)
        assert len(model.pages) <= 8
        if width == 700:
            output = ROOT / 'dist/qt-fixture'
            output.mkdir(parents=True, exist_ok=True)
            view.grab().save(str(output / 'journal-wrapped.png'))
    view.scrollToBottom()
    view.layout_visible_rows()
    assert view.verticalScrollBar().value() == view.verticalScrollBar().maximum()
    view.verticalScrollBar().setValue(400)
    view.layout_visible_rows()
    assert view.verticalScrollBar().value() == 400
    view.close()
    journal.close()
print('Journal wrapping passed: wide/narrow resize, complete text, paged history and scroll position')
