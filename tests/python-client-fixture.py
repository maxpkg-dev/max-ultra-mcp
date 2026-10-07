# Exercise controller lifetime with synthetic transport and no scene operations.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import sys
from pathlib import Path
import tempfile
import time
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from max_ultra import client as module
from max_ultra.qt import QtWidgets
from max_ultra.wire import BoundedQueue, encode, decode
from max_ultra.settings import Settings


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
            finally:
                if instance:
                    instance.close(reload=True)
                for journal in journals:
                    journal.close()
                QtWidgets.QApplication.processEvents()
    return "Controller fixture passed: startup, hide/restore, three dialogs and disposal"


print(run())
