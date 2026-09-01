# MaxScript Programming Rules

Read this reference completely before creating or editing a persistent MaxScript source file. These are the portable MaxScript rules used by Max Ultra MCP, adapted from the repository coding rules and the official MaxPkg code rules. They prevent common parser, scope, path, UI, and lifecycle failures without imposing Max Ultra product identity on unrelated user projects.

## Rule precedence

1. Inspect the target project before editing.
2. Read its `AGENTS.md`, `.agents/coding-rules.md`, `code-rules.md`, contribution guide, and nearby source conventions when present.
3. Follow the target project's stricter rules first.
4. Use this reference for every uncovered MaxScript decision.
5. For MaxPkg adaptation, also use `max-ultra-maxpkg-packaging`; its live-fetched official `code-rules.md` and prompt govern package-specific behavior.

Do not add 3DGROUND attribution, a Max Ultra product name, or another author's copyright to a user's project unless that project already requires it or the user explicitly requests it.

## Preserve behavior and scope

- Read the complete relevant script, helpers, rollouts, macros, callbacks, settings, and installer integration before changing architecture.
- Keep changes focused on the requested behavior.
- Preserve runtime features, settings, callbacks, compatibility logic, and user data unless a change is explicitly requested.
- Do not turn a one-off script into a startup script, MacroScript, persistent callback, installer, or network client without authorization.
- Do not delete or replace user files merely because a new script artifact or package is created.

## Safe identifiers

MaxScript identifiers are case-insensitive and can collide with built-ins, rollout clauses, properties, types, and context-sensitive keywords.

Avoid short ambiguous identifiers such as:

- `path`, `text`, `name`, `section`, `icon`, `ok`, `value`;
- `result`, `item`, `data` when a role-specific name is practical;
- `open` and `close` for function names.

Prefer names such as `sourceFilePath`, `messageContent`, `packageName`, `iniSectionName`, `isSuccessful`, `operationResult`, and `sceneNodeData`. Name booleans as questions or states and collections by their contents. Never create identifiers that differ only by capitalization.

## Functions, scope, and structure

- Declare temporary state with `local`.
- Minimize globals and prefix every unavoidable project global consistently.
- Group related data in a focused `struct` instead of undocumented parallel arrays.
- Define every helper before any function, rollout handler, callback, or generated script that calls it.
- Give every value-producing or success/failure function an explicit `return`.
- Keep each function focused and use early guard returns when they clarify failure.
- Put the opening parenthesis on the same line as its owner and align the closing parenthesis.
- Wrap each complete `if` test in parentheses. Use `do` without `else`; use `then` only when an `else` follows.
- Use `for index in 1 to count do (...)` for numeric ranges. Do not use assignment-style loops.
- Check collection bounds before indexing and delete selected indexes in descending order.
- Do not use mapped `copy` on arrays.
- Format named arguments exactly as `argumentName: argumentValue`.

## Strings and generated source

- Use `+` for string concatenation. Reserve `format` for intentional formatted stream output.
- Convert non-string values explicitly.
- Prefer verbatim literals for reviewed static Windows paths.
- Escape quotes, backslashes, newlines, and externally supplied content at the boundary before generating source.
- Never concatenate raw user prose, object names, or paths into executable MaxScript.
- Treat generated MaxScript, macros, and cleanup files as production source. Inspect their final text, not only the generator.

## Files and paths

- Resolve helpers and read-only resources relative to the executing script with `getFilenamePath (getThisScriptFileName())` unless the verified execution context requires another API.
- Do not hard-code developer-machine paths, user names, drive letters, current 3ds Max versions, or temporary package GUID folders.
- Distinguish source, destination, package-relative, installed, and user-writable paths by name.
- Normalize paths at clear boundaries and verify a file or directory before using it.
- Default to refusing overwrite. Never delete a directory until its resolved ownership and exact target are verified.
- Save plain source as UTF-8 `.ms`; do not disguise plain source with an `.mse` extension.
- When MaxScript must create a source file, use `createFile ... encoding:#utf8 writeBOM:false`, close the stream on success and failure, and verify the written file.

## Errors and cleanup

- Use `try/catch` only when the fallback or cleanup behavior is understood.
- Do not hide a required failure in an empty `catch`.
- Preserve the original exception text in actionable diagnostics.
- Stop when continuing could leave partial output, modify the wrong scene, or delete the wrong file.
- Empty catches are acceptable only for bounded best-effort cleanup or truly optional UI work.
- Make install, uninstall, callback, and settings initialization idempotent where practical.

## 3ds Max and UI safety

- Run scene, viewport, renderer, MaxScript UI, WinForms, and UIAccessor work on the 3ds Max main thread.
- Do not move Max APIs into a background worker. Background work may perform transport or pure computation only.
- Keep transport, processing, and UI state separate.
- Avoid unbounded callbacks, timers, scene scans, waits, and retries.
- Follow the target UI's established rollout layout and avoid absolute `pos:` placement when standard layout controls are reliable.
- For .NET text input, manage `enableAccelerators`, preserve Tab navigation, configure multiline behavior explicitly, and never bind the same event repeatedly when a rollout reopens.
- Restore temporary UI, viewport, selection, and accelerator state in cleanup paths.

## Verification before execution or handoff

1. Review the final diff and search for stale identifiers, old control names, hard-coded paths, unfinished markers, and accidental globals.
2. Check helper definition order, explicit returns, collection bounds, string escaping, and every required file check.
3. Load or parse the script in a supported real 3ds Max version when available.
4. Test both success and failure paths in a disposable scene or fixture; never use an automated test on a real user scene.
5. Verify UI reopen/close behavior, repeated event registration, callbacks, timers, and cleanup when applicable.
6. Inspect generated scripts and package artifacts as final files.
7. Report exactly which Max versions and runtime paths were tested. Do not claim real-Max compatibility from static inspection alone.

Sources:

- [Max Ultra MCP repository coding rules](https://github.com/maxpkg-dev/max-ultra-mcp/blob/main/.agents/coding-rules.md)
- [Official MaxPkg MaxScript coding rules](https://github.com/maxpkg-dev/max-dev-tool/blob/main/code-rules.md)

