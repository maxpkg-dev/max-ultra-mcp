# Exercise dialog sizing, read-only built-ins and navigation without real helpers.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import configparser
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch, Mock
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from max_ultra.qt import QtWidgets, QtCore, max_parent
from max_ultra.dialogs import SkillsWindow, Onboarding, SkillHelpWindow, SettingsWindow
from max_ultra.wire import encode


def run():
    application = QtWidgets.QApplication.instance()
    from max_ultra.client import Client
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
    client = SimpleNamespace(root=ROOT, settings=SimpleNamespace(get=lambda *args: "builtin", boolean=lambda section, key, default: default),
        save_setting=lambda *args: None, skills_operation=lambda *args: calls.append(args),
        donate=lambda: None, refresh_agents=lambda: None, cancel_integration=lambda: None,
        integration=None, integration_steps=[], integration_result=None, integration_message="Fixture status",
        version="Fixture", update_helper=None, set_autostart=lambda *args: None,
        check_updates=lambda: None, show_onboarding=lambda: None,
        client_state=lambda identifier: "configured",
        manual_setup=lambda: '{"mcpServers":{"max-ultra-mcp":{"command":"node","args":[],"env":{}}}}')
    skills = SkillsWindow(client, max_parent())
    onboarding = Onboarding(client, max_parent())
    settings = SettingsWindow(client, max_parent())
    help_windows = []
    try:
        settings.show()
        application.processEvents()
        assert [group.title() for group in settings.findChildren(QtWidgets.QGroupBox)] == ['Autostart', 'Server console', 'Updates', 'AI client integration', 'About']
        checkboxes = settings.findChildren(QtWidgets.QCheckBox)
        assert len(checkboxes) == 3
        assert [box.isChecked() for box in checkboxes] == [False, False, True]
        assert all('check.svg' in box.styleSheet() for box in checkboxes)
        client.update_helper = object()
        settings.update_status()
        assert not settings.check_updates.isEnabled()
        client.update_helper = None
        client.update_message = 'Synthetic update result'
        settings.update_status()
        assert settings.update_status_label.text() == client.update_message
        parser = configparser.ConfigParser()
        parser['result'] = {'haslist': 'true', 'count': '2', 'message': encode('Synthetic catalog')}
        for index, source in enumerate(['Built-in', 'Custom']):
            parser['skill' + str(index)] = {key: encode(value) for key, value in
                {'id': str(index), 'name': 'Example ' + source, 'description': 'Example description',
                 'author': 'Fixture Author', 'source': source}.items()}
        with tempfile.TemporaryDirectory() as folder:
            skills.apply_result(SimpleNamespace(snapshot=parser, result=Path(folder) / 'result.ini'))
        skills.show()
        skills.list.setCurrentItem(skills.list.topLevelItem(0))
        application.processEvents()
        assert skills.list.topLevelItem(0).text(1) == 'Example description'
        assert skills.list.columnCount() == 2
        assert skills.list.headerItem().text(0) == 'Name'
        assert skills.list.headerItem().text(1) == 'Description'
        skills.set_preview_html('<html><body><div class="skill-header" id="skill-header" role="navigation"><a style="display:none">Back</a><span>Back</span><span>Custom Ready</span></div><h1>Fixture instructions</h1><p>Back is valid document text.</p><a href="skill-ref:references/test.md">Reference</a></body></html>')
        assert skills.preview.toPlainText().startswith('Fixture instructions')
        assert 'Back is valid document text.' in skills.preview.toPlainText()
        assert 'Custom Ready' not in skills.preview.toPlainText()
        assert 'skill-ref:references/test.md' in skills.preview.toHtml()
        assert not skills.delete_button.isVisible()
        previous = list(calls)
        skills.delete_selected()
        assert calls == previous, 'Built-in deletion reached the helper'
        assert skills.list.height() < 180 and skills.preview.height() > 400
        skills.source.setCurrentIndex(1)
        skills.list.setCurrentItem(skills.list.topLevelItem(1))
        assert skills.delete_button.isVisible()
        skills.open_document('1', 'references/example.md')
        assert skills.back_button.isVisible()
        skills.back()
        assert skills.current_document == ('1', 'SKILL.md')
        assert not skills.back_button.isVisible()
        skills.resize(320, 300)
        application.processEvents()
        assert skills.width() == 320
        onboarding.show()
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
        assert all(button.text() != 'Copy Skill Creation Prompt' for button in skills.buttons)
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
            with patch.object(QtWidgets.QApplication, 'clipboard', return_value=clipboard):
                help_window.copy_button.click()
            clipboard.setText.assert_called_once_with(help_window.copy_text)
            assert help_window.copy_button.text() == 'Copied'
            assert help_window.copy_button.icon().cacheKey() == help_window.copied_icon.cacheKey()
            assert help_window.copy_reset.isActive() and help_window.copy_reset.interval() == 2000
            help_window.copy_reset.timeout.emit()
            assert help_window.copy_button.text() == help_window.copy_label
            assert help_window.copy_button.icon().cacheKey() == help_window.copy_icon.cacheKey()
            help_window.resize(320, 300)
            application.processEvents()
            assert help_window.width() == 320
        return 'Dialog fixtures passed: metadata, tabs, protected built-ins, Back, compact layout and expanding setup text'
    finally:
        for window in [skills, onboarding, settings] + help_windows:
            window.close()
            window.deleteLater()
        application.processEvents()


if __name__ == '__main__':
    print(run())
