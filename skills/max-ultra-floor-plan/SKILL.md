---
name: max-ultra-floor-plan
description: Build dimensional 3D architectural floor plans in an already-open Autodesk 3ds Max scene through Max Ultra MCP. Use for plans interpreted from images, drawings, or explicit wall dimensions when the result needs walls, door/window openings, and a floor. Do not use for generic polygon objects or read-only plan analysis.
---

# Max Ultra Floor Plan

Create the plan through the structured floor-plan tools and preserve a reversible modeling lineage. The source image stays in the conversation; send only reviewed dimensions and topology to Max Ultra MCP.

## Required modeling lineage

The wall model must follow this order:

1. Create the complete two-dimensional wall footprint as a SplineShape.
2. Preserve that object as the source spline. Do not add modifiers, collapse, delete, or edit it after validation.
3. Copy the source spline into a separate working wall object.
4. Apply Extrude to the working copy and collapse only that copy to Editable Mesh.
5. Create the opening-aware wall topology through `meshOp` on the working copy, then convert it to Editable Poly.

`max_build_floor_plan` implements this sequence. Its returned `modelingWorkflow` must be `spline-copy-extrude-meshop`. Retain `sourceSplineName` and `wallMeshName` as post-state evidence. The source spline is hidden to keep the viewport clean, but it remains in the scene as the recoverable two-dimensional source of truth.

Do not replace this workflow with Box walls, destructive edits to the source spline, or Boolean cutters. Named door and window placeholders are references; the wall mesh must already contain the corresponding openings.

## Operating sequence

1. Call `max_list_instances`; explicitly select an instance when several are connected.
2. Call `max_get_info` and read scene units. Never change system or display units.
3. Interpret the supplied plan into structured millimeter data. Ask one concrete question when a critical dimension cannot be determined reliably.
4. Read [references/plan-schema.md](references/plan-schema.md) before assembling the payload.
5. Call `max_validate_floor_plan`. Resolve every blocker and review warnings.
6. Optionally call `max_build_floor_plan` with `dryRun:true` to inspect the intended script and post-state without changing the scene.
7. Call `max_build_floor_plan` with the unchanged payload and validation token.
8. Verify the reported workflow, source spline name, wall mesh name, wall/opening counts, bounds, and scene revision.
9. Set a top view, frame the result, and call `max_capture_viewport`. Then inspect a perspective view and capture again.
10. Compare both images with the source plan. If the geometry is clearly wrong, call `max_undo`, correct the structured payload, validate again, and rebuild.

## Boundaries

- Keep mutations serial and respect the AI client's normal write approval.
- Never infer a critical wall, opening, or scale dimension merely to avoid asking the user.
- Do not bake the plan origin into every interpreted wall when the structured `origin` field expresses it correctly.
- Do not modify or delete the preserved source spline during later material, modifier, or furnishing work.
- Do not claim a visual match until top and perspective screenshots have been inspected.
- Do not save the scene unless the user explicitly requests it.

