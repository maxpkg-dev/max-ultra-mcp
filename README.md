# 3DGROUND - Max Ultra MCP

Max Ultra MCP connects ChatGPT, Codex, and other MCP clients to Autodesk 3ds Max. It exposes semantic tools for scene operations, viewport inspection, rendering, MaxScript, process-scoped UI automation, and architectural workflows while keeping all 3ds Max API work on the Max main thread.

## Project status

The v1 architecture and mock-tested MCP surface are implemented. The current automated suite covers the 3ds Max 2022 and 2027 protocol endpoints, multi-instance routing, authenticated STDIO transport, structured responses, viewport images, render jobs, UI boundaries, and floor-plan generation. Real 3ds Max and renderer-version acceptance testing remains required before a production release.

The first production-foundations increment adds session-owned common jobs and read-only material diagnostics. The remaining workflow backlog includes asset relinking and collection, Corona/V-Ray configuration, camera composition, render masks, batch FBX/GLB export, performance analysis, proxy conversion, and AI-assisted material editing. See [Required Production Use Cases](docs/USE_CASES.md).

### Recent changes in 1.1.0

- Added a session-owned common job API for listing, monitoring, waiting for, cancelling, and retrieving long-operation results without leaking jobs between MCP clients.
- Added read-only material diagnostics for missing assignments, invalid materials, incomplete Multi/Sub materials, and missing bitmap files.
- Added privacy-safe semantic activity labels to the in-Max panel, with a shortened request identifier retained for troubleshooting.
- Added an identity-verified first-step restart: a re-run stops the previous unshared daemon, waits for its loopback endpoint to close, and then launches the replacement; connected client-owned STDIO hosts exit when that verified daemon connection closes.
- Reused validation tokens for destructive plan/apply workflows so payload, selected Max instance, scene revision, targets, and detected capabilities stay bound together.
- Corrected viewport framing commands: selection framing now affects only the active viewport, and scene extents use the documented `max tool zoomextents` command.
- Added clean visual-review captures: the viewport is maximized, temporary Realistic/Shaded review settings remove grid and selection noise, Nitrous anti-aliasing is raised to 8X, and the user's display settings are restored after the image is saved.
- Corrected floor-plan wall winding, added mitered corners and trimmed T-junctions, expanded floor slabs to the outside wall envelope, removed opening Dummy helpers, and added a guarded Normal-modifier screenshot comparison tool.
- Expanded mock, contract, CLI, packaging, and agent-reference coverage for the new behavior.

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
- Inspect and operate UI controls only inside the selected `3dsmax.exe` process.
- Validate and build a dimensioned house plan interpreted from an attached image.
- Use unrestricted `max_execute` when a semantic tool does not exist yet.

## Installation for release users

MaxPkg release packages bundle a portable Node.js runtime. Users do not install Node.js, change `PATH`, require administrator rights, or download dependencies at runtime.

1. Install the Max Ultra MCP `.mzp` through MaxPkg.
2. Run this single file once in every 3ds Max process that should connect:

   ```maxscript
   01_START_MAX_ULTRA_MCP_FIRST.ms
   ```

3. When no supported AI client is configured, the first-start script opens **AI Client Setup** automatically. On **1. Setup**, select **ChatGPT Desktop / Codex** and/or **Claude Code**, then choose **Install selected**. After reconnecting the client, use **2. Test prompt** to copy a safe, read-only connection test.
4. Restart or reconnect each newly configured AI client.

The onboarding uses official `codex mcp` and `claude mcp` commands when their CLIs are available. ChatGPT Desktop and Codex share the OpenAI MCP configuration. Claude Code registration is user-scoped. If a CLI is unavailable, the same window shows and copies exact STDIO values for manual or other-client setup. It never writes client configuration files directly.

Closing onboarding dismisses its automatic display without stopping the bridge. Open it again at any time with **AI setup** beside **Hide panel**, or with **Settings -> Open AI client setup**. The standalone `scripts\install-chatgpt-codex.bat` remains available for headless OpenAI-client registration, but it is not required for normal first start.

> The source repository does not contain the portable Node.js binary. Maintainers create it with `scripts\prepare-portable-node.ps1`, then prepare the pinned MaxPkg Packager project with `scripts\prepare-maxpkg.ps1`.

Maintainers publish a tested MZP with `RELEASE_MZP_TO_GITHUB.bat`. The guarded workflow compares `core\package.json`, the newest versioned package below ignored `dist/`, and GitHub Releases before creating a `v<VERSION>` release and uploading the MZP plus its SHA-256 file. See [MaxPkg packaging](docs/MAXPKG.md#publish-the-mzp-to-github-releases).

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

The MaxPkg skill resolves the current official repository commit at execution time, reads its prompts directly from GitHub, and prepares every adapted project with the matching original `maxpkg-packager.ms`, `_install.ms`, and `_uninstall.ms`. Both standard hooks are mandatory in the stricter Max Ultra workflow.

The MCP server remains fully usable without these skills. Skill installation is client-specific and is not required for bridge startup or onboarding registration. The installer does not modify an agent's skill directory automatically.

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
skills/                           optional agent skills and focused references
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
