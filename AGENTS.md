# Max Ultra MCP Agent Guide

This file is the repository entry point for AI coding agents. It describes what to read, where to make changes, and which product invariants must not be broken.

## Required reading order

1. [README.md](README.md) for the user-facing product contract.
2. [docs/V1.md](docs/V1.md) for architecture and the implemented v1 MCP surface.
3. [docs/USE_CASES.md](docs/USE_CASES.md) for mandatory production workflows that may still be backlog items.
4. [.agents/coding-rules.md](.agents/coding-rules.md) for authoritative source, MaxScript, lifecycle, UI, and verification rules.
5. [docs/PRIVACY.md](docs/PRIVACY.md) for required anonymization, placeholders, and sensitive-data review.
6. [docs/MAXPKG.md](docs/MAXPKG.md) before changing release layout, package lifecycle, or installation behavior.
7. [.agents/release-rules.md](.agents/release-rules.md) before preparing, building, or publishing a release.

Do not infer that a documented backlog tool is implemented. Confirm it in `core/tool-catalog.js`, `core/tool-runtime.js`, and tests.


For the shared Codex CLI and Claude Code policy on persistent instructions, on-demand skills, natural 3D-request routing, and suitable hooks, read [.agents/agent-interop.md](.agents/agent-interop.md). Keep client-specific adapters thin and update the canonical documents first.
## Product boundaries

- Product identity is `3DGROUND - Max Ultra MCP`.
- User-facing and source-controlled text must be English only.
- The target product range is 3ds Max 2022 through 2027. Automated protocol tests currently exercise the 2022 and 2027 endpoints; do not claim complete real-version validation without evidence.
- Release users must not need a system Node.js installation. Source development may use Node.js 22+; release preparation bundles pinned Node.js 24 LTS.
- The server remains Node.js unless profiling demonstrates a specific operation that justifies a native GUP.
- `01_START_MAX_ULTRA_MCP_FIRST.ms` is the only normal end-user entry point. Preserve automatic AI-client onboarding, its setup and read-only test-prompt pages, the persistent header/settings entry points, and closable dismissal behavior.
- MaxPkg is the release installation system. Preserve the pinned-tooling workflow, production file allowlist, dynamic package-root paths, standard hooks, and focused uninstall cleanup.

## Architecture

```text
MCP client
  -> core/server.js --stdio
  -> authenticated local control connection
  -> core/server.js --daemon
  -> persistent loopback TCP
  -> 01_START_MAX_ULTRA_MCP_FIRST.ms
  -> bounded 3ds Max main-thread queue
```

The daemon is shared. Instance selection and jobs belong to the individual MCP session. Never move selected-instance state into a process-global default shared by clients.

## Non-negotiable invariants

- Keep MCP STDOUT JSON-RPC only. Send diagnostics to STDERR or logs.
- Never commit real user paths, customer data, credentials, machine identifiers, raw logs, or metadata-bearing media. Follow `docs/PRIVACY.md`.
- Discover or register AI clients through their official CLIs. Do not directly rewrite Codex, ChatGPT, Claude Code, or other client configuration files.
- Bind local transports to `127.0.0.1` and preserve installation-token authentication.
- Never call 3ds Max scene, viewport, renderer, SDK, WinForms, or UIAccessor APIs from a transport/background thread.
- Serialize scene mutations through the Max main-thread queue.
- Auto-route only when exactly one Max is connected. Require explicit selection when several are connected.
- UI Automation may control only HWNDs owned by the selected `3dsmax.exe` PID. Revalidate ownership immediately before every mutation.
- Never present coordinate clicking or an unknown renderer API as verified semantic success.
- Keep arbitrary `max_execute` unrestricted, but annotate it as destructive and open-world.
- Preserve structured envelopes, stable error codes, scene revisions, stale NodeRef rejection, and post-state evidence.
- Long operations must be cancellable jobs and must not block MCP initialization or tool discovery.
- Automated tests must never open, modify, or save a real user scene.

## Important code locations

| Area | Files |
| --- | --- |
| Process modes and bridge routing | `core/server.js` |
| MCP STDIO and JSON-RPC | `core/stdio-host.js` |
| Public tool schemas and profiles | `core/tool-catalog.js` |
| Semantic tool dispatch | `core/tool-runtime.js` |
| Control client and authentication | `core/bridge-control-client.js`, `core/local-auth.js` |
| Floor-plan validation/build | `core/floor-plan.js` |
| Windows UI Automation | `core/windows-ui.js`, `scripts/max-ui-automation.ps1` |
| Max bootstrap and main-thread queue | `01_START_MAX_ULTRA_MCP_FIRST.ms` |
| AI-client onboarding and registration | `01_START_MAX_ULTRA_MCP_FIRST.ms`, `scripts/agent-integration.ps1` |
| Mock and contract tests | `tests/smoke-test.js`, `tests/v1-smoke-test.js`, `tests/cli-integration-test.js` |
| Optional agent skills | `skills/` |
| Release/runtime tooling | `version.ini`, `CHANGELOG.md`, `.agents/release-rules.md`, `scripts/prepare-release.ps1`, `scripts/prepare-portable-node.ps1`, `scripts/build-release.ps1`, `scripts/build-sea.ps1` |
| MaxPkg packaging | `docs/MAXPKG.md`, `maxpkg-files.txt`, `scripts/prepare-maxpkg.ps1`, `scripts/sync-maxpkg-tooling.ps1` |
| GitHub MZP release | `RELEASE_MZP_TO_GITHUB.bat`, `scripts/publish-github-release.ps1`, `scripts/release-mzp-utils.ps1` |

## Adding or changing an MCP tool

1. Define one canonical public name and JSON Schema in `core/tool-catalog.js`.
2. Assign the smallest appropriate profile: `core`, `archviz`, or `full`.
3. Set accurate MCP annotations. Filesystem, arbitrary script, and plugin/UI operations usually require `openWorldHint`.
4. Validate arguments at the host boundary and again where MaxScript literals are generated.
5. Implement semantic behavior in `core/tool-runtime.js` or a focused module. Do not generate ad hoc MaxScript in the STDIO host.
6. Use NodeRefs with handles and scene revisions for scene targets.
7. Support `dryRun`, plan/apply tokens, or jobs when the operation is destructive, ambiguous, or long-running.
8. Return created/changed handles, counts, paths, bounding boxes, applied settings, or another verifiable post-state.
9. Add mock contract coverage. Add real-Max fixture requirements to the relevant specification when mocks cannot prove behavior.
10. Update user documentation only for behavior that is actually implemented and tested.

## Renderer and plugin adapters

- Detect the active renderer, plugin class, plugin version, and supported properties before mutation.
- Keep generic Max render settings separate from Corona and V-Ray adapters.
- Prefer property/capability introspection over version-string assumptions.
- Return `RENDERER_UNSUPPORTED` when a required API is unknown.
- Do not use standard 3ds Max render elements as a fallback for V-Ray-specific elements.
- Preserve exact `applied`, `unchanged`, `unsupported`, and `warnings` lists for configuration operations.

## Asset and filesystem workflows

- Normalize and validate every path.
- Distinguish read-only scan roots from write destinations.
- Never overwrite different files that share a basename without an explicit collision policy.
- Copy successfully before repathing the scene.
- Produce a manifest for collection, export, and proxy jobs.
- Do not delete original geometry during proxy conversion. Verified conversion moves originals to a recoverable backup layer; deletion is separate.
- Batch export must not replace an unsaved working scene without explicit authorization and should use a dedicated Max worker.

## Natural-language material editing

The AI client interprets natural language. The MCP server receives an explicit structured material query/edit plan. Never evaluate raw user prose as MaxScript.

Before applying a material edit, detect shared materials and maps. Default to cloning for matched objects when an edit would otherwise affect unmatched nodes.

## Commands

Run the complete verification suite from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-smoke.ps1
```

Individual Node suites:

```powershell
node .\tests\smoke-test.js
node .\tests\v1-smoke-test.js
node .\tests\cli-integration-test.js
```

Additional required checks:

```powershell
git diff --check
rg -n --hidden --glob '!.git/**' "\p{Cyrillic}" .
git status --short
```

The Cyrillic scan must return no matches. Source files and examples are English-only even when the user conversation is in another language.

## Verification expectations

- Syntax-check changed JavaScript and PowerShell files.
- Run all three mock/contract/CLI suites for protocol or tool changes.
- Confirm that CLI integration leaves no daemon or mock processes behind.
- Test JSON parsing for changed configuration/example data.
- Check generated MaxScript structure in mocks, but do not treat that as proof of renderer/plugin compatibility.
- Clearly report which behavior was mock-tested and which still requires a real 3ds Max fixture.

## Git and handoff

- Preserve unrelated user changes.
- Do not push unless the user explicitly requests it.
- Do not create empty commits when there is nothing to record.
- Use concise English commit messages.
- Leave the working tree clean after a requested commit.
- In the final report, lead with the result, list verification performed, and disclose real-Max or renderer testing that remains.
