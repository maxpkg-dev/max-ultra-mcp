# Verify clipboard feedback and timer restart with the real Qt event loop.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import sys
from pathlib import Path
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'python'))
from max_ultra.qt import QtWidgets, QtCore
from max_ultra.widgets import copy_action

def wait(milliseconds):
    loop = QtCore.QEventLoop()
    QtCore.QTimer.singleShot(milliseconds, loop.quit)
    loop.exec_()

app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
labels = ['Copy', 'Copy JSON configuration', 'Copy Prompt', 'Copy Template']
value = ['Initial text']
buttons = [copy_action(ROOT, label, lambda: value[0]) for label in labels]
icons = [button.icon().cacheKey() for button in buttons]
clipboard = Mock()
with patch.object(QtWidgets.QApplication, 'clipboard', return_value=clipboard):
    for button in buttons:
        button.click()
    wait(1100)
    value[0] = 'Updated text\nwith newlines'
    for button in buttons:
        button.click()
    clipboard.setText.assert_called_with(value[0])
    wait(1100)
    for button, original_icon in zip(buttons, icons):
        assert button.text() == 'Copied'
        assert button.icon().cacheKey() != original_icon
        assert button.copy_reset.isActive()
    wait(1100)
    for button, label, original_icon in zip(buttons, labels, icons):
        assert button.text() == label
        assert button.accessibleName() == label
        assert button.icon().cacheKey() == original_icon
        assert not button.copy_reset.isActive()
    for button in buttons:
        button.deleteLater()
    app.processEvents()
print('Copy feedback passed: all labels, check icons, live content, two-second reset and repeated clicks')
