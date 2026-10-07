# Verify visible vector pixels in both embedded Qt versions, including Qt 5.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from max_ultra.qt import QtWidgets, QtGui
from max_ultra.widgets import ActionButton


def run():
    application = QtWidgets.QApplication.instance()
    assert application is not None
    assets = list((ROOT / "assets/icons").glob("*.svg"))
    assets += list((ROOT / "assets/client-logos").glob("*.svg"))
    for asset in assets:
        glyph = QtGui.QIcon(str(asset))
        pixels = glyph.pixmap(64, 64).toImage()
        assert not pixels.isNull(), str(asset)
        opaque = sum(pixels.pixelColor(x, y).alpha() > 32
                     for y in range(pixels.height()) for x in range(pixels.width()))
        assert 20 < opaque < pixels.width() * pixels.height() * 0.8, str(asset)
        if asset.parent.name == "client-logos":
            points = [(x, y) for y in range(pixels.height()) for x in range(pixels.width())
                      if pixels.pixelColor(x, y).alpha() > 32]
            span = max(max(x for x, y in points) - min(x for x, y in points) + 1,
                       max(y for x, y in points) - min(y for x, y in points) + 1)
            assert 49 <= span <= 53, "Unequal visible logo size: " + str(asset)
            assert all(min(pixels.pixelColor(x, y).red(), pixels.pixelColor(x, y).green(),
                           pixels.pixelColor(x, y).blue()) > 240 for x, y in points), str(asset)
        # Painting must not clear a borrowed PySide2 QIcon through its style option.
        button = ActionButton()
        button.resize(80, 80)
        button.setIconSize(pixels.size())
        button.setStyleSheet("QToolButton { background:#000; border:none; }")
        button.setIcon(glyph)
        painted = button.grab().toImage()
        visible = sum(painted.pixelColor(x, y).lightness() > 40
                      for y in range(10, 70) for x in range(10, 70))
        assert visible > 20, "Button lost SVG artwork: " + str(asset)
        button.deleteLater()
    antigravity = QtGui.QIcon(str(ROOT / "assets/client-logos/antigravity.svg")).pixmap(180, 180).toImage()
    assert antigravity.pixelColor(90, 50).alpha() > 200
    assert antigravity.pixelColor(90, 140).alpha() == 0, "Antigravity silhouette lost its open bottom"
    assert antigravity.pixelColor(25, 30).alpha() == 0, "Unclipped Antigravity artwork"
    application.processEvents()
    return "All action and client SVGs render visible pixels; Antigravity silhouette is intact"


if __name__ == "__main__":
    application = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    print(run())
