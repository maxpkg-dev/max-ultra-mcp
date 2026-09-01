# Coding-agent integration

This document is the shared policy for Codex CLI, Claude Code, and other coding agents working in this repository. It supplements `AGENTS.md`; it does not replace the product and safety invariants there.

## Keep in persistent project instructions

Persistent instructions should contain only information needed on nearly every repository task:

- the required reading order and authoritative code locations;
- product identity, supported 3ds Max range, main-thread, transport, privacy, and release invariants;
- standard verification commands and the no-commit/no-push boundary;
- the distinction between implemented tools and documented backlog.

Do not copy detailed modeling, renderer, MaxPkg, or UI procedures into `AGENTS.md` or `CLAUDE.md`. Those workflows are loaded on demand from the canonical skills under `skills/`.

## Route natural 3D requests

A request such as “make X in 3ds Max”, “do X in my 3D program”, or “change X in the 3D editor” is intent to use Max Ultra MCP when its tools are available. The agent should:

1. Call `max_list_instances` immediately.
2. If exactly one instance is connected, call `max_select_instance` for it. If several exist and the request uniquely identifies one by version, scene, or other returned evidence, select that match.
3. If no instance is connected, ask exactly one short question telling the user how to connect Max. If several remain ambiguous, ask exactly one short question naming the concise choices. Do not mutate a scene or UI until the answer resolves the target.
4. Use the narrowest semantic tool, with MaxScript and process-scoped UI automation only as reviewed fallbacks.
5. Verify the post-state with a query, viewport capture, render result, or window capture appropriate to the operation.

The canonical behavior is in `skills/max-ultra-mcp/SKILL.md`. Repository adapters under `.agents/skills/` and `.claude/skills/` only make that skill discoverable to each client.

## Load skills on demand

- Use `max-ultra-mcp` for ordinary scene, viewport, script, file, and Max-owned UI work.
- Load the focused camera, character/object modeling, floor-plan, MaxPkg, renderer-settings, or spline skill only when its description matches the request.
- Treat skill references as conditional detail. Read only the reference named for the active workflow, except where a skill explicitly requires a complete rules reference before authoring persistent MaxScript.
- Keep the live MCP tool list and `max_capabilities` authoritative. A skill never proves that a backlog tool exists.

## Suitable hook checks

Hooks may run deterministic, side-effect-free repository checks such as JavaScript or PowerShell syntax validation, `git diff --check`, the English-only scan, or an explicitly requested test suite. Keep hook output bounded and privacy-safe.

Do not use hooks to select a 3ds Max instance, approve writes, execute MaxScript, mutate a scene, control a window, capture user UI, build a release, commit, or push. Those steps require current task context and the normal approval boundary. Agent-specific hook files are intentionally not duplicated in this repository; both clients can call the same commands documented in `AGENTS.md` when a team chooses to configure trusted local hooks.

## Thin client adapters

- Codex CLI reads root `AGENTS.md` and discovers the adapter skill under `.agents/skills/max-ultra-mcp/`.
- Claude Code reads root `CLAUDE.md`, which imports `AGENTS.md`, and discovers the adapter skill under `.claude/skills/max-ultra-mcp/`.
- Both adapters point to `skills/max-ultra-mcp/SKILL.md`; update the canonical skill first.
- `plugins/max-ultra-mcp` packages synchronized copies of all canonical skills for ChatGPT Desktop and Codex natural-language routing. Validate the plugin and keep every copied skill byte-identical before release.
