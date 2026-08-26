---
name: max-ultra-mcp
description: Control and inspect already-open Autodesk 3ds Max scenes through Max Ultra MCP. Use for scene, viewport, rendering, MaxScript, Max-owned UI automation, or structured floor-plan tasks when Max Ultra MCP tools are available. Do not use for editing the Max Ultra MCP repository itself.
---

# Max Ultra MCP

Use the semantic MCP surface to produce a verified result in the selected 3ds Max process. Keep raw MaxScript and UI automation as explicit fallbacks, not the default implementation path.

## Operating workflow

1. Call `max_list_instances`. When several instances are connected, ask the user which one to use unless the request already identifies it, then call `max_select_instance`.
2. Call `max_capabilities` before renderer-, plugin-, import/export-, or profile-dependent work.
3. Read the smallest useful state with `max_scene_summary`, `max_query_scene`, or a domain-specific read tool.
4. Prefer a semantic tool with structured arguments and post-state evidence. Respect write approval, `dryRun`, validation tokens, scene revisions, and NodeRefs when the selected tool exposes them.
5. Run mutations serially. Do not assume a write succeeded from transport success alone.
6. Verify the post-state. For visual changes, call `max_capture_viewport` after framing the relevant objects or camera and inspect the returned image.

## Tool priority

Use the first applicable level:

1. A semantic Max Ultra MCP tool.
2. `max_run_macro`, `max_run_action`, or `max_run_script_file` for an existing registered operation.
3. `max_run_script` for a small, reviewable MaxScript operation.
4. `max_execute` only when no narrower tool fits.
5. Max-owned UI Automation only when the operation is available solely through a UI or a third-party rollout.

Never generate MaxScript merely to recreate an available semantic tool. Never use UI coordinates when a semantic operation, macro/action identifier, or stable Automation selector is available.

## Conditional references

- Read [references/maxscript.md](references/maxscript.md) before authoring MaxScript for `max_run_script` or `max_execute`.
- Read [references/workflows.md](references/workflows.md) for multi-step viewport, rendering, floor-plan, script-rollout, and verification sequences.
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
- `UI_ELEMENT_NOT_FOUND`: inspect the confirmed Max-owned window again and rebuild the selector from stable fields.
- `BRIDGE_DOWN`, `MAX_NOT_CONNECTED`, or control authentication failure: report the connection problem without attempting scene mutations.
