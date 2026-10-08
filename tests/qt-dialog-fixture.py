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
from max_ultra.qt import QtWidgets, QtCore, QtGui, Qt, max_parent
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
        save_setting=Mock(return_value=True), skills_operation=lambda *args: calls.append(args),
        donate=lambda: None, refresh_agents=lambda: None, cancel_integration=lambda: None,
        integration=None, integration_steps=[], integration_result=None, integration_message="Fixture status",
        version="Fixture", update_helper=None, set_autostart=lambda *args: None, sync_autostart=lambda: False,
        check_updates=lambda: None, show_onboarding=lambda: None, set_theme=lambda identifier: True,
        client_state=lambda identifier: "configured",
        manual_setup=lambda: '{"mcpServers":{"max-ultra-mcp":{"command":"node","args":[],"env":{}}}}')
    skills = SkillsWindow(client, max_parent())
    onboarding = Onboarding(client, max_parent())
    settings = SettingsWindow(client, max_parent())
    client.panel = skills
    client.panel_opacity = 100
    client.set_panel_opacity = lambda value, persist=False: Client.set_panel_opacity(client, value, persist)
    help_windows = []
    try:
        skills.show()
        onboarding.setWindowOpacity(0.8)
        original_opacity = onboarding.windowOpacity()
        onboarding.show()
        settings.show()
        application.processEvents()
        assert abs(skills.windowOpacity() - 0.5) < 0.01
        assert abs(onboarding.windowOpacity() - original_opacity * 0.5) < 0.01
        assert settings.windowOpacity() == 1.0
        settings.show()
        assert abs(skills.windowOpacity() - 0.5) < 0.01
        from max_ultra.widgets import Window
        late_window = Window(ROOT, 'Synthetic late window', None)
        late_window.show()
        assert abs(late_window.windowOpacity() - 0.5) < 0.01
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
        assert abs(skills.windowOpacity() - 0.35) < 0.01
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
        assert [group.title() for group in settings.findChildren(QtWidgets.QGroupBox)] == ['Appearance', 'Autostart', 'Server console', 'Updates', 'AI client integration', 'About']
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
        long_html = '<p>Start</p>' + '<p>Example paragraph</p>' * 100 + '<a name="end"></a><p>End</p>'
        skills.set_preview_html(long_html)
        application.processEvents()
        skills.preview.verticalScrollBar().setValue(180)
        skills.open_document('1', 'references/example.md')
        assert skills.back_button.isVisible()
        skills.back()
        skills.set_preview_html(long_html)
        assert skills.preview.verticalScrollBar().value() == 180
        before_anchor = list(calls)
        skills.navigate(QtCore.QUrl('#end'))
        assert skills.preview.verticalScrollBar().value() > 180
        assert calls == before_anchor, 'Local anchors must not start helper reads'
        assert skills.current_document == ('1', 'SKILL.md')
        assert not skills.back_button.isVisible()
        skills.resize(320, 300)
        application.processEvents()
        assert skills.width() == 320
        onboarding.show()
        client.manual_setup = lambda: '{"mcpServers":{"max-ultra-mcp":{"command":"updated-node","args":["--stdio"],"env":{"MAX_ULTRA_MCP_PORT":"49000"}}}}'
        onboarding.update_status()
        assert onboarding.manual_fields[0].toPlainText() == 'updated-node'
        assert '49000' in onboarding.manual_fields[2].toPlainText()
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
        return 'Dialog fixtures passed: metadata, tabs, protected built-ins, Back, compact layout and expanding setup text'
    finally:
        for window in [skills, onboarding, settings] + help_windows:
            window.close()
            window.deleteLater()
        application.processEvents()


if __name__ == '__main__':
    print(run())
