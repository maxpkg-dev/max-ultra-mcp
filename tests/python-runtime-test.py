# Behavior tests for the standalone Python runtime, without touching a Max scene.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import pathlib
import sys
import tempfile
import unittest
import ast
import hashlib
import os
import socket
import threading
import time
import zipfile
import runpy
import types
import json
import shutil
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "python"))
from max_ultra.journal import Journal
from max_ultra.wire import FrameReader, BoundedQueue, encode, decode, MAX_FRAME
from max_ultra.settings import Settings
from max_ultra.transport import Transport, probe
from max_ultra.updates import verify_package, staged_version, GUID
from max_ultra.installation import complete_installation, installation_ready
from max_ultra.processes import launch_helper
from max_ultra import themes


class RuntimeTests(unittest.TestCase):
    def test_installed_cleanup_preserves_modified_and_user_files(self):
        with tempfile.TemporaryDirectory() as folder:
            base = pathlib.Path(folder)
            root = base / GUID
            (root / 'assets').mkdir(parents=True)
            (root / 'manifest.ini').write_text('[package]\npackageGuid=' + GUID + '\nversion=1.5.0\n')
            (root / 'assets/old.png').write_bytes(b'old packaged icon')
            (root / 'assets/modified.png').write_bytes(b'user changed this')
            (root / 'user.txt').write_text('keep')
            (root / 'maxpkg-files.txt').write_text('manifest.ini\nuser.txt\n')
            digest = hashlib.sha256(b'old packaged icon').hexdigest()
            inventory = {'assets/old.png': digest, 'assets/modified.png': digest}
            (root / 'assets/obsolete-1.4.7.json').write_text(json.dumps(inventory))
            self.assertFalse(installation_ready(root, base))
            result = complete_installation(root, base)
            self.assertEqual(result['removed'], ['assets/old.png'])
            self.assertEqual(result['preserved'], ['assets/modified.png'])
            self.assertTrue(installation_ready(root, base))
            self.assertEqual((root / 'user.txt').read_text(), 'keep')
            self.assertEqual(complete_installation(root, base)['removed'], [])
            (root / 'maxpkg-files.txt').write_text('missing.py\n')
            with self.assertRaisesRegex(ValueError, 'Required installed file'):
                complete_installation(root, base)
            (root / 'maxpkg-files.txt').write_text('manifest.ini\n')
            with self.assertRaises(ValueError):
                complete_installation(root, base / 'elsewhere')
            (root / 'assets/obsolete-1.4.7.json').write_text(json.dumps({'../user.txt': digest}))
            with self.assertRaises(ValueError):
                complete_installation(root, base)

    def test_theme_files_reload_and_invalid_palette_is_atomic(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            for source in themes.THEME_DIRECTORY.glob('*.json'):
                shutil.copyfile(str(source), str(directory / source.name))
            try:
                with mock.patch.object(themes, 'THEME_DIRECTORY', directory):
                    themes.select('forest')
                    filename = directory / 'forest.json'
                    document = json.loads(filename.read_text())
                    document['colors']['window_background'] = '#102030'
                    document['colors']['log_success'] = '#abcdef'
                    filename.write_text(json.dumps(document))
                    themes.select('forest')
                    self.assertEqual(themes.style('@window_background @log_success'), '#102030 #abcdef')
                    self.assertEqual(themes.style('#242320 #78e196'), '#102030 #abcdef')
                    document['colors']['window_background'] = 'not-a-color'
                    filename.write_text(json.dumps(document))
                    with self.assertRaises(ValueError):
                        themes.select('forest')
                    self.assertEqual(themes.style('@window_background'), '#102030')
                    self.assertEqual(themes.current, 'forest')
            finally:
                themes.select('graphite')

    def test_max_theme_reads_user_colors_without_writing_them(self):
        before = dict(themes.max_colors)
        previous_palette = themes.THEMES['max']
        try:
            def read(name):
                value = .1 if name in ('text', 'windowText', 'rollupTitleText') else .9
                return types.SimpleNamespace(x=value, y=value, z=value)
            manager = types.SimpleNamespace(getColor=read)
            runtime = types.SimpleNamespace(colorMan=manager, Name=lambda name: name)
            themes.select('max')
            self.assertTrue(themes.read_max_colors(runtime))
            self.assertFalse(themes.read_max_colors(runtime))
            self.assertEqual(themes.style('#242320'), '#e6e6e6')
            self.assertEqual(themes.style('#e8e3da'), '#1a1a1a')
            self.assertTrue(themes.max_is_light())
            self.assertEqual(themes.style('#78e196'), '#246d37')
            self.assertEqual(themes.color_hex(types.SimpleNamespace(x=68,y=68,z=68)), '#444444')
        finally:
            themes.max_colors = before
            themes.THEMES['max'] = previous_palette
            themes.select('graphite')

    def test_theme_selection_and_persistence(self):
        try:
            with tempfile.TemporaryDirectory() as folder:
                filename = pathlib.Path(folder) / 'settings.ini'
                for identifier in themes.THEMES:
                    Settings(filename).set_many('appearance', {'theme': identifier})
                    self.assertEqual(themes.select(Settings(filename).get('appearance', 'theme')), identifier)
                    self.assertEqual(themes.style('#242320'), themes.THEMES[identifier][1][0])
                    self.assertEqual(themes.style('#78e196 #efa35c'), '#78e196 #efa35c')
                    content = '<style>body { background:rgb(28,28,26); }</style><code>#242320</code>'
                    self.assertIn('<code>#242320</code>', themes.html(content))
                    if identifier != 'graphite':
                        self.assertIn(themes.THEMES[identifier][1][1], themes.html(content))
                self.assertEqual(themes.select('unknown'), 'graphite')
        finally:
            themes.select('graphite')

    def test_bootstrap_uses_its_own_package_with_another_copy_loaded(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        source = (root / 'python/bootstrap.py').read_text(encoding='utf-8')
        saved = {key: value for key, value in sys.modules.items() if key == 'max_ultra' or key.startswith('max_ultra.') or key in ('pymxs', '_max_ultra_session')}
        previous_path = list(sys.path)
        previous_bytecode = sys.dont_write_bytecode
        scheduled, errors = [], []
        try:
            with tempfile.TemporaryDirectory() as folder:
                copies = [pathlib.Path(folder) / name / 'python' for name in ('current', 'old')]
                for copy in copies:
                    package = copy / 'max_ultra'
                    package.mkdir(parents=True)
                    (package / '__init__.py').write_text('')
                (copies[0] / 'bootstrap.py').write_text(source, encoding='utf-8')
                (copies[0].parent / '01_START_MAX_ULTRA_MCP_FIRST.ms').write_text('-- synthetic entry')
                (copies[0] / 'max_ultra/client.py').write_text('class Client:\n    def __init__(self, *args, **kwargs): self.resumed = False\n    def resume_pending_update(self): self.resumed = True\n')
                (copies[1] / 'max_ultra/client.py').write_text('class Client:\n    def __init__(self, *args, **kwargs): pass\n')
                # Reproduce a source tree already in sys.path behind an older
                # installed package, with the old package cached as well.
                sys.path[:0] = [str(copies[1]), str(copies[0])]
                for key in list(sys.modules):
                    if key == 'max_ultra' or key.startswith('max_ultra.') or key == '_max_ultra_session':
                        del sys.modules[key]
                __import__('max_ultra.client')
                qt = types.ModuleType('max_ultra.qt')
                qt.QtCore = types.SimpleNamespace(QTimer=types.SimpleNamespace(singleShot=lambda delay, callback: scheduled.append(callback)))
                qt.QtWidgets = types.SimpleNamespace(QMessageBox=types.SimpleNamespace(critical=lambda *args: errors.append(args)))
                rt = types.SimpleNamespace(globalVars=types.SimpleNamespace(isGlobal=lambda name: False), Name=lambda name: name)
                with mock.patch.dict(sys.modules, {'max_ultra.qt': qt, 'pymxs': types.SimpleNamespace(runtime=rt)}):
                    runpy.run_path(str(copies[0] / 'bootstrap.py'))
                    scheduled.pop()()
                    self.assertEqual(errors, [])
                    self.assertTrue(sys.modules['_max_ultra_session'].client.resumed)
                    self.assertEqual(pathlib.Path(sys.modules['max_ultra.client'].__file__).parent, copies[0] / 'max_ultra')
        finally:
            sys.path[:] = previous_path
            sys.dont_write_bytecode = previous_bytecode
            for key in list(sys.modules):
                if key == 'max_ultra' or key.startswith('max_ultra.') or key in ('pymxs', '_max_ultra_session'):
                    del sys.modules[key]
            sys.modules.update(saved)

    def test_all_python_sources_parse(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        for filename in list((root / "python").rglob("*.py")) + [root / "scripts/maxpkg-uninstall.py"]:
            ast.parse(filename.read_text(encoding="utf-8-sig"), filename=str(filename))

    def test_journal_write_failure_is_not_silent(self):
        with tempfile.TemporaryDirectory() as folder:
            journal = Journal(pathlib.Path(folder) / "session.sqlite3")
            journal._db.execute("PRAGMA query_only=ON")
            with self.assertRaises(Exception):
                journal.append("error", "Must not report success")
            self.assertEqual(journal.count(), 0)
            journal.close()

    def test_update_revalidation(self):
        with tempfile.TemporaryDirectory() as folder:
            staging = pathlib.Path(folder) / "updates"
            staging.mkdir()
            package = staging / ("max-ultra-mcp@1.5.0@" + GUID + ".mzp")
            with zipfile.ZipFile(str(package), "w") as archive:
                archive.writestr("manifest.ini", "[package]\nversion=1.5.0\n")
            checksum = pathlib.Path(str(package) + ".sha256")
            checksum.write_text(hashlib.sha256(package.read_bytes()).hexdigest() + "  " + package.name)
            self.assertEqual(verify_package(package, staging, "1.5.0"), package)
            self.assertEqual(staged_version(package), "1.5.0")
            with self.assertRaises(ValueError):
                staged_version(staging / "unrelated.mzp")
            with self.assertRaises(ValueError):
                verify_package(package, staging, "1.5.1")
            with self.assertRaises(ValueError):
                verify_package(package, staging / "other", "1.5.0")
            with package.open("ab") as stream:
                stream.write(b"changed")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                verify_package(package, staging, "1.5.0")

    @unittest.skipUnless(os.name == "nt", "Windows helper lifecycle")
    def test_owned_helper_job_cleanup(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "scripts").mkdir()
            marker = root / "started.txt"
            (root / "scripts/fixture.ps1").write_text("param([string]$Marker)\n[IO.File]::WriteAllText($Marker, 'started')\nStart-Sleep -Seconds 60\n")
            process = launch_helper(root, "fixture.ps1", ["-Marker", str(marker)], managed=True)
            try:
                deadline = time.monotonic() + 10
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(marker.exists(), "Owned suspended helper did not resume")
            finally:
                process.owned_job.close()
                process.wait(timeout=5)
            self.assertIsNotNone(process.returncode)

    @unittest.skipUnless(os.name == "nt", "Windows lifecycle mutex")
    def test_real_socket_worker_fragmentation_cancel_and_shutdown(self):
        with tempfile.TemporaryDirectory() as folder, socket.socket() as server:
            server.bind(("127.0.0.1", 0))
            server.listen(4)
            server.settimeout(10)
            port = server.getsockname()[1]
            finished = threading.Event()
            replies, errors = [], []
            def serve():
                try:
                    with server.accept()[0] as connection, connection.makefile("rb") as stream:
                        self.assertIn(b"\tprobe", stream.readline())
                        connection.sendall(("CONTROL_RESPONSE\tbootstrap-control\tok\t" + encode('{"server":"max-ultra-mcp","healthy":true}') + "\n").encode("ascii"))
                    with server.accept()[0] as connection, connection.makefile("rb") as stream:
                        self.assertTrue(stream.readline().startswith(b"HELLO\t1\t"))
                        connection.sendall(b"REQUEST\tfixture\texe")
                        connection.sendall(("cute\t" + encode("synthetic") + "\nCANCEL\tfixture\n").encode("ascii"))
                        connection.settimeout(10)
                        replies.append(stream.readline())
                        self.assertEqual(stream.read(1), b"")
                except Exception as error:
                    errors.append(error)
                finally:
                    finished.set()
            worker = threading.Thread(target=serve, daemon=True)
            worker.start()
            transport = Transport(folder, folder, port, "HELLO\t1\t" + encode("mock-max-2027-1"), allow_launch=False)
            transport.start()
            try:
                lines = []
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    line = transport.inbound.pop()
                    if line:
                        lines.append(line)
                        if line.startswith("CANCEL"):
                            break
                    time.sleep(0.01)
                self.assertIsNone(transport.error)
                self.assertEqual([line.split("\t")[0] for line in lines], ["EVENT", "REQUEST", "CANCEL"])
                transport.outbound.put("RESPONSE\tfixture\tok\t" + encode("synthetic reply"))
                deadline = time.monotonic() + 5
                while not replies and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertIn(b"RESPONSE\tfixture\tok", replies[0])
            finally:
                transport.stop()
                transport.thread.join(3)
                worker.join(3)
            self.assertFalse(transport.thread.is_alive())
            self.assertTrue(finished.is_set())
            self.assertEqual(errors, [])
    def test_history_full_search_and_reopen(self):
        with tempfile.TemporaryDirectory() as folder:
            filename = pathlib.Path(folder) / "session.sqlite3"
            journal = Journal(filename)
            # The same persistent representation as append; batch a large fixture.
            with journal._db:
                journal._db.executemany("INSERT INTO entries(stamp,category,message) VALUES (?,?,?)", (("2026-01-01T12:00:00", "info" if index % 2 else "warning", "Example event {}".format(index)) for index in range(100000)))
            self.assertEqual(journal.count(), 100000)
            self.assertEqual(journal.page()[0][3], "Example event 0")
            self.assertEqual(journal.page(99999, 1)[0][3], "Example event 99999")
            self.assertEqual(journal.count(category="warning"), 50000)
            self.assertEqual(journal.count(search="event 99999"), 1)
            journal.append("error", "authorization: Bearer private-secret control-token=" + "a" * 64)
            self.assertNotIn("private-secret", journal.tail(1)[0][3])
            self.assertNotIn("a" * 64, journal.tail(1)[0][3])
            destination = pathlib.Path(folder) / "export.txt"
            journal.export(destination, "event 99999")
            self.assertIn("Example event 99999", destination.read_text())
            journal.close()
            journal = Journal(filename)
            self.assertEqual(journal.count(), 100001)
            journal.close()

    def test_frames_fragmented_and_deadline(self):
        reader = FrameReader()
        self.assertEqual(reader.feed(b"REQUEST\t1", 0), [])
        self.assertEqual(reader.feed(b"\texecute\t-\nCANCEL\t1\n", 1), ["REQUEST\t1\texecute\t-", "CANCEL\t1"])
        reader.feed(b"partial", 2)
        with self.assertRaises(TimeoutError):
            reader.check_deadline(8)
        with self.assertRaises(ValueError):
            FrameReader().feed(b"a" * (MAX_FRAME + 1))
        self.assertEqual(decode(encode("Unicode \u03bb\n\t")), "Unicode \u03bb\n\t")

    def test_queue_bounds_and_release(self):
        queue = BoundedQueue()
        for _ in range(64):
            queue.put("item")
        with self.assertRaises(BufferError):
            queue.put("overflow")
        self.assertEqual(queue.pop(), "item")
        queue.put("replacement")
        queue.clear()
        self.assertIsNone(queue.pop())
        queue.put("a" * MAX_FRAME)
        queue.put("b" * MAX_FRAME)
        with self.assertRaises(BufferError):
            queue.put("x")

    def test_existing_settings_survive(self):
        with tempfile.TemporaryDirectory() as folder:
            filename = pathlib.Path(folder) / "panel.ini"
            filename.write_text("[panel]\nx=120\nhidden=true\n[custom]\nkeep=yes\n", encoding="utf-16")
            settings = Settings(filename)
            self.assertTrue(settings.boolean("panel", "hidden"))
            settings.set_many("panel", {"width": 320})
            reopened = Settings(filename)
            self.assertEqual(reopened.get("custom", "keep"), "yes")
            self.assertEqual(reopened.integer("panel", "x"), 120)


if __name__ == "__main__":
    unittest.main()
