# Verify rendered progress capsules and animation lifecycle without Max scenes.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
from max_ultra.qt import QtWidgets, QtGui, QtCore, Qt
from max_ultra.widgets import PillProgressBar
from max_ultra import themes

app = QtWidgets.QApplication.instance()
bar = PillProgressBar()
bar.setTextVisible(False)
bar.show()
try:
    for height in (6, 12, 20):
        bar.setFixedHeight(height)
        for width in (40, 180, 500):
            bar.resize(width, height)
            for value in (0, 1, 5, 50, 100):
                bar.setRange(0, 100)
                bar.setValue(value)
                app.processEvents()
                assert bar.height() == height
                pixels = bar.grab().toImage()
                assert not pixels.isNull()
                # The outermost corner must not be an opaque rectangular fill.
                assert pixels.pixelColor(0, 0).alpha() < 255
                assert bar.value() == value and not bar._animation.isActive()
            bar.setRange(0, 0)
            assert bar._animation.isActive()
            for phase in (0, 20, 40, 60, 79):
                bar._phase = phase
                bar.update()
                app.processEvents()
                pixels = bar.grab().toImage()
                assert pixels.pixelColor(0, 0).alpha() < 255
                assert pixels.pixelColor(pixels.width()-1, 0).alpha() < 255
            bar.hide()
            assert not bar._animation.isActive()
            bar.show()
            assert bar._animation.isActive()
    bar.setFixedHeight(12)
    bar.resize(300, 12)
    bar._phase = 0
    bar.grab().save(str(Path(__file__).resolve().parents[1]/'dist/progress-rounded.png'))
finally:
    bar.close()
print('Progress capsules: determinate, busy endpoints, resizing and hidden animation passed')
