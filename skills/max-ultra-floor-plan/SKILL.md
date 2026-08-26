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

Do not replace this workflow with Box walls, destructive edits to the source spline, or Boolean cutters. The wall mesh must contain the openings directly. No door/window Dummy helpers should remain after the build.

## Operating sequence

1. Call `max_list_instances`; explicitly select an instance when several are connected.
2. Call `max_get_info` and read scene units. Never change system or display units.
3. Resolve dimensions using the precedence rules below, then interpret the supplied plan into structured millimeter data. Ask one concrete question when a critical dimension cannot be determined reliably.
4. Read [references/plan-schema.md](references/plan-schema.md) before assembling the payload.
5. Call `max_validate_floor_plan`. Resolve every blocker and review warnings.
6. Optionally call `max_build_floor_plan` with `dryRun:true` to inspect the intended script and post-state without changing the scene.
7. Call `max_build_floor_plan` with the unchanged payload and validation token.
8. Verify the reported workflow, source spline name, wall mesh name, wall/opening counts, bounds, and scene revision.
9. Set a top view, frame the result, and call `max_capture_viewport` with `reviewPreset:"clean-shaded"`. Then use a perspective view, frame the same wall mesh, and capture a baseline image with the same preset.
10. Inspect exterior faces, interior faces, opening reveals, wall junctions, floor perimeter, and every custom roof or gable created for the plan. The floor must reach at least the outside faces of perimeter walls, and a branch wall must stop at the receiving wall face instead of penetrating it.
11. For any wall, gable, roof, slab, or other custom shell that appears inside-out, call `max_add_normal_modifier` with `flip:true` and capture the exact same view. Immediately call `max_undo` after the comparison. Reapply Flip only when the second image is consistently correct across the complete shell, including its exterior and underside.
12. After normal orientation is accepted, check custom geometry for false gradients, diagonal bands, faceting, or broken planar highlights. Call `max_add_smooth_modifier` with `threshold:30` and capture the identical view. Keep Auto Smooth only when it removes the artifact without softening intended hard edges.
13. Compare the final top and perspective images with the source plan. If geometry is clearly wrong, call `max_undo`, correct the structured payload, validate again, and rebuild.

## Normal-orientation review

The builder returns `normalOrientation: "outward"` and creates wall faces with outward winding. Dark shading alone is not proof of flipped normals because viewport lighting, material settings, and backface display can produce similar results.

Use the Normal modifier only as an A/B diagnostic. Keep camera/view, framing, viewport mode, and lighting unchanged between screenshots. Review every generated custom shell, not only the wall mesh. A roof comparison must include the exterior slopes, eaves, gables, and underside; a wall comparison must include both sides and opening reveals. `max_add_normal_modifier` deliberately sets `unify:false`: Autodesk documents that Normal-modifier Unify does not work on Editable Poly. If only some faces remain reversed, treat that as a topology defect and rebuild; do not leave a global Flip modifier as a partial repair.

## Shading review

Correct normals before evaluating smoothing. Dark or missing faces indicate orientation or topology; Smooth cannot repair a flipped shell.

For manually generated non-primitive geometry, compare the same clean-shaded view before and after `max_add_smooth_modifier`. The default uses Auto Smooth with a 30-degree threshold and keeps Prevent Indirect Smoothing off. This assigns smoothing groups by the angle between adjacent faces and is appropriate for the planar and folded custom meshes common in roofs, gables, slabs, and architectural details.

Keep the modifier only when planar faces shade cleanly and intended corners remain sharp. If smoothing leaks across a corner, retry with `preventIndirect:true` or correct the topology/smoothing groups. Never use Smooth to hide overlapping faces, non-planar n-gons, duplicate geometry, or wrong normals.

## Dimension source precedence

1. A dimension or constraint explicitly stated by the user in the current prompt overrides the attached drawing.
2. Otherwise, readable dimension labels, grids, legends, and scale marks in the attached plan image are the source of truth.
3. Derive an unlabelled distance from a complete labelled dimension chain or a clearly stated image scale only when that derivation is unambiguous.
4. Use workflow defaults only for values genuinely absent from both the prompt and the drawing, such as wall height when the plan contains only two-dimensional dimensions.

Never replace a readable printed dimension with a pixel-proportion estimate. If labels conflict, a dimension chain does not close, the image is cropped, or a critical label is unreadable, stop before validation and ask one specific question. Record which values came from the prompt, drawing labels, derived chains, and defaults in the final summary.

## Boundaries

- Keep mutations serial and respect the AI client's normal write approval.
- Never infer a critical wall, opening, or scale dimension merely to avoid asking the user.
- Do not bake the plan origin into every interpreted wall when the structured `origin` field expresses it correctly.
- Do not modify or delete the preserved source spline during later material, modifier, or furnishing work.
- Do not leave opening helpers, comparison-only modifiers, or other temporary diagnostic nodes in the accepted result.
- Do not claim a visual match until top and perspective screenshots have been inspected.
- Do not save the scene unless the user explicitly requests it.
