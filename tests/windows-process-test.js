/*
 * Verifies system executable resolution and isolated launchers without a Max scene.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const { resolveWindowsPowerShell } = require("../core/windows-process");
const root = path.resolve(__dirname, "..");
const windowsRoot = "D:\\Windows With Spaces";
const nativePowerShell = path.win32.join(windowsRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
const sysnativePowerShell = path.win32.join(windowsRoot, "Sysnative", "WindowsPowerShell", "v1.0", "powershell.exe");

for (const PATH of ["", "X:\\unrelated"]) {
  assert.equal(resolveWindowsPowerShell({ env: { SystemRoot: windowsRoot, PATH }, arch: "x64", isFile: (candidate) => candidate === nativePowerShell }), nativePowerShell);
}
assert.equal(resolveWindowsPowerShell({ env: { windir: windowsRoot }, arch: "x64", isFile: (candidate) => candidate === nativePowerShell }), nativePowerShell);
assert.equal(resolveWindowsPowerShell({ env: { SystemRoot: windowsRoot }, arch: "ia32", isFile: (candidate) => candidate === sysnativePowerShell }), sysnativePowerShell);
assert.equal(resolveWindowsPowerShell({ env: { SystemRoot: windowsRoot }, arch: "ia32", isFile: (candidate) => candidate === nativePowerShell }), nativePowerShell);
for (const env of [{ PATH: windowsRoot }, { SystemRoot: "." }, { SystemRoot: "D:relative" }, { SystemRoot: windowsRoot }]) {
  assert.throws(() => resolveWindowsPowerShell({ env, isFile: () => false }), { code: "POWERSHELL_NOT_FOUND" });
}

const bootstrap = fs.readFileSync(path.join(root, "01_START_MAX_ULTRA_MCP_FIRST.ms"), "utf8");
assert.doesNotMatch(bootstrap, /startInfo\.FileName = "(?:powershell|cmd)\.exe"/);
assert.equal((bootstrap.match(/startInfo\.WorkingDirectory = validateProcessWorkingDirectory /g) || []).length, 4);
assert.match(bootstrap, /environmentClass\.SystemDirectory/);
assert.match(bootstrap, /Is64BitOperatingSystem and not environmentClass\.Is64BitProcess/);
assert.match(bootstrap, /PROCESS_WORKING_DIRECTORY_MISSING/);
assert.ok(bootstrap.indexOf("fn resolveWindowsExecutable") < bootstrap.indexOf("fn launchDetachedShutdownHelper"));
const uninstall = fs.readFileSync(path.join(root, "scripts/maxpkg-uninstall.ms"), "utf8");
assert.match(uninstall, /startInfo\.FileName = maxUltraMcpResolveWindowsExecutable/);
assert.match(uninstall, /startInfo\.WorkingDirectory = maxUltraMcpValidateWorkingDirectory/);
for (const relativeFile of ["core/windows-ui.js", "core/image-utils.js"]) {
  assert.match(fs.readFileSync(path.join(root, relativeFile), "utf8"), /execFile\(resolveWindowsPowerShell\(\),/);
}
if (process.platform === "win32") {
  const actualPowerShell = resolveWindowsPowerShell();
  const cmd = path.join(process.env.SystemRoot, "System32", "cmd.exe");
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-launch space-"));
  try {
    const launcher = path.join(fixture, "start-server.bat");
    fs.copyFileSync(path.join(root, "scripts/start-server.bat"), launcher);
    fs.copyFileSync(path.join(root, "scripts/resolve-windows-powershell.bat"), path.join(fixture, "resolve-windows-powershell.bat"));
    fs.writeFileSync(path.join(fixture, "run-node-script.ps1"),
      '[Console]::WriteLine("FIXTURE:" + ($args -join "|"))\r\nexit 0\r\n');
    for (const PATH of ["", path.join(fixture, "unrelated")]) {
      const output = execFileSync(cmd, ["/d", "/c", 'call "' + launcher + '" --no-pause'], {
        cwd: root, env: { ...process.env, PATH }, windowsHide: true, windowsVerbatimArguments: true, encoding: "utf8", timeout: 30000,
      });
      assert.match(output, /FIXTURE:core\\server\.js\|--daemon/);
      const probe = execFileSync(actualPowerShell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", '[Console]::WriteLine("ABSOLUTE_OK")'], {
        cwd: root, env: { ...process.env, PATH }, windowsHide: true, encoding: "utf8", timeout: 30000,
      });
      assert.match(probe, /ABSOLUTE_OK/);
    }
    const missing = spawnSync(cmd, ["/d", "/c", 'call "' + launcher + '" --no-pause'], {
      cwd: root, windowsVerbatimArguments: true, env: { ...process.env, PATH: "", SystemRoot: path.join(fixture, "missing"), windir: path.join(fixture, "missing") },
      windowsHide: true, encoding: "utf8", timeout: 30000,
    });
    assert.equal(missing.status, 2);
    assert.match(missing.stderr, /POWERSHELL_NOT_FOUND/);
    assert.doesNotMatch(missing.stdout, /FIXTURE:/);

    const fakeWindowsRoot = path.join(fixture, "Windows Root");
    const fakeExe = path.join(fakeWindowsRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
    fs.mkdirSync(path.dirname(fakeExe), { recursive: true });
    fs.writeFileSync(fakeExe, "resolver fixture only");
    fs.writeFileSync(path.join(fixture, "probe.bat"),
      '@echo off\r\ncall "%~dp0resolve-windows-powershell.bat"\r\nif errorlevel 1 exit /b %ERRORLEVEL%\r\necho RESOLVED:%MAX_ULTRA_POWERSHELL_EXE%\r\n');
    const resolved = execFileSync(cmd, ["/d", "/c", "probe.bat"], {
      cwd: fixture, env: { ...process.env, PATH: "", SystemRoot: fakeWindowsRoot, windir: fakeWindowsRoot },
      windowsHide: true, encoding: "utf8", timeout: 30000,
    });
    assert.ok(resolved.includes("RESOLVED:" + fakeExe));
    assert.equal(resolveWindowsPowerShell({ env: { SystemRoot: fakeWindowsRoot }, arch: "x64" }), fakeExe);
    fs.unlinkSync(fakeExe);
    fs.mkdirSync(fakeExe);
    assert.throws(() => resolveWindowsPowerShell({ env: { SystemRoot: fakeWindowsRoot }, arch: "x64" }), { code: "POWERSHELL_NOT_FOUND" });
    const directoryProbe = spawnSync(cmd, ["/d", "/c", "probe.bat"], {
      cwd: fixture, env: { ...process.env, PATH: "", SystemRoot: fakeWindowsRoot, windir: fakeWindowsRoot },
      windowsHide: true, encoding: "utf8", timeout: 30000,
    });
    assert.equal(directoryProbe.status, 2);
    assert.match(directoryProbe.stderr, /POWERSHELL_NOT_FOUND/);
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true });
  }
}
console.log("Windows process launch tests passed: PATH isolation, spaces, native architecture, and missing executable diagnostics.");