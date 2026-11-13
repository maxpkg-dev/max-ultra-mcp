# Exercise dialog sizing, read-only built-ins and navigation without real helpers.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import configparser
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch, Mock
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from max_ultra.qt import QtWidgets, QtCore, QtGui, Qt, max_parent
from max_ultra.dialogs import Onboarding, SkillHelpWindow, SettingsWindow
from max_ultra.skills_window import SkillsWindow, SkillDetailsWindow, MetadataBadge, METADATA_BLOCK, read_skill_document, render_markdown
from max_ultra.widgets import DESTRUCTIVE_STYLE
from max_ultra.wire import encode


def run():
    application = QtWidgets.QApplication.instance()
    from max_ultra.client import Client
    refresh_client = SimpleNamespace(disposed=False, integration=None, reconnect_pending=False,
        connection_state='reconnecting', reconnect=Mock(), refresh_agents=Mock(), panel=SimpleNamespace(update_ai=Mock()))
    Client.reconnect_and_refresh(refresh_client)
    Client.reconnect_and_refresh(refresh_client)
    assert refresh_client.reconnect.call_count == 1
    Client.poll_connection_refresh(refresh_client)
    assert not refresh_client.refresh_agents.called
    refresh_client.connection_state = 'connected'
    Client.poll_connection_refresh(refresh_client)
    Client.poll_connection_refresh(refresh_client)
    assert refresh_client.refresh_agents.call_count == 1
    refresh_client.integration = object()
    Client.reconnect_and_refresh(refresh_client)
    assert refresh_client.reconnect.call_count == 1
    refresh_client.integration = None
    refresh_client.connection_state = 'reconnecting'
    refresh_client.refresh_connection_deadline = 1
    Client.poll_connection_refresh(refresh_client)
    assert refresh_client.refresh_agents.call_count == 2
    status_client = SimpleNamespace(connection_state='connected', status='Synthetic connection',
        transport=SimpleNamespace(connection=object()), reconnect_pending=False,
        integration_failed=False, integration=None, ai_status=lambda: ('Ready', 'ready'))
    assert Client.mini_status(status_client)[0] == 'ready'
    status_client.connection_state = 'error'
    assert Client.mini_status(status_client)[0] == 'error'
    status_client.connection_state = 'reconnecting'
    assert Client.mini_status(status_client)[0] == 'warning'
    status_client.connection_state = 'connected'
    status_client.ai_status = lambda: ('Checking', 'checking')
    assert Client.mini_status(status_client)[0] == 'warning'
    calls = []
    def skills_operation(*args):
        calls.append(args)
        client.skills_operation_name = args[0]
        return True
    def show_dialog(key, kind):
        if key not in client.dialogs:
            client.dialogs[key] = kind(client, max_parent())
        client.dialogs[key].show()
        return client.dialogs[key]
    client = SimpleNamespace(root=ROOT, settings=SimpleNamespace(get=lambda *args: "builtin", boolean=lambda section, key, default: default),
        save_setting=Mock(return_value=True), skills_operation=skills_operation, skills_operation_name="",
        catalog_operation=lambda: True, page_operation=lambda identifier: True, dialogs={}, show_dialog=show_dialog, state_directory=None,
        donate=lambda: None, refresh_agents=lambda: None, cancel_integration=lambda: None,
        integration=None, integration_steps=[], integration_result=None, integration_message="Fixture status",
        version="Fixture", update_helper=None, set_autostart=lambda *args: None, sync_autostart=lambda: False,
        check_updates=lambda: None, show_onboarding=lambda: None, set_theme=lambda identifier: True,
        client_state=lambda identifier: "configured",
        manual_setup=lambda: '{"mcpServers":{"max-ultra-mcp":{"command":"node","args":[],"env":{}}}}')
    # Keep the first paint away from the real per-user skill store.
    environment = patch.dict('os.environ', {'MAX_ULTRA_MCP_SKILLS_ROOT': tempfile.mkdtemp(prefix='max-ultra-dialog-fixture-')})
    environment.start()
    skills = SkillsWindow(client, max_parent())
    client.dialogs["skills"] = skills
    assert list(skills.navigation) == ['community', 'builtin'], 'Community is the first filter'
    assert skills.category == "community" and skills.navigation["community"].isChecked(), 'Community is always the starting filter, whatever was saved'
    onboarding = Onboarding(client, max_parent())
    settings = SettingsWindow(client, max_parent())
    client.panel = skills
    client.panel_opacity = 100
    client.set_panel_opacity = lambda value, persist=False: Client.set_panel_opacity(client, value, persist)
    help_windows = []
    try:
        skills.show()
        application.processEvents()
        assert not skills.sections['builtin'].grid.cards, 'Cards behind the other filter are not built at opening'
        assert skills.sections['installed'].hint.text().startswith('No skills are installed yet') and skills.sections['community'].header.spinner.isHidden()
        skills.navigation['builtin'].click()
        application.processEvents()
        assert len(skills.sections['builtin'].grid.cards) >= 9 and skills.sections['builtin'].hint_row.isHidden(), 'Built-in skills are shown without any helper'
        assert not calls and skills.navigation['builtin'].count == len(skills.sections['builtin'].grid.cards)
        assert skills.navigation['community'].count is None, 'An unknown list is never shown as zero'
        assert all(skills.sections[key].header.isHidden() and skills.sections[key].grid.isHidden() for key in ('installed', 'community'))
        skills.present()
        assert skills.category == 'community' and skills.navigation['community'].isChecked() and not calls, 'Reopening returns to Community without a helper for local skills'
        assert skills.sections['community'].header.spinner.isHidden(), 'The catalog is requested only after the window has painted'
        application.processEvents()
        assert not calls and not skills.sections['community'].header.spinner.isHidden(), 'Only the catalog loads in the background'
        client.skills_operation_name = 'community-install'
        skills.set_busy(True)
        application.processEvents()
        assert skills.progress.isVisible() and skills.elapsed.isVisible() and skills.elapsed_timer.isActive()
        assert not skills.import_folder_button.isEnabled() and not skills.import_zips_button.isEnabled() and not skills.refresh_button.isEnabled()
        assert skills.close_button.isEnabled() and skills.search.isEnabled() and skills.donate_button.isEnabled()
        skills.set_busy(False)
        assert skills.progress.isHidden() and not skills.elapsed_timer.isActive()
        assert skills.import_folder_button.isEnabled() and skills.refresh_button.isEnabled()
        skills.resize(1040, 860)
        onboarding.setWindowOpacity(0.8)
        original_opacity = onboarding.windowOpacity()
        onboarding.show()
        settings.show()
        application.processEvents()
        assert skills.windowOpacity() == 1.0 and skills.settings_veil.isVisible()
        assert abs(onboarding.windowOpacity() - original_opacity) < 0.01 and onboarding.settings_veil.isVisible()
        assert settings.windowOpacity() == 1.0
        settings.show()
        assert skills.windowOpacity() == 1.0 and skills.settings_veil.isVisible()
        from max_ultra.widgets import Window
        late_window = Window(ROOT, 'Synthetic late window', None)
        late_window.show()
        assert late_window.windowOpacity() == 1.0 and late_window.settings_veil.isVisible()
        settings.close()
        application.processEvents()
        assert skills.windowOpacity() == 1.0
        assert abs(onboarding.windowOpacity() - original_opacity) < 0.01
        assert late_window.windowOpacity() == 1.0
        late_window.close()
        late_window.deleteLater()
        onboarding.setWindowOpacity(1.0)
        settings.show()
        application.processEvents()
        def opacity_mouse(kind, buttons):
            option = QtWidgets.QStyleOptionSlider()
            settings.opacity_slider.initStyleOption(option)
            handle = settings.opacity_slider.style().subControlRect(QtWidgets.QStyle.CC_Slider, option, QtWidgets.QStyle.SC_SliderHandle, settings.opacity_slider)
            event = QtGui.QMouseEvent(kind, QtCore.QPointF(handle.center()), Qt.LeftButton, buttons, Qt.NoModifier)
            application.sendEvent(settings.opacity_slider, event)
        opacity_mouse(QtCore.QEvent.MouseButtonPress, Qt.LeftButton)
        settings.opacity_slider.setValue(60)
        assert abs(skills.windowOpacity() - 0.6) < 0.01
        def wait_opacity(milliseconds):
            loop = QtCore.QEventLoop()
            QtCore.QTimer.singleShot(milliseconds, loop.quit)
            loop.exec_()
        wait_opacity(1100)
        assert abs(skills.windowOpacity() - 0.6) < 0.01
        settings.opacity_slider.setValue(70)
        assert abs(skills.windowOpacity() - 0.7) < 0.01
        opacity_mouse(QtCore.QEvent.MouseButtonRelease, Qt.NoButton)
        assert abs(skills.windowOpacity() - 0.7) < 0.01 and skills.settings_veil.isVisible()
        opacity_mouse(QtCore.QEvent.MouseButtonPress, Qt.LeftButton)
        settings.opacity_slider.setValue(60)
        settings.close()
        wait_opacity(1100)
        assert abs(skills.windowOpacity() - 0.6) < 0.01
        client.save_setting.assert_called_with('appearance', {'panelOpacity': 60})
        settings.show()
        settings.opacity_slider.setValue(0)
        assert settings.opacity_slider.value() == 20
        assert skills.windowOpacity() > 0
        settings.opacity_slider.setValue(100)
        settings.close()
        assert skills.windowOpacity() == 1.0
        settings.show()
        assert [group.title() for group in settings.findChildren(QtWidgets.QGroupBox)] == ['Appearance', 'Autostart', 'Server console', 'Updates', 'AI client integration']
        checkboxes = settings.findChildren(QtWidgets.QCheckBox)
        assert len(checkboxes) == 4
        assert [box.isChecked() for box in checkboxes] == [True, False, False, True]
        checkboxes[0].setChecked(False)
        client.save_setting.assert_called_with('settings', {'highlightLogBackgrounds': False})
        assert all('check.svg' in box.styleSheet() for box in checkboxes)
        client.update_helper = object()
        settings.update_status()
        assert not settings.check_updates.isEnabled()
        client.update_helper = None
        client.update_message = 'Synthetic update result'
        settings.update_status()
        assert settings.update_status_label.text() == client.update_message
        parser = configparser.ConfigParser()
        parser['result'] = {'ok': 'true', 'haslist': 'true', 'count': '2', 'message': encode('Synthetic catalog')}
        custom_identifier = 'user/00000000-0000-4000-8000-000000000001'
        for index, source in enumerate(['Built-in', 'Custom']):
            parser['skill' + str(index)] = {key: encode(value) for key, value in
                {'id': 'bundled/example' if source == 'Built-in' else custom_identifier, 'name': 'example-' + source.lower(), 'description': 'Example description',
                 'state': 'Read only' if source == 'Built-in' else 'ready',
                 'author': 'Fixture Author', 'version': '1.2.3', 'title': 'Example ' + source, 'displayDescription': 'Example description', 'displaySource': 'Community Skills', 'website': 'https://example.com/skills', 'email': 'author@example.com', 'source': source}.items()}
        client.skills_operation_name = 'list'
        with tempfile.TemporaryDirectory() as folder:
            skills.apply_result(SimpleNamespace(snapshot=parser, result=Path(folder) / 'result.ini'))
        skills.show()
        application.processEvents()
        assert skills.status.isHidden(), 'A background list refresh has no status message'
        skills.resize(1180, 820)
        skills.navigation['builtin'].click()
        application.processEvents()
        builtin_card = skills.sections['builtin'].grid.cards[0]
        builtin_height = builtin_card.height()
        assert skills.sections['builtin'].grid.columns == 3, 'The default window shows three cards per row'
        assert skills.sections['builtin'].header.isHidden(), 'The Built-in filter needs no heading of its own'
        skills.navigation['community'].click()
        application.processEvents()
        custom_card = skills.sections['installed'].grid.cards[0]
        assert not skills.sections['installed'].header.isHidden() and skills.sections['installed'].header.title.text() == 'Installed'
        assert skills.sections['community'].header.title.text() == 'Not installed'
        assert skills.sections['installed'].header.geometry().top() < skills.sections['community'].header.geometry().top(), 'Installed skills come before the ones that are not installed'
        assert builtin_card.delete_button is None and builtin_card.install_button is None, 'Built-in skills cannot be deleted'
        assert custom_card.delete_button._theme_style == DESTRUCTIVE_STYLE and custom_card.delete_button.toolButtonStyle() == Qt.ToolButtonIconOnly
        assert custom_card.delete_button.toolTip() == 'Delete Skill' and custom_card.delete_button.accessibleName() == 'Delete Skill'
        assert [badge.text() for badge in builtin_card.findChildren(MetadataBadge)] == ['Built-in', 'Fixture Author', '1.2.3']
        assert [badge.text() for badge in custom_card.findChildren(MetadataBadge)] == ['Installed', 'Fixture Author', '1.2.3']
        assert [chip.text() for chip in skills.navigation.values()] == ['Community', 'Built-in 1'], 'The Community counter waits for the catalog'
        assert skills.sections['community'].hint.text() == 'Loading the community catalog...'
        assert not skills.sections['community'].grid.cards
        assert builtin_card.details_button.accessibleName() == 'View details for Example Built-in'
        assert not skills.compact
        assert skills.search.geometry().right() < skills.import_folder_button.geometry().left() < skills.import_zips_button.geometry().left() < skills.refresh_button.geometry().left(), 'Import actions sit beside the search field'
        assert skills.import_folder_button.toolButtonStyle() == Qt.ToolButtonTextBesideIcon and skills.refresh_button.toolButtonStyle() == Qt.ToolButtonIconOnly
        assert [link.text() for link in skills.footer_links] == ['How to Create and Import Skills', 'Submit Your Skill', 'Open Online Catalog']
        assert all(not link.isHidden() for link in skills.footer_links) and all(button.isHidden() for button in skills.footer_buttons)
        assert skills.footer_links[0].geometry().right() < skills.footer_links[1].geometry().left() < skills.footer_links[2].geometry().left()
        assert skills.footer_links[2].geometry().right() < skills.donate_button.geometry().left(), 'Help links share the bottom row with Donate'
        assert skills.donate_button.geometry().top() > skills.scroll.geometry().bottom()
        skills.resize(1040, 860)
        previous = list(calls)
        skills.delete_skill(builtin_card.item)
        assert calls == previous, 'Built-in deletion reached the helper'
        builtin_menu = skills.card_menu(builtin_card.item)
        custom_menu = skills.card_menu(custom_card.item)
        assert [item.text() for item in builtin_menu.actions()] == ['View details', 'Open folder']
        assert [item.text() for item in custom_menu.actions()] == ['View details', 'Open folder', '', 'Delete']
        assert custom_menu.actions()[2].isSeparator()
        assert custom_menu.actions()[3].property('destructive')
        assert all(not item.icon().isNull() for item in custom_menu.actions() if not item.isSeparator())
        custom_menu.resize(custom_menu.sizeHint())
        assert not custom_menu.grab().isNull()
        assert len({custom_menu.actionGeometry(item).height() for item in custom_menu.actions() if not item.isSeparator()}) == 1
        for index in (0, 1, 3):
            custom_menu.setActiveAction(custom_menu.actions()[index])
            assert not custom_menu.grab().isNull()
        assert not custom_menu.mask().contains(QtCore.QPoint(0, 0))
        assert custom_menu.mask().contains(custom_menu.rect().center())
        custom_menu.grab().save(str(ROOT / 'dist/skills-context-menu.png'))
        package = Path(os.environ['MAX_ULTRA_MCP_SKILLS_ROOT']) / 'packages' / custom_identifier.split('/')[1]
        (package / 'references').mkdir(parents=True)
        (package / 'SKILL.md').write_text('---\nname: example-custom\ndescription: Fixture description for the details window.\n---\n# Fixture instructions\n\nBack is valid document text.\n\n[Reference](references/example.md)\n\n<script>alert(1)</script>\n\n' + 'Example paragraph.\n\n' * 100, encoding='utf-8')
        (package / 'references' / 'example.md').write_text('# Reference\n\nReference body.\n', encoding='utf-8')
        custom_menu.actions()[0].trigger()
        details = client.dialogs['skill_details']
        application.processEvents()
        assert details.title.text() == 'Example Custom' and details.isVisible()
        assert all(call[0] != 'read' for call in calls), 'Instructions are read in the window, never through a helper process'
        shown = details.preview.toPlainText()
        assert 'Fixture instructions' in shown and 'Back is valid document text.' in shown, 'Instructions are visible as soon as the window opens'
        assert 'example-custom' in shown and 'Fixture description for the details window.' in shown
        assert '<script>alert(1)</script>' in shown and '<script' not in details.preview.toHtml().replace('&lt;script', ''), 'Raw HTML in a skill is shown as text, never interpreted'
        assert 'references/example.md' in details.preview.toHtml()
        assert not details.note.text() and details.close_button.isEnabled()
        assert abs(builtin_height - custom_card.height()) <= 2, 'Built-in cards are as tall as the other cards'
        information = details.information.text()
        assert 'Source:</b> Community Skills' in information and 'Type:</b> Custom' in information and 'Status:</b> ready' in information
        assert 'https://example.com/skills' in information and 'mailto:author%40example.com' in information
        assert details.information._theme_label.count('color:@support_link') == 2
        assert [badge.text() for badge in details.findChildren(MetadataBadge)] == ['Installed', 'Fixture Author', '1.2.3']
        assert details.folder_button.isVisible() and not details.online_button.isVisible()
        with patch.object(QtGui.QDesktopServices, 'openUrl', return_value=True) as opener:
            details.open_link('https://example.com/skills')
            assert opener.call_count == 1
            details.open_link('file:///unsafe')
            assert opener.call_count == 1
        skills.show_details(builtin_card.item)
        application.processEvents()
        assert client.dialogs['skill_details'] is details and details.title.text() == 'Example Built-in'
        assert sum(isinstance(window, SkillDetailsWindow) for window in application.topLevelWidgets()) == 1, 'Details reuse one window'
        assert [badge.text() for badge in details.findChildren(MetadataBadge) if not badge.isHidden()] == ['Built-in', 'Fixture Author', '1.2.3']
        details.close()
        skills.show_details(custom_card.item)
        assert details.isVisible() and details.title.text() == 'Example Custom', 'A closed details window reopens'
        with patch.object(QtWidgets.QMessageBox, 'question', return_value=QtWidgets.QMessageBox.Yes):
            custom_menu.actions()[3].trigger()
        assert calls[-1] == ('delete', ['-SkillId', custom_identifier])
        assert not custom_card.delete_button.isEnabled(), 'A running change disables further changes'
        skills.set_busy(False)
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'packages' / custom_identifier.split('/')[1]
            target.mkdir(parents=True)
            with patch.dict('os.environ', {'MAX_ULTRA_MCP_SKILLS_ROOT': folder}), patch.object(QtGui.QDesktopServices, 'openUrl', return_value=True) as open_url:
                skills.open_skill_folder(custom_card.item)
                assert Path(open_url.call_args[0][0].toLocalFile()) == target.resolve()
                details.open_folder()
                assert open_url.call_count == 2
        builtin_menu.deleteLater()
        custom_menu.deleteLater()
        details.resize(820, 760)
        skills.show_details(custom_card.item)
        application.processEvents()
        details.preview.verticalScrollBar().setValue(180)
        details.navigate(QtCore.QUrl('references/example.md'))
        assert details.back_button.isVisible() and details.current_document == (custom_identifier, 'references/example.md')
        assert 'Reference body.' in details.preview.toPlainText() and 'Fixture instructions' not in details.preview.toPlainText()
        details.back()
        assert 'Fixture instructions' in details.preview.toPlainText() and details.preview.verticalScrollBar().value() == 180
        assert details.current_document == (custom_identifier, 'SKILL.md') and not details.back_button.isVisible()
        assert all(call[0] != 'read' for call in calls)
        for unsafe in ('../outside.md', 'C:/outside.md', 'references/../../outside.md', 'references/missing.md', 'notes.exe'):
            assert not read_skill_document(ROOT, custom_card.item['local'], unsafe)[0], unsafe
        details.navigate(QtCore.QUrl('references/missing.md'))
        assert 'no longer available' in details.note.text() and 'Fixture instructions' in details.preview.toPlainText(), 'A failed read keeps the previous document'
        details.back()
        details.apply_document(False, 'Synthetic read failure', '')
        assert details.note.text() == 'Synthetic read failure' and 'Fixture instructions' in details.preview.toPlainText()
        long_html = '<p>Start</p>' + '<p>Example paragraph</p>' * 100 + '<a name="end"></a><p>End</p>'
        details.apply_document(True, '', long_html)
        application.processEvents()
        details.preview.verticalScrollBar().setValue(180)
        before_anchor = list(calls)
        details.navigate(QtCore.QUrl('#end'))
        assert details.preview.verticalScrollBar().value() > 180
        assert calls == before_anchor, 'Local anchors must not start helper reads'
        details.show_report('<p>1 imported, 1 failed.</p>')
        assert details.title.text() == 'Import Report' and not details.folder_button.isVisible() and '1 failed' in details.preview.toPlainText()
        skills.resize(360, 300)
        application.processEvents()
        assert skills.width() == 360 and skills.compact
        assert skills.import_folder_button.toolButtonStyle() == Qt.ToolButtonIconOnly and skills.import_zips_button.toolButtonStyle() == Qt.ToolButtonIconOnly
        assert all(link.isHidden() for link in skills.footer_links), 'A narrow window replaces the help links with icons'
        assert all(not button.isHidden() and button.toolButtonStyle() == Qt.ToolButtonIconOnly for button in skills.footer_buttons)
        assert [button.toolTip() for button in skills.footer_buttons] == ['How to Create and Import Skills', 'Submit Your Skill', 'Open Online Catalog']
        assert skills.sections['installed'].grid.columns == 1 and skills.scroll.horizontalScrollBar().maximum() == 0
        assert skills.navigation['builtin'].geometry().right() < skills.width()
        onboarding.show()
        client.manual_setup = lambda: '{"mcpServers":{"max-ultra-mcp":{"command":"updated-node","args":["--stdio"],"env":{"MAX_ULTRA_MCP_PORT":"49000"}}}}'
        onboarding.update_status()
        assert onboarding.manual_fields[0].toPlainText() == 'updated-node'
        assert '49000' in onboarding.manual_fields[2].toPlainText()
        onboarding.tabs.setCurrentIndex(2)
        onboarding.resize(670, 570)
        application.processEvents()
        application.processEvents()
        assert onboarding.tabs.widget(2).verticalScrollBar().maximum() == 0
        onboarding.tabs.setCurrentIndex(0)
        onboarding.resize(670, 570)
        application.processEvents()
        first = onboarding.detail.height()
        onboarding.resize(800, 770)
        application.processEvents()
        assert onboarding.detail.height() >= first + 190
        assert onboarding.detail.mapTo(onboarding, QtCore.QPoint(0, onboarding.detail.height())).y() > 690
        client.integration_client = ""
        client.integration_action = "Status"
        client.integration = SimpleNamespace(started=100.0)
        with patch("max_ultra.dialogs.time.monotonic", return_value=112.7):
            onboarding.update_status()
        assert onboarding.elapsed.isVisible() and onboarding.elapsed.text() == "12 s"
        assert onboarding.elapsed.geometry().left() > onboarding.progress.geometry().right()
        client.integration = None
        onboarding.update_status()
        assert not onboarding.elapsed.isVisible()
        client.integration = SimpleNamespace(started=200.0)
        with patch("max_ultra.dialogs.time.monotonic", return_value=200.2):
            onboarding.update_status()
        assert onboarding.elapsed.text() == "0 s"
        client.integration_client = "claudeCode"
        client.integration_action = "InstallCli"
        client.client_state = lambda identifier: "check_failed"
        onboarding.update_status()
        assert [label.text() for label in onboarding.card_statuses] == ['Waiting...', 'Setting up...', 'Waiting...']
        assert all(not label.isEnabled() and '#81796e' in label.styleSheet() for label in onboarding.card_statuses)
        assert all(not button.isEnabled() for button in onboarding.cards)
        client.integration = None
        onboarding.update_status()
        assert all(label.isEnabled() and 'Check failed' in label.text() for label in onboarding.card_statuses)
        assert all(button.text() != 'Copy Skill Creation Prompt' for button in skills.findChildren(QtWidgets.QToolButton))
        for submit in [False, True]:
            help_window = SkillHelpWindow(client, max_parent(), submit=submit)
            help_windows.append(help_window)
            help_window.show()
            application.processEvents()
            assert help_window.guide.toPlainText()
            assert help_window.text.toPlainText() == help_window.copy_text
            if submit:
                assert help_window.copy_text.startswith('To: info@3dground.net\nSubject:')
                assert 'Permission:\n' in help_window.copy_text
            else:
                assert help_window.copy_text == (ROOT / 'docs/SKILL_CREATION_PROMPT.md').read_text(encoding='utf-8-sig')
            clipboard = Mock()
            original_icon = help_window.copy_button.icon().cacheKey()
            with patch.object(QtWidgets.QApplication, 'clipboard', return_value=clipboard):
                help_window.copy_button.click()
            clipboard.setText.assert_called_once_with(help_window.copy_text)
            assert help_window.copy_button.text() == 'Copied'
            assert help_window.copy_button.icon().cacheKey() != original_icon
            timer = help_window.copy_button.copy_reset
            assert timer.isActive() and timer.interval() == 2000
            timer.timeout.emit()
            assert help_window.copy_button.text() == help_window.copy_label
            assert help_window.copy_button.icon().cacheKey() == original_icon
            help_window.resize(320, 300)
            application.processEvents()
            assert help_window.width() == 320
        details.apply_document(True, '', '<html><head><style>p{font-size:14px}h1{font-size:25px}</style></head><body>' + METADATA_BLOCK.format('SKILL', 'Heading', 'Introductory description') + '<p style="font-size:30px">Responsive example text for reading.</p>' * 100 + '</body></html>')
        for width, points in [(380, 8), (560, 9), (800, 10), (1250, 11), (1280, 16), (1800, 20), (2400, 24), (3000, 28), (3600, 32), (1251, 14)]:
            details.resize(width, 800)
            application.processEvents()
            assert details.preview._text_points == points
            cursor = details.preview.document().find('Responsive')
            assert cursor.charFormat().fontPointSize() == points
            heading = details.preview.document().find('Heading')
            assert heading.charFormat().fontPointSize() > points
            assert heading.charFormat().font().pointSizeF() > points
            table = next(frame for frame in details.preview.document().rootFrame().childFrames() if isinstance(frame, QtGui.QTextTable))
            assert table.format().border() == 1
            assert table.format().borderStyle() == QtGui.QTextFrameFormat.BorderStyle_Solid
            assert details.preview.document().documentMargin() == details.preview._document_padding
            assert 16 <= details.preview._document_padding <= 40
            if width in (380, 1800):
                saved_scroll = details.preview.verticalScrollBar().value()
                details.preview.verticalScrollBar().setValue(0)
                details.preview.grab().save(str(ROOT / 'dist' / ('skills-responsive-%d.png' % width)))
                details.preview.verticalScrollBar().setValue(saved_scroll)
        details.preview.verticalScrollBar().setValue(400)
        anchor = details.preview.cursorForPosition(QtCore.QPoint(0, 0)).position()
        details.resize(1800, 800)
        application.processEvents()
        restored = details.preview.cursorForPosition(QtCore.QPoint(0, 0)).position()
        assert abs(restored - anchor) < 40
        import subprocess
        sample = '---\nname: narrow-example\ndescription: Guide architectural composition, lighting and presentation using a verified workflow.\n---\n# Example workflow\n\nA sample body paragraph for readable content width.'
        actual_html = render_markdown(sample)
        details.resize(320, 800)
        application.processEvents()
        details.apply_document(True, '', actual_html)
        details.preview.verticalScrollBar().setValue(0)
        application.processEvents()
        table = next(frame for frame in details.preview.document().rootFrame().childFrames() if isinstance(frame, QtGui.QTextTable))
        assert table.format().border() == 1
        body_cursor = details.preview.document().find('A sample body')
        body_rect = details.preview.document().documentLayout().blockBoundingRect(body_cursor.block())
        body_block = body_cursor.block()
        body_layout = body_block.layout()
        effective_left = body_rect.left() + body_layout.lineAt(0).x()
        assert 15 <= effective_left <= 18, effective_left
        details.preview.grab().save(str(ROOT / 'dist/skills-actual-narrow.png'))
        # A resize while QTextDocument removes the old contents used to nest
        # setHtml inside itself and insert the metadata twice.
        details.preview.setHtml('<p>Welcome</p>')
        resized_during_load = [False]
        def resize_during_load(*args):
            if not resized_during_load[0]:
                resized_during_load[0] = True
                details.resize(1000, 800)
                application.processEvents()
        details.preview.document().contentsChange.connect(resize_during_load)
        details.apply_document(True, '', actual_html)
        application.processEvents()
        details.preview.document().contentsChange.disconnect(resize_during_load)
        assert details.preview.toPlainText().count('narrow-example') == 1
        assert len(details.preview.document().rootFrame().childFrames()) == 1
        details.preview.setHtml('<p>Example text and <a href="https://example.com/skill">reference</a></p>')
        details.preview.selectAll()
        menu = details.preview.document_menu(QtCore.QPoint(0, 0))
        actions = [item for item in menu.actions() if not item.isSeparator()]
        assert [item.text() for item in actions] == ['Copy', 'Copy Link Location', 'Select All']
        assert actions[0].isEnabled() and not actions[1].isEnabled()
        assert all(not item.icon().isNull() for item in actions)
        clipboard = Mock()
        with patch.object(QtWidgets.QApplication, 'clipboard', return_value=clipboard), patch.object(type(details.preview), 'anchorAt', return_value='https://example.com/skill'):
            link_menu = details.preview.document_menu(QtCore.QPoint(0, 0))
            link_menu.actions()[1].trigger()
        clipboard.setText.assert_called_once_with('https://example.com/skill')
        menu.resize(menu.sizeHint())
        assert len({menu.actionGeometry(item).height() for item in actions}) == 1
        for item in actions:
            menu.setActiveAction(item)
            assert not menu.grab().isNull()
        assert not menu.mask().contains(QtCore.QPoint(0, 0))
        assert menu.mask().contains(menu.rect().center())
        menu.grab().save(str(ROOT / 'dist/skills-document-menu.png'))
        menu.deleteLater()
        link_menu.deleteLater()
        return 'Dialog fixtures passed: metadata, cards, protected built-ins, one details window, Back, compact layout and responsive preview text'
    finally:
        for window in [skills, onboarding, settings] + help_windows + [window for key, window in client.dialogs.items() if key != 'skills']:
            window.close()
            window.deleteLater()
        application.processEvents()
        environment.stop()


if __name__ == '__main__':
    print(run())
