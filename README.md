# 3DGROUND - Max Ultra MCP

Max Ultra MCP connects ChatGPT, Codex, and other MCP clients to Autodesk 3ds Max. It exposes semantic tools for scene operations, viewport inspection, rendering, MaxScript, process-scoped UI automation, and architectural workflows while keeping all 3ds Max API work on the Max main thread.

## Project status

The v1 architecture and mock-tested MCP surface are implemented. The current automated suite covers the 3ds Max 2022 and 2027 protocol endpoints, multi-instance routing, authenticated STDIO transport, structured responses, viewport images, render jobs, UI boundaries, and floor-plan generation. Real 3ds Max and renderer-version acceptance testing remains required before a production release.

The required production workflow backlog includes asset relinking and collection, Corona/V-Ray configuration, camera composition, render masks, material diagnostics, batch FBX/GLB export, performance analysis, proxy conversion, and AI-assisted material editing. See [Required Production Use Cases](docs/USE_CASES.md).

## What users can do

- Connect one or more already-open 3ds Max instances to one local bridge.
- Let each ChatGPT or Codex client select its own Max instance.
- Inspect and modify scenes through structured MCP tools.
- Capture viewport screenshots and return them directly to the model.
- Start, monitor, cancel, and retrieve renders.
- Run MaxScript text, files, macros, and Action Table commands.
- Inspect and operate UI controls only inside the selected `3dsmax.exe` process.
- Validate and build a dimensioned house plan interpreted from an attached image.
- Use unrestricted `max_execute` when a semantic tool does not exist yet.

## Installation for release users

Release packages bundle a portable Node.js runtime. Users do not install Node.js, change `PATH`, require administrator rights, or download dependencies at runtime.

1. Extract or install Max Ultra MCP into a stable local directory.
2. Run:

   ```bat
   scripts\install-chatgpt-codex.bat
   ```

3. Run this file once in every 3ds Max process that should connect:

   ```text
   01_START_MAX_ULTRA_MCP_FIRST.ms
   ```

4. Restart or reconnect the MCP client if it was already open.

The installer uses the bundled runtime and registers the STDIO host through the Codex CLI when available. If the CLI is unavailable, it prints the exact command and arguments required by the desktop MCP settings. It does not rewrite application configuration files directly.

> The source repository does not contain the portable Node.js binary. Maintainers create it with `scripts\prepare-portable-node.ps1` when building a release.

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
ChatGPT Desktop / Codex
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
- [Instructions for AI coding agents](AGENTS.md)

## Repository layout

```text
01_START_MAX_ULTRA_MCP_FIRST.ms   user-facing 3ds Max bootstrap
core/                             MCP host, daemon, tool runtime, tests
scripts/                          launch, installation, packaging, UI helpers
examples/                         runnable and acceptance examples
docs/                             architecture and product specifications
runtime/                          portable runtime location in release builds
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
