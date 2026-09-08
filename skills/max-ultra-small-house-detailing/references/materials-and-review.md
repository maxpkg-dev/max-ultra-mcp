# Architectural Materials and Review

## Assignment and runtime support

Run `max_material_find_unassigned` before changing assignments. Inspect the active renderer with `max_renderer_properties_get` before renderer-specific configuration and inspect actual material/map classes and supported properties before editing them. Discover shared materials and maps; clone for matched objects when a change would otherwise affect unmatched nodes.

If the audit fails or times out, do not repeat it indefinitely or call it complete. A small result limit does not establish a cheap scan. Use a bounded targeted read of affected nodes, face material IDs, Multi/Sub slots, map inputs, and file existence when available, and disclose incomplete coverage. Stop dependent edits if the required state cannot be established.

## Timber mapping

- Locate the user's actual wood asset and verify texture paths and channel roles. Keep color, roughness, normal/bump, and masks spatially aligned, using the appropriate color-space handling for each input.
- Align UVs to each board's longitudinal axis. Review broad faces, sides, and end grain separately; box mapping alone does not demonstrate correct end grain. Preserve one consistent convention between map Real World Scale and mapping modifiers.
- Change only the requested texture axis. Distinguish feature size from repeat count: multiplying feature size by a factor requires dividing repeats by that factor. Read back the current mapping before applying relative changes.
- Randomize subtly per board, object, or coherent element with stable variation, using inspected map capabilities. Per-triangle randomization can expose diagonal shading on an otherwise flat board.
- Separate concave contact dirt from edge wear. Avoid outlining every board in black or using strong bump to disguise poor joints.

## Glass and lighting review

Inspect duplicated panes, intersections, thickness, normals, roughness/bump, absorption, and interface count before attributing noise to exposure. Preserve the requested reflective and transparent appearance. Material opacity cannot repair a missing wall; removing refraction is not a reliable way to transmit light.

The source session's glass speed observation was not a controlled benchmark. Do not promise a speedup or reuse a ray-switch recipe. If simplification is requested, preserve the original geometry/material, inspect current renderer support, scope the alternative to the intended view, and compare camera, resolution, exposure, denoising, and stopping criteria consistently. Use actual render statistics and visual evidence.

Match lighting references through direction, softness, sky balance, and contrast. Preserve existing exposure and tone-mapping overrides unless the requested edit needs them; inspect the effective camera/VFB values. A clay review should retain intended glass behavior. Use cancellable render tools for authorized comparisons, not a blocking raw render call.
