# Capabilities and Boundaries

## Profiles

- `core` covers connection, scene, objects, viewport, production rendering, scripts, diagnostics, and Max-owned UI Automation.
- `archviz` adds materials and structured floor-plan validation/build.
- `full` adds layers, modifiers, import/export, and animation helpers.

Use `max_capabilities` and the client's advertised tool list as runtime truth. Do not assume a tool is available because it appears in documentation for another profile or release.

## Renderers and plugins

- Detect the selected Max version, active renderer, plugin hints, and supported operations before using renderer-specific behavior.
- Generic production rendering may work when a renderer-specific interactive adapter does not.
- Treat plugin class names and properties as versioned capabilities, not universal constants.
- Return or report `RENDERER_UNSUPPORTED` when an operation cannot be verified.
- Do not substitute standard 3ds Max render elements for a renderer-specific element and claim equivalence.

## Filesystem and scene lifecycle

Opening, saving, merging, importing, exporting, script-file execution, render output, and other file operations are open-world. Use an explicit user-approved path and preserve overwrite behavior. Never infer permission to replace a scene or output merely because the directory exists.

For an unsaved or dirty scene, do not reset, open another file, or start a batch workflow without explicit authorization that addresses the current work.

## UI Automation

UI tools may operate only on windows owned by the selected `3dsmax.exe` PID. The MCP boundary revalidates ownership, but the agent must still:

- select the intended Max instance first;
- inspect the current window instead of guessing selectors;
- wait for enabled/visible state before mutation;
- treat a recreated control as a new target;
- visually or semantically verify the result.

Do not use UI Automation to control ChatGPT, Codex, Explorer, a browser, or any other process.

## Semantic workflow availability

Some production workflows may be documented as acceptance requirements before their dedicated tools are implemented. Confirm the live tool list before promising semantic support. If no dedicated tool exists:

1. explain that the semantic workflow is unavailable in the connected build;
2. offer a read-only investigation when possible;
3. offer a reviewed `max_run_script` or `max_execute` fallback only when the task can be implemented safely and the user approves arbitrary script execution;
4. do not represent the fallback as equivalent to a validated plan/apply workflow.

## Confirmation and stopping conditions

- Read-only inspection can proceed without scene-write authorization.
- Use the MCP client's normal confirmation for annotated write or destructive tools.
- Ask for new authorization before expanding from scene inspection to filesystem mutation, batch processing, or persistent UI/plugin changes.
- Stop a retry loop after the reported error repeats without a changed input or external state. Report the exact blocker and preserve the scene.
