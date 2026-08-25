# 3D Ground Max Ultra MCP for 3ds Max

Max Ultra MCP is a standalone, dependency-free local bridge that lets ChatGPT, Codex, and other MCP agents control 3ds Max processes that are already open with short semantic calls. Each bootstrapped Max registers independently with its release, PID, process-start identity, health, and live scene state. The same bootstrap supports Max 2022 and 2027.

Semantic tools cover common work without MaxScript boilerplate. `max_execute` remains an advanced full-control escape hatch: supplied MaxScript can change scenes, files, render settings, and the Max UI. Keep the listener on its default loopback address, inspect the automatic inventory, and target the intended process. Max Ultra MCP never chooses arbitrarily when several Max instances are connected.

## First step: run one file in 3ds Max

The only manual Max-side action is **Scripting > Run Script** and selecting:

```text
C:\Projects\Scripts\max-ultra-mcp\01_START_MAX_ULTRA_MCP_FIRST.ms
```

The file header and panel title identify it as the first step. It handles the local server and connects the current Max automatically:

- On the first run in a Max process, a background worker probes the configured loopback endpoint with an identity-aware Max Ultra MCP control request. If a healthy server is already listening, it attaches without opening another server window.
- If the port is closed, a named Windows lifecycle mutex prevents concurrent Max processes from launching duplicates. The worker starts the sibling `start-server.bat --no-pause` in a branded console, retries with bounded delays (`150, 250, 500, 750, 1000, 1500, 2000 ms` plus bounded 500 ms probes), then connects.
- Re-running the first-step file is an intentional clean restart. It disposes the previous in-Max client, timer, worker, and panel; verifies the listener's Max Ultra MCP identity; asks that server to shut itself down; waits boundedly for the port to close; launches a fresh server; and reconnects.
- Max Ultra MCP never enumerates or kills arbitrary Node, PowerShell, or CMD processes. Shutdown is accepted only through the verified Max Ultra MCP loopback protocol and the server terminates itself. If another service owns the port or identity cannot be proven, restart/launch is refused and the panel shows the error.
- All connect probes, mutex waits, process launch, sleeps, port-close checks, and startup retries run in the background worker. The 3ds Max UI thread remains available; it only drains bounded events/requests and updates the panel.

Keep the first-step file beside `start-server.bat`. If it must be copied elsewhere, set `MAX_ULTRA_MCP_ROOT` to this project directory so the launcher can be resolved safely. Automatic launch is disabled for non-loopback hosts. A manually started BAT console may remain at its stopped prompt after verified server shutdown; automatically launched consoles use `--no-pause` and close with their server.

Run the same first-step file once in every open Max 2022/2027 process that should connect. The panel reports probing, waiting for another launcher, starting, verified shutdown, port release, fresh-server health, connection, and any bounded timeout/failure.

### Professional color-coded panel log

The 30-entry RichTextBox log is the panel's primary full-width, tall surface; there are no separate connection/scene/activity group boxes. Two concise lines above it show lifecycle status and the combined server, Max/PID, scene, object, selection, and dirty-state context. The action row stays below. The resizable panel expands the log in both width and height while retaining a readable minimum size and accessible name.

When the panel moves, Max Ultra MCP stores only its integer `x/y` coordinates in `%USERPROFILE%`'s 3ds Max user-scripts area under `MaxUltraMCP\panel-ui.ini`. On the next first-step launch it accepts the position only when the complete default panel rectangle fits inside a current monitor working area; otherwise it centers the panel on the primary working area. No scene, server, credential, or other application state is written.

The log uses the same category-driven approach the user liked in Collect Asset, adapted to Max Ultra MCP: success is dark green, normal information is steel blue, warnings are amber, errors are dark red, and debug messages are olive. It uses a light gray surface, Segoe UI, a fixed border, per-entry `SelectionColor`, and resets the selection color after rendering. Every update stays on Max's main thread, retains only the newest 30 entries, and scrolls to the newest line with `ScrollToCaret()`.

## Connect Codex or another MCP host once

The local server launcher is:

```text
C:\Projects\Scripts\max-ultra-mcp\start-server.bat
```

The first-step MaxScript normally starts it, so users do not need to launch it manually. Add Max Ultra MCP to Codex once:

```powershell
codex mcp add max-ultra-mcp -- cmd.exe /d /c C:\Projects\Scripts\max-ultra-mcp\start-server.bat --no-pause
```

Equivalent `%USERPROFILE%\.codex\config.toml` or trusted project `.codex/config.toml` entry:

```toml
[mcp_servers.max-ultra-mcp]
command = "cmd.exe"
args = ["/d", "/c", "C:\\Projects\\Scripts\\max-ultra-mcp\\start-server.bat", "--no-pause"]
startup_timeout_sec = 10
tool_timeout_sec = 600
```

Restart the MCP host after changing its configuration. MCP JSON-RPC uses stdout; human-readable status uses stderr.
## Concise agent tools and targeting

Agents can use Max Ultra MCP without knowing its socket/bootstrap mechanics or generating MaxScript for common actions. Tool results are compact by default; pass `details: true` only when deeper identity, UI, or execution diagnostics are useful.

Start with `max_list_instances`. One connected Max is auto-targeted. With several, call `max_select_instance` once; later calls can omit `instance_id`. The server clears a default selection if that process disconnects and never silently picks among several unselected instances.

| Tool | Concise purpose |
| --- | --- |
| `max_list_instances` | Compact live inventory; `details: true` adds full identity/scene state |
| `max_select_instance` | Set the explicit default target for later short calls |
| `max_scene_summary` | Current scene path, dirty state, object/selection counts, and frame |
| `max_create_box` | Create a named standard Box from position/dimensions; no MaxScript needed |
| `max_health` | Main-thread health and identity check |
| `max_snapshot` | Detailed non-mutating Max/scene snapshot |
| `max_logs` | Detailed server and bounded 30-entry panel diagnostics |
| `max_smoke` | Fixed non-mutating main-thread evaluation |
| `max_execute` | Advanced arbitrary-MaxScript escape hatch |
| `max_panel` | Show/hide/minimize/restore the Max Ultra MCP panel |
| `max_ui_list` | Compact bounded Max-owned UI inspection; `details: true` adds all fields |
| `max_ui_invoke` | Guarded action on one discovered control |
| `max_viewport_screenshot` | Active viewport as an MCP PNG image |

Typical short calls:

```json
{"name":"max_list_instances","arguments":{}}
{"name":"max_select_instance","arguments":{"instance_id":"max-2027-12345-..."}}
{"name":"max_scene_summary","arguments":{}}
{"name":"max_create_box","arguments":{"name":"AgentBox"}}
{"name":"max_viewport_screenshot","arguments":{}}
```

`max_create_box` defaults to origin, `20 x 20 x 20`, and selects the new Box. Position, dimensions, selection, and exact name are explicit schema fields. It refuses an existing exact name and never saves the scene. Use `max_execute` only for operations that do not yet have a semantic tool; arbitrary code is not sandboxed.

### Real Box launcher and reusable action template

For a runnable local example, start Max Ultra MCP, load the bootstrap, then double-click:

```text
C:\Projects\Scripts\max-ultra-mcp\example-create-test-box.bat
```

The visible flow is deliberately thin: the BAT finds Node and calls `example-create-box.js`; that file exports the copyable `createTestBox()` function and contains only a short, single-purpose MaxScript action plus one `runMaxAction(...)` call. `run-max-action.js` owns connection setup, inventory discovery, sole-instance routing, live-list refusal, console errors, and cleanup. `bridge-control-client.js` owns the protocol plumbing. Future local examples can copy the small action function without duplicating sockets or safety logic.

The example creates one standard Box named `MaxUltraMCP_TestBox` at origin with size `20 x 20 x 20`. It refuses a duplicate name, prints and refuses when several Max instances are connected, and never saves. Use it only where adding that test object is acceptable. Automated verification runs the action against mock Max 2022/2027 clients, never a real user scene.
### UI accessor workflow

UI actions are explicit and two-phase so a stale or ambiguous control is never clicked silently:

1. Call `max_ui_list` for the intended instance. Choose `scope = "max_window"` for the main Max tree or `scope = "popups"` for current Max dialogs. Keep `max_depth` and `limit` as small as practical; optional `title_contains` and `class_contains` filters affect returned records without pruning traversal.
2. Select one returned record using its `hwnd`, `parentHwnd`, `text`, `className`, `resourceId`, `dllFileName`, `depth`, and `rect`.
3. Call `max_ui_invoke` with that `target_hwnd`. Pass `expected_text` and `expected_class` to reject stale/reused handles.
4. Choose `press_button` (uses `UIAccessor.PressButton`), `set_window_text` (uses `UIAccessor.SetWindowText` plus `value`), or `send_message` (uses `windows.sendMessage` plus integer `message`, `wparam`, and `lparam`).

The bootstrap rejects HWNDs outside the selected Max main-window/popup hierarchy. Discovery is bounded to depth 6 and 200 returned controls, and discovery/invocation each run as one queued main-thread request.

## Performance and main-thread contract

Networking never waits on the Max UI thread. A background worker owns TCP connect/read/write and exchanges messages through synchronized .NET queues. A 250 ms WinForms timer on Max's UI thread drains at most 16 lightweight transport messages and executes at most one queued Max request per tick. Heartbeats are queued every 2.5 seconds; UI button callbacks only request transport state changes and never connect or wait synchronously.

All 3ds Max API, scene, UI, and viewport work runs on Max's main thread. A long arbitrary MaxScript can still occupy the UI for as long as that script runs. Server timeout sends cancellation for work still waiting in the main-thread queue, but already executing MaxScript cannot be safely preempted. Long workflows should use short idempotent chunks with progress returned between calls. Screenshot capture is one bounded main-thread request; file/network transfer remains outside the UI thread.

The additional control client is also loopback-only by default and exposes only inventory plus `max_execute`. It uses the same selection rules and main-thread request path as MCP; it exists for runnable local command examples such as the Box launcher.

## Local verification

No package install is needed. The wrappers find Node.js 18+ on `PATH` or Codex's bundled dependency installation:

```powershell
cd C:\Projects\Scripts\max-ultra-mcp
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-smoke.ps1
```

The smoke test uses independent mock Max 2022 and 2027 clients. It verifies all 13 semantic/advanced tools, the identity probe and self-shutdown protocol, compact-versus-detailed payloads, routing/cancellation, Box safety, panel/UI actions, color-category RichTextBox rendering, the 30-entry/auto-scroll invariants, screenshot cleanup, and bounded async transport. Static checks cover the first-step filename, previous-client disposal, named mutex, loopback guard, ProcessStartInfo launch, no `WaitForExit`, bounded backoff, verified shutdown, and one final transport connect. It never opens Max or changes a real scene.

Environment overrides:

- `MAX_ULTRA_MCP_HOST` defaults to `127.0.0.1` and should remain loopback.
- `MAX_ULTRA_MCP_PORT` defaults to `47635`.
- `MAX_ULTRA_MCP_TIMEOUT_MS` defaults to `5000` for short tools.
- `MAX_ULTRA_MCP_ROOT` optionally locates `start-server.bat` when the first-step file is not kept in the project root.

The first-step script reads `MAX_ULTRA_MCP_HOST` and `MAX_ULTRA_MCP_PORT`, so server and bootstrap stay aligned. Auto-start remains loopback-only.

## Remaining real-Max validation

Mock and static tests cannot prove version-specific MaxScript/.NET parsing. In Max 2022 and 2027, run `01_START_MAX_ULTRA_MCP_FIRST.ms` from this project in an empty throwaway scene, verify auto-start/connection and one clean re-run restart, then run `max_health`, `max_smoke`, panel actions, a viewport screenshot, and harmless `max_execute` such as `maxVersion()`. No destructive real-scene action is part of repository verification.