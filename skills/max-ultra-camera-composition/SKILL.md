---
name: max-ultra-camera-composition
description: Create, position, and visually verify cameras in an already-open Autodesk 3ds Max scene through Max Ultra MCP. Use for architectural, interior, exterior, product, or subject framing where render aspect, Safe Frame, lens choice, perspective, and composition matter. Do not use for free perspective viewport inspection that does not create or modify a camera.
---

# Max Ultra Camera Composition

Compose against the final render frame, not the arbitrary viewport rectangle. Activate the camera and enable Safe Frame before judging position, rotation, lens, subject coverage, or negative space. Keep Safe Frame enabled throughout every comparison screenshot.

## Operating workflow

1. Call `max_list_instances`; explicitly select the target when several Max instances are connected.
2. Call `max_get_info`, `max_capabilities`, and `max_render_settings_get`. Record scene units, scene revision, renderer, output size, and aspect.
3. Confirm the intended output orientation and aspect. Change resolution with `max_render_settings_set` only when requested or when existing settings cannot satisfy the task. Do not change scene units.
4. Resolve the subject and important foreground/background objects by NodeRef. Use scene bounds and user intent to define the focal point, edge clearance, horizon, verticals, and intentional negative space.
5. Reuse the requested camera. Otherwise evaluate existing cameras and create one with `max_create_primitive` only when no suitable camera exists. Use a unique descriptive name.
6. Position and rotate it with `max_transform_object`. Adjust supported camera properties through one bounded `max_run_script` operation only when semantic tools do not expose them. Prefer moving the camera before forcing an extreme lens.
7. Call `max_activate_camera`, then deterministically set `displaySafeFrames = true` with [references/composition-workflow.md](references/composition-workflow.md). Never use Shift+F or another toggle whose prior state is unknown.
8. Call `max_redraw_viewports`, then `max_capture_viewport` with the `clean-realistic` review preset. The capture must remain in the active camera view, show Safe Frame, and use the maximized viewport supplied by the tool.
9. Inspect only the rendered live area inside the outer Safe Frame. Apply one small camera or lens correction at a time, reactivate the camera if needed, redraw, and capture again.
10. Stop when the requested constraints are met and successive changes no longer improve the image. Return the camera NodeRef, transform, lens or FOV, render size and aspect, Safe Frame state, decisions, and final image evidence.

## Composition rules

- When the task has one newly created or explicitly isolated object, use single-object framing by default: aim at the center of its world bounding box, center it in the Safe Frame, keep the complete object visible on every side, and use an even margin. Do not offset it to a thirds intersection unless the user requests a stylized composition or reserved negative space.
- Choose one primary visual subject and make its hierarchy obvious before optimizing secondary details.
- Use thirds, centered symmetry, diagonals, leading lines, or intentional negative space according to the subject. Do not force thirds onto a composition that is stronger when centered.
- Keep important geometry clear of the frame edge unless edge tension is intentional. For animation or broadcast delivery, honor action/title guides requested by the user.
- Preserve believable verticals and horizon placement in architectural views. Avoid accidental roll and converging verticals unless intentional.
- Build depth with foreground, subject, and background layers without obscuring the subject.
- Check clipping, intersections, excessive empty space, tangencies, distracting bright areas, and objects cut by the frame.
- Treat focal length as a perspective decision, not merely a zoom control. Move the camera and reassess before using an extreme FOV.
- Never use perspective-viewport orbit commands in a camera view. Modify the camera transform explicitly so the result is reproducible and renderable.

## Boundaries

- Safe Frame is mandatory before the first composition judgment and must still be enabled for the accepted screenshot.
- A single-object acceptance screenshot must prove that the entire object fits inside Safe Frame; selection, helpers, or unrelated scene objects must not affect its framing bounds.
- Render resolution defines Safe Frame proportions. Never judge final composition at an unrelated aspect.
- Do not mutate an existing camera, render resolution, or lens when the user asked only for analysis.
- Keep mutations serial, preserve NodeRef scene revisions, and use normal write approval.
- Do not add animation, depth of field, exposure, clipping planes, or renderer-specific effects unless requested.
- Do not save the scene unless the user explicitly requests it.
