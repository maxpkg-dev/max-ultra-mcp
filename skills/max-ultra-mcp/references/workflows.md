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
3. Call `max_redraw_viewports` after a scene or display-mode change.
4. Call `max_capture_viewport` and inspect the returned image, viewport type, camera metadata, and dimensions.

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
4. Prefer AutomationId, parent chain, class/control type, and accessible name. Localized text is weaker; coordinates are the final reviewed fallback.
5. Set fields with `max_ui_set_value` or `max_ui_select` and invoke with `max_ui_invoke`.
6. Wait for the expected state change, inspect again, then verify the scene and capture the viewport or window.

Reinspect after a window is recreated. Never reuse an HWND or selector without process ownership validation.

## Floor plan interpreted from an image

1. Interpret dimensions in the model and produce structured plan data in millimeters. The source image remains in the conversation.
2. Do not change the scene's system units.
3. Ask one concrete question when critical geometry cannot be determined reliably.
4. Call `max_validate_floor_plan` and resolve every blocker.
5. Call `max_build_floor_plan` with the unchanged payload and returned validation token.
6. Capture top and perspective views, compare them with the plan, and use undo before rebuilding when a clear error is found.
7. Report wall, opening, door, and window counts plus the verified model bounds.

## Read-only connection check

1. `max_list_instances` and explicit selection when needed.
2. `max_health`.
3. `max_scene_summary`.
4. `max_capture_viewport`.

Do not run MaxScript, render, save, or mutate the scene during a connection check.
