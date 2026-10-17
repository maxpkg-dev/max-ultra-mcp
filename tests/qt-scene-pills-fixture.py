# Verify scene capsule clipboard values and independent feedback without scenes.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))
from max_ultra.qt import QtWidgets, QtCore, QtGui, Qt
from max_ultra.widgets import ScenePills
from max_ultra import themes
themes.select('graphite')
def wait(milliseconds):
    deadline = time.monotonic() + milliseconds / 1000
    while time.monotonic() < deadline:
        app.processEvents()
        time.sleep(0.01)

app = QtWidgets.QApplication.instance()
if app is None:
    raise RuntimeError('Run this fixture in a dedicated Qt test host with an existing application')
pills = ScenePills()
pills.setText('PID 34343 | Scene Example.max | Objects 25 | Selection 3')
pills.scene_path = 'C:/ExampleProject/Example.max'
pills.resize(900, 40)
pills.show()
app.processEvents()

def click(index):
    app.processEvents()
    rectangle = next(rect for key, rect in pills._hit_regions if key == index)
    for kind, buttons in ((QtCore.QEvent.MouseButtonPress, Qt.LeftButton), (QtCore.QEvent.MouseButtonRelease, Qt.NoButton)):
        event = QtGui.QMouseEvent(kind, rectangle.center(), Qt.LeftButton, buttons, Qt.NoModifier)
        app.sendEvent(pills, event)
    app.processEvents()

try:
    for index, value in enumerate(['PID 34343', pills.scene_path, 'Objects 25', 'Selection 3']):
        click(index)
        assert app.clipboard().text() == value
        assert index in pills._copied
    wait(1100)
    click(0)
    pills.setText('PID 34343 | Scene Example.max | Objects 26 | Selection 4')
    wait(1100)
    assert pills._copied == {0}
    wait(1100)
    assert not pills._copied
    click(3)
    assert app.clipboard().text() == 'Selection 4'
    for width in (280, 500, 1250, 1800):
        pills.resize(width, 40)
        app.processEvents()
        click(2)
        assert app.clipboard().text() == 'Objects 26'
    pills.scene_path = ''
    app.clipboard().setText('unchanged')
    click(1)
    assert app.clipboard().text() == 'Untitled'
    print('Scene capsule clipboard, compact mapping, repeated clicks and timed feedback passed')
finally:
    pills.close()
