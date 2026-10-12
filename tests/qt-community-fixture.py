# Exercise the native catalog and import report without network or user state.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import configparser
import json
import subprocess
import tempfile
from pathlib import Path
from types import SimpleNamespace
from max_ultra.qt import QtWidgets, QtCore, QtGui, Qt
from max_ultra import themes
from max_ultra.community_dialog import CommunityWindow, MetadataBadge, display_date
from max_ultra.dialogs import ResponsiveSkillBrowser, SkillsWindow
from max_ultra.widgets import Window, DESTRUCTIVE_STYLE
from unittest.mock import patch
from max_ultra.wire import encode
from max_ultra.helpers import Helper

root = Path(__file__).resolve().parents[1]
app = QtWidgets.QApplication.instance()
calls = []
client = SimpleNamespace(root=root, skills_operation=lambda *args: calls.append(args) or True)
window = CommunityWindow(client, None)
entry = dict(id='example-skill', name='example-skill', title='Example Skill', author='Example Author', description='A readable description of a synthetic workflow. ' * 3, version='1.0.0', sha256='a'*64, installState='available')
parser = configparser.ConfigParser()
parser.read_dict({'result': {'ok': 'true', 'message': encode('Choose a skill'), 'community': encode(json.dumps([entry]))}})
try:
    assert display_date('2026-06-13') == '13 Jun, 2026'
    assert display_date('2026-02-30') == ''
    window.show()
    window.apply_result(SimpleNamespace(snapshot=parser))
    assert not calls, 'Viewing a catalog must never install'
    links = [label for label in window.findChildren(QtWidgets.QLabel) if 'View details</a>' in label.text()]
    assert len(links) == 1 and '/docs/skills/example-skill.html' in links[0].text()
    assert links[0].openExternalLinks()
    confirmation = QtWidgets.QMessageBox(window)
    confirmation.setText('Delete this synthetic skill?')
    confirmation.setStandardButtons(QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No)
    confirmation.show()
    app.processEvents()
    yes, no = confirmation.button(QtWidgets.QMessageBox.Yes), confirmation.button(QtWidgets.QMessageBox.No)
    assert yes.width() >= 90 and yes.height() >= 36
    assert abs(yes.x() - no.x()) >= min(yes.width(), no.width()) + 6
    confirmation.close()
    assert 'background:@ready_background' in window.install_buttons[0][0]._theme_style
    window.set_busy(False)
    assert window.search.cursor().shape() == Qt.IBeamCursor
    assert window.install_buttons[0][0].cursor().shape() == Qt.PointingHandCursor
    window.install_buttons[0][0].click()
    assert calls[0] == ('community-install', ['-SkillId', 'example-skill', '-Source', '1.0.0', '-Revision', 'a'*64])
    window.set_busy(True)
    app.processEvents()
    assert window.progress.height() == 12
    window.show_progress({'phase': 'download', 'bytes': 512, 'total': 1024})
    assert window.progress.value() == 512 and '50%' in window.status.text()
    window.show_progress({'phase': 'download', 'bytes': 512, 'total': None})
    assert window.progress.maximum() == 0 and '%' not in window.status.text()
    window.show_progress({'phase': 'verify'})
    assert window.progress.maximum() == 0 and 'Verifying' in window.status.text()
    with tempfile.TemporaryDirectory() as folder:
        helper = Helper.__new__(Helper)
        helper.result = Path(folder) / 'operation.ini'
        assert helper.read_progress() is None
        progress_file = Path(str(helper.result) + '.progress.json')
        progress_file.write_text(json.dumps({'phase': 'download', 'bytes': 75, 'total': 100}))
        window.show_progress(helper.read_progress())
        assert window.progress.value() == 75 and '75%' in window.status.text()
        progress_file.write_text('{')
        assert helper.read_progress() is None
    assert not window.install_buttons[0][0].isEnabled() and not window.retry.isEnabled()
    assert window.install_buttons[0][0].cursor().shape() == Qt.ArrowCursor
    window.set_busy(False)
    for width in (320, 760, 1800):
        window.resize(width, 600)
        app.processEvents()
        assert window.scroll.horizontalScrollBar().maximum() == 0
        card = window.card_widgets[0][0]
        assert card.mapTo(window, QtCore.QPoint(0, 0)).x() == window.search.x()
        assert card.width() == window.scroll.viewport().width()
        badges = window.card_widgets[0][0].findChildren(MetadataBadge)
        assert len(badges) == 3
        assert [badge.toolTip() for badge in badges] == ['Example Author', '1.0.0', 'Not specified']
        assert all(not badge.wordWrap() and badge.fontMetrics().height() <= badge.height() <= badge.fontMetrics().height() + 4 for badge in badges)
        assert badges[0].accessibleName() == 'Author: Example Author'
        assert badges[1].accessibleName() == 'Version: 1.0.0'
        if width == 760:
            window.grab().save(str(root/'dist'/'community-catalog.png'))
    window.search.setText('no match')
    assert window.card_widgets[0][0].isHidden()
    window.search.clear()
    for policy in (Qt.ScrollBarAlwaysOn, Qt.ScrollBarAlwaysOff):
        window.scroll.setVerticalScrollBarPolicy(policy)
        for _ in range(3):
            app.processEvents()
        card = window.card_widgets[0][0]
        assert card.mapTo(window, QtCore.QPoint(0, 0)).x() == window.search.x()
        assert card.width() == window.scroll.viewport().width()
    window.scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
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
    assert trash._theme_style == DESTRUCTIVE_STYLE
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
    install = next(button for button in skills.buttons if button.text() == 'Discover Community Skills')
    assert not install.icon().isNull() and '@ready_background' in install._theme_style
    rows = [skills.outer.itemAt(i).layout() for i in range(skills.outer.count()) if skills.outer.itemAt(i).layout()]
    import_row = next(row for row in rows if row.count() and row.itemAt(0).widget() is install)
    assert [import_row.itemAt(i).widget().text() for i in range(import_row.count()) if import_row.itemAt(i).widget()][:3] == ['Discover Community Skills', 'Import Folder', 'Import ZIPs']
    assert import_row.itemAt(import_row.count()-1).widget() is skills.delete_button
    assert import_row.itemAt(import_row.count()-2).spacerItem() is not None
    assert 'background:@delete_background' in skills.delete_button._theme_style
    assert skills.delete_button._theme_style == DESTRUCTIVE_STYLE
    assert import_row.itemAt(1).spacerItem().sizeHint().width() == 14
    assert sum(button.text() == 'Discover Community Skills' for button in skills.buttons) == 1
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
        custom = QtWidgets.QTreeWidgetItem(['Example', 'Geometry fixture'])
        custom.setData(0, Qt.UserRole, ('user/example', 'Custom'))
        skills.list.addTopLevelItem(custom)
        skills.source.setCurrentIndex(1)
        skills.list.setCurrentItem(custom)
        skills.show()
        other = QtWidgets.QTreeWidgetItem(['Other', 'Context target'])
        other.setData(0, Qt.UserRole, ('user/other', 'Custom'))
        skills.list.addTopLevelItem(other)
        app.processEvents()
        before_context = list(calls)
        position = skills.list.visualItemRect(other).center()
        press = QtGui.QMouseEvent(QtCore.QEvent.MouseButtonPress, QtCore.QPointF(position), Qt.RightButton, Qt.RightButton, Qt.NoModifier)
        QtWidgets.QApplication.sendEvent(skills.list.viewport(), press)
        assert skills.list.currentItem() is custom and calls == before_context
        with patch('max_ultra.dialogs.SkillsMenu.exec_', return_value=0) as popup:
            skills.show_skill_menu(position)
            assert popup.call_count == 1 and calls == before_context
        for width in (1040, 800, 620, 500, 400, 320, 1040):
            skills.resize(width, 600)
            for _ in range(3):
                app.processEvents()
            assert skills.delete_button.isVisible()
            assert skills.delete_button.width() == skills.donate_button.width()
            assert install.toolButtonStyle() == Qt.ToolButtonTextBesideIcon
            imports = [button for button in skills.buttons if button.text() in ('Import Folder', 'Import ZIPs')]
            assert imports[0].toolButtonStyle() == imports[1].toolButtonStyle()
            help_buttons = [button for button in skills.buttons if button.text() in ('How to create and import skills', 'Submit Your Skill')]
            assert all(button.toolButtonStyle() == Qt.ToolButtonTextBesideIcon for button in help_buttons)
            assert all(button.width() > button.iconSize().width() + 20 for button in help_buttons)
            assert help_buttons[0].geometry().right() + 4 < help_buttons[1].geometry().left(), [button.geometry() for button in help_buttons]
            assert help_buttons[1].geometry().right() + 4 < skills.donate_button.geometry().left()
            if skills.donate_button.toolButtonStyle() == Qt.ToolButtonIconOnly:
                assert skills.delete_button.toolButtonStyle() == Qt.ToolButtonIconOnly
            if width == 800:
                assert all(button.toolButtonStyle() == Qt.ToolButtonTextBesideIcon for button in help_buttons)
            if width == 320:
                imports = [button for button in skills.buttons if button.text() in ('Import Folder', 'Import ZIPs')]
                assert all(button.toolButtonStyle() == Qt.ToolButtonIconOnly for button in imports)
            assert skills.delete_button.mapTo(skills, QtCore.QPoint(skills.delete_button.width(), 0)).x() == skills.donate_button.mapTo(skills, QtCore.QPoint(skills.donate_button.width(), 0)).x()

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
    entry['author'] = 'A long author name together with another long contributor name'
    window.entries = [entry]
    window.render_cards()
    window.resize(320, 600)
    for _ in range(3):
        app.processEvents()
    badges = window.card_widgets[0][0].findChildren(MetadataBadge)
    assert len(badges) == 3 and all(not badge.wordWrap() for badge in badges)
    assert badges[0].toolTip() == entry['author']
    assert badges[0].text() == entry['author'], 'Author must remain complete'
    assert badges[0].width() >= badges[0].fontMetrics().horizontalAdvance(entry['author']) + 14
    assert window.scroll.horizontalScrollBar().maximum() == 0
finally:
    themes.max_colors = {}
    themes.select('graphite')
    window.close()
print('Community UI: click-only install, busy/error/empty states, narrow layout and themed report passed')
