# Exercise live theme changes through a real Qt combo popup without scene access.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'python'))
from max_ultra import themes
from max_ultra.qt import QtWidgets, QtGui, QtSvg
from max_ultra.widgets import Window
from max_ultra.dialogs import PassiveBrowser

app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
windows = [Window(ROOT, title, None) for title in ('Panel', 'Settings', 'Skills')]
picker = QtWidgets.QComboBox(windows[1])
windows[1].outer.addWidget(picker)
browser = PassiveBrowser(windows[2])
windows[2].outer.addWidget(browser)
browser.setHtml('<p style="color:#efb577">Skill help</p><pre>#242320</pre>')
label = QtWidgets.QLabel(windows[0])
windows[0].outer.addWidget(label)
themes.set_label(label, '<a style="color:#efb577">Help</a>')
for identifier in themes.THEMES:
    picker.addItem(identifier, identifier)

def change(index):
    themes.select(picker.itemData(index))
    themes.apply_all(windows)

picker.currentIndexChanged.connect(change)
for window in windows:
    window.show()
picker.showPopup()
app.processEvents()
picker.hidePopup()
# Guard against the exact PySide6 overload failure reported by the user.
def invalid_update(*args):
    raise AssertionError('Do not call item-view update() without an index')
picker.view().update = invalid_update
for identifier in ('plum', 'max', 'forest', 'coffee', 'graphite'):
    picker.setCurrentIndex(picker.findData(identifier))
    app.processEvents()
    for window in windows:
        assert window.palette().color(QtGui.QPalette.Window).name() == themes.THEMES[identifier][1][0]
        assert window.updatesEnabled()
    assert '#242320' in browser.toPlainText()
    assert themes.THEMES[identifier][1][6] in label.text()
renderer = QtSvg.QSvgRenderer(str(ROOT / 'assets/icons/circle-question-mark.svg'))
assert renderer.isValid()
for window in windows:
    window.close()
print('Qt theme dropdown, popup, all windows, rich content and help SVG passed')
