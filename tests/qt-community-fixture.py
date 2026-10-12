# Exercise the native catalog and import report without network or user state.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import configparser
import json
import subprocess
from pathlib import Path
from types import SimpleNamespace
from max_ultra.qt import QtWidgets, QtCore, QtGui, Qt
from max_ultra import themes
from max_ultra.community_dialog import CommunityWindow
from max_ultra.dialogs import ResponsiveSkillBrowser
from max_ultra.wire import encode

root = Path(__file__).resolve().parents[1]
app = QtWidgets.QApplication.instance()
calls = []
client = SimpleNamespace(root=root, skills_operation=lambda *args: calls.append(args) or True)
window = CommunityWindow(client, None)
entry = dict(id='example-skill', name='example-skill', title='Example Skill', author='Example Author', description='A readable description of a synthetic workflow. ' * 3, version='1.0.0', sha256='a'*64, installState='available')
parser = configparser.ConfigParser()
parser.read_dict({'result': {'ok': 'true', 'message': encode('Choose a skill'), 'community': encode(json.dumps([entry]))}})
try:
    window.show()
    window.apply_result(SimpleNamespace(snapshot=parser))
    assert not calls, 'Viewing a catalog must never install'
    window.set_busy(False)
    window.install_buttons[0][0].click()
    assert calls[0] == ('community-install', ['-SkillId', 'example-skill', '-Source', '1.0.0', '-Revision', 'a'*64])
    window.set_busy(True)
    assert not window.install_buttons[0][0].isEnabled() and not window.retry.isEnabled()
    window.set_busy(False)
    for width in (320, 760, 1800):
        window.resize(width, 600)
        app.processEvents()
        assert window.scroll.horizontalScrollBar().maximum() == 0
        if width == 760:
            window.grab().save(str(root/'dist'/'community-catalog.png'))
    window.search.setText('no match')
    assert window.card_widgets[0][0].isHidden()
    window.search.clear()
    entry['installState'] = 'installed'
    window.entries = [entry]
    window.render_cards()
    assert not window.install_buttons[0][0].isEnabled()
    window.show_error('Offline')
    assert 'Open catalog' in window.status.text() and window.retry.isEnabled()
    window.entries = []
    window.render_cards()
    assert not window.install_buttons
    report = subprocess.check_output([str(root/'runtime/win-x64/node.exe'), '-e', "process.stdout.write(require('./core/skill-markdown').renderImportReport([{name:'Example imported skill'}],[{name:'Other skill',reason:'Example conflict'}]))"], cwd=str(root), creationflags=subprocess.CREATE_NO_WINDOW).decode('utf-8')
    browser = ResponsiveSkillBrowser()
    browser.resize(640, 540)
    browser.show()
    for name in ('graphite', 'max'):
        themes.select(name)
        if name == 'max':
            themes.max_colors = {key: '#eeeeee' for key in themes.definition['colorMan']}
            themes.max_colors['text'] = '#202020'
            themes.max_colors['windowText'] = '#202020'
        themes.apply(browser)
        browser.setHtml(report)
        app.processEvents()
        for word in ('1 imported', 'Example imported skill', 'Example conflict'):
            cursor = browser.document().find(word)
            assert not cursor.isNull()
            assert cursor.charFormat().foreground().color().name() == themes.style('@field_text')
        tables = [frame for frame in browser.document().rootFrame().childFrames() if isinstance(frame, QtGui.QTextTable)]
        assert len(tables) == 2
        assert tables[0].cellAt(0,0).format().toTableCellFormat().topBorder() > 0
        browser.grab().save(str(root/'dist'/('import-report-'+name+'.png')))
    browser.close()
finally:
    themes.max_colors = {}
    themes.select('graphite')
    window.close()
print('Community UI: click-only install, busy/error/empty states, narrow layout and themed report passed')
