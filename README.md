# 3DGROUND - Max Ultra MCP

Max Ultra MCP connects ChatGPT, Codex, and other MCP clients to Autodesk 3ds Max. It exposes semantic tools for scene operations, viewport inspection, rendering, MaxScript, process-scoped UI automation, and architectural workflows while keeping all 3ds Max API work on the Max main thread.

## Project status

The v1 architecture and mock-tested MCP surface are implemented. The current automated suite covers the 3ds Max 2022 and 2027 protocol endpoints, multi-instance routing, authenticated STDIO transport, structured responses, viewport images, render jobs, UI boundaries, and floor-plan generation. Real 3ds Max and renderer-version acceptance testing remains required before a production release.

The required production workflow backlog includes asset relinking and collection, Corona/V-Ray configuration, camera composition, render masks, material diagnostics, batch FBX/GLB export, performance analysis, proxy conversion, and AI-assisted material editing. See [Required Production Use Cases](docs/USE_CASES.md).

## What users can do

- Start the bridge and configure ChatGPT Desktop, Codex, Claude Code, or another STDIO client from one MaxScript entry point.
- Connect one or more already-open 3ds Max instances to one local bridge.
- Let each connected MCP client select its own Max instance.
- Inspect and modify scenes through structured MCP tools.
- Capture viewport screenshots and return them directly to the model.
- Start, monitor, cancel, and retrieve renders.
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

## First AI-assisted house plan

The complete image-to-scene example is in [examples/house-plan-from-image](examples/house-plan-from-image/README.md).

1. Attach `plan-example.png` to ChatGPT or Codex.
2. Send the English prompt from `PROMPT.md`.
3. The model interprets dimensions into structured JSON.
4. MCP validates the plan and returns a validation token.
5. MCP builds wall segments, openings, placeholders, and the floor in one undo transaction.
6. The model captures top and perspective viewport screenshots and verifies the result.

The source image is interpreted by the model. Raw image bytes are not passed to 3ds Max.

## Tool profiles

- `core`: connection, scene, objects, viewport, rendering, scripts, diagnostics, and UI automation.
- `archviz`: core plus materials and structured floor-plan workflows.
- `full`: archviz plus layers, modifiers, import/export, and animation helpers.

Set the profile with `MAX_ULTRA_MCP_TOOL_PROFILE`. The default is `archviz`.

## Optional agent skill

The release includes [`skills/max-ultra-mcp`](skills/max-ultra-mcp/SKILL.md), a portable optional skill for agents that support file-based skills. It teaches instance selection, semantic-tool priority, verification, renderer/UI boundaries, and reviewed MaxScript escape-hatch patterns without duplicating the generated MCP tool catalog.

The MCP server remains fully usable without the skill. Skill installation is client-specific and is not required for bridge startup or onboarding registration. The installer does not modify an agent's skill directory automatically.

## Security model

- Network listeners bind to `127.0.0.1` only.
- Local control requests use a random installation token.
- Committed documentation, fixtures, logs, and media use synthetic or anonymized data; see the privacy policy.
- STDOUT from the MCP host contains only JSON-RPC; logs go to STDERR or log files.
- Scene mutations are serialized through the Max main-thread queue.
- UI Automation rejects every HWND not owned by the selected `3dsmax.exe` process.
- Arbitrary MaxScript is intentionally powerful and is annotated as a destructive, open-world operation for client approval.
- Unknown renderer APIs return explicit unsupported errors instead of reporting false success.

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
- If the daemon console was closed manually, rerun `01_START_MAX_ULTRA_MCP_FIRST.ms`.
- `BRIDGE_DOWN` means the local daemon is unavailable.
- `MAX_NOT_CONNECTED` means no live bootstrap is connected.
- `RENDERER_UNSUPPORTED` means the active renderer or plugin version lacks a verified adapter for the requested operation.
- PowerShell 7 is not required. Normal scripts use Windows PowerShell 5.1.

For detailed endpoint recovery and panel behavior, see [docs/README.md](docs/README.md).
