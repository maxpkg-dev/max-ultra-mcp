# House plan from an attached image

This example demonstrates the complete vision-to-3ds-Max workflow.

When the prompt does not explicitly override a value, readable dimension labels and scale information in the attached plan are authoritative. Defaults apply only to values absent from both sources; ambiguous critical dimensions require one specific user question before validation.

- `plan-example.png` is the dimensioned input attached to ChatGPT or Codex.
- `PROMPT.md` is the ready-to-use English prompt.
- `expected-plan.json` is a deterministic normalized interpretation used by tests and manual comparison.
- `expected-result.png` is an AI-generated visual reference, not proof from 3ds Max. A real run must return its own viewport screenshots through `max_capture_viewport`.

## Expected tool sequence

1. `max_list_instances`; `max_select_instance` when needed.
2. `max_validate_floor_plan` with the interpreted JSON.
3. Resolve blockers instead of guessing critical dimensions.
4. `max_build_floor_plan` with the unchanged JSON and `validationToken`.
5. `max_set_view`, `max_zoom_extents`, and `max_capture_viewport` for top and perspective checks.
6. If normals still look globally reversed, capture an identical A/B view with `max_add_normal_modifier`, then immediately `max_undo` the diagnostic modifier.
7. Repeat validation/build if visual comparison exposes a geometry mistake.

The builder keeps current 3ds Max system units unchanged and converts every millimeter value with `units.decodeValue`. It preserves a hidden joined wall-footprint SplineShape, copies and extrudes a separate working object, and creates outward-facing opening-aware Editable Poly topology through `meshOp` in one undo transaction. Corners are mitered, branch walls stop at receiving wall faces, the floor extends to the outside wall envelope, and no opening Dummy helpers remain. No Boolean operations, furniture, door models, or window models are added in v1.

## Deterministic acceptance values

- Centerline perimeter: 10000 × 8000 mm.
- Finished exterior wall and floor envelope: 10300 × 8300 mm.
- Wall height: 3000 mm.
- Exterior/interior thickness: 300/150 mm.
- Walls: 7.
- Doors: 4.
- Windows: 5.
- Floor slab: 200 mm.
