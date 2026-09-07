---
name: max-ultra-armchair-modeling
description: Build or refine a reference-driven chair or armchair in Autodesk 3ds Max through Max Ultra MCP, with verified component likeness, upholstery form, and an editable subdivision cage. Use for chair and armchair reconstruction, including stock-ready requests; not for other furniture, characters, or repository editing.
---

# Max Ultra Armchair Modeling

Deliver one named Editable Poly scene node with intentional separate polygon Elements for the frame, seat, back, trims, and other physically separate parts. Preserve the editable cage and live TurboSmooth at one iteration. Mesh validity and resemblance are separate acceptance questions.

Use `max-ultra-mcp` for connection, instance selection, units, safe operations, and captures. This skill owns the chair/armchair modeling workflow instead of `max-ultra-character-object-modeling`; do not load both as competing mandatory workflows. Other furniture remains with the generic modeling skill.

## Establish the reference

Read [references/reference-and-acceptance.md](references/reference-and-acceptance.md) before reconstruction and use its comparison record throughout. Inspect the actual supplied images before searching. Establish 5-10 identifying features and a coupled dimension scheme. Manufacturer dimensions are authoritative for the specified product/version; distinguish photograph estimates and hidden-detail assumptions. Explicit user modifications take precedence over reproducing the catalog product.

Resolve uncertain visible features through targeted same-product evidence. Match viewpoint and perspective before judging geometry. Known substantial silhouette or distinctive-component errors block seams, UVs, materials, and small details. These are internal visual gates, not requests for permission at every stage.

## Construct and review incrementally

1. Call `max_list_instances`, select the only or uniquely identified instance, and inspect `max_get_info` and `max_capabilities`. Preserve scene units; generic modifier access requires the `full` profile. The live schemas remain authoritative.
2. Plan component-local cross-sections, quad loops, support spacing, joints, contact, and intentional Elements. Read [references/component-form.md](references/component-form.md) for frame and armrest construction and, when upholstered, cushion, seam, and fold construction before defining those surfaces.
3. Choose the simplest construction that accurately matches the component. A genuinely rectangular constant-section rail may start from `max_create_box` or an equivalent simple mesh, then become an Editable Poly cage with the required bevel/support topology. For custom forms, generate reviewed object-local vertices and zero-based faces with `subdivisionReady:true`. Do not substitute generic boxes for distinctive armrests or cushions. Use `requireSingleShell:true` only for an actually continuous component, never for the whole assembled chair by default.
4. For generated mesh data, validate each bounded payload with `max_validate_polygon_mesh`, resolve blockers, and create it with `max_create_polygon_mesh` using the unchanged payload and token. For both construction paths, verify NodeRefs, Editable Poly class, bounds, counts, winding, and boundaries after topology edits. Respect each call's limits; construct and review parts over multiple calls. A tool payload limit must not define the chair's complexity.
5. Inspect unsmoothed and one-iteration smoothed component views. Correct the cage for silhouette, cross-section, pinching, volume loss, and highlight-flow errors. More polygons or smoothing iterations cannot substitute for a better form.
6. Assemble reviewed components into one Editable Poly base using a narrow reviewed `max_run_script` attachment operation when no semantic tool is available. Temporary component nodes are allowed during construction. Preserve their transforms and intentional Elements; verify the assembled cage and retire only task-owned construction duplicates. Do not weld physically separate parts to force one shell or collapse a smoothed result into the cage.
7. Keep a quad-dominant cage with gradual density changes, controlled triangles, no n-gons in curved transitions, and poles away from silhouette/highlight-critical regions. Eliminate degenerate faces, isolated vertices, non-manifold edges, accidental holes, duplicate surfaces, z-fighting, and unintended intersections. Explain legitimate openings and joinery contact.
8. Keep TurboSmooth above the Editable Poly and any justified shading modifiers, using `max_add_modifier` with `iterations:1` and `useRenderIterations:false`. Do not collapse the stack or add iterations to hide errors. Correct local winding directly; retain a Normal Flip only if an identical-view comparison proves a whole shell is reversed. Retain Smooth only when an A/B comparison fixes cage shading without losing intended edges.

## Complete only the requested scope

Capture and inspect the assembled cage and smooth result from front, side, three-quarter, rear, underside, and meaningful component closeups. Use maximized `max_capture_viewport` images and a side-by-side comparison with the reference at a matched viewpoint. Document each identifying feature's evidence and remaining deviation before claiming likeness.

Geometry-only requests stay geometry-only. Explicit stock-ready requests also include UVs, checker verification, materials, and a test render unless the user limits scope to geometry. Read [references/stock-delivery.md](references/stock-delivery.md) only when that finish is requested. Save, package, export, and publish only within the requested scope; stock-ready wording does not authorize publication or promise platform compliance.

Report final node, Element count and purposes, cage/stack state, dimensions, visual comparisons, and unresolved estimates. A passed validator, quad percentage, or polygon count does not prove professional quality or likeness. Correct known material form errors; if blocked, disclose the concrete limitation and incomplete result. This workflow needs validation on an actual reconstruction; structural skill checks alone do not prove modeling effectiveness.
