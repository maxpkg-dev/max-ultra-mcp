# 3DGROUND - Max Ultra MCP

Max Ultra MCP connects ChatGPT, Codex, and other MCP clients to Autodesk 3ds Max. It exposes semantic tools for scene operations, viewport inspection, rendering, MaxScript, process-scoped UI automation, and architectural workflows while keeping all 3ds Max API work on the Max main thread.

## Project status

The v1 architecture and mock-tested MCP surface are implemented. The current automated suite covers the 3ds Max 2022 and 2027 protocol endpoints, multi-instance routing, authenticated STDIO transport, structured responses, viewport images, render jobs, UI boundaries, and floor-plan generation. Real 3ds Max and renderer-version acceptance testing remains required before a production release.

The first production-foundations increment adds session-owned common jobs and read-only material diagnostics. The remaining workflow backlog includes asset relinking and collection, Corona/V-Ray configuration, camera composition, render masks, batch FBX/GLB export, performance analysis, proxy conversion, and AI-assisted material editing. See [Required Production Use Cases](docs/USE_CASES.md).

### Recent changes in 1.2.1

- Updated release tooling to the official MaxPkg Packager 1.2.0 revision and exact SHA-256.
- Added official `MaxPkgPackerApi` automation guidance for validation, configuration, and MZP builds through MCP.
- Expanded bounded MaxScript results to 500,000 characters with explicit truncation metadata so complete MaxPkg state responses remain valid JSON.
- Fixed quoted update-helper paths that end in a backslash and improved startup failure diagnostics.
- Matched update and onboarding status backgrounds to the active ColorMan rollout background.
## What users can do

- Start the bridge and configure ChatGPT Desktop, Codex, Claude Code, or another STDIO client from one MaxScript entry point.
- Connect one or more already-open 3ds Max instances to one local bridge.
- Let each connected MCP client select its own Max instance.
- Inspect and modify scenes through structured MCP tools.
- Validate and create custom Editable Poly topology from object-local vertices and zero-based polygon faces.
- Maximize the active viewport, temporarily clean and improve its display, capture it, restore the user's display settings, and return the screenshot directly to the model.
- Start, monitor, cancel, and retrieve renders.
- Monitor, wait for, cancel, and retrieve any session-owned long operation through the common job API.
- Find geometry with missing, invalid, unsupported, incomplete Multi/Sub, or missing-bitmap material assignments without changing selection.
- Run MaxScript text, files, macros, and Action Table commands.
- Inspect, diagnose, and capture top-level or child UI only inside the selected `3dsmax.exe` process.
- Validate and build a dimensioned house plan interpreted from an attached image.
- Use unrestricted `max_execute` when a semantic tool does not exist yet.

## Automatic updates

The Settings window enables automatic update checks by default. Version metadata and release assets are downloaded with Windows `curl.exe` from a hidden detached helper process, so network waits never block the 3ds Max UI thread. Only a stable official GitHub Release whose MZP filename, package GUID, asset URLs, and SHA-256 all match is accepted. The verified MZP is installed through MaxPkg, the active bridge is disposed, and `01_START_MAX_ULTRA_MCP_FIRST.ms` restarts automatically from the updated package. Failed checks or installation attempts keep the previous installation recoverable. Disable automatic checks or use **Check now** in Settings at any time.

## Installation for release users

MaxPkg release packages bundle a portable Node.js runtime. Users do not install Node.js, change `PATH`, require administrator rights, or download dependencies at runtime.

1. Install the Max Ultra MCP `.mzp` through MaxPkg.
2. Run this single file once in every 3ds Max process that should connect:

   ```maxscript
   01_START_MAX_ULTRA_MCP_FIRST.ms
   ```

3. Two seconds after startup, the first-start script checks AI registration readiness once. When both client results are conclusive and no supported AI client is configured, it opens **AI Client Setup** automatically unless that automatic opening was dismissed; a failed check stays visible as **Check failed** without opening setup. On **1. Setup**, select **ChatGPT Desktop / Codex** and/or **Claude Code**, then choose **Install selected**. After reconnecting the client, use **2. Test prompt** to copy a safe, read-only connection test.
4. Restart or reconnect each newly configured AI client.
5. For natural-language routing in ChatGPT Desktop and Codex, install the packaged plugin once from the installation root:

   ```powershell
   codex plugin marketplace add "<INSTALL_ROOT>"
   codex plugin add max-ultra-mcp@3dground-max-ultra-mcp
   ```

   Start a new task after installation. Requests in any language such as "create a teapot in 3ds Max" then activate the Max Ultra MCP workflow automatically.

The onboarding uses official `codex mcp` and `claude mcp` commands when their CLIs are available. ChatGPT Desktop and Codex share the OpenAI MCP configuration. Claude Code registration is user-scoped. If a CLI is unavailable, the same window shows and copies exact STDIO values for manual or other-client setup. It never writes client configuration files directly.

Closing onboarding dismisses only its automatic display without stopping the bridge or disabling readiness checks. The main panel uses one fixed-width aggregate AI button rather than presenting an unconfigured optional client as a separate red requirement. When one or both registrations are ready, the green button names the ready clients; when none is ready, it displays **Click to set up AI agent**. Restart, runtime, setup, and check failures remain explicit aggregate states, while the Setup page retains per-client details. These statuses do not claim that an AI chat is currently connected. The automatic check runs once with a 30-second timeout, while the refresh icon runs it immediately on demand. Open setup again through the aggregate status or **Settings -> Open AI client setup**. The standalone `scripts\install-chatgpt-codex.bat` remains available for headless OpenAI registration, but it is not required for normal first start.

### Main panel

Activity timestamps use a two-space unfilled gap before the colored status badge; the badge's nearest surrounding space remains filled.

Every rollout and control uses fixed declared coordinates and dimensions. The panel performs no resize callbacks, client-area measurement, or saved width/height restoration; only its position and Hide state persist.

The rollout floater uses a fixed 720×640 content size and compact toolbox chrome with no icon, Minimize, or Maximize buttons; only the close action remains visible, and mouse resizing is disabled. Previously saved custom width and height values are ignored, while window position and Hide state remain persistent. Programmatic `max_panel minimize/restore` behavior remains available. Its four borderless zones are a 44 px AI readiness strip, a 36 px server context strip, a flexible Activity log with **Reconnect**, **Stop / Exit**, and **Settings**, and a 44 px support footer with project links and an accented **Donate** action. The layout accounts for native window chrome so the footer remains visible. The log uses six-pixel native RichEdit margins on both horizontal sides, keeps three empty display lines below its latest entry, and inserts new text before them; protocol responses omit this visual padding. Each category badge includes one filled space before `[` and after `]`. Its status name is padded to seven characters and rendered in a dedicated monospaced font, giving every colored badge the same pixel width. An unfilled ` > ` separator and additional spacing keep the following message on a stable vertical line. This alignment is display-only and does not alter MCP activity responses. The badge background uses the category color; its text uses a darker, more saturated shade of the same color, while light themes use a lighter badge surface to retain contrast. The timestamp and message retain the category foreground color without a fill. Line separators and the three trailing display lines retain the normal log background. Server labels and footer links inherit an opaque `Parent.BackColor` only when it is consistent with the active Max theme; unrelated system-white host colors are rejected and the ColorMan rollout color is used instead. Donate, Refresh, Hide panel, Reconnect, Stop / Exit, and Settings load packaged, ready-to-use white PNG renditions of the Lucide `heart`, `refresh-cw`, `panel-top-close`, `plug-zap`, `power`, and `settings` icons directly through WinForms. They are not rebuilt or recolored at runtime, and no SVG renderer is required. Hide panel uses the same 120 px width as Settings. Reconnect uses `plug-zap`, keeping it visually distinct from the AI status refresh action. The server line uses lighter green text when connected, amber while starting or reconnecting, and lighter red text when stopped or failed. The visible failure message stays at **Please restart the script** so the row does not shift; full diagnostics remain in the Activity log, tooltip, and accessibility description. It otherwise shows only endpoint, PID, scene filename, object count, and selection count. **Connect only** has been removed; **Reconnect** remains the manual attach retry for an already-running daemon.

**Hide panel** preserves the window position and makes the floater invisible without destroying it or stopping the bridge. The compact panel renders **Expand MCP Server** in bold high-contrast text over the current green, amber, or red connection color. Its initial position is fully visible, but manual dragging may lower it until only the 24 px title strip remains above the Windows taskbar, keeping a recovery handle available. **Expand MCP Server** reuses the live floater when possible and recreates it at the saved position only when necessary. In the main panel, the endpoint or connection problem beginning with **Server** is also bold while PID and scene context remain regular. After the first successful connection, the Activity log can show at most three highlighted support reminders: after one minute, ten minutes after the first reminder, and 60 minutes after the second. Hide/Expand and Reconnect do not restart that schedule.

> The source repository does not contain the portable Node.js binary. Maintainers create it with `scripts\prepare-portable-node.ps1`, then prepare the pinned MaxPkg Packager project with `scripts\prepare-maxpkg.ps1`.

Maintainers set the intended release in `version.ini`, then run `PREPARE_RELEASE.bat` to synchronize Node metadata, promote reviewed `CHANGELOG.md` entries, regenerate MaxPkg settings with the permanent `Free` license, and run verification. `-Version <VERSION>` remains an optional override. The installed UI reads the packaged `manifest.ini` version, with `version.ini` as the source-checkout fallback. MZP build, commits, push, and publishing remain explicit maintainer steps. See [MaxPkg packaging](docs/MAXPKG.md#prepare-a-versioned-release).

## Development checkout

Requirements:

- Windows with Windows PowerShell 5.1.
- Node.js 22 or newer, unless `runtime\win-x64\node.exe` has been prepared.
- Autodesk 3ds Max only for real integration testing; mock tests do not launch Max.

Start the bridge daemon:

```powershell
node .\core\server.js --daemon
```

Register the development STDIO host:

```powershell
codex mcp add max-ultra-mcp --env MAX_ULTRA_MCP_TOOL_PROFILE=archviz -- node "<PROJECT_ROOT>\core\server.js" --stdio
```

Then run `01_START_MAX_ULTRA_MCP_FIRST.ms` inside 3ds Max.

## Read-only diagnostics CLI

The source checkout includes a developer/agent diagnostics launcher:

```powershell
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" --help
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" status
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" skills
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" skills --check
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" health
& ".\diagnostics\Max Ultra MCP Diagnostics.bat" capabilities
```

The launcher starts `core\cli.js` with the bundled Node.js runtime when present, falls back to development Node.js, and forwards the requested command. It does not start a second MCP server, register a client, install a skill, execute MaxScript, change a scene, capture a viewport, or save a file.

`status` probes the official Codex and Claude Code CLIs with their read-only `mcp get`/`mcp list` commands and checks the existing authenticated daemon connection. `setup` prints exact `codex mcp add` and `claude mcp add --scope user` commands for review but never runs them. `skills` discovers every `skills\*\SKILL.md` folder without a fixed catalog, returns its name, description, and path, and extracts the MCP tool names referenced by its Markdown files. `skills --check` compares those references with live `max_capabilities`; the CLI helps an agent discover and verify a workflow, while the agent and MCP tools still execute it.

The batch launcher is intentionally source-only and excluded from the MaxPkg production allowlist. The underlying read-only `core\cli.js` remains package-local for agent diagnostics.

## Natural-language quick start

A request such as "create a one-meter cube in 3ds Max", "fix the layout in my 3D program", or "render this in the 3D editor" is enough. An agent using the packaged skill should route that request to Max Ultra MCP and begin with instance discovery.

1. Call `max_list_instances({})`.
2. When exactly one instance is returned, call `max_select_instance({"instance_id":"<INSTANCE_ID>"})`. When several are returned, select a uniquely identified version or scene; otherwise ask one short question. When none are returned, ask one short connection question and do not mutate a scene or UI.
3. Perform the narrowest semantic operation.
4. Query the post-state and capture the relevant viewport, render, or window.

For a Max-owned tool window, use this compact inspection loop:

```text
max_list_instances -> max_select_instance
max_ui_list_windows -> max_ui_inspect
max_ui_capture_window({ window: { hwnd: <HWND> } })
max_ui_diagnostics({ window: { hwnd: <HWND> }, maxDepth: 5, limit: 200 })
narrow semantic tool or reviewed max_run_script
max_ui_inspect -> max_ui_capture_window / max_ui_diagnostics
```

A supplied HWND is captured through the native Windows path after selected-process ownership is revalidated, so child and MAXScriptDialog windows do not need to be rediscovered through UI Automation. Diagnostics return bounded UI Automation and native HWND trees plus compact MSHTML WebBrowser DPI, zoom, DOM-count, layout, and scroll metrics when available; they do not return raw DOM or page source.

## How the connection works

```text
ChatGPT Desktop / Codex / Claude Code / other MCP client
        | MCP JSON-RPC over STDIO
        v
MCP host: core/server.js --stdio
        | authenticated loopback control protocol
        v
Bridge daemon: core/server.js --daemon
        | persistent TCP on 127.0.0.1
        v
MaxScript bootstrap in each 3ds Max process
        | bounded main-thread queue
        v
3ds Max scene, viewport, renderer, and Max-owned UI
```

One daemon can serve several MCP clients and several Max processes. Selection is stored per MCP client. Exactly one connected Max routes automatically; multiple connected instances require `max_list_instances` followed by `max_select_instance`.

Each connected AI-client session normally owns one `core/server.js --stdio` process. These are not extra daemons. Re-running the first-step file replaces the previous daemon only when it is not shared by another open Max; connected STDIO hosts then exit with that daemon and the AI client may start a fresh host. Max Ultra MCP never terminates `node_repl.exe`, unrelated Node.js processes, or an endpoint whose identity cannot be verified.

## First AI-assisted house plan

The complete image-to-scene example is in [examples/house-plan-from-image](examples/house-plan-from-image/README.md).

1. Attach `plan-example.png` to ChatGPT or Codex.
2. Send the English prompt from `PROMPT.md`.
3. The model interprets dimensions into structured JSON.
4. MCP validates the plan and returns a validation token.
5. MCP creates and preserves a wall-plan source spline, extrudes a separate copy, builds outward-facing opening-aware wall topology through `meshOp`, joins walls without penetration, and adds the expanded floor in one undo transaction.
6. The model captures top and perspective viewport screenshots, optionally performs a reversible Normal-modifier A/B comparison, and verifies the result without leaving opening helpers.

The source image is interpreted by the model. Raw image bytes are not passed to 3ds Max.

## Tool profiles

- `core`: connection, scene, objects, viewport, rendering, scripts, diagnostics, and UI automation.
- `archviz`: core plus materials and structured floor-plan workflows.
- `full`: archviz plus layers, modifiers, import/export, and animation helpers.

Set the profile with `MAX_ULTRA_MCP_TOOL_PROFILE`. The default is `archviz`.

## Optional agent skills

The release includes seven portable file-based skills: [`max-ultra-mcp`](skills/max-ultra-mcp/SKILL.md) for general 3ds Max control, [`max-ultra-camera-composition`](skills/max-ultra-camera-composition/SKILL.md) for Safe Frame-aware camera placement, [`max-ultra-character-object-modeling`](skills/max-ultra-character-object-modeling/SKILL.md) for reference-driven single-mesh subdivision modeling, [`max-ultra-renderer-settings`](skills/max-ultra-renderer-settings/SKILL.md) for runtime-inspected renderer configuration, [`max-ultra-spline-modeling`](skills/max-ultra-spline-modeling/SKILL.md) for paths/profiles and non-destructive modifier sources, [`max-ultra-floor-plan`](skills/max-ultra-floor-plan/SKILL.md) for dimensional image/drawing-to-model workflows with a preserved wall spline, and [`max-ultra-maxpkg-packaging`](skills/max-ultra-maxpkg-packaging/SKILL.md) for adapting new or existing 3ds Max scripts to the official MaxPkg workflow.

The MaxPkg skill resolves the current official repository commit at execution time, reads its prompts and automation API documentation directly from GitHub, and prepares every adapted project with the matching original `maxpkg-packager.ms`, `_install.ms`, and `_uninstall.ms`. Both standard hooks are mandatory in the stricter Max Ultra workflow.

The general skill loads its packaged MaxScript code rules before creating or editing reusable scripts. Target-project rules take precedence when they are stricter.

The MCP server remains fully usable without these skills. Skill installation is client-specific and is not required for bridge startup or onboarding registration. The installer does not modify an agent's skill directory automatically.

For ChatGPT Desktop and Codex, the repo-local `plugins/max-ultra-mcp` plugin packages the same seven skills and exposes them through the `3dground-max-ultra-mcp` marketplace. The plugin supplies workflow routing; the separately registered local MCP server remains the authoritative tool transport.

## Security model

- Network listeners bind to `127.0.0.1` only.
- Local control requests use a random installation token.
- Committed documentation, fixtures, logs, and media use synthetic or anonymized data; see the privacy policy.
- STDOUT from the MCP host contains only JSON-RPC; logs go to STDERR or log files.
- Scene mutations are serialized through the Max main-thread queue.
- UI Automation rejects every HWND not owned by the selected `3dsmax.exe` process.
- Arbitrary MaxScript is intentionally powerful and is annotated as a destructive, open-world operation for client approval.
- Unknown renderer APIs return explicit unsupported errors instead of reporting false success.
- Native code is never required for normal operation. Any future managed or native helper must be package-local, optional, and covered by a Node.js/MaxScript fallback.

## Verification

Run all mock, contract, and CLI integration suites:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-smoke.ps1
```

The suites never open, modify, or save a real 3ds Max scene.

Before a production release, also test real 3ds Max versions and installed Corona/V-Ray adapters using the acceptance fixtures described in [USE_CASES.md](docs/USE_CASES.md).

## Documentation

- [V1 architecture, MCP integration, and tool behavior](docs/V1.md)
- [Required production use cases and acceptance contracts](docs/USE_CASES.md)
- [Privacy and data sanitization policy](docs/PRIVACY.md)
- [Detailed bootstrap, panel, lifecycle, and example documentation](docs/README.md)
- [Portable runtime layout](runtime/README.md)
- [Experimental single-executable packaging](docs/SEA.md)
- [MaxPkg packaging and lifecycle](docs/MAXPKG.md)
- [Instructions for AI coding agents](AGENTS.md)
- [Optional Max Ultra MCP agent skill](skills/max-ultra-mcp/SKILL.md)
- [Optional Max Ultra camera-composition agent skill](skills/max-ultra-camera-composition/SKILL.md)
- [Optional Max Ultra character/object-modeling agent skill](skills/max-ultra-character-object-modeling/SKILL.md)
- [Optional Max Ultra renderer-settings agent skill](skills/max-ultra-renderer-settings/SKILL.md)
- [Optional Max Ultra spline-modeling agent skill](skills/max-ultra-spline-modeling/SKILL.md)
- [Optional Max Ultra floor-plan agent skill](skills/max-ultra-floor-plan/SKILL.md)
- [Optional Max Ultra MaxPkg-packaging agent skill](skills/max-ultra-maxpkg-packaging/SKILL.md)

## Repository layout

```text
01_START_MAX_ULTRA_MCP_FIRST.ms   user-facing 3ds Max bootstrap
core/                             MCP host, daemon, and production tool runtime
tests/                            automated suites, helpers, and real-Max fixtures
skills/                           canonical agent skills and focused references
plugins/max-ultra-mcp/             ChatGPT and Codex natural-language routing plugin
scripts/                          launch, installation, packaging, UI helpers
examples/                         runnable and acceptance examples
docs/                             architecture and product specifications
runtime/                          portable runtime location in release builds
assets/                           source-controlled MaxPkg icon artwork
AGENTS.md                         repository contract for AI coding agents
```

## Troubleshooting

- If several Max instances are connected, select one explicitly.
- If the daemon was stopped, rerun `01_START_MAX_ULTRA_MCP_FIRST.ms`. Automatic launches are hidden by default; enable the visible server console in Settings when diagnosing startup.
- Seeing one `node.exe --stdio` per connected ChatGPT, Codex, Claude Code, or other MCP session is expected. `node_repl.exe` processes belong to the AI client, not Max Ultra MCP. Close/reconnect the corresponding AI task to remove an idle client-owned host.
- `BRIDGE_DOWN` means the local daemon is unavailable.
- `MAX_NOT_CONNECTED` means no live bootstrap is connected.
- `RENDERER_UNSUPPORTED` means the active renderer or plugin version lacks a verified adapter for the requested operation.
- PowerShell 7 is not required. Normal scripts use Windows PowerShell 5.1.

For detailed endpoint recovery and panel behavior, see [docs/README.md](docs/README.md).
