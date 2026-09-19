# Floor finishes and ceiling assemblies

Use this reference only for requested finish or ceiling work. The floor-plan builder remains responsible for the dimensional wall shell and its openings, using its preserved spline, extruded copy, and meshOp workflow. Its floor slab does not establish a parquet layout or ceiling design. Inspect an existing slab before creating another.

## Layout before thickness

Establish finish zones from the actual material, pattern, level, and intended continuity. Adjacent rooms can share one coordinated pattern origin; a room name alone does not justify restarting the pattern. Read board or tile dimensions, joint width, direction, borders, and transition positions from the brief. Distinguish herringbone butt joints from chevron miters and custom panels rather than accepting a visually similar preset.

Trace closed, coplanar boundaries against receiving wall faces, including returns, doorways, and required pocket recesses. Preserve intentional voids. Use explicit corner/line knots on straight boundaries. Keep editable contours through the spline skill's source-and-working-copy workflow. Reuse suitable destination layers; do not impose a numbered layer schedule on an existing scene.

## Choose generated, custom, or combined construction

- Use an installed floor generator when its supported pattern and boundary handling match the design. Discover its class, properties, enum meanings, and angle units; do not reuse enum numbers from another installation. Max Ultra MCP has no dedicated FloorGenerator adapter. Use inspected generic modifier support or a bounded reviewed script through the selected Max instance.
- For custom panels, borders, or inlays, construct a dimensioned repeat with the general polygon or spline workflow. Verify joints, thickness, bevels, and grain direction on one sample before extending the field.
- Combine a generated field with custom thresholds or infills when useful. Trim away the corresponding generated coverage so the systems meet without overlapping solids. If a requested plugin is unavailable, explain the limitation and use an equivalent editable construction when it satisfies the brief; do not silently claim plugin output.

Preserve a continuous phase where intended. At real changes of pattern or material, fit both fields to the same threshold or border edges. Avoid slivers, doubled surfaces, and arbitrary strips inside openings. Pattern choice, joint widths, and finish levels are project inputs, not fixed architectural defaults.

## Levels and enclosure

Measure the evaluated upper surface, including extrusion and bevel contributions, relative to the finished-floor datum. Align adjoining finishes unless a step is specified. Do not infer the surface elevation from the pivot or source spline alone.

Keep any backing slab separate from the finish pieces. Fit its top below the finish build-up and its footprint to the intended enclosure, preserving courtyards, stairs, and other deliberate voids. Check gaps beneath finish joints and slab-to-wall contacts without adding an unsolicited slab to a finish-only correction.

For requested ceiling work, distinguish an upper closure slab from a suspended ceiling. Derive the visible ceiling level, thickness, cutouts, and shadow gaps from the brief and fixture layout. Keep the perimeter and hole contours coplanar, with appropriate contour winding; reject crossing or duplicate segments. Inspect actual holes after capping and thickness modifiers, including their side walls. Do not assume a Shell direction or a nested contour produced the desired result.

## Review

Check plan coverage and pattern phase, then sections or oblique close-ups of transitions, thickness, cuts, and contacts. Preserve planar faces and deliberate hard edges. Do not apply global TurboSmooth to floors or ceilings. Correct overlap, winding, or planarity before changing smoothing. Our `max_add_smooth_modifier` takes a threshold in degrees and enables Auto Smooth; it is not a setter for an external workflow's radians or disabled-Auto-Smooth recipe. Keep smoothing changes only when the relevant comparison supports them.

Recheck mapping after boundary or size edits using [materials and review](materials-and-review.md). Report uncertain dimensions and the actual checks performed; a viewport review alone does not verify final renderer appearance.
