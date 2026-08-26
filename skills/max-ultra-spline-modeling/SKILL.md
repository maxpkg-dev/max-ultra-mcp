---
name: max-ultra-spline-modeling
description: Create and edit open or closed SplineShape curves in an already-open Autodesk 3ds Max scene through Max Ultra MCP. Use for paths, outlines, profiles, bezier curves, logos, and source shapes for Extrude or Sweep. Use max-ultra-floor-plan for dimensional architectural plans and max-ultra-mcp polygon guidance for mesh-only topology.
---

# Max Ultra Spline Modeling

Model reviewable spline topology through Max Ultra MCP. There is no generic semantic spline-construction tool in v1, so use `max_run_script` with one bounded, generated MaxScript block after confirming the target instance and scene units.

## Modeling decisions

1. Decide whether each curve is an open path or closed profile before generating knots.
2. Keep coordinates object-local when practical and use the node transform for placement.
3. Use `#corner #line` for exact polygonal paths. Use smooth or Bezier knot types only when curvature is intentional.
4. Put separate contours in separate splines inside one SplineShape when they belong to one profile.
5. Reverse inner closed contours relative to the outer contour when they must become holes after capping or extrusion.
6. Preserve the current system and display units. Convert explicit physical values with `units.decodeValue`.

Read [references/maxscript-patterns.md](references/maxscript-patterns.md) before generating or editing spline MaxScript.

## Operating workflow

1. Call `max_list_instances` and explicitly select the target when several Max instances are connected.
2. Call `max_get_info` and record scene units and scene revision.
3. Convert the request into reviewed contour data: positions, knot types, segment types, closed flags, optional handles, node position, and intended modifier workflow.
4. Generate one bounded `max_run_script` operation. Validate names, numbers, knot counts, and all externally supplied strings before embedding them.
5. Create a SplineShape, call `addNewSpline` once per contour, add knots in order, close only reviewed closed contours, and call `updateShape` after construction.
6. Return verifiable post-state: node handle, exact name, class, spline count, knot counts, closed flags, and bounding box.
7. Frame the result, capture the viewport, and inspect the curve from a useful view. Use a second angle for non-planar 3D paths.

## Source preservation

When the requested result remains an editable SplineShape, the created spline itself is the source and no redundant copy is required.

Before applying Extrude, Sweep, Loft-related conversion, `convertToMesh`, `convertToPoly`, or a destructive modifier collapse:

1. Keep the original SplineShape unchanged as the source object.
2. Copy it to a separately named working object.
3. Store the source handle on the working object with a user property.
4. Apply modifiers and collapse only the working copy.
5. Hide the source only after the working result is verified; never delete it automatically.

This invariant also applies when a spline is reconstructed from a reference image or imported outline and later becomes geometry.

## Editing existing splines

- Resolve the target by NodeRef handle and verify `isValidNode` plus the SplineShape-compatible class immediately before mutation.
- Treat spline and knot indices as operation-local. Re-query counts after insert, delete, weld, reverse, detach, or topology-changing commands.
- Use explicit weld tolerances in physical units. Do not apply a scene-wide or guessed tolerance.
- Keep one named undo transaction around the complete edit.
- Return the same measured post-state as creation and capture the viewport when the shape changed visually.

## Boundaries

- Do not route architectural wall, door, window, and floor construction through this generic skill; use `max-ultra-floor-plan`.
- Do not collapse a source spline merely to make viewport verification easier.
- Do not add rendering thickness, Extrude, Sweep, interpolation changes, or normalization unless the request requires them.
- Do not use UI Automation for ordinary spline construction or sub-object edits.
- Do not save the scene unless the user explicitly requests it.

