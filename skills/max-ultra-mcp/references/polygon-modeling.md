# Polygon Modeling

Use the semantic polygon tools when a requested object cannot be represented accurately by a primitive or the floor-plan builder.

## Preferred workflow

1. Call `max_get_info` and read the current scene units. Do not change system or display units.
2. Design one object-local vertex array and zero-based face arrays. Put world placement in `mesh.position` instead of baking the same offset into every vertex.
3. Call `max_validate_polygon_mesh` with the complete mesh payload.
4. Resolve every blocker. Review open-edge, winding, isolated-vertex, and non-planar n-gon warnings.
5. Call `max_create_polygon_mesh` with the unchanged mesh payload and returned `validationToken`.
6. Verify the returned NodeRef, actual vertex/edge/face/open-edge counts, and Editable Poly class.
7. Frame the object, use wireframe or smooth shading as appropriate, capture at least two useful viewport angles, and inspect the images.

Use a primitive semantic tool when it represents the requested shape without custom topology. Do not generate a dense mesh merely to reproduce a box, plane, sphere, or cylinder.

## Mesh payload

- `vertices` are object-local `[x,y,z]` points.
- `faces` use zero-based vertex indices. A face can be an index array or `{vertices, materialId, smoothingGroup}`.
- `units:"scene"` treats numbers as current system units. Prefer an explicit physical unit such as `mm`, `cm`, `m`, `in`, or `ft` when dimensions come from a drawing or prompt.
- `position` is the node translation in the same declared units.
- Vertex winding controls the normal. Viewed from outside, use counter-clockwise winding.
- `allowNonManifold` defaults to false. Enable it only when an edge shared by more than two faces is intentional.

Example closed quad cube:

```json
{
  "name": "MCP_Model_Cube",
  "units": "mm",
  "vertices": [
    [-500, -500, -500], [500, -500, -500],
    [500, 500, -500], [-500, 500, -500],
    [-500, -500, 500], [500, -500, 500],
    [500, 500, 500], [-500, 500, 500]
  ],
  "faces": [
    [0, 3, 2, 1], [4, 5, 6, 7],
    [0, 1, 5, 4], [1, 2, 6, 5],
    [2, 3, 7, 6], [3, 0, 4, 7]
  ],
  "position": [0, 0, 500],
  "layer": "MCP_MODELING",
  "select": true
}
```

## Topology decisions

- Prefer quads for surfaces intended for later subdivision and triangles where tessellation must be explicit.
- Split concave or visibly non-planar n-gons into reviewed triangles or quads. 3ds Max can triangulate an n-gon differently from the model's assumption.
- Share vertex indices across faces that must be welded. Duplicate vertices intentionally at disconnected shells or when topology requires a split.
- Keep material IDs positive and aligned with the intended Multi/Sub-Object slots. A material assignment is a separate operation.
- A boundary warning is expected for an intentionally open surface. It is suspicious for a closed solid.
- Inconsistent winding is not automatically repaired because reversing the wrong face can invert a deliberate shell.

The synchronous v1 path accepts at most 10,000 vertices, 20,000 polygons, 256 vertices per polygon, and 100,000 total face-vertex references. Use import or a future asynchronous geometry job for larger topology.

## Iteration and edits

`max_create_polygon_mesh` creates new topology; it does not rewrite an arbitrary existing object's sub-object structure. For a procedural modeling pass, keep the reviewed structured payload, undo the previous creation when necessary, revise the arrays, validate again, and rebuild with the new token.

Use existing transform, modifier, material, layer, clone, and selection tools after creation. When a narrow edit to an existing Editable Poly has no semantic tool, read [maxscript.md](maxscript.md), resolve the target by NodeRef, and use a small reviewed `polyOp` or `meshOp` fallback. Never insert raw user prose into executable MaxScript, and never treat guessed sub-object indices as stable after a topology-changing operation.

## Implementation behavior

The creator builds an Editable Mesh from object-local points, adds polygons through `meshop.createPolygon`, and converts the result to Editable Poly. Bulk polygon creation runs with inner undo disabled to avoid a complete mesh copy for every face, while object creation remains one named outer undo record. Physical unit conversion uses `units.decodeValue` and never changes scene units.

Official references:

- [Custom mesh construction](https://help.autodesk.com/cloudhelp/2024/ENU/MAXScript-Help/files/How-To-Practical-Examples/GUID-BFE0D012-E8F6-4903-B3C5-ABDA06F4F18C.html)
- [`meshop.createPolygon` and bulk undo guidance](https://help.autodesk.com/cloudhelp/2021/ENU/3DSMax-MAXScript/files/GUID-D05BCFB5-BD5A-4B17-B053-64841171A8C8.htm)
- [Editable Poly create methods](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Editable-Meshes-Splines-Patches/Editable_Poly/Editable_Poly-Methods/GUID-1B692115-DBBF-4D06-8B05-BFF7296BECCA.html)
