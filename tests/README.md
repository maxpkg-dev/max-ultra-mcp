# Tests

All automated verification code and test-only fixtures live in this directory.

## Suites

- `smoke-test.js` verifies the original tool surface, routing, lifecycle, packaging, documentation contracts, MaxScript structure, and examples.
- `v1-smoke-test.js` verifies tool profiles, structured envelopes, revisions, jobs, floor-plan generation, screenshots, and multi-client routing.
- `cli-integration-test.js` launches real daemon and STDIO child processes, replaces the daemon behind the same live STDIO host, and verifies authenticated JSON-only MCP recovery.
- `diagnostics-cli-test.js` verifies help and dynamic skill discovery without Max, Codex/Claude setup instructions, the source-only launcher, MaxPkg exclusion, and read-only status/health/capabilities/skill checks against a mock Max.
- `helpers/mock-max-client.js` simulates supported 3ds Max protocol endpoints without opening 3ds Max.
- `fixtures/ui-automation-rollout/` contains the MaxScript rollout used for real-Max UI Automation verification.
- `ui-automation-helper-test.ps1` verifies direct HWND capture and bounded native WinForms diagnostics against a temporary synthetic process named `3dsmax.exe`.

Run every automated suite from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-smoke.ps1
```

Run an individual suite with Node.js 22+:

```powershell
node .\tests\smoke-test.js
node .\tests\v1-smoke-test.js
node .\tests\cli-integration-test.js
node .\tests\diagnostics-cli-test.js
```

The JavaScript suites use mock Max clients only. They must never open, modify, render, or save a real user scene. The v1 suite covers common session-owned jobs, render compatibility wrappers, plan-token binding, tool schemas, actionable error hints, bounded material-diagnostic generation/parsing, and privacy-safe activity labels. The synthetic UI helper test is part of `run-smoke.ps1`; it launches no Autodesk software and touches no scene. It verifies direct HWND capture, bounded native diagnostics, evidence fields, and cleanup. Child/MAXScriptDialog, plugin WebBrowser, material-class, renderer-specific, and other real-Max behavior still requires an explicitly selected disposable 3ds Max fixture.


## Windows helper launch regression

windows-process-test.js exercises empty and unrelated PATH values, Windows and project paths with spaces, SystemRoot/windir fallback, Sysnative selection for a simulated 32-bit caller, missing executables, and directory-as-executable rejection. The real Windows fixture invokes a copied startup BAT and a synthetic PowerShell runner; it never launches a daemon or touches 3ds Max.

Before claiming real-Max acceptance, test update checking, AI Setup, and automatic startup in isolated 2022 and 2027 profiles with a modified process PATH. Confirm that a missing package working directory reports PROCESS_WORKING_DIRECTORY_MISSING, and that a valid helper still launches with spaces in its package path. Static MaxScript checks do not prove these live behaviors.