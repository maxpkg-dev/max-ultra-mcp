# 3DGROUND - Max Ultra MCP

Max Ultra MCP is a standalone local MCP bridge for controlling already-open Autodesk 3ds Max 2022 and 2027 processes with concise semantic tools. Networking remains off the Max UI thread; scene, viewport, UIAccessor, and WinForms work is marshalled through a bounded main-thread queue.

## One-file first start

The only file a 3ds Max user runs manually is the root file:

```text
01_START_MAX_ULTRA_MCP_FIRST.ms
```

Run it once in every Max process that should connect. It locates `scripts\start-server.bat` relative to the project root, probes the configured loopback endpoint, launches a minimized branded server console when needed, and connects the current Max. Running the file again disposes the previous in-Max client, then explicitly reuses a healthy compatible server or launches a new one when absent. An unexpected disconnect or manually closed server is terminal for that session: the bootstrap reports the failure and does not relaunch until the first-step file is explicitly run again. Panel **Reconnect** and **Connect only** actions attach only to an already-running server.

A manual diagnostic launch remains visible:

```bat
scripts\start-server.bat
```

Automatic launch uses `--no-pause --port <PORT>` and starts minimized. It also passes a unique launch token, the Max PID, and a port-scoped ownership-file path. The Node process writes the record only after listening, including its own PID/start time and the exact BAT launcher PID/start time. Manual BAT launches omit this metadata and remain outside automatic shutdown.

## Safe endpoint recovery

The default endpoint is `127.0.0.1:47635`.

- A healthy current Max Ultra MCP server is reused on first start.
- A compatible legacy bridge that lacks `probe` is recognized through its live `CONTROL list` inventory. First start may attach to it.
- Re-running against a legacy bridge, or encountering a truly unknown occupant, never kills a process. The bootstrap scans only the next 10 loopback ports, selects a free fallback, starts Max Ultra MCP there, and reports `MAX_ULTRA_MCP_PORT=<PORT>` in the panel.
- The MaxScript uses CONTROL only for endpoint discovery and never sends a shutdown command. On Window X, **Stop / Exit**, or `#preSystemShutdown`, it launches `scripts\stop-owned-server.bat` detached and cancels its transport worker; that path never relaunches a server.
- The helper counts live `3dsmax.exe` processes without using the bridge connection. It proceeds only when the count is exactly one and, in normal operation, that PID is the Max process that dispatched it. Zero or two-plus processes leave the server running.
- Before termination, the helper requires a Max-created ownership record for the selected port (or the same launch token during a fallback-port startup race). It verifies project root, server script, ownership token, Node PID/name/start time/command line, and BAT PID/name/start time/command line. It force-stops only those exact verified PIDs. Missing, stale, manual, mismatched, or inaccessible metadata fails closed.
- General protocol clients retain `shutdown`, `shutdown_owned`, and idle-shutdown controls, but the root MaxScript does not call them.

## Panel behavior

The compact panel shows two status/context rows above a tall log.

- Running/connected is green; connecting/restarting/retrying is amber; errors are red; stopped/unknown is neutral. Status text is bold and always names the state, so color is not the only cue.
- Panel and log colors derive from 3ds Max `ColorMan` background/text colors, with safe fallbacks. The log uses a lighter theme surface, a one-pixel flat black boundary, and blue/cyan informational text. Success, warning, error, and debug colors remain distinct.
- The RichTextBox is read-only, wrapped, capped at 30 entries, and auto-scrolls to the latest entry.
- The compact **Hide panel** action sits at the upper-right beside the status row. Its former lower-right position contains **Settings**. The settings window currently contains one auto-saving checkbox, **Autostart with 3ds Max**; changing it immediately writes `[settings] autostart` in `MaxUltraMCP\panel-ui.ini` and creates or removes `3DGROUND-Max-Ultra-MCP-Autostart.ms` under `#userStartupScripts` for the current Max version. The generated startup script stores the absolute path to `01_START_MAX_ULTRA_MCP_FIRST.ms`, launches it through `fileIn` when present, and otherwise disables the INI setting and schedules its own deletion for `#postSystemStartup`, after the startup-script file is no longer open.
- Final normal window `x`/`y` plus user-resized `width`/`height` are saved before cleanup in the per-user scripts `MaxUltraMCP\panel-ui.ini` file. Existing position-only files remain compatible and use the 680×500 default size. On launch, corrupt or missing values fall back safely; size is constrained to the panel's 540×420 layout minimum and the selected monitor's current working area, and position is clamped so the full panel remains visible. If monitor topology or DPI scaling changed, the nearest current screen is used; an unusable position centers the validated size on the primary screen.
- **Hide panel** saves the current normal geometry and hides only the main panel. The server and Max client remain connected. A compact borderless mini-panel appears at its last saved position (lower-left of the 3ds Max screen on first use), with one **Expand MCP Server** action and no minimize, maximize, or close controls. Drag the mini-panel by its **Max Ultra MCP** label; its clamped on-screen position is saved in the same per-user INI file. Expanding revalidates and restores/focuses the main panel at its previous size and position, then removes the mini-panel. Minimized or maximized state is never persisted: normal-state move/resize tracking updates the INI geometry, with WinForms restore bounds used only as a fallback. Repeated hide requests reuse the same mini-panel instead of creating duplicates, and a failed expansion leaves it available to retry.
- Window X and **Stop / Exit** first stop and unsubscribe the Max-side timer, start the detached exactly-one-Max helper, and cancel transport. If two or more Max processes are live, the helper leaves the server available to them. If exactly one is live, it terminates only the ownership-verified Max-launched server/BAT chain. A pre-existing/manual server is disconnected but left running. The `#preSystemShutdown` callback applies the same idempotent cleanup during Max exit. Re-run cleanup disposes the prior timer, worker/form handlers, and restore mini-panel without invoking the shutdown helper, then begins a new explicit start flow.
- Shutdown is deliberately fail-closed: if helper startup is delayed until the closing Max has fully exited, it sees zero Max processes and leaves the server running; likewise, unreadable process metadata or a missing/corrupt ownership file leaves it running. Run the root script and use **Stop / Exit** again after resolving the metadata issue rather than terminating arbitrary processes.

## Concise MCP tools

| Tool | Purpose |
| --- | --- |
| `max_list_instances` | Compact live Max inventory |
| `max_select_instance` | Choose the default instance |
| `max_scene_summary` | Concise scene/object/selection state |
| `max_create_box` | Create a standard Box without MaxScript boilerplate |
| `max_viewport_screenshot` | Capture the selected viewport |
| `max_ui_list` | Discover bounded Max-owned UI controls |
| `max_ui_invoke` | Guarded invoke with stale-handle checks |
| `max_health` | Transport/main-thread health |
| `max_snapshot` | Detailed diagnostics snapshot |
| `max_panel` | Show, hide, minimize, or restore the panel |
| `max_logs` | Read bounded panel activity |
| `max_smoke` | Non-destructive protocol smoke request |
| `max_execute` | Advanced MaxScript escape hatch |

When exactly one Max is connected, short calls route automatically. With several instances, the server returns the live inventory and requires `instance_id` or an explicit `max_select_instance` call.

## Runnable Box example

Run:

```bat
examples\example-create-test-box.bat
```

The visible action in `examples\example-create-box.js` is intentionally short: it creates one clearly named Box at origin and does not save the scene. `examples\run-max-action.js` owns connection, inventory, sole-instance routing, multi-instance refusal, error handling, and cleanup. `core\bridge-control-client.js` owns protocol plumbing.

The BAT passes `examples\example-create-box.js` directly to `scripts\run-node-script.ps1`. The shared runner owns Node.js 18+ discovery, script validation, safe argument forwarding, execution errors, and the child exit code; example launchers contain no environment-specific Node path plumbing.

If exactly one Max is connected, the action targets it. If several are connected, the example prints the live inventory and refuses to modify an arbitrary scene.

## Agent configuration

Use the absolute path to the launcher on the machine where the repository is installed. Replace `<PROJECT_ROOT>` with that location; do not copy this placeholder literally.

```powershell
codex mcp add max-ultra-mcp -- cmd.exe /d /c "<PROJECT_ROOT>\scripts\start-server.bat" --no-pause
```

Equivalent configuration shape:

```toml
[mcp_servers.max-ultra-mcp]
command = "cmd.exe"
args = ["/d", "/c", "<PROJECT_ROOT>\\scripts\\start-server.bat", "--no-pause"]
```


## PowerShell versions

PowerShell 7 (`pwsh`) is not required by Max Ultra MCP. Normal startup and verification use Windows PowerShell 5.1 (`powershell.exe`). PowerShell 7 is needed only for external/custom automation that explicitly invokes `pwsh` or uses PowerShell 7-only syntax.

```powershell
powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion"
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
```

The first command checks Windows PowerShell 5.1. The second checks optional PowerShell 7; if `pwsh` is not found, normal project operation is unaffected.

## Environment

- `MAX_ULTRA_MCP_HOST` — listener host; defaults to `127.0.0.1`.
- `MAX_ULTRA_MCP_PORT` — listener port; defaults to `47635`.
- `MAX_ULTRA_MCP_TIMEOUT_MS` — request timeout; defaults to `5000`.
- `MAX_ULTRA_MCP_ROOT` — optional project root when the first-start MaxScript is copied elsewhere.

Automatic launch/recovery is loopback-only.
## Repository layout

```text
01_START_MAX_ULTRA_MCP_FIRST.ms   one user-facing MaxScript entry point
README.md                         concise start page and documentation links
core/                             server, protocol client, mock, smoke, package metadata
scripts/                          launchers, shared Node.js runner, and detached owned-server shutdown helper
examples/                         runnable Box action and reusable action helper
docs/README.md                    detailed documentation
.agents/                          adapted project coding instructions
```

## Verification

From the project root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-smoke.ps1
```

Or with Node 18+:

```powershell
node .\core\smoke-test.js
```

The suite uses mock Max 2022 and 2027 clients only. It verifies all 13 tools, routing/cancellation, Box safety, panel/UI/screenshot protocol, RichTextBox bounds/autoscroll, normal-state position/size persistence, draggable restore-mini-panel position persistence, screen-clamping invariants, FormClosing persistence order, Hide/restore-mini-panel isolation, theme/status invariants, legacy/fallback recovery, minimized launch, external ownership records, two-plus-Max refusal, and detached exactly-one-Max shutdown without a live bridge connection. It does not open 3ds Max, manipulate a real scene, or save a scene.
