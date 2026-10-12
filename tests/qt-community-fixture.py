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
from max_ultra.dialogs import ResponsiveSkillBrowser, SkillsWindow
from max_ultra.widgets import Window
from unittest.mock import patch
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
    assert 'background:@ready_background' in window.install_buttons[0][0]._theme_style
    window.set_busy(False)
    assert window.search.cursor().shape() == Qt.IBeamCursor
    assert window.install_buttons[0][0].cursor().shape() == Qt.PointingHandCursor
    window.install_buttons[0][0].click()
    assert calls[0] == ('community-install', ['-SkillId', 'example-skill', '-Source', '1.0.0', '-Revision', 'a'*64])
    window.set_busy(True)
    assert not window.install_buttons[0][0].isEnabled() and not window.retry.isEnabled()
    assert window.install_buttons[0][0].cursor().shape() == Qt.ArrowCursor
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
    assert window.install_buttons[0][0].cursor().shape() == Qt.ArrowCursor
    entry.update(installedId='user/00000000-0000-4000-8000-000000000000', installedRevision='fixture-revision')
    window.render_cards()
    trash = window.install_buttons[1][0]
    assert trash.cursor().shape() == Qt.PointingHandCursor
    assert trash.toolButtonStyle() == Qt.ToolButtonIconOnly and 'background:@delete_background' in trash._theme_style
    assert trash.toolTip() == 'Delete Installed Skill' and trash.accessibleName() == 'Delete Installed Skill'
    previous = len(calls)
    with patch.object(QtWidgets.QMessageBox, 'question', return_value=QtWidgets.QMessageBox.No):
        trash.click()
    assert len(calls) == previous
    with patch.object(QtWidgets.QMessageBox, 'question', return_value=QtWidgets.QMessageBox.Yes):
        trash.click()
    assert calls[-1][0] == 'community-delete' and calls[-1][1][1] == entry['installedId']
    window.set_busy(True)
    assert not trash.isEnabled()
    assert trash.cursor().shape() == Qt.ArrowCursor
    window.set_busy(False)
    window.resize(760, 600)
    app.processEvents()
    window.grab().save(str(root/'dist'/'community-delete-card.png'))
    window.show_error('Offline')
    assert 'Open Online Catalog' in window.status.text() and window.retry.isEnabled()
    empty = configparser.ConfigParser()
    empty.read_dict({'result': {'haslist': 'true', 'count': '0'}})
    window.sync_installed(empty)
    assert window.entries[0]['installState'] == 'available' and not window.entries[0]['installedId']
    assert len(window.install_buttons) == 1 and window.install_buttons[0][0].text() == 'Install'
    window.entries = []
    window.render_cards()
    assert not window.install_buttons
    # Real source -> store -> CLI INI -> Qt item -> About, no synthetic metadata shortcut.
    expected = {'max-ultra-floor-plan': 'Anastasiia Reznichenko', 'max-ultra-camera-composition': 'Yuriy Bobak', 'max-ultra-small-house-detailing': 'Yuriy Bobak, Anastasiia Reznichenko'}
    ini_text = subprocess.check_output([str(root/'runtime/win-x64/node.exe'), '-e', "const {SkillStore}=require('./core/skill-store');process.stdout.write(require('./core/skills-cli').ini({skills:new SkillStore().builtins()}))"], cwd=str(root), creationflags=subprocess.CREATE_NO_WINDOW).decode('utf-8')
    snapshot = configparser.ConfigParser()
    snapshot.read_string(ini_text)
    fixture_client = SimpleNamespace(root=root, settings=SimpleNamespace(get=lambda *args: 'builtin'), save_setting=lambda *args: True, skills_operation=lambda *args: None, donate=lambda: None)
    skills = SkillsWindow(fixture_client, None)
    install = next(button for button in skills.buttons if button.text() == 'Install Community Skills')
    assert not install.icon().isNull() and '@ready_background' in install._theme_style
    rows = [skills.outer.itemAt(i).layout() for i in range(skills.outer.count()) if skills.outer.itemAt(i).layout()]
    import_row = next(row for row in rows if row.count() and row.itemAt(0).widget() is install)
    assert [import_row.itemAt(i).widget().text() for i in range(import_row.count()) if import_row.itemAt(i).widget()][:3] == ['Install Community Skills', 'Import Folder', 'Import ZIPs']
    assert import_row.itemAt(import_row.count()-1).widget() is skills.delete_button
    assert import_row.itemAt(import_row.count()-2).spacerItem() is not None
    assert 'background:@delete_background' in skills.delete_button._theme_style
    assert import_row.itemAt(1).spacerItem().sizeHint().width() == 14
    assert sum(button.text() == 'Install Community Skills' for button in skills.buttons) == 1
    assert any(button.text() == 'Open Online Catalog' for button in window.findChildren(QtWidgets.QToolButton))
    skills.apply_result(SimpleNamespace(snapshot=snapshot, result=root/'dist'/'missing-author-fixture'))
    seen = []
    def inspect_about(dialog):
        text = dialog.findChild(QtWidgets.QTextBrowser).toPlainText()
        assert ('Author: ' + wanted) in text and 'Not specified' not in text
        seen.append(wanted)
        return 0
    try:
        for index in range(skills.list.topLevelItemCount()):
            item = skills.list.topLevelItem(index)
            identifier = item.data(0, Qt.UserRole)[0].split('/')[-1]
            wanted = expected.get(identifier, 'Lukianenko Vasyl')
            assert item.data(0, Qt.UserRole+1)['author'] == wanted
            with patch.object(Window, 'exec_', inspect_about):
                skills.show_skill_about(item)
        assert len(seen) == 9
    finally:
        skills.close()
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
        themes.apply(window)
        assert themes.style('@community_card_background') != themes.style('@window_background')
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
