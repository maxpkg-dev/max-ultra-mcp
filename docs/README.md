# 3DGROUND - Max Ultra MCP

Max Ultra MCP is a standalone local MCP bridge for controlling already-open Autodesk 3ds Max 2022 and 2027 processes with concise semantic tools. Networking remains off the Max UI thread; scene, viewport, UIAccessor, and WinForms work is marshalled through a bounded main-thread queue.

## One-file first start

The only file a 3ds Max user runs manually is the root file:

```text
01_START_MAX_ULTRA_MCP_FIRST.ms
```

Run it once in every Max process that should connect. It locates `scripts\start-server.bat` relative to the project root, probes the configured loopback endpoint, launches the server with no console window by default, and connects the current Max. Running the file again disposes the previous in-Max client. If no other Max shares the verified daemon, the replacement bootstrap sends authenticated `shutdown_owned`, waits for the endpoint to close, launches a fresh daemon, and reconnects. If another Max shares it, the daemon is reused without interruption. An unexpected disconnect remains terminal for the Max-side transport until the first-step file is explicitly run again, but it no longer terminates an AI client's STDIO host. Panel **Reconnect** attaches only to an already-running server; the redundant **Connect only** action is no longer shown.

Two seconds after startup, the same file starts one hidden, non-blocking AI registration-readiness check. It checks the shared ChatGPT Desktop/Codex registration and Claude Code once, with a 30-second timeout and no periodic recheck. The main panel shows the aggregate result; this describes whether MCP registration is ready, not whether an AI chat is currently connected. The refresh icon starts an immediate manual check, and clicking the status opens **AI Client Setup**. Dismissing onboarding suppresses only its automatic opening when no supported registration exists; it never suppresses the delayed readiness check or manual refresh.

The onboarding window retains its borderless rollout header and WinForms `TabControl`. Selecting **Setup** or **Test prompt** removes the previous content rollout and loads the selected rollout into the same `RolloutFloater`. The Setup page installs selected registrations through official CLIs and displays manual STDIO values for other clients. Its per-client details use the explicit readiness states **MCP ready**, **Setup required**, **Restart required**, **Client not found**, **Runtime missing**, **Setup failed**, **Check failed**, **Waiting…**, and **Checking…**. The main strip condenses them into one aggregate status button so an unused optional client is not shown as a separate failure. Muted ColorMan-derived colors reinforce each state without replacing its text. Copy buttons briefly display **Copied** after a successful clipboard write. The Test prompt page copies a non-mutating prompt that checks instance discovery, health, scene summary, and viewport image return. The window can be closed without stopping the bridge.

A manual diagnostic launch remains visible:

```bat
scripts\start-server.bat
```

Automatic launch uses `--no-pause --port <PORT>`. Its default `ProcessStartInfo` path uses `UseShellExecute=false`, `CreateNoWindow=true`, and the hidden window style, so neither the BAT console nor a taskbar button appears. Cold portable-runtime startup receives a bounded health window of roughly 25 seconds. If the BAT launcher exits earlier, the panel reports its exit code immediately. Enable **Show server console when starting** in Settings to use a normal visible diagnostic console on the next automatic server launch, or run `scripts\start-server.bat` directly to see the launcher error. The setting does not restart an already-running server. Automatic launch also passes a unique launch token, the Max PID, and a port-scoped ownership-file path. The Node process writes the record only after listening, including its own PID/start time and the exact BAT launcher PID/start time. Manual BAT launches omit this metadata and remain outside automatic shutdown.

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

The main window is one rollout floater with compact `FixedToolWindow` chrome and mouse resizing disabled. It has no window icon, Minimize, or Maximize buttons, leaving only the close action, while programmatic `max_panel minimize/restore` remains supported. The content is split into four permanently expanded, borderless zones:

1. A 44 px AI status strip shows one fixed-width aggregate registration-readiness button, the manual refresh icon, and **Hide panel**.
2. A 36 px server context strip shows one explicit connection indicator and a concise state line.
3. A fixed 484 px **Activity** zone contains the 720 px-wide log, with **Reconnect**, **Stop / Exit**, and **Settings** directly below it.
4. A 44 px support footer contains one rotating linked promotion and the visually distinct **Donate** action.

- WinForms controls use one ColorMan-aware visual system with flat borders, consistent spacing and font metrics, and derived hover, pressed, disabled, success, warning, and error colors.
- The AI strip shows registration readiness rather than live chat connectivity. If either client is ready, one fixed-width green button names the ready client or clients and suppresses the optional unconfigured client's warning from the main panel. If neither is ready, the same button displays **Click to set up AI agent**; detailed individual states remain in Setup and its tooltip. Its automatic check starts once, two seconds after bootstrap, and has a 30-second timeout. It does not poll periodically; the refresh icon runs an immediate on-demand check. Setup opens automatically only after conclusive results show no configured client; **Check failed** remains visible for manual retry without opening setup.
- A healthy Max-to-daemon connection uses a muted green indicator and shows `Server 127.0.0.1:<PORT> | PID <PID> | Scene <FILENAME> | Objects <COUNT> | Selection <COUNT>`. Only the scene filename is shown. Starting and reconnecting states use muted amber; stopped and failed states use muted red, with the actionable problem replacing the server endpoint. Text accompanies every color state.
- Panel and log colors derive from 3ds Max `ColorMan` background/text colors, with safe fallbacks. The borderless RichTextBox is read-only, wrapped, capped at 30 entries, and preserves its colored success, warning, error, system, debug, and informational messages plus its existing scroll behavior. Native RichEdit margins provide six pixels of internal space on both horizontal sides. Consecutive entries remain compact without permanent empty display lines, and automatic scrolling does not move the read-only caret.
- Clicking the aggregate AI status opens the same onboarding window used on first start. **Settings** also contains **Open AI client setup...**, so a dismissed onboarding window is always recoverable.
- **Reconnect** is the only manual attach retry and never launches a stopped daemon. **Connect only** has been removed. Rerun `01_START_MAX_ULTRA_MCP_FIRST.ms` when the local server must be started again.
- The draggable restore mini-panel starts fully inside the selected monitor. Its lower Y clamp keeps only a 24 px title strip above the Windows taskbar, allowing the panel to be parked low while preserving a reachable drag handle.
- The support footer uses a borderless, single-line RichTextBox whose rollout-matched background is resolved through the same ColorMan-aware parent validation as Server labels. Its complete underlined message is clickable and rotates to a different random maxpkg.dev, 3dground.net, Max Ultra MCP catalog, or donation promotion every 30 seconds. The dedicated **Donate** action keeps its warm accent and icon. Donate, Refresh, Hide panel, Reconnect, Stop / Exit, and Settings load packaged, ready-to-use white PNG renditions of their Lucide icons directly through WinForms. The icons are not rebuilt or recolored at runtime, and no SVG renderer is required. Hide panel uses the same 120 px width as Settings, and Reconnect uses the distinct `plug-zap` icon instead of duplicating Refresh. Settings About presents the product, version, author, **3dground.net**, and **maxpkg.dev** in one centered column using native MAXScript labels and hyperlinks, followed by the themed Donate action.
- Two unfilled spaces separate each timestamp from its badge. The badge includes one filled space before `[` and after `]`; status names are padded to seven characters and rendered in a dedicated monospaced font, giving all colored badges the same pixel width. An unfilled ` > ` separator and additional spacing align the following messages; these presentation characters never enter MCP activity responses. The badge background uses the category color and its text uses a darker, more saturated shade of the same hue; light themes receive a lighter badge surface for contrast. The timestamp and message retain the category foreground color without a fill. Newline separators keep the normal log background.
- After the first successful bridge connection, the Activity log shows its first highlighted support reminder at the absolute one-minute deadline. The second appears ten minutes after the first, and the third 60 minutes after the second, for a maximum of three per active bridge session. A delayed UI tick emits at most one due reminder, and Hide/Expand or Reconnect does not reset the schedule. The exact local-only message is: `Max Ultra MCP is maintained independently in personal time. Without community support, continued development may not be sustainable. If it helps your work, please use Donate to support it.` Its underlined `Donate` word opens the secure donation checkout only after explicit activation.
- The settings window also contains the auto-saving **Autostart with 3ds Max** checkbox. Changing it immediately writes `[settings] autostart` in `MaxUltraMCP\panel-ui.ini` and creates or removes `3DGROUND-Max-Ultra-MCP-Autostart.ms` under `#userStartupScripts` for the current Max version. The generated startup script stores the absolute path to `01_START_MAX_ULTRA_MCP_FIRST.ms`, launches it through `fileIn` when present, and otherwise disables the INI setting and schedules its own deletion for `#postSystemStartup`, after the startup-script file is no longer open.
- **Check and install updates automatically** is enabled by default. A hidden detached helper uses Windows `curl.exe` to check only the latest stable official GitHub Release, verifies the exact MZP identity and SHA-256, and stores it below the per-user `MaxUltraMCP\updates` state folder. **Check now** runs the same operation on demand. The verified package is installed through MaxPkg and the bootstrap restarts automatically; network work and downloads never run on the 3ds Max UI thread.
- **Show server console when starting** is disabled by default and is saved as `[settings] showServerConsole`. Enabling it affects only a future automatic launch and is intended for diagnosing startup failures. Directly running `scripts\start-server.bat` remains the always-visible manual diagnostic path.
- Final normal window `x`/`y` and the explicit `hidden` state are saved before cleanup in the per-user scripts `MaxUltraMCP\panel-ui.ini` file. Legacy `width`/`height` keys are ignored and are no longer read or written. Every rollout and control uses fixed declared coordinates and dimensions; there are no runtime client-area measurements or resize callbacks. Existing position-only files remain compatible and default to expanded. Position is clamped so the whole fixed 720×640 panel remains visible whenever the work area can contain it; if monitor topology or DPI scaling changed, the nearest current screen is used and an unusable position is centered on the primary screen.
- **Hide panel** saves `[panel] hidden=true` and the current normal position, then sets the rollout floater to invisible without destroying it or stopping the server, Max client, timers, or support-reminder schedule. A compact borderless mini-panel with a one-pixel theme-derived muted outline appears at its last saved position (lower-left of the 3ds Max screen on first use), with one **Expand MCP Server** action and no minimize, maximize, or close controls. The title and action use a bold system font. The action uses the live green, amber, or red connection color as its background with theme text on top for contrast. Drag the mini-panel by its **Max Ultra MCP** label; its clamped on-screen position is saved in the same per-user INI file. **Expand MCP Server** first reuses and focuses the existing hidden floater; it recreates the floater at the saved, clamped position only if that UI instance is no longer valid. It then writes `hidden=false` and removes the mini-panel. The next script start still goes directly to the mini-panel while the saved state is hidden. Failed Hide/Expand transitions roll the INI value back to the actually available UI. Minimized or maximized state is never persisted. Repeated hide requests reuse the same mini-panel, and a failed expansion leaves it available to retry.
- Window X and **Stop / Exit** first stop and unsubscribe the Max-side timer, start the detached exactly-one-Max helper, and cancel transport. If two or more Max processes are live, the helper leaves the server available to them. If exactly one is live, it terminates only the ownership-verified Max-launched server/BAT chain. A pre-existing/manual server is disconnected but left running. The `#preSystemShutdown` callback applies the same idempotent cleanup during Max exit. Re-run cleanup disposes the prior timer, worker/form handlers, and restore mini-panel without invoking the detached helper; the new background worker then performs the authenticated replacement flow.
- Shutdown is deliberately fail-closed: if helper startup is delayed until the closing Max has fully exited, it sees zero Max processes and leaves the server running; likewise, unreadable process metadata or a missing/corrupt ownership file leaves it running. Run the root script and use **Stop / Exit** again after resolving the metadata issue rather than terminating arbitrary processes.

## Concise MCP tools

The mandatory production workflow backlog and acceptance contracts are defined in [USE_CASES.md](USE_CASES.md).
The table below documents the original direct-control surface retained for examples and regression compatibility. Agent-facing v1 profiles expose 61–75 tools; see [V1.md](V1.md).


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
| `max_ui_capture_window` | Capture an exact Max-owned top-level or child HWND without top-level rediscovery |
| `max_ui_diagnostics` | Return bounded UI Automation/native WinForms trees and compact WebBrowser layout evidence |
| `max_get_info` | Detailed Max, scene, object, polygon/vertex, selection, material, layer, animation, and render information |
| `max_panel` | Show, hide, minimize, or restore the panel |
| `max_logs` | Read bounded panel activity |
| `max_smoke` | Non-destructive protocol smoke request |
| `max_execute` | Advanced MaxScript escape hatch |

Natural requests such as “make this in 3ds Max”, “build this in my 3D program”, or “change this in my 3D editor” are Max Ultra MCP requests. The agent first lists instances and explicitly selects the only or uniquely identified match. With zero connections or several ambiguous instances it asks exactly one short question and does not operate on an uncertain window.

For Max-owned UI, inspect first, capture the returned HWND directly, and add `max_ui_diagnostics` only when UI Automation/native WinForms or embedded WebBrowser layout evidence is needed. After any action, re-inspect, re-capture, or query Max state to verify the result.

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
If a configured STDIO host started before the installed MCP runtime was updated, onboarding reports **Restart required** in amber. Restart or reconnect the AI client once to load new STDIO code and tool schemas. Ordinary daemon replacement no longer exits an already-running STDIO host: the next tool call performs one shared verified reconnect attempt for up to ten seconds on the same configured loopback endpoint. MCP `ping` and `tools/list` remain available while the daemon is down. An interrupted request is returned once as `BRIDGE_DOWN` and is never replayed automatically; inspect fresh state before retrying a possible mutation. Daemon-owned selection and jobs do not survive replacement. Control clients reload the package token file before protected requests, so token-file rotation remains compatible. A changed fallback port still requires updating or reconnecting the AI client. One `core/server.js --stdio` process per active AI-client session is expected. `node_repl.exe` belongs to the AI client and is never terminated by Max Ultra MCP.

The MaxPkg release contains the general skill at `skills\max-ultra-mcp\SKILL.md`, the camera-composition skill at `skills\max-ultra-camera-composition\SKILL.md`, the character/object-modeling skill at `skills\max-ultra-character-object-modeling\SKILL.md`, the renderer-settings skill at `skills\max-ultra-renderer-settings\SKILL.md`, the generic spline-modeling skill at `skills\max-ultra-spline-modeling\SKILL.md`, the architectural plan skill at `skills\max-ultra-floor-plan\SKILL.md`, and the MaxPkg adaptation skill at `skills\max-ultra-maxpkg-packaging\SKILL.md`. MCP registration does not silently copy skill files into an AI client profile. Clients that support skills can load or install any folder separately; clients without skill support continue to use the complete MCP schemas and initialization instructions.

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

### Developer and agent diagnostics

From a source checkout, run:

```powershell
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" --help
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" status
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" setup --profile archviz
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" skills
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" skills --check
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" health
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" capabilities
```

The launcher resolves the repository root from its `diagnostics` directory, starts `core\cli.js` with package-local Node.js when available, and otherwise uses development Node.js. It forwards only the CLI command and options. It does not start a daemon or STDIO host, change the selected Max scene, inspect or capture the viewport, or install an MCP registration.

`status` checks Codex and Claude Code registrations without writing either configuration. `setup` prints their official installation and verification commands without executing them. `skills` scans every package-local `SKILL.md` instead of using a hard-coded list, so the general, floor-plan, camera, character/object, renderer, spline, MaxScript/viewport/render references, and MaxPkg workflows remain discoverable as the catalog evolves. `skills --check` compares referenced tool names with the selected Max capabilities; the CLI does not interpret or run the skill workflow.

The diagnostics batch file is developer-only and must remain outside `maxpkg-files.txt`. The normal release flow continues to begin with `01_START_MAX_ULTRA_MCP_FIRST.ms`.


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
- `MAX_ULTRA_MCP_TOKEN_FILE` — optional absolute control-token file override; the default is the stable per-user `%LOCALAPPDATA%\3DGROUND\MaxUltraMCP\runtime\state\control-token`.

Automatic launch/recovery is loopback-only.
## Repository layout

```text
01_START_MAX_ULTRA_MCP_FIRST.ms   one user-facing MaxScript entry point
README.md                         concise start page and documentation links
core/                             production server, protocol, tools, and package metadata
diagnostics/                      source-only developer and agent launchers; excluded from MaxPkg
tests/                            automated suites, test helpers, and real-Max fixtures
skills/                           optional agent skills and focused references
scripts/                          launchers, shared Node.js runner, and detached owned-server shutdown helper
examples/                         BAT-only launcher root plus same-named implementation folders
docs/README.md                    detailed documentation
.agents/ and .claude/             canonical project policy plus thin Codex/Claude skill adapters
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

The JavaScript suites use mock Max 2022 and 2027 clients only. The regression suite verifies the original 13 tools, lifecycle behavior, UI-helper source guards, and agent-adapter packaging; the v1 suite verifies 61–75 profile tools, envelopes, revisions, floor plans, renderer introspection, images, and render jobs; the CLI suite launches real daemon/STDIO child processes and verifies authenticated JSON-only MCP transport. A separate PowerShell helper fixture creates a disposable owned WinForms window and verifies direct HWND capture, bounded native diagnostics, evidence fields, and cleanup. None of these checks opens 3ds Max or modifies a real scene. Child/MAXScriptDialog and plugin/WebBrowser evidence still require the real-Max fixture.
