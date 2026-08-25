# 3D Ground - Max Ultra MCP

Max Ultra MCP connects AI agents to already-open Autodesk 3ds Max 2022 and 2027 instances while keeping all Max UI and scene work on the main thread.

## Start here

Run this single file from 3ds Max:

```text
01_START_MAX_ULTRA_MCP_FIRST.ms
```

It verifies the loopback endpoint, starts the project server in a minimized console when needed, and connects the current Max instance. Re-running the file performs a verified clean restart.

- Closing the panel with X or pressing **Stop / Exit** disconnects Max and immediately stops the exact server launched by that bootstrap session. A pre-existing or manually launched server is left running.
- **Hide panel** keeps the bridge running and replaces the main panel with a compact lower-left **Expand MCP Server** mini-panel.
- If the BAT/server is closed manually, this Max session stops with an actionable error. It does not launch the server again; explicitly run `01_START_MAX_ULTRA_MCP_FIRST.ms` to start a new session.
- **Reconnect** and **Connect only** never launch a stopped server.

For a visible diagnostic server console, run `scripts\start-server.bat` manually.

## PowerShell requirement

PowerShell 7 (`pwsh`) is **not required** for normal Max Ultra MCP operation. The supplied BAT and smoke launchers use Windows PowerShell 5.1 (`powershell.exe`), which is included with supported Windows versions. PowerShell 7 is needed only if your own external automation explicitly chooses `pwsh` or depends on a PowerShell 7-only feature.

The public launchers pass one project-relative JavaScript path to `scripts\run-node-script.ps1`. That shared helper owns Node.js 18+ discovery, version and script validation, safe argument forwarding, process execution, and exit-code reporting.

Check Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion"
```

Check optional PowerShell 7:

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
```

If the second command is not found, Max Ultra MCP still operates normally.

## Verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-smoke.ps1
```

The smoke suite uses mock Max clients and never opens, changes, or saves a real scene.

See [the detailed documentation](docs/README.md) for MCP configuration, tools, endpoint recovery, panel behavior, examples, environment variables, and repository layout.
