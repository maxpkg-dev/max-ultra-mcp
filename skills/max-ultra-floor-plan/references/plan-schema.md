# Structured Plan Schema

Use millimeters. Wall coordinates describe two-dimensional centerlines; wall thickness expands on both sides of each centerline. Opening offsets are measured from the referenced wall's `start` point toward its `end` point.

## Required plan data

- `units` must be `mm` in v1.
- `origin` is a two-dimensional placement offset.
- `wallHeight` applies to all generated walls.
- Every wall requires a unique `id`, `start`, `end`, and positive `thickness`.
- Every opening requires a unique `id`, a valid `wallId`, `type`, `offsetFromStart`, `width`, and `height`.
- A window also requires `sillHeight`; a door is normalized to a zero sill.
- Openings on one wall must not overlap or extend beyond that wall.
- The optional floor uses a closed `outline` and positive downward `thickness`.

Example:

```json
{
  "units": "mm",
  "origin": [0, 0],
  "wallHeight": 3000,
  "walls": [
    { "id": "W1", "start": [0, 0], "end": [6000, 0], "thickness": 300 },
    { "id": "W2", "start": [6000, 0], "end": [6000, 4000], "thickness": 300 },
    { "id": "W3", "start": [6000, 4000], "end": [0, 4000], "thickness": 300 },
    { "id": "W4", "start": [0, 4000], "end": [0, 0], "thickness": 300 }
  ],
  "openings": [
    {
      "id": "D1",
      "wallId": "W1",
      "type": "door",
      "offsetFromStart": 1200,
      "width": 900,
      "height": 2100,
      "sillHeight": 0
    },
    {
      "id": "WIN1",
      "wallId": "W2",
      "type": "window",
      "offsetFromStart": 1400,
      "width": 1600,
      "height": 1400,
      "sillHeight": 900
    }
  ],
  "floor": {
    "enabled": true,
    "thickness": 200,
    "outline": [[0, 0], [6000, 0], [6000, 4000], [0, 4000]]
  }
}
```

## Interpretation checks

- Establish one reliable scale or dimension chain before deriving coordinates from an image.
- Keep exterior and interior thicknesses distinct when the drawing distinguishes them.
- Orient each wall deliberately because opening offsets depend on start-to-end direction.
- Confirm that the opening top does not exceed `wallHeight`.
- Preserve connected endpoints where walls meet; the builder extends wall ends by half thickness to cover ordinary corners.
- Treat unclear diagonal, curved, stepped, or multi-level walls as blockers unless their intended geometry is explicit.

## Builder post-state

The builder returns:

- `sourceSplineName`: the hidden, unchanged SplineShape source.
- `wallMeshName`: the visible Editable Poly working result.
- `modelingWorkflow`: `spline-copy-extrude-meshop`.
- Validated wall, door, window, and opening counts.
- Generated wall-piece and placeholder counts.
- The expected model bounding box and updated scene revision.

After creation, inspect the actual viewport. Structured post-state proves the executed workflow and expected counts, but it does not prove that image interpretation was visually correct.

