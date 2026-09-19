---
name: max-ultra-small-house-detailing
description: Create or refine houses and interior architectural assemblies in Autodesk 3ds Max through Max Ultra MCP. Use for roofs, facades, fitted furnishings, floor finishes, ceilings, windows, doors, moldings, and ornament placement from plans or references, including individual details in apartments and other interiors. Use max-ultra-floor-plan for wall-shell and opening-layout construction. Does not produce construction documentation.
---

# Max Ultra House and Interior Architectural Detailing

Start from a supplied plan, dimensions, and visual references, or continue an existing house scene, to create coherent, editable architectural assemblies. For a new house, establish the dimensional shell through the floor-plan skill before adding roofs, facades, and requested furnishings. This is architectural 3D modeling, not construction documentation or engineering certification. This workflow adapts architectural skills supplied by Yuriy Bobak (Bobak Studio). The supplied notes describe one 3ds Max 2027 / Corona 15 Hotfix 2 session; they are evidence for checks to perform, not universal plugin behavior or building specifications. Scene coordinates, asset choices, dimensions, and render presets from that session are intentionally excluded.

The same assembly checks apply to an apartment, another interior, or a single requested detail; they do not require building a complete house. Additional workflow contributions supplied by Anastasiia Reznichenko inform the floor, opening, trim, and UV references; see [attribution and source terms](ATTRIBUTION.md). Use the current brief and scene, not the source projects' dimensions, layer numbering, renderer, or approval history.

## Establish scope and geometry

1. Follow [max-ultra-mcp](../max-ultra-mcp/SKILL.md) for instance discovery and selection, current capabilities, serial mutations, NodeRefs, and verified script fallbacks. Read current scene units, bounds, layers, renderer, and affected geometry. Never reuse historical handles or change system units. Start in the selected scene without clearing unrelated contents; a request for a house is not permission to reset an existing scene.
2. For a new house, derive the dimensional wall/opening/floor plan from the available inputs; resolve missing critical scale or layout information before construction. Use [max-ultra-floor-plan](../max-ultra-floor-plan/SKILL.md) when constructing dimensional walls, openings, and floors. Its dimension precedence, validation token, source spline, and wall lineage remain authoritative. The floor-plan builder does not generate complete roofs, cladding, or furnished houses.
3. Establish facade directions, ridge direction, entry, glazing, room boundaries, and reference scale. Separate measured dimensions from inferred ones. Ask about unresolved critical dimensions before dependent construction; continue independent work within the request.
4. For discrepancies, compare a top view with an interior or exterior view. Check wall ends, opening returns, furniture bounds, and camera orientation together before moving architecture to match an imported asset.
5. Preserve useful existing parts and sources. Create separate, named assemblies for the requested walls, glazing, roof, timber, drainage, furnishings, or site elements. A complete house need not be one subdivision mesh. Use the general skill's validated polygon workflow for custom mesh topology and [max-ultra-spline-modeling](../max-ultra-spline-modeling/SKILL.md) for editable profiles.

Record the finished-floor datum, relevant ceiling/opening levels, and which dimensions are measured, derived, or estimated. Convert physical values into current scene units; neither millimeters nor world Z=0 is a mandatory scene convention. Resolve missing dimensions that determine fit before dependent construction, while continuing independent authorized work. Reuse the scene's organization and preserve approved neighboring geometry and shared sources. Respect requested review boundaries; a complete authorized workflow does not require a new approval after each internal step.

## Editable architectural details

- Derive roof pitch, overhang, ridge, verge, eaves, and flashing overlaps from the current brief and references. Check the assembly from exterior and underside views; inspect wall-to-roof and gable junctions before adding small details.
- Keep repeated boards editable or instanced as appropriate. Stagger joints with useful end lengths, deliberate corner/frame termination, and no repeated column of short fragments unless specified. Decking and parquet stop at their intended boundaries, including glazing and thresholds.
- Fit gutters, outlets, downpipes, brackets, and seam details together. For standing-seam snow guards, align clamps with seams. Row counts and routes come from the project. Lightning protection and similar details are visual assemblies unless engineering is explicitly in scope; do not claim compliance from a model.
- Use planar faces and consistent winding for flat construction. Inspect normals after deformation, beveling, or conversion. Preserve correct authored normals on unchanged imported assets.
- For diagonal bands or flicker, investigate duplicates/coplanar overlaps first, then planarity, winding, explicit normals, smoothing and negative transforms, then UVs/material IDs/face randomization, then bump/displacement and reflections. Compare the same clean-shaded view. Viewport clipping can improve depth precision but cannot repair intersections; a global Flip cannot repair a partly reversed shell.

## Read detail only when needed

- For finish patterns, thresholds, backing slabs, or ceiling cutouts, read [references/floors-and-ceilings.md](references/floors-and-ceilings.md).
- For window/door assemblies, reveals, casings, sills, or plinth junctions, read [references/openings-and-joinery.md](references/openings-and-joinery.md).
- For cornices, baseboards, swept profiles, or repeated ornament, read [references/trim-and-ornaments.md](references/trim-and-ornaments.md).
- For timber UVs, materials, glass, or shading that persists after geometry checks, read [references/materials-and-review.md](references/materials-and-review.md).
- For Cosmos assets, fitted furniture, conversion failures, or saving/exporting the result, read [references/assets-and-delivery.md](references/assets-and-delivery.md).
- For camera creation or repair, use [max-ultra-camera-composition](../max-ultra-camera-composition/SKILL.md), including its camera-basis check. For renderer configuration or lighting-specific properties, use [max-ultra-renderer-settings](../max-ultra-renderer-settings/SKILL.md); discover light classes/properties as well as renderer properties before editing them.
- For reference-driven chair reconstruction, use [max-ultra-armchair-modeling](../max-ultra-armchair-modeling/SKILL.md). Furniture placement here does not replace that reconstruction workflow.

## Acceptance

Verify affected bounds, joints, clearances, material assignments, and visible orientation against the plan and references. Inspect framed top and perspective viewport captures; roof details also need underside evidence. State what was measured and what remains an approximation. A viewport check does not prove final renderer appearance.

Render only when requested or already authorized. Save/export only when requested, following the delivery reference. Creating a house does not automatically authorize a site redesign, new furniture, renderer change, scene overwrite, or extra deliverable. This skill adds workflow guidance, not new MCP tools or guaranteed Corona/Cosmos compatibility.
