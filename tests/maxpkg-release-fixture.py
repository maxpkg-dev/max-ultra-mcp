# Exercise original MaxPkg tooling in a dedicated process and isolated directories.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

import json
import os
from pathlib import Path
import traceback
import shutil
import hashlib
import socket
import sys
import time
from pymxs import runtime as rt

if os.environ.get("MAX_ULTRA_RELEASE_FIXTURE") != "1":
    raise RuntimeError("Requires a dedicated release fixture process")
ROOT = Path(__file__).resolve().parents[1]
WORK = Path(os.environ["MAX_ULTRA_RELEASE_FIXTURE_ROOT"]).resolve()
if ROOT / "dist" not in WORK.parents:
    raise RuntimeError("Fixture must remain under the project's dist directory")
WORK.mkdir(parents=True, exist_ok=True)
REPORT = WORK / "report.json"
report = {"ok": False, "stage": "starting", "year": int(rt.maxVersion()[7])}


def save():
    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")


def api(method):
    result = json.loads(str(rt.execute("MaxPkgPackerApi." + method + "()")))
    if not result["ok"]:
        raise RuntimeError(json.dumps(result))
    return result["data"]


def run():
    try:
        if int(rt.objects.count) != 0 or str(rt.maxFileName):
            raise RuntimeError("Fixture refuses a nonempty scene")
        report["directories"] = {}
        for identifier in ("temp", "userScripts", "userMacros", "userIcons", "userStartupScripts"):
            target = WORK / identifier
            target.mkdir(exist_ok=True)
            rt.setDir(rt.Name(identifier), str(target))
            actual = Path(str(rt.getDir(rt.Name(identifier)))).resolve()
            if actual != target:
                raise RuntimeError("Could not isolate " + identifier)
            report["directories"][identifier] = str(actual)
        report["stage"] = "isolated"
        save()
        if os.environ.get("MAX_ULTRA_RELEASE_FIXTURE_MODE") == "migrate":
            start_migration()
            return
        rt.fileIn(str(ROOT / "maxpkg-packager.ms"), quiet=True)
        report["packager"] = api("ping")
        api("getSchema")
        state = api("reload")
        if Path(state["projectRoot"]).resolve() != ROOT:
            raise RuntimeError("Unexpected packager project")
        api("validate")
        report["stage"] = "validated"
        save()
        report["build"] = api("build")
        if not report["build"]["exists"]:
            raise RuntimeError("Packager returned no archive")
        report["ok"] = True
        report["stage"] = "built"
    except Exception:
        report["error"] = traceback.format_exc()
    finally:
        save()
        if report.get("stage") != "waiting-legacy":
            rt.quitMax(noPrompt=True)


def start_migration():
    # Only the MaxPkg notification facade is simulated. Extraction, generated
    # macros, both original hooks and both real client bootstraps are executed.
    for key in ("LOCALAPPDATA", "APPDATA", "USERPROFILE", "HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"):
        target = WORK / "environment" / key
        target.mkdir(parents=True, exist_ok=True)
        os.environ[key] = str(target)
        rt.execute('(dotNetClass "System.Environment").SetEnvironmentVariable "' + key + '" @"' + str(target) + '"')
    sock = socket.socket()
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    sock.close()
    os.environ['MAX_ULTRA_MCP_PORT'] = str(port)
    rt.execute('(dotNetClass "System.Environment").SetEnvironmentVariable "MAX_ULTRA_MCP_PORT" "' + str(port) + '"')
    rt.execute('global MaxPkg; struct MaxUltraFixturePackageManager (fn packageInstalled packageGuid = true); MaxPkg = MaxUltraFixturePackageManager()')
    state = WORK / 'userScripts/MaxUltraMCP'
    state.mkdir(parents=True, exist_ok=True)
    settings = state / 'panel-ui.ini'
    settings.write_text('[updates]\nautomatic=false\n[panel]\nx=120\ny=140\n[fixture]\nkeep=preserved\n', encoding='utf-16')
    old = next((ROOT / 'dist/migration-1.5.0/published-1.4.7').glob('*.mzp'))
    rt.fileIn(str(old), quiet=True)
    installed = WORK / 'temp' / old.stem.split('@')[2]
    report['installedRoot'] = str(installed)
    report['port'] = port
    rt.fileIn(str(installed / '01_START_MAX_ULTRA_MCP_FIRST.ms'), quiet=True)
    report['stage'] = 'waiting-legacy'
    report['deadline'] = time.monotonic() + 90
    save()
    QTimer.singleShot(500, poll_migration)


def poll_migration():
    try:
        if time.monotonic() > report['deadline']:
            raise TimeoutError('Migration timed out at ' + report['stage'])
        installed = Path(report['installedRoot'])
        state = WORK / 'userScripts/MaxUltraMCP'
        if report['stage'] == 'waiting-legacy':
            legacy = rt.MaxUltraMcpActiveClient
            if str(legacy.connectionState) != 'connected':
                QTimer.singleShot(500, poll_migration)
                return
            report['legacyConnected'] = True
            token = Path(os.environ['LOCALAPPDATA']) / '3DGROUND/MaxUltraMCP/runtime/state/control-token'
            report['tokenHash'] = hashlib.sha256(token.read_bytes()).hexdigest()
            update = next((ROOT / 'dist/maxpkg').glob('max-ultra-mcp@1.5.0@*.mzp'))
            staging = state / 'updates'
            staging.mkdir(exist_ok=True)
            staged = staging / update.name
            shutil.copyfile(str(update), str(staged))
            Path(str(staged)+'.sha256').write_text(hashlib.sha256(staged.read_bytes()).hexdigest()+'  '+staged.name)
            rt.setINISetting(str(state / 'panel-ui.ini'), 'updates', 'pendingPackage', str(staged))
            report['stage'] = 'waiting-python'
            save()
            rt.fileIn(str(installed / '01_START_MAX_ULTRA_MCP_FIRST.ms'), quiet=True)
        else:
            anchor = sys.modules.get('_max_ultra_session')
            client = getattr(anchor, 'client', None)
            if client and client.version == '1.5.0' and client.connection_state == 'connected':
                assert client.settings.get('fixture', 'keep') == 'preserved'
                token = Path(os.environ['LOCALAPPDATA']) / '3DGROUND/MaxUltraMCP/runtime/state/control-token'
                assert hashlib.sha256(token.read_bytes()).hexdigest() == report['tokenHash']
                inventory = json.loads((installed / 'assets/obsolete-1.4.7.json').read_text())
                assert all(not (installed / relative).exists() for relative in inventory)
                assert int(rt.objects.count) == 0
                report.update(ok=True, stage='migrated', removedObsoleteFiles=len(inventory), settingsPreserved=True, authenticationPreserved=True)
                client.close(reload=True)
                save()
                rt.quitMax(noPrompt=True)
                return
        QTimer.singleShot(500, poll_migration)
    except Exception:
        report['error'] = traceback.format_exc()
        save()
        rt.quitMax(noPrompt=True)


save()
try:
    from PySide6.QtCore import QTimer
except ImportError:
    from PySide2.QtCore import QTimer
QTimer.singleShot(1000, run)
