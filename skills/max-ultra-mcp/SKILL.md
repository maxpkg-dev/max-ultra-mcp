---
name: max-ultra-mcp
description: Use Max Ultra MCP when the user asks to create, edit, inspect, render, or otherwise work in Autodesk 3ds Max, their 3D program, or their 3D editor. Covers scene, file, modeling, viewport, rendering, MaxScript, and Max-owned UI workflows; use focused Max Ultra skills for specialized work. Do not use for editing the Max Ultra MCP repository itself.
---

# Max Ultra MCP

Use `max-ultra-renderer-settings` for renderer configuration based on runtime property introspection. Use `max-ultra-camera-composition` for camera placement, Safe Frame, lens, and visual-composition tasks. Use `max-ultra-maxpkg-packaging` when a new or existing script must be adapted, configured, built, or verified for MaxPkg. Keep this general skill for ordinary scene, viewport, file, script, and diagnostic work.

Use the semantic MCP surface to produce a verified result in the selected 3ds Max process. Keep raw MaxScript and UI automation as explicit fallbacks, not the default implementation path.

For reference-driven character, creature, product, or prop subdivision modeling, use `max-ultra-character-object-modeling`. For spline paths, profiles, and source shapes, use `max-ultra-spline-modeling`. For dimensional architectural floor plans, use `max-ultra-floor-plan` so its stricter wall-source preservation workflow is loaded.

## Operating workflow

1. Treat a natural request such as"��y��y�make X in 3ds Maz��y��y�,"��y��y�do X in my 3D prograk�u���], or+�u���\change X in the 3D editor��y��y� as intent to use Max Ultra MCP. Call `max_list_instances` immediately.
2. With no connected instance, ask exactly one short question telling the user to open 3ds Max and run `01_START_MAX_ULTRA_MCP_FIRST.ms`; do not attempt a mutation. With exactly one instance, call `max_select_instance` for it.
3. With several instances, select one without asking only when the request uniquely matches returned evidence such as version or scene. Otherwise ask exactly one short question naming the concise choices, and do not work in an uncertain window.
4. Call `max_capabilities` before renderer-, plugin-, import/export-, or profile-dependent work.
5. Read the smallest useful state with `max_scene_summary`, `max_query_scene`, or a domain-specific read tool.
6. Prefer a semantic tool with structured arguments and post-state evidence. Respect write approval, `dryRun`, validation tokens, scene revisions, and NodeRefs when the selected tool exposes them.
7. Run mutations serially. Do not assume a write succeeded from transport success alone.
8. Verify the post-state. For every visual check, frame the relevant objects or camera and call `max_capture_viewport`; never use an unmaximized raw viewport bitmap as final evidence. Use the default `clean-realistic` review preset unless topology, normals, or an intentionally selected diagnostic style requires another preset, then inspect the returned image. Before presenting a finished result in chat, follow the final showcase sequence in the workflows reference listed below.

## Tool priority

Use the first applicable level:

1. A semantic Max Ultra MCP tool.
2. `max_run_macro`, `max_run_action`, or `max_run_script_file` for an existing registered operation.
3. `max_run_script` for a small, reviewable MaxScript operation.
4. `max_execute` only when no narrower tool fits.
5. Max-owned UI Automation only when the operation is available solely through a UI or a third-party rollout.

Never generate MaxScript merely to recreate an available semantic tool. Never use UI coordinates when a semantic operation, macro/action identifier, or stable Automation selector is available.

## Conditional references

- Read [references/code-rules.md](references/code-rules.md) completely before creating or editing a persistent MaxScript source file, rollout, MacroScript, callback, generated script, or reusable `max_run_script` body.
- Read [references/maxscript.md](references/maxscript.md) before authoring MaxScript for `max_run_script` or `max_execute`.
- Read [references/polygon-modeling.md](references/polygon-modeling.md) when synthesizing custom polygon topology from dimensions, a reference image, or a modeling request.
- Read [references/scene-files-and-scripts.md](references/scene-files-and-scripts.md) before creating, opening, saving, merging, or resetting scenes; managing XRefs or File Properties; or creating a persistent script file.
- Read [references/workflows.md](references/workflows.md) for multi-step viewport, rendering, script-rollout, and verification sequences.
- Read [references/capabilities-and-boundaries.md](references/capabilities-and-boundaries.md) for renderer/plugin detection, filesystem operations, profiles, UI scope, or an unavailable semantic workflow.

## Boundaries

- Treat scene open/new/reset/save/merge, arbitrary scripts, filesystem writes, renders, and UI mutations as writes requiring the client's normal approval flow.
- Do not change system units to satisfy an input unit. Convert values within the operation.
- Do not operate on a node by name alone when a NodeRef or handle is available.
- Do not control an HWND outside the selected `3dsmax.exe` process.
- Do not claim renderer or plugin support when capability discovery cannot verify it.
- Images attached to the conversation are interpreted by the model. Send structured measurements to MCP; do not send source image bytes to 3ds Max.
- Keep user paths, scene names, assets, and diagnostic output out of generated documentation unless the user explicitly needs those local values.

## Error recovery

- `INSTANCE_REQUIRED`: list instances and select one explicitly.
- `STALE_NODE_REF`: query the scene again and reacquire the target; do not silently fall back to a same-named node.
- `VALIDATION_FAILED`: correct blockers and validate again before applying.
- `RENDERER_UNSUPPORTED`: report the missing capability or offer a reviewed generic alternative; never imitate success.
- `UI_ELEMENT_NOT_FOUND`: re-run `max_ui_list_windows` or `max_ui_inspect`, then retry with a fresh Max-owned HWND. Pass that HWND directly to `max_ui_capture_window`; use `max_ui_diagnostics` when bounded UI Automation/native WinForms or WebBrowser metrics are needed.
- `BRIDGE_DOWN`, `MAX_NOT_CONNECTED`, or control authentication failure: report the connection problem without attempting scene mutations.
