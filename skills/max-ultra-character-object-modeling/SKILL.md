---
name: max-ultra-character-object-modeling
description: Build a character, creature, product, prop, or other reference-driven subject as one professional subdivision-ready Editable Poly through Max Ultra MCP. Use when likeness, silhouette, quad topology, deformation flow, and a non-collapsed one-iteration TurboSmooth result matter. Do not use for architectural floor plans, spline-only work, or requests that are accurately represented by a true primitive.
---

# Max Ultra Character and Object Modeling

Reconstruct the subject from reviewed vertex positions and polygon faces. The accepted result is one coherent Editable Poly node with a deliberate middle-poly control cage and a non-collapsed TurboSmooth modifier. Do not imitate the subject by arranging boxes, cylinders, spheres, capsules, or other visible primitives.

Read [references/subdivision-topology.md](references/subdivision-topology.md) before generating topology.

## Reference and shape analysis

1. Call `max_list_instances`, select explicitly when needed, then call `max_get_info` and `max_capabilities`. Preserve scene units and require the `full` tool profile for generic modifier access.
2. Treat explicit user dimensions as authoritative. Otherwise infer proportions from supplied references. Ask one concrete question when an unseen side or critical proportion cannot be reconstructed reliably.
3. Identify primary masses, silhouette landmarks, centerline, major cross-sections, hard/soft transitions, openings, articulation zones, and intentional asymmetry before defining vertices.
4. Choose a middle-poly density that describes the silhouette and required deformations without relying on TurboSmooth to invent missing form.
5. Plan loop routes, poles, boundary loops, support loops, material boundaries, and areas where density may change before creation.

## Required construction workflow

1. Build one complete object-local vertex array and zero-based polygon-face array with `subdivisionReady:true`. Set `requireSingleShell:true` only when the subject must be one physically continuous surface. Do not call `max_create_primitive` for subject geometry.
2. When bilateral symmetry is appropriate, design one side and mirror its data before submission. Weld the centerline by sharing center vertex indices; do not leave overlapping halves or separate mirrored nodes.
3. Keep the cage quad-dominant. Use triangles only where controlled and place poles away from silhouette-critical and deforming regions. Split n-gons before submission.
4. Call `max_validate_polygon_mesh`. Resolve all blockers and review every boundary, winding, isolated-vertex, shell, valence, quad-ratio, and planarity result.
5. Call `max_create_polygon_mesh` with the unchanged payload and token. Verify the NodeRef, Editable Poly class, bounds, counts, and open-edge count.
6. Inspect the unsmoothed cage from front, side, and three-quarter views with maximized screenshots. Correct silhouette, proportions, spacing, winding, intersections, and topology before subdivision.
7. Check normal orientation on every custom shell. Use `max_add_normal_modifier` only as an identical-view A/B test, undo it, and keep Flip only when the entire shell is consistently corrected.
8. If the cage has incorrect planar shading, add `max_add_smooth_modifier` with `threshold:30` and Auto Smooth enabled. Keep it only when the identical-view comparison removes artifacts without smoothing intended hard edges.
9. Add TurboSmooth with `max_add_modifier`, exactly one viewport iteration, `useRenderIterations:false`, and no collapse. TurboSmooth must remain above any retained Normal or Smooth modifier.
10. Capture the same views again and compare cage versus subdivided result. Revise and rebuild when there is pinching, volume loss, lumpy highlights, a broken silhouette, or poor deformation flow. Never hide bad topology with extra iterations.

## Acceptance standard

- The subject reads correctly in silhouette before TurboSmooth.
- The result is one named Editable Poly node, not a primitive assembly.
- Continuous surfaces share vertices and edges; there are no accidental overlaps, duplicate shells, zero-area faces, isolated vertices, or non-manifold edges. Multiple intentional polygon Elements may exist inside the same Editable Poly node for genuinely separate parts.
- Quads form useful loops with gradual density changes. Poles are intentional and placed in low-deformation, low-curvature areas.
- Character joints and facial features have deformation-aware loops. Hard-surface edges have support loops with deliberate, visually consistent spacing.
- Hard-surface overlays, inserts, trims, fasteners, and floating panels may be separate polygon Elements inside the same Editable Poly node. Each Element must have deliberate clearance or thickness, clean boundaries, and subdivision support.
- TurboSmooth uses one iteration, remains live in the stack, and does not replace the middle-poly source cage.
- Final screenshots show clean shading, correct normals, stable highlights, and requested likeness from multiple useful views.

## Boundaries

- Do not create primitive placeholders as the delivered model and do not claim a primitive assembly is professional polygon modeling.
- Do not collapse Editable Poly, Normal, Smooth, or TurboSmooth unless the user explicitly requests destructive finalization.
- Do not increase TurboSmooth beyond one iteration merely to make the surface look finished.
- Do not create separate scene nodes for eyes, teeth, clothing, panels, accessories, or floating details unless requested. They may be intentional polygon Elements inside the one subject mesh when the reference has physically separate parts.
- Do not weld physically separate parts merely to force one connected shell. Report the final Element count and the purpose of each disconnected Element.
- Do not leave coplanar overlay faces, z-fighting surfaces, hidden duplicate panels, or accidental interpenetration between Elements.
- Do not add UVs, materials, rigging, sculpt detail, or animation unless requested.
- Do not save the scene unless the user explicitly requests it.
