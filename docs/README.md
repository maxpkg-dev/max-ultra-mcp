# 3D Ground - Max Ultra MCP

Max Ultra MCP is a standalone local MCP bridge for controlling already-open Autodesk 3ds Max 2022 and 2027 processes with concise semantic tools. Networking remains off the Max UI thread; scene, viewport, UIAccessor, and WinForms work is marshalled through a bounded main-thread queue.

## One-file first start

The only file a 3ds Max user runs manually is the root file:

```text
01_START_MAX_ULTRA_MCP_FIRST.ms
```

Run it once in every Max process that should connect. It locates `scripts\start-server.bat` relative to the project root, probes the configured loopback endpoint, launches a minimized branded server console when needed, and connects the current Max. Running the file again disposes the previous in-Max client and performs a verified clean restart. An unexpected disconnect or manually closed server is terminal for that session: the bootstrap reports the failure and does not relaunch until the first-step file is explicitly run again. Panel **Reconnect** and **Connect only** actions attach only to an already-running server.

A manual diagnostic launch remains visible:

```bat
scripts\start-server.bat
```

Automatic launch uses `--no-pause --port <PORT>` and starts minimized. The BAT accepts the selected fallback port and passes it to the core server.

## Safe endpoint recovery

The default endpoint is `127.0.0.1:47635`.

- A healthy current Max Ultra MCP server is reused on first start.
- A compatible legacy bridge that lacks `probe` is recognized through its live `CONTROL list` inventory. First start may attach to it.
- Re-running against a legacy bridge, or encountering a truly unknown occupant, never kills a process. The bootstrap scans only the next 10 loopback ports, selects a free fallback, starts Max Ultra MCP there, and reports `MAX_ULTRA_MCP_PORT=<PORT>` in the panel.
- Current servers identify themselves through `CONTROL probe`. A bootstrap-owned server uses `shutdown_owned_when_idle` with the exact captured server identity; an identity mismatch is rejected. General control clients retain `shutdown` and `shutdown_when_idle`. Arbitrary Node, PowerShell, or command-shell processes are never terminated.

## Panel behavior

The compact panel shows two status/context rows above a tall log.

- Running/connected is green; connecting/restarting/retrying is amber; errors are red; stopped/unknown is neutral. Status text is bold and always names the state, so color is not the only cue.
- Panel and log colors derive from 3ds Max `ColorMan` background/text colors, with safe fallbacks. The log uses a lighter theme surface, a one-pixel flat black boundary, and blue/cyan informational text. Success, warning, error, and debug colors remain distinct.
- The RichTextBox is read-only, wrapped, capped at 30 entries, and auto-scrolls to the latest entry.
- Final window `x`/`y` are saved before cleanup in the user-scripts `MaxUltraMCP\panel-ui.ini` file. On the next launch, the full 680×500 bounds must fit a current screen working area or the panel centers safely.
- **Hide panel** saves position and hides only the panel. The server and Max client remain connected. A small borderless `Max Ultra MCP - Show` bubble appears near the lower-left of that screen's working area; clicking it restores/focuses the panel and disposes the bubble.
- Window X and **Stop / Exit** disconnect Max and arm shutdown only for the exact server launched by this bootstrap session; that server exits when the last connected Max disconnects. A pre-existing/manual server is disconnected but left running. The `#preSystemShutdown` callback applies the same idempotent cleanup during Max exit. Re-run cleanup removes any restore bubble and leaves restart to the verified first-step flow.

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
scripts/                          BAT/PowerShell server and smoke launchers
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

The suite uses mock Max 2022 and 2027 clients only. It verifies all 13 tools, routing/cancellation, Box safety, panel/UI/screenshot protocol, RichTextBox bounds/autoscroll, FormClosing persistence order, Hide/bubble isolation, theme/status invariants, legacy/fallback recovery, minimized launch, and identity-verified shutdown-on-idle. It does not open 3ds Max, manipulate a real scene, or save a scene.
