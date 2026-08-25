# Max Ultra MCP Coding Rules

These rules apply to every change in this repository. They are adapted from the prior runtime project's conventions for this standalone Max Ultra MCP product.

## Project contract

- Keep the product identity consistently **3D Ground - Max Ultra MCP**. Do not reintroduce legacy bridge identities or environment-variable prefixes.
- Support Autodesk 3ds Max 2022 and 2027.
- Keep networking and transport work off the Max main thread. Marshal all 3ds Max UI, scene, viewport, and API work through the bounded main-thread queue.
- Never manipulate or save a real user scene from automated tests.
- Preserve concise semantic MCP tools for routine operations and retain generic MaxScript execution as an advanced escape hatch.
- Keep normal tool responses compact. Return detailed diagnostics only when requested or required to explain an error.

## Source headers and attribution

Every source file must begin with a short responsibility comment before executable or global code, followed by the applicable comment-style equivalents of:

- `Copyright (c) 2026 Lukianenko Vasyl`
- `Project website: https://3dground.net`
- `Developed by Lukianenko Vasyl`

Data-only metadata files are exempt when their format does not support comments.

## MaxScript structure

- Minimize globals. `MaxUltraMcpActiveClient` is the one intentional lifecycle facade required to dispose an earlier bootstrap instance on script re-evaluation. Do not add another global without documenting why it is unavoidable.
- Group related state and behavior in focused structs. Keep transport lifecycle, UI state, and protocol data separate where practical.
- Define every helper method before any method that calls it; do not rely on MaxScript forward method lookup.
- Give value-producing and success/failure functions explicit `return` statements.
- Put an opening parenthesis on the same line as the construct that owns it and align the closing parenthesis with that construct.
- Wrap each complete `if` test expression in parentheses. Use `do` when there is no `else`, and `then` only when an `else` follows.
- Use `for index in 1 to count` for numeric loops.
- Do not use mapped `copy` on arrays.
- Format named arguments exactly as `key: value`.
- Avoid ambiguous or reserved local names such as `result`, `item`, `path`, `text`, `name`, and `data`. Prefer role-specific names.
- Do not name functions `open` or `close`.
- Prefer verbatim strings for Windows paths and `+` for string concatenation.

## JavaScript structure

- Use descriptive function and variable names and keep protocol/routing mechanics inside reusable server or client helpers.
- Validate all external input at the boundary and return stable, concise structured errors.
- Keep high-level action examples thin. They must not duplicate socket, discovery, routing, or generic error plumbing.
- Keep local bridge control operations identity-verifiable. A process may shut itself down after a verified control request; never enumerate and kill arbitrary Node, PowerShell, or command-shell processes.

## Error handling and filesystem safety

- Use empty `catch` blocks only for best-effort cleanup or optional UI work. Log or return important operational failures with enough context to act on them.
- Normalize filesystem paths before use, verify expected files/directories, and keep user-writable UI state separate from installed project files.
- Persist only the panel state the product needs. Validate restored window bounds against current screens and use a sensible visible default when invalid.
- When a loopback port is occupied, never terminate an occupant that cannot be proven to be Max Ultra MCP. Recognize compatible legacy bridge responses where possible; otherwise select a bounded free fallback port and explain how the MCP host must use it.

## UI conventions

- Keep the panel compact and readable: concise status/context lines above one tall, full-width activity log.
- The activity log is a .NET RichTextBox with category colors, at most 30 entries, automatic scroll-to-latest behavior, and a flat one-pixel product-colored outline.
- Do not add a redundant recent-errors group. Preserve keyboard/readability accessibility and responsive resizing.
- Perform every WinForms/3ds Max UI mutation on the Max main thread.

## Protocol and lifecycle safety

- Inventory Max 2022/2027 instances automatically. Auto-route only when exactly one instance exists; require explicit selection when several exist.
- Re-running the first-step MaxScript must prevent overlapping restarts, dispose the earlier in-Max client/timer/panel, request identity-verified server self-shutdown, wait boundedly for the endpoint to close, launch a fresh server, and reconnect.
- A healthy first run may attach to an already-running compatible server. A recognized legacy server may be used safely, but if it cannot perform identity-verified self-shutdown, restart onto a free fallback port instead of killing a process.
- Retry/backoff and port scans must be bounded. Keep the Max main thread responsive.

## Verification before handoff

- Run Node syntax checks and the complete mock/smoke suite from the target repository.
- Verify Max 2022/2027 inventory, routing, cancellation, execution, panel actions, screenshots, UI discovery/invoke, semantic tools, control probe/shutdown, bootstrap restart/recovery, log layout/style, and Box example safety.
- Run `git diff --check`, scan for stale identity strings, unexpected globals, unfinished-work markers, and inspect `git status --short`.
- Do not remove migrated source artifacts until the destination is complete and all required checks pass. Preserve unrelated files and user changes.
