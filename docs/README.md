# 3DGROUND - Max Ultra MCP

Max Ultra MCP is a standalone local MCP bridge for controlling already-open Autodesk 3ds Max 2022 and 2027 processes with concise semantic tools. Networking remains off the Max UI thread; scene, viewport, UIAccessor, and WinForms work is marshalled through a bounded main-thread queue.

## One-file first start

The only file a 3ds Max user runs manually is the root file:

```text
01_START_MAX_ULTRA_MCP_FIRST.ms
```

Run it once in every Max process that should connect. It locates `scripts\start-server.bat` relative to the project root, probes the configured loopback endpoint, launches the server with no console window by default, and connects the current Max. Running the file again disposes the previous in-Max client. If no other Max shares the verified daemon, the replacement bootstrap sends authenticated `shutdown_owned`, waits for the endpoint to close, launches a fresh daemon, and reconnects. If another Max shares it, the daemon is reused without interruption. An unexpected disconnect or stopped server is terminal for that session: the bootstrap reports the failure and does not relaunch until the first-step file is explicitly run again. Panel **Reconnect** and **Connect only** actions attach only to an already-running server.

After bridge startup, the same file starts a hidden, non-blocking client-status check. If neither the shared ChatGPT Desktop/Codex registration nor Claude Code is configured and onboarding was not dismissed earlier, **AI Client Setup** opens automatically. A borderless rollout header uses a WinForms `TabControl`; selecting **Setup** or **Test prompt** removes the previous content rollout and loads the selected rollout into the same `RolloutFloater`. The Setup page installs selected registrations through official CLIs and displays manual STDIO values for other clients. Status label backgrounds use the current `ColorMan #rollupTitleFace` color so they match the native rollout surface. Copy buttons briefly display **Copied** after a successful clipboard write. The Test prompt page copies a non-mutating prompt that checks instance discovery, health, scene summary, and viewport image return. The window can be closed without stopping the bridge.

A manual diagnostic launch remains visible:

```bat
scripts\start-server.bat
```

Automatic launch uses `--no-pause --port <PORT>`. Its default `ProcessStartInfo` path uses `UseShellExecute=false`, `CreateNoWindow=true`, and the hidden window style, so neither the BAT console nor a taskbar button appears. Enable **Show server console when starting** in Settings to use a normal visible diagnostic console on the next automatic server launch. The setting does not restart an already-running server. Automatic launch also passes a unique launch token, the Max PID, and a port-scoped ownership-file path. The Node process writes the record only after listening, including its own PID/start time and the exact BAT launcher PID/start time. Manual BAT launches omit this metadata and remain outside automatic shutdown.

## Safe endpoint recovery

The default endpoint is `127.0.0.1:47635`.

- A healthy current Max Ultra MCP server is reused on first start.
- A compatible legacy bridge that lacks `probe` is recognized through its live `CONTROL list` inventory. First start may attach to it.
- Re-running against a legacy bridge, or encountering a truly unknown occupant, never kills a process. The bootstrap scans only the next 10 loopback ports, selects a free fallback, starts Max Ultra MCP there, and reports `MAX_ULTRA_MCP_PORT=<PORT>` in the panel.
- On a first-step re-run, MaxScript uses the package-local control token and the exact current probe identity to request `shutdown_owned` only when no other Max shares the daemon. It waits boundedly for the loopback endpoint to close before launching the replacement. On Window X, **Stop / Exit**, or `#preSystemShutdown`, it instead launches `scripts\stop-owned-server.bat` detached and cancels its transport worker; that path never relaunches a server.
- The helper counts live `3dsmax.exe` processes without using the bridge connection. It proceeds only when the count is exactly one and, in normal operation, that PID is the Max process that dispatched it. Zero or two-plus processes leave the server running.
- Before termination, the helper requires a Max-created ownership record for the selected port (or the same launch token during a fallback-port startup race). It verifies project root, server script, ownership token, Node PID/name/start time/command line, and BAT PID/name/start time/command line. It force-stops only those exact verified PIDs. Missing, stale, manual, mismatched, or inaccessible metadata fails closed.
- General protocol clients retain `shutdown`, `shutdown_owned`, and idle-shutdown controls. The root MaxScript uses only identity-bound `shutdown_owned` for a replacement start; it never sends unrestricted shutdown to an unknown endpoint.

## Panel behavior

The compact panel shows two status/context rows above a tall log.

- Running/connected is green; connecting/restarting/retrying is amber; errors are red; stopped/unknown is neutral. Status text is bold and always names the state, so color is not the only cue.
- Panel and log colors derive from 3ds Max `ColorMan` background/text colors, with safe fallbacks. The log uses a lighter theme surface, a one-pixel flat black boundary, and blue/cyan informational text. Success, warning, error, and debug colors remain distinct.
- The RichTextBox is read-only, wrapped, capped at 30 entries, and auto-scrolls to the latest entry.
- **AI setup** is always available beside **Hide panel**. It opens the same onboarding window used on first start. **Settings** also contains **Open AI client setup...**, so a dismissed onboarding window is always recoverable.
- The settings window also contains the auto-saving **Autostart with 3ds Max** checkbox. Changing it immediately writes `[settings] autostart` in `MaxUltraMCP\panel-ui.ini` and creates or removes `3DGROUND-Max-Ultra-MCP-Autostart.ms` under `#userStartupScripts` for the current Max version. The generated startup script stores the absolute path to `01_START_MAX_ULTRA_MCP_FIRST.ms`, launches it through `fileIn` when present, and otherwise disables the INI setting and schedules its own deletion for `#postSystemStartup`, after the startup-script file is no longer open.
- **Show server console when starting** is disabled by default and is saved as `[settings] showServerConsole`. Enabling it affects only a future automatic launch and is intended for diagnosing startup failures. Directly running `scripts\start-server.bat` remains the always-visible manual diagnostic path.
- Final normal window `x`/`y` plus user-resized `width`/`height` and the explicit `hidden` state are saved before cleanup in the per-user scripts `MaxUltraMCP\panel-ui.ini` file. Existing position-only files remain compatible and default to expanded. On launch, corrupt or missing values fall back safely; size is constrained to the panel's 540×420 layout minimum and the selected monitor's current working area, and position is clamped so the full panel remains visible. If monitor topology or DPI scaling changed, the nearest current screen is used; an unusable position centers the validated size on the primary screen.
- **Hide panel** saves `[panel] hidden=true`, saves the current normal geometry, and hides only the main panel. The server and Max client remain connected. A compact borderless mini-panel with a one-pixel black outer outline appears at its last saved position (lower-left of the 3ds Max screen on first use), with one **Expand MCP Server** action and no minimize, maximize, or close controls. Its button color continues to follow live connection state—green when connected, amber while starting/reconnecting, and red on errors. Drag the mini-panel by its **Max Ultra MCP** label; its clamped on-screen position is saved in the same per-user INI file. The next script start goes directly to this mini-panel while the saved state is hidden. Expanding writes `hidden=false`, revalidates and restores/focuses the main panel at its previous size and position, then removes the mini-panel. Failed Hide/Expand transitions roll the INI value back to the actually available UI. Minimized or maximized state is never persisted: normal-state move/resize tracking updates the INI geometry, with WinForms restore bounds used only as a fallback. Repeated hide requests reuse the same mini-panel instead of creating duplicates, and a failed expansion leaves it available to retry.
- Window X and **Stop / Exit** first stop and unsubscribe the Max-side timer, start the detached exactly-one-Max helper, and cancel transport. If two or more Max processes are live, the helper leaves the server available to them. If exactly one is live, it terminates only the ownership-verified Max-launched server/BAT chain. A pre-existing/manual server is disconnected but left running. The `#preSystemShutdown` callback applies the same idempotent cleanup during Max exit. Re-run cleanup disposes the prior timer, worker/form handlers, and restore mini-panel without invoking the detached helper; the new background worker then performs the authenticated replacement flow.
- Shutdown is deliberately fail-closed: if helper startup is delayed until the closing Max has fully exited, it sees zero Max processes and leaves the server running; likewise, unreadable process metadata or a missing/corrupt ownership file leaves it running. Run the root script and use **Stop / Exit** again after resolving the metadata issue rather than terminating arbitrary processes.

## Concise MCP tools

The mandatory production workflow backlog and acceptance contracts are defined in [USE_CASES.md](USE_CASES.md).
The table below documents the original direct-control surface retained for examples and regression compatibility. Agent-facing v1 profiles expose 60–74 tools; see [V1.md](V1.md).


| Tool | Purpose |
| --- | --- |
| `max_list_instances` | Compact live Max inventory |
| `max_select_instance` | Choose the default instance |
| `max_scene_summary` | Concise scene/object/selection state |
| `max_create_box` | Create a standard Box without MaxScript boilerplate |
| `max_viewport_screenshot` | Maximize and capture the selected viewport |
| `max_ui_list` | Discover bounded Max-owned UI controls |
| `max_ui_invoke` | Guarded invoke with stale-handle checks |
| `max_health` | Transport/main-thread health |
| `max_get_info` | Detailed Max, scene, object, polygon/vertex, selection, material, layer, animation, and render information |
| `max_panel` | Show, hide, minimize, or restore the panel |
| `max_logs` | Read bounded panel activity |
| `max_smoke` | Non-destructive protocol smoke request |
| `max_execute` | Advanced MaxScript escape hatch |

When exactly one Max is connected, short calls route automatically. With several instances, the server returns the live inventory and requires `instance_id` or an explicit `max_select_instance` call.

## Runnable examples

The root of `examples\` contains only BAT launchers. Every launcher has a same-named subfolder containing its JavaScript implementation:

| Launcher | Action |
| --- | --- |
| `example-list-instances.bat` | List all connected 3ds Max instances |
| `example-health-check.bat` | Check the selected or only Max instance |
| `example-scene-summary.bat` | Read a detailed scene summary |
| `example-get-max-info.bat` | Read detailed 3ds Max and scene information |
| `example-viewport-screenshot.bat` | Maximize the active viewport, save a PNG, and open it |
| `example-press-render-button.bat` | Start the current production render through the MaxScript equivalent of F9 |
| `example-create-test-box.bat` | Create one named Box at the origin |
| `example-create-spline-text.bat` | Create, extrude, select, and frame the 3DGROUND - Max Ultra MCP spline text |

For example, `examples\example-create-test-box.bat` launches `examples\example-create-test-box\example-create-test-box.js`. Each JavaScript file imports `core\bridge-control-client.js` directly. There is no `_shared` action layer or example-specific routing framework.

Each BAT passes its implementation directly to `scripts\run-node-script.ps1`. The shared runner prefers the packaged portable runtime and accepts Node.js 22+ as a development fallback; it owns script validation, safe argument forwarding, execution errors, and the child exit code.

Read-only examples can list all instances. Examples that target a scene use the server's normal routing: exactly one connected Max routes automatically, while several instances require a prior explicit `max_select_instance` call. Creation examples check their object names first, never overwrite existing objects, and never save the scene. The MCP title example creates an aligned classic Text shape named `MaxUltraMCP_Title`, adds an Extrude modifier, selects it, and runs Zoom Extents in the active viewport.

The shared screenshot handler runs `max tool maximize` before every capture and compares the active viewport pixel area before and after the toggle; if it was already maximized, the handler toggles it back to the larger state. It leaves the active viewport maximized. The example overwrites `%TEMP%\3DGROUND-Max-Ultra-MCP-Examples\viewport-current.png` and opens that file with the default Windows image viewer. Because every run uses the same filename, captures do not accumulate on disk. The Render example executes `max quick render`, the MaxScript command equivalent to the main-toolbar Render action/F9, so it does not depend on toolbar visibility, HWND discovery, localization, or screen coordinates. It uses the current production renderer and render settings; its BAT asks for confirmation before starting.

## Agent configuration

The normal packaged-release flow starts inside 3ds Max:

```text
01_START_MAX_ULTRA_MCP_FIRST.ms
```

The onboarding status/install work runs in a hidden Windows PowerShell 5.1 child process. The Max UI timer only polls process completion, so CLI discovery and registration do not block the 3ds Max main thread. It resolves known per-user Codex and Claude Code CLI locations in addition to `PATH`, which handles a 3ds Max process started before an agent was installed or updated. `scripts\agent-integration.ps1` writes a short per-run INI result below the existing per-user `MaxUltraMCP` state directory. It contains status labels and local runtime paths, never raw CLI output, environment dumps, access tokens, or client configuration contents.
If a configured STDIO host started before the installed MCP runtime was updated, onboarding reports **Restart required** in amber. Restart or reconnect the AI client once. A STDIO host with a live daemon connection now exits when that verified daemon is replaced; a host that has not connected yet remains owned by its AI-client session. Control clients reload the package token file before subsequent requests, so later token-file rotation does not require another code change. One `core/server.js --stdio` process per active AI-client session is expected. `node_repl.exe` belongs to the AI client and is never terminated by Max Ultra MCP.

The MaxPkg release contains the general skill at `skills\max-ultra-mcp\SKILL.md`, the camera-composition skill at `skills\max-ultra-camera-composition\SKILL.md`, the character/object-modeling skill at `skills\max-ultra-character-object-modeling\SKILL.md`, the renderer-settings skill at `skills\max-ultra-renderer-settings\SKILL.md`, the generic spline-modeling skill at `skills\max-ultra-spline-modeling\SKILL.md`, and the architectural plan skill at `skills\max-ultra-floor-plan\SKILL.md`. MCP registration does not silently copy skill files into an AI client profile. Clients that support skills can load or install any folder separately; clients without skill support continue to use the complete MCP schemas and initialization instructions.

Supported automatic targets:

- **ChatGPT Desktop / Codex** through `codex mcp add`. These OpenAI clients share the same local Codex MCP configuration.
- **Claude Code** through `claude mcp add ... --scope user`.
- Other STDIO-capable agents through the copyable manual command, arguments, and environment values.

For a development checkout, the equivalent OpenAI registration is:

```powershell
codex mcp add max-ultra-mcp --env MAX_ULTRA_MCP_TOOL_PROFILE=archviz -- node "<PROJECT_ROOT>\core\server.js" --stdio
```

The equivalent Claude Code registration is:

```powershell
claude mcp add max-ultra-mcp --scope user --env MAX_ULTRA_MCP_TOOL_PROFILE=archviz -- node "<PROJECT_ROOT>\core\server.js" --stdio
```

See [V1.md](V1.md) for the portable-runtime TOML configuration and client lifecycle details.


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
- `MAX_ULTRA_MCP_TOKEN_FILE` — optional absolute control-token file override; the default is `runtime\state\control-token` below the executing package root.

Automatic launch/recovery is loopback-only.
## Repository layout

```text
01_START_MAX_ULTRA_MCP_FIRST.ms   one user-facing MaxScript entry point
README.md                         concise start page and documentation links
core/                             production server, protocol, tools, and package metadata
tests/                            automated suites, test helpers, and real-Max fixtures
skills/                           optional agent skills and focused references
scripts/                          launchers, shared Node.js runner, and detached owned-server shutdown helper
examples/                         BAT-only launcher root plus same-named implementation folders
docs/README.md                    detailed documentation
.agents/                          adapted project coding instructions
maxpkg-files.txt                  reviewed production allowlist for MaxPkg
```

## Verification

From the project root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-smoke.ps1
```

Or with Node 22+:

```powershell
node .\tests\smoke-test.js
```

The three suites use mock Max 2022 and 2027 clients only. The regression suite verifies the original 13 tools and lifecycle behavior; the v1 suite verifies 60-74 profile tools, envelopes, revisions, floor plans, renderer introspection, images, and render jobs; the CLI suite launches real daemon/STDIO child processes and verifies authenticated JSON-only MCP transport. They do not open 3ds Max, manipulate a real scene, or save a scene.
