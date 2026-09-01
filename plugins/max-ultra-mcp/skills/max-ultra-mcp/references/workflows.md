# Verified Workflows

Use these sequences as decision guides. Skip steps that do not apply, but preserve discovery, approval, and post-state verification.

## Scene mutation

1. `max_scene_summary` to record the current scene revision and basic state.
2. Query or select targets using semantic tools and retain their NodeRefs.
3. Call the narrowest mutation tool with the reviewed arguments.
4. Inspect returned handles, counts, properties, warnings, and scene revision.
5. Query the changed state. Frame the result and call `max_capture_viewport` when visual confirmation is meaningful.

Do not reacquire a stale node by name after `STALE_NODE_REF`. Query again and use the new NodeRef.

## Viewport inspection

1. Set or activate the requested view with `max_set_view` or `max_activate_camera`.
2. Use `max_frame_selection` or `max_zoom_extents` when the subject is not already framed.
3. If a free perspective angle is needed, switch to `perspective`, frame the subject, and use the reviewed `viewport.rotate` fallback in [maxscript.md](maxscript.md). Use small yaw/pitch steps and never orbit an active camera view; move or rotate the camera explicitly instead.
4. Choose the capture preset:
   - `clean-realistic` is the default for materials, composition, lighting, architectural form, and general visual review.
   - `clean-shaded` removes material interpretation from topology, silhouette, junction, opening, and normal-orientation checks.
   - `clean-current` preserves an intentionally chosen diagnostic style such as wireframe while still removing visual clutter.
5. Call `max_redraw_viewports` after changing the view or display mode.
6. Call `max_capture_viewport` with the chosen preset and inspect the returned image, viewport type, camera metadata, dimensions, preset, and restore status.

Capture always maximizes the active viewport. It temporarily hides the grid, edged faces, selected edged faces, selection brackets, selection and hover overlays/outlines, and raises Nitrous anti-aliasing to 8X. It restores those display settings after saving the image and leaves only the viewport maximized. Do not recreate this preparation with arbitrary MaxScript.

For visual composition, capture after each meaningful angle adjustment. Compare the image with the requested subject placement, then apply another small orbit rather than guessing a large correction. For A/B comparisons, keep the view, framing, review preset, and lighting identical.

### Final showcase capture for chat

Use this sequence when the purpose of the screenshot is to present the finished work attractively to the user, rather than to diagnose topology, normals, selection, or UI behavior.

1. Recall the scene summary recorded before the work. When the scene was empty and the completed result is exactly one visible object, clear selection with `max_select_objects` using `mode:"clear"` and an empty `nodes` array.
2. Call `max_zoom_extents` so the single result fills the active viewport. In a pre-existing or multi-object scene, frame only the intended result or use its reviewed camera instead of exposing unrelated scene content.
3. Ensure no workflow-owned modal dialog, context menu, rollout, tooltip, transform gizmo, or temporary helper obscures the result. Do not close unrelated user windows merely to clean the image.
4. Call `max_redraw_viewports`, then `max_capture_viewport` with `reviewPreset:"clean-realistic"`. Capture maximizes the active viewport and temporarily removes the grid, selection brackets, selected edges, selection and hover outlines, and other supported viewport clutter.
5. Inspect the returned image before presenting it. Repeat only when the object is clipped, too small, obscured, badly framed, or shown from an unhelpful angle.

Do not use this showcase cleanup for evidence that specifically needs selected nodes, edged faces, wireframe, gizmos, plugin windows, or before/after diagnostic state. Do not mutate the user's persistent viewport preferences for a screenshot; rely on the temporary capture preset and its restore result.
## Production render


1. Call `max_capabilities` and `max_render_settings_get`.
2. Apply only reviewed resolution, frame, and output changes through `max_render_settings_set`.
3. Call `max_render_start` and retain the returned job id.
4. Use `max_render_status` or bounded `max_render_wait` without blocking unrelated MCP discovery.
5. Use `max_render_cancel` when the user requests cancellation or a stopping condition is reached.
6. Call `max_render_get_result` only after successful completion and inspect the returned image.

Never invent progress when the renderer reports none. Renderer-specific interactive operations require an advertised capability.

## Script rollout and UI Automation

1. Run the reviewed script with `max_run_script_file`.
2. Wait for its top-level Max-owned window using `max_ui_wait`.
3. Inspect the window with `max_ui_inspect`; use `max_ui_find` when a stable selector can be formed.
4. Retain the verified decimal HWND when the agent must capture or diagnose that exact standalone dialog.
5. Prefer AutomationId, parent chain, class/control type, and accessible name. Localized text is weaker; coordinates are the final reviewed fallback.
6. Set fields with `max_ui_set_value` or `max_ui_select` and invoke with `max_ui_invoke`.
7. Wait for the expected state change, inspect again, then verify the scene and capture the viewport or exact window.

Call `max_ui_capture_window` with only `window.hwnd` when other Max windows could overlap the intended evidence. Call `max_ui_diagnostics` with the same HWND for bounded UIA/native WinForms trees and available WebBrowser layout, scroll, zoom, and DPI metrics. Reinspect after a window is recreated. Never reuse an HWND or selector without process ownership validation.

## Read-only connection check

1. `max_list_instances` and explicit selection when needed.
2. `max_health`.
3. `max_scene_summary`.
4. `max_capture_viewport`.

Do not run MaxScript, render, save, or mutate the scene during a connection check.
