# House plan from an attached image

This example demonstrates the complete vision-to-3ds-Max workflow.

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
6. `max_undo` and repeat validation/build if visual comparison exposes a mistake.

The builder keeps current 3ds Max system units unchanged and converts every millimeter value with `units.decodeValue`. Walls are built from box segments around openings in one undo transaction. Door and window locations receive named Dummy placeholders; no Boolean operations, furniture, door models, or window models are added in v1.

## Deterministic acceptance values

- Outer dimensions: 10000 × 8000 mm.
- Wall height: 3000 mm.
- Exterior/interior thickness: 300/150 mm.
- Walls: 7.
- Doors: 4.
- Windows: 5.
- Floor slab: 200 mm.
