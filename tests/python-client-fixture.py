# Exercise controller lifetime with synthetic transport and no scene operations.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import sys
from pathlib import Path
import tempfile
import time
import types
import configparser
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from max_ultra import client as module
from max_ultra.qt import QtWidgets
from max_ultra.wire import BoundedQueue, encode, decode
from max_ultra.settings import Settings
from max_ultra.updates import GUID


class FakeTransport:
    def __init__(self, *args, **kwargs):
        self.inbound, self.outbound = BoundedQueue(), BoundedQueue()
        self.thread = mock.Mock(is_alive=lambda: False)
        self.stop_event = mock.Mock(is_set=lambda: False)
        self.connection = None
        self.error = None
        self.port = 47635

    def start(self):
        pass

    def stop(self):
        pass


def run():
    with tempfile.TemporaryDirectory(prefix="max-ultra-controller-fixture-") as folder:
        actual_settings = Settings
        actual_journal = module.Journal
        journals = []
        def journal_factory(filename):
            journal = actual_journal(filename)
            journals.append(journal)
            return journal
        with mock.patch.object(module, "Transport", FakeTransport), mock.patch.object(module, "MaxApi"), mock.patch.object(module, "Journal", side_effect=journal_factory), mock.patch.object(module, "Settings", side_effect=lambda filename: actual_settings(Path(folder) / "settings.ini")), mock.patch.dict(module.os.environ, {"LOCALAPPDATA": folder}):
            instance = None
            try:
                instance = module.Client(ROOT)
                instance.automatic_due = 0
                instance.timer.stop()
                assert instance.version == "1.4.7"
                instance.hide_panel()
                assert not instance.panel.isVisible() and instance.mini.isVisible()
                instance.show_panel()
                assert instance.panel.isVisible() and not instance.mini.isVisible()
                instance.show_settings()
                instance.show_onboarding()
                instance.show_dialog("skills", module.SkillsWindow)
                QtWidgets.QApplication.processEvents()
                assert len(instance.dialogs) == 3
                instance.log("info", "Synthetic controller fixture")
                instance.panel.refresh()
                instance.api.request.return_value = (True, '{"synthetic":true}')
                instance.process_request(["REQUEST", "expired", "execute", encode("synthetic"), "-", str(int(time.time() * 1000) - 1)])
                assert "REQUEST_EXPIRED" in decode(instance.transport.outbound.pop().split("\t")[3])
                instance.api.request.assert_not_called()
                instance.cancelled.add("cancelled")
                instance.process_request(["REQUEST", "cancelled", "execute", encode("synthetic")])
                assert "cancelled" in decode(instance.transport.outbound.pop().split("\t")[3])
                instance.api.request.assert_not_called()
                instance.transport.inbound.put("REQUEST\tqueued\texecute\t" + encode("synthetic"))
                instance.transport.inbound.put("CANCEL\tqueued")
                instance.transport.connection = object()
                instance.last_status = time.monotonic()
                instance.tick()
                assert "cancelled" in decode(instance.transport.outbound.pop().split("\t")[3])
                instance.api.request.assert_not_called()
                instance.process_request(["REQUEST", "accepted", "execute", encode("synthetic")])
                assert instance.transport.outbound.pop().split("\t")[2] == "ok"
                instance.api.request.assert_called_once()
                for dialog in instance.dialogs.values():
                    dialog.resize(320, 320)
                    QtWidgets.QApplication.processEvents()
                    assert dialog.width() == 320
                instance.storage_failure("Synthetic disk failure")
                assert instance.panel.storage_error.isVisible()
                instance.integration_result = configparser.ConfigParser()
                instance.integration_result['runtime'] = {'command': 'detected-node', 'server': 'example/server.js', 'environment': 'MAX_ULTRA_MCP_TOOL_PROFILE=core'}
                assert 'detected-node' in instance.manual_setup()
                assert 'core' in instance.manual_setup()
                original_rt = instance.rt
                fake_rt = mock.Mock()
                instance.rt = fake_rt
                try:
                    fake_rt.getDir.return_value = folder
                    instance.settings.set_many('settings', {'autostart': True})
                    assert not instance.sync_autostart()
                    instance.autostart_file().write_text('-- synthetic startup')
                    assert instance.sync_autostart()
                    # Legacy pending settings have no pendingVersion; infer it
                    # from the validated package name before verification.
                    package = str(Path(folder) / ('max-ultra-mcp@1.5.0@' + GUID + '.mzp'))
                    instance.settings.set_many('updates', {'pendingPackage': package, 'pendingVersion': ''})
                    with mock.patch.object(instance, 'stage_update_package') as stage:
                        instance.resume_pending_update()
                        stage.assert_called_once_with(package, '1.5.0')
                    callbacks = []
                    with mock.patch.object(instance.tasks, 'submit', side_effect=lambda operation, completed, failed: callbacks.append((operation, completed, failed))):
                        instance.stage_update_package(package, '1.5.0')
                        instance.stage_update_package(package, '1.5.0')
                    assert len(callbacks) == 1
                    callbacks[0][2](ValueError('Synthetic checksum failure'))
                    assert not instance.disposed and not instance.update_applying
                    assert instance.settings.get('updates', 'pendingPackage') == package
                    anchor = types.ModuleType('_max_ultra_session')
                    fake_rt.fileIn.side_effect = [RuntimeError('Synthetic installer failure'), None]
                    with mock.patch.dict(sys.modules, {'_max_ultra_session': anchor}):
                        instance.install_update(package, '1.5.0')
                        assert anchor.skip_pending_once
                    assert fake_rt.fileIn.call_count == 2
                    assert str(fake_rt.fileIn.call_args[0][0]).endswith('01_START_MAX_ULTRA_MCP_FIRST.ms')
                    assert instance.settings.get('updates', 'pendingPackage') == package
                    assert 'Synthetic installer failure' in instance.settings.get('updates', 'lastStatus')
                    fake_rt.fileIn.side_effect = None
                    installed = configparser.ConfigParser()
                    installed['package'] = {'version': '1.5.0'}
                    with mock.patch.object(module, 'read_ini', return_value=installed):
                        instance.install_update(package, '1.5.0')
                    assert instance.settings.get('updates', 'pendingPackage') == ''
                    assert instance.settings.get('updates', 'lastStatus') == 'Installed version 1.5.0'
                finally:
                    instance.rt = original_rt
            finally:
                if instance:
                    instance.close(reload=True)
                for journal in journals:
                    journal.close()
                QtWidgets.QApplication.processEvents()
    return "Controller fixture passed: startup, hide/restore, three dialogs and disposal"


print(run())
