# Exercise the unified Skills window: cards, catalog, automatic updates and import report without network or user state.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import configparser
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from types import SimpleNamespace
from max_ultra.qt import QtWidgets, QtCore, QtGui, Qt
from max_ultra import themes
from max_ultra.skills_window import SkillsWindow, SkillDetailsWindow, MetadataBadge, newer_version
from max_ultra.dialogs import ResponsiveSkillBrowser
from max_ultra.widgets import DESTRUCTIVE_STYLE
from unittest.mock import patch
from max_ultra.wire import encode
from max_ultra.helpers import Helper

root = Path(__file__).resolve().parents[1]
(root / 'dist').mkdir(exist_ok=True)
app = QtWidgets.QApplication.instance()
calls, catalog_calls, page_calls, saved, accept = [], [], [], [], [True]
state = Path(tempfile.mkdtemp(prefix='max-ultra-skills-fixture-'))
# Keep the first paint away from the real per-user skill store.
previous_store = os.environ.get('MAX_ULTRA_MCP_SKILLS_ROOT')
os.environ['MAX_ULTRA_MCP_SKILLS_ROOT'] = str(state / 'store')
client = SimpleNamespace(root=root, dialogs={}, skills_operation_name='', state_directory=state,
                         settings=SimpleNamespace(get=lambda section, key, default: default), save_setting=lambda *args: saved.append(args) or True, donate=lambda: None)


def skills_operation(name, arguments=None):
    if not accept[0]:
        return False
    calls.append((name, arguments))
    client.skills_operation_name = name
    return True


def show_dialog(key, kind):
    if key not in client.dialogs:
        client.dialogs[key] = kind(client, None)
    client.dialogs[key].show()
    return client.dialogs[key]


client.skills_operation = skills_operation
client.catalog_operation = lambda: catalog_calls.append(1) or True
client.page_operation = lambda identifier: page_calls.append(identifier) or True
client.show_dialog = show_dialog
# Real source -> store -> CLI INI -> Qt card, no synthetic metadata shortcut for built-in skills.
builtin_ini = subprocess.check_output([str(root/'runtime/win-x64/node.exe'), '-e', "const {SkillStore}=require('./core/skill-store');process.stdout.write(require('./core/skills-cli').ini({skills:new SkillStore().builtins()}))"], cwd=str(root), creationflags=subprocess.CREATE_NO_WINDOW).decode('utf-8')
custom_identifier = 'user/00000000-0000-4000-8000-000000000000'


def local_result(custom=()):
    parser = configparser.ConfigParser()
    parser.read_string(builtin_ini)
    count = parser.getint('result', 'count')
    for offset, skill in enumerate(custom):
        parser['skill' + str(count + offset)] = {key: encode(value) for key, value in skill.items()}
    parser.set('result', 'count', str(count + len(custom)))
    return SimpleNamespace(snapshot=parser, result=state / 'missing-result')


def catalog_result(entries):
    parser = configparser.ConfigParser()
    parser.read_dict({'result': {'ok': 'true', 'message': encode('Choose a skill'), 'community': encode(json.dumps(entries))}})
    return SimpleNamespace(snapshot=parser, result=state / 'missing-result')


def finish(window, result):
    window.apply_result(result)
    window.operation_finished()
    window.set_busy(False)


def settle():
    for _ in range(3):
        app.processEvents()


entry = dict(id='example-skill', name='example-skill', title='Example Skill', author='Example Author', description='A readable description of a synthetic workflow. ' * 3, version='1.0.0', sha256='a'*64, installState='available')
installed = dict(id=custom_identifier, name='example-skill', title='Example Skill', author='Example Author', description='A readable description.', version='1.0.0', source='Custom', displaySource='Community Skills', state='ready', revision='fixture-revision')
window = SkillsWindow(client, None)
client.dialogs['skills'] = window
try:
    assert newer_version('1.10.0', '1.9.9') and not newer_version('1.0.0', '1.0.0') and not newer_version('1.0.0', '') and not newer_version('next', '1.0.0')
    direct = {skill['id']: skill for skill in window.local}
    assert len(direct) >= 9 and all(skill['source'] == 'Built-in' for skill in direct.values()), 'Built-in skills are read from disk at once'
    assert window.category == 'community' and not window.sections['builtin'].grid.cards, 'Cards behind the other filter are not built at opening'
    first_builtin = window.ensure_cards('builtin')[0]
    assert len(window.sections['builtin'].grid.cards) == len(direct) and not calls
    window.show()
    window.refresh()
    settle()
    assert not calls and catalog_calls == [1], 'Refreshing reads local skills from disk and starts one helper, for the catalog only'
    client.skills_operation_name = 'list'
    community = window.sections['community']
    assert community.header.spinner.isVisible() and community.hint.text() == 'Loading the community catalog...'
    assert window.search.isEnabled() and window.import_folder_button.isEnabled(), 'Loading never blocks the window'
    finish(window, local_result())
    for skill in window.local:
        for field in ('name', 'title', 'description', 'displayDescription', 'author', 'version', 'displaySource', 'website', 'email', 'state'):
            assert direct[skill['id']][field] == skill[field], ('The first paint must match the validated list', skill['id'], field)
    assert window.sections['builtin'].grid.cards[0] is first_builtin, 'An answer that changes nothing does not rebuild the cards'
    expected = {'max-ultra-floor-plan': 'Anastasiia Reznichenko', 'max-ultra-camera-composition': 'Yuriy Bobak', 'max-ultra-small-house-detailing': 'Yuriy Bobak, Anastasiia Reznichenko'}
    builtin_cards = window.sections['builtin'].grid.cards
    assert len(builtin_cards) >= 9
    for card in builtin_cards:
        wanted = expected.get(card.item['local']['id'].split('/')[-1], 'Lukianenko Vasyl')
        assert card.item['author'] == wanted and wanted in [badge.text() for badge in card.findChildren(MetadataBadge)]
        assert card.delete_button is None and card.install_button is None
    assert [card.item['title'] for card in builtin_cards] == sorted((card.item['title'] for card in builtin_cards), key=str.casefold)
    window.apply_catalog(catalog_result([entry]))
    settle()
    assert not calls, 'Viewing a catalog must never install'
    assert not community.header.spinner.isVisible() and community.header.note.text() == '1'
    assert [chip.text() for chip in window.navigation.values()] == ['Community 1', 'Built-in {}'.format(len(builtin_cards))]
    assert window.sections['installed'].hint.text().startswith('No skills are installed yet') and community.header.title.text() == 'Not installed'
    card = community.grid.cards[0]
    assert 'dashed' in card._theme_style, 'Cards that are not installed are visually separate'
    assert 'background:@ready_background' in card.install_button._theme_style and card.delete_button is None
    assert window.search.cursor().shape() == Qt.IBeamCursor
    assert card.install_button.cursor().shape() == Qt.PointingHandCursor and card.details_button.cursor().shape() == Qt.PointingHandCursor
    confirmation = QtWidgets.QMessageBox(window)
    confirmation.setText('Delete this synthetic skill?')
    confirmation.setStandardButtons(QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No)
    confirmation.show()
    app.processEvents()
    yes, no = confirmation.button(QtWidgets.QMessageBox.Yes), confirmation.button(QtWidgets.QMessageBox.No)
    assert yes.width() >= 90 and yes.height() >= 36
    assert abs(yes.x() - no.x()) >= min(yes.width(), no.width()) + 6
    confirmation.close()
    card.details_button.click()
    details = client.dialogs['skill_details']
    settle()
    assert details.title.text() == 'Example Skill' and details.online_button.isVisible() and not details.folder_button.isVisible()
    assert not calls, 'Opening details never starts a skill operation'
    overlay = details.loading_overlay
    assert page_calls == ['example-skill'] and overlay.isVisible() and overlay.timer.isActive() and overlay.size() == details.preview.size(), 'The online description loads behind the shared loader'

    def page_result(text, ok='true', message=''):
        answer = configparser.ConfigParser()
        answer.read_dict({'result': {'ok': ok, 'message': encode(message), 'text': encode(text)}})
        return SimpleNamespace(snapshot=answer, result=state / 'missing-result')

    details.apply_page('another-skill', page_result('# Other\n\nStale answer.'))
    assert overlay.isVisible() and 'Stale answer' not in details.preview.toPlainText(), 'An answer for a skill that is no longer shown is ignored'
    details.apply_page('example-skill', page_result('<!-- generated -->\n# Example Skill\n\nBy **Example Author**.\n\n## How to use\n\nOnline description body. [Guide](../INSTALL.md) <b>raw</b>\n'))
    shown = details.preview.toPlainText()
    assert overlay.isHidden() and not overlay.timer.isActive() and details.preview.isVisible() and details.filler.isHidden() and details.summary.isHidden()
    assert 'Online description body.' in shown and 'How to use' in shown and 'generated' not in shown, 'The online description is shown inside the window'
    assert not shown.lstrip().startswith('Example Skill'), 'The title is not repeated above the description'
    assert '<b>raw</b>' in shown, 'Raw HTML from the network is shown as text, never interpreted'
    with patch.object(QtGui.QDesktopServices, 'openUrl', return_value=True) as opener:
        details.navigate(QtCore.QUrl('../INSTALL.md'))
        assert opener.call_args[0][0].toString() == 'https://maxpkg-dev.github.io/max-ultra-mcp-community-skills/docs/INSTALL.md'
        details.navigate(QtCore.QUrl('../../../outside.md'))
        assert opener.call_count == 1, 'A relative link never leaves the catalog site'
    card.details_button.click()
    assert page_calls == ['example-skill'] and 'Online description body.' in details.preview.toPlainText(), 'A description read once is shown again without a request'
    other = dict(card.item, title='Other Skill', catalog=dict(entry, id='other-skill'))
    details.show_item(other)
    settle()
    assert page_calls == ['example-skill', 'other-skill'] and overlay.isVisible() and not details.preview.toPlainText().strip()
    details.page_failed('other-skill', 'Cannot reach the community catalog.')
    settle()
    assert overlay.isHidden() and details.preview.isHidden() and details.filler.isVisible() and details.summary.isVisible(), 'Without a connection the window offers the online page instead'
    assert not details.note.text() and 'could not be loaded' in details.fallback.text() and 'online page' in details.fallback.text()
    button = details.fallback_button
    assert button.isVisible() and button.text() == 'Open Online Page'
    assert abs(button.mapTo(details, button.rect().center()).x() - details.width() // 2) <= 12, 'The fallback action is centered in the window'
    with patch.object(QtGui.QDesktopServices, 'openUrl', return_value=True) as opener:
        button.click()
        assert opener.call_args[0][0].toString().endswith('/docs/skills/other-skill.html')
    details.apply_page('other-skill', page_result('', 'false', 'The online description exceeds the size limit.'))
    assert details.filler.isVisible() and not details.note.text(), 'A refused answer falls back the same way'
    client.page_operation = lambda identifier: False
    details.show_item(dict(card.item, title='Third Skill', catalog=dict(entry, id='third-skill')))
    assert details.filler.isVisible() and overlay.isHidden(), 'A request that cannot start falls back at once'
    client.page_operation = lambda identifier: page_calls.append(identifier) or True
    card.details_button.click()
    assert details.title.text() == 'Example Skill' and details.preview.isVisible() and details.filler.isHidden()
    with patch.object(QtGui.QDesktopServices, 'openUrl', return_value=True) as opener:
        details.open_online()
        assert opener.call_args[0][0].toString().endswith('/docs/skills/example-skill.html')
    card.install_button.click()
    assert calls[-1] == ('community-install', ['-SkillId', 'example-skill', '-Source', '1.0.0', '-Revision', 'a'*64])
    assert window.status.text().startswith('Downloading, verifying and importing Example Skill')
    started = window.operation_started
    with patch('max_ultra.skills_window.time.monotonic', return_value=started + 12.9):
        window.update_elapsed()
    assert window.elapsed.text() == '12 s' and window.elapsed_timer.isActive()
    window.set_busy(True)
    assert window.operation_started == started
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
    assert not card.install_button.isEnabled() and not window.refresh_button.isEnabled() and not window.import_zips_button.isEnabled()
    assert card.install_button.cursor().shape() == Qt.ArrowCursor
    assert card.details_button.isEnabled() and window.search.isEnabled(), 'Reading stays available while a skill installs'
    window.set_busy(False)
    assert window.elapsed.isHidden() and not window.elapsed_timer.isActive() and card.install_button.isEnabled()
    for width, columns in ((380, 1), (760, 2), (1180, 3), (1800, 4)):
        window.resize(width, 700)
        window.navigation['builtin'].click()
        settle()
        grid = window.sections['builtin'].grid
        assert window.scroll.horizontalScrollBar().maximum() == 0
        assert grid.columns == columns, (width, grid.columns)
        assert all(item.geometry().right() < grid.width() for item in grid.cards)
        assert len({item.height() for item in grid.cards[:columns]}) == 1, 'Cards in one row share a height'
        builtin_height = grid.cards[0].height()
        if width == 1180:
            window.grab().save(str(root/'dist'/'skills-window-builtin.png'))
        window.navigation['community'].click()
        settle()
        assert window.scroll.horizontalScrollBar().maximum() == 0 and community.grid.columns == columns
        assert 0.8 < builtin_height / community.grid.cards[0].height() < 1.25, 'Built-in cards use the same full layout as community cards'
        assert window.compact == (width < SkillsWindow.COMPACT_WIDTH)
        badges = community.grid.cards[0].findChildren(MetadataBadge)
        assert [badge.toolTip() for badge in badges] == ['Not installed', 'Example Author', '1.0.0']
        assert all(not badge.wordWrap() and badge.fontMetrics().height() <= badge.height() <= badge.fontMetrics().height() + 4 for badge in badges)
        assert badges[1].accessibleName() == 'Author: Example Author' and badges[2].accessibleName() == 'Version: 1.0.0'
        if width == 1180:
            window.grab().save(str(root/'dist'/'skills-window.png'))
            window.scroll.verticalScrollBar().setValue(window.scroll.verticalScrollBar().maximum())
            settle()
            window.grab().save(str(root/'dist'/'skills-window-community.png'))
    window.resize(1180, 820)
    settle()
    window.search.setText('no match')
    assert all(item.isHidden() for section in window.sections.values() for item in section.grid.cards)
    assert not window.empty.isHidden() and all(section.header.isHidden() for section in window.sections.values())
    window.search.setText('EXAMPLE author')
    assert not community.grid.cards[0].isHidden() and window.sections['builtin'].grid.isHidden() and window.empty.isHidden()
    window.search.setText('camera composition')
    builtin = window.sections['builtin']
    assert not builtin.header.isHidden() and int(builtin.header.note.text()) >= 1 and community.grid.isHidden(), 'A search also finds built-in skills from the Community filter'
    window.search.clear()
    assert builtin.grid.isHidden() and builtin.header.isHidden() and not community.header.isHidden()
    window.navigation['builtin'].click()
    assert window.category == 'builtin' and not saved, 'The chosen filter is not remembered'
    assert community.header.isHidden() and window.sections['installed'].header.isHidden() and not builtin.grid.isHidden() and builtin.header.isHidden()
    window.navigation['community'].click()
    assert not community.header.isHidden() and builtin.grid.isHidden()
    client.skills_operation_name = 'community-install'
    finish(window, local_result([installed]))
    settle()
    assert not community.grid.cards and community.hint.text() == 'Every published community skill is already installed.', 'An installed skill is not repeated under Community'
    owned_card = window.sections['installed'].grid.cards[0]
    assert owned_card.item['catalog'] == entry and not owned_card.item['notice']
    assert [badge.text() for badge in owned_card.findChildren(MetadataBadge)] == ['Installed', 'Example Author', '1.0.0']
    trash = owned_card.delete_button
    assert trash.cursor().shape() == Qt.PointingHandCursor
    assert trash.toolButtonStyle() == Qt.ToolButtonIconOnly and trash._theme_style == DESTRUCTIVE_STYLE
    owned_card.details_button.click()
    assert details.online_button.isVisible() and details.folder_button.isVisible()
    assert all(call[0] != 'read' for call in calls) and window.sections['installed'].grid.cards[0] is owned_card, 'Reading a skill starts no helper and rebuilds nothing'
    previous = len(calls)
    with patch.object(QtWidgets.QMessageBox, 'question', return_value=QtWidgets.QMessageBox.No):
        trash.click()
    assert len(calls) == previous
    with patch.object(QtWidgets.QMessageBox, 'question', return_value=QtWidgets.QMessageBox.Yes):
        trash.click()
    assert calls[-1] == ('delete', ['-SkillId', custom_identifier])
    assert not trash.isEnabled() and trash.cursor().shape() == Qt.ArrowCursor
    window.set_busy(False)
    # A newer catalog version replaces an unedited community copy without a click, once per catalog load.
    newer = dict(entry, version='1.1.0')
    window.apply_catalog(catalog_result([newer]))
    assert calls[-1] == ('community-sync', None) and window.status.text() == 'Updating installed community skills...'
    client.skills_operation_name = 'community-sync'
    refused = local_result([installed])
    refused.snapshot.set('result', 'community', encode(json.dumps([newer])))
    refused.snapshot.set('result', 'message', encode('Not updated: Example Skill: its local files were edited, so your copy was kept'))
    finish(window, refused)
    assert sum(name == 'community-sync' for name, _ in calls) == 1, 'A refused update is not retried in a loop'
    assert 'Not updated' in window.status.text()
    assert window.sections['installed'].grid.cards[0].item['notice'] == 'Version 1.1.0 is available in Community.'
    client.skills_operation_name = 'list'
    finish(window, local_result([dict(installed, displaySource='Personal')]))
    window.apply_catalog(catalog_result([newer]))
    assert sum(name == 'community-sync' for name, _ in calls) == 1, 'A personal copy is never replaced automatically'
    assert window.sections['installed'].grid.cards[0].item['notice'] == 'Version 1.1.0 is available in Community. Your local copy is not overwritten.'
    # An action requested while another helper runs waits for it instead of being dropped.
    client.skills_operation_name = 'list'
    finish(window, local_result())
    accept[0] = False
    previous = len(calls)
    window.install(community.grid.cards[0].item)
    assert len(calls) == previous and len(window.queue) == 1
    accept[0] = True
    window.operation_finished()
    assert calls[-1][0] == 'community-install' and not window.queue
    window.set_busy(False)
    window.catalog_failed('Offline')
    assert community.hint.text() == 'Offline The saved list is shown.'
    assert not community.retry.isHidden() and community.grid.cards, 'The saved catalog stays visible when a refresh fails'
    community.retry.click()
    assert len(catalog_calls) == 2 and community.retry.isHidden()
    window.apply_catalog(catalog_result([newer]))
    # The saved lists make the next opening immediate, before any helper has answered.
    previous = len(calls)
    reopened = SkillsWindow(client, None)
    assert len(calls) == previous and reopened.community == window.community
    assert sorted(skill['id'] for skill in reopened.local) == sorted(skill['id'] for skill in window.local)
    assert len(reopened.sections['community'].grid.cards) == 1 and len(reopened.ensure_cards('builtin')) == len(builtin_cards)
    reopened.deleteLater()
    (state / 'skills-cache.json').write_text('{', encoding='utf-8')
    (state / 'store').mkdir()
    (state / 'store' / 'registry.json').write_text(json.dumps({'schemaVersion': 1, 'revision': 1, 'skills': [dict(installed, id=custom_identifier.split('/')[1], source='synthetic-source'), {'id': 'not-an-identifier'}]}), encoding='utf-8')
    blank = SkillsWindow(client, None)
    assert blank.community is None and len(blank.ensure_cards('builtin')) == len(builtin_cards), 'Without saved lists the built-in skills still appear at once'
    assert blank.sections['community'].hint.text() == 'Loading the community catalog...'
    stored = blank.sections['installed'].grid.cards
    assert len(stored) == 1 and stored[0].item['local']['id'] == custom_identifier and stored[0].item['local']['source'] == 'Custom', 'Installed skills are read from the store at once'
    assert stored[0].item['title'] == 'Example Skill' and stored[0].delete_button is not None
    blank.deleteLater()
    (state / 'store' / 'registry.json').unlink()
    report = subprocess.check_output([str(root/'runtime/win-x64/node.exe'), '-e', "process.stdout.write(require('./core/skill-markdown').renderImportReport([{name:'Example imported skill'}],[{name:'Other skill',reason:'Example conflict'}]))"], cwd=str(root), creationflags=subprocess.CREATE_NO_WINDOW).decode('utf-8')
    failed = local_result()
    failed.result = state / 'import-result'
    Path(str(failed.result) + '.html').write_text(report, encoding='utf-8')
    failed.snapshot.set('result', 'message', encode('1 imported, 1 failed.'))
    client.skills_operation_name = 'add-zips'
    finish(window, failed)
    assert details.title.text() == 'Import Report' and 'Example conflict' in details.preview.toPlainText()
    assert window.status.text() == '1 imported, 1 failed.'
    succeeded = local_result()
    succeeded.result = failed.result
    succeeded.snapshot.set('result', 'message', encode('2 imported, 0 failed.'))
    details.show_item(community.grid.cards[0].item)
    finish(window, succeeded)
    assert details.title.text() == 'Example Skill', 'A clean import does not open a report'
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
    long_author = 'A long author name together with another long contributor name and one more studio name'
    window.apply_catalog(catalog_result([dict(entry, author=long_author)]))
    window.resize(380, 600)
    settle()
    card = community.grid.cards[0]
    badges = card.findChildren(MetadataBadge)
    assert badges[1].text() == long_author and badges[1].toolTip() == long_author, 'The complete author stays available'
    assert all(not badge.wordWrap() and badge.geometry().right() < card.width() for badge in badges), 'A long author never widens its card'
    assert window.scroll.horizontalScrollBar().maximum() == 0
    # The result of an operation is a closable banner colored by its outcome, not a bare line of text.
    assert [SkillsWindow.result_kind(*case) for case in ((True, 'Skill installed. Start a new conversation in your AI client.'), (True, '2 imported, 0 failed.'), (True, '1 imported, 1 failed.'), (True, 'Removal incomplete. Resolve the reported error and click Delete to retry.'), (True, 'Not updated: Example Skill: its local files were edited'), (False, 'Offline'))] == ['success', 'success', 'warning', 'warning', 'warning', 'error']
    banner = window.status
    for kind in ('success', 'warning', 'error', 'info'):
        window.set_status('Skill installed. Start a new conversation in your AI client.', kind)
        settle()
        assert banner.isVisible() and banner.kind == kind and ('@log_%s_background' % kind) in banner._theme_style and themes.style('@log_%s' % kind) in banner.styleSheet()
    assert banner.text() == 'Skill installed. Start a new conversation in your AI client.' and banner.accessibleName() == banner.text()
    assert banner.geometry().top() > window.navigation['community'].geometry().bottom() and banner.geometry().bottom() < window.scroll.geometry().top()
    assert banner.close_button.toolTip() == 'Dismiss' and banner.close_button.geometry().right() < banner.width() and banner.close_button.cursor().shape() == Qt.PointingHandCursor
    window.resize(380, 600)
    settle()
    assert banner.width() <= window.width() and banner.label.heightForWidth(banner.label.width()) <= banner.label.height(), 'A long message wraps inside a narrow banner'
    banner.close_button.click()
    assert banner.isHidden(), 'The banner can be dismissed'
    window.set_status('Deleting Example Skill...')
    assert banner.isVisible() and banner.kind == 'info'
    window.set_status('')
    assert banner.isHidden()
    asked = len(catalog_calls)
    window.present()
    settle()
    assert len(catalog_calls) == asked and window.category == 'community', 'A catalog checked moments ago is not requested again on opening'
    window.catalog_checked -= SkillsWindow.CATALOG_FRESH_SECONDS + 1
    window.present()
    settle()
    assert len(catalog_calls) == asked + 1, 'An older catalog is refreshed in the background'
    window.apply_catalog(catalog_result([dict(entry, author=long_author)]))
    window.refresh()
    assert len(catalog_calls) == asked + 2, 'Refresh always asks for the catalog'
    assert sum(isinstance(item, SkillDetailsWindow) for item in app.topLevelWidgets()) == 1
finally:
    themes.max_colors = {}
    themes.select('graphite')
    for item in list(client.dialogs.values()):
        item.close()
        item.deleteLater()
    shutil.rmtree(str(state), ignore_errors=True)
    if previous_store is None:
        os.environ.pop('MAX_ULTRA_MCP_SKILLS_ROOT', None)
    else:
        os.environ['MAX_ULTRA_MCP_SKILLS_ROOT'] = previous_store
print('Skills UI: instant cached open, cards, click-only install, automatic update, busy/error/empty states, narrow layout and themed report passed')
