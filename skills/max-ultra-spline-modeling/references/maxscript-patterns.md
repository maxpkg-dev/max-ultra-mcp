# Spline MaxScript Patterns

Generate literals from validated structured data. Never insert raw user prose, unescaped names, or unchecked paths into executable MaxScript.

## New SplineShape

Use one outer block and one named undo transaction. This straight-segment example shows the required construction order; adapt the reviewed values rather than copying them blindly.

```maxscript
(
    fn mm value = units.decodeValue ((value as string) + "mm")

    local shapeName = "MCP_Profile_SOURCE"
    if (getNodeByName shapeName exact:true != undefined) do throw (shapeName + " already exists")

    local createdShape = undefined
    undo "Max Ultra MCP: Create spline profile" on (
        createdShape = splineShape name:shapeName
        addNewSpline createdShape
        addKnot createdShape 1 #corner #line [mm 0, mm 0, mm 0]
        addKnot createdShape 1 #corner #line [mm 2000, mm 0, mm 0]
        addKnot createdShape 1 #corner #line [mm 2000, mm 1000, mm 0]
        addKnot createdShape 1 #corner #line [mm 0, mm 1000, mm 0]
        close createdShape 1
        updateShape createdShape
        setUserProp createdShape "MaxUltraMCPRole" "SplineSource"
        select createdShape
    )

    #(
        "handle", getHandleByAnim createdShape,
        "name", createdShape.name,
        "class", classOf createdShape.baseObject,
        "splines", numSplines createdShape,
        "knots", numKnots createdShape 1,
        "closed", isClosed createdShape 1,
        "bounds", #(createdShape.min, createdShape.max)
    )
)
```

Always call `updateShape` after adding, moving, deleting, reversing, opening, or closing spline topology.

## Knot and segment selection

- `#corner #line`: exact polyline corner and straight outgoing segment.
- `#smooth #curve`: automatically smooth curved knot when exact tangent handles are not required.
- `#bezier` or `#bezierCorner`: explicit curve control. Supply reviewed in/out handle positions to `addKnot`; do not invent handles from prose when curvature is dimension-critical.
- The segment type belongs to the segment leaving the knot. Review the final knot carefully on closed splines.

For precise curves, store each knot as structured data containing `point`, `knotType`, `segmentType`, and optional `inVec` and `outVec`. Reject unsupported combinations before script generation.

## Multiple contours and holes

Call `addNewSpline` for every contour and address splines with one-based indices. Keep outer and inner loops separate. For a capped profile, orient holes opposite to the outer contour; use `reverse shape splineIndex` only after the desired winding is known.

Check each contour independently:

- at least two knots for an open path;
- at least three non-collinear knots for a closed profile;
- no accidental duplicate consecutive knots;
- no closure call for an intended open path;
- no self-intersection unless it is deliberate and supported by the downstream modifier.

## Non-destructive modifier workflow

Copy before a modifier or conversion changes the source representation:

```maxscript
(
    local sourceHandle = 12345
    local sourceShape = maxOps.getNodeByHandle sourceHandle
    if (not (isValidNode sourceShape)) do throw "Source spline no longer exists"
    if (superClassOf sourceShape != Shape) do throw "Target is not a shape"

    local workingShape = undefined
    undo "Max Ultra MCP: Extrude spline copy" on (
        workingShape = copy sourceShape
        workingShape.name = uniqueName (sourceShape.name + "_WORK")
        setUserProp workingShape "MaxUltraMCPSourceHandle" (sourceHandle as string)
        addModifier workingShape (Extrude amount:(units.decodeValue "300mm"))
    )

    #("sourceHandle", sourceHandle, "workingHandle", getHandleByAnim workingShape, "workingName", workingShape.name)
)
```

Do not convert or collapse `sourceShape`. If a later operation requires Editable Mesh or Editable Poly, convert only `workingShape` and verify its class afterward.

## Editing an existing shape

Resolve by handle, validate the class, and keep topology changes in one undo record. After any operation that renumbers knots or splines, stop using previous sub-object indices and query again.

Prefer direct spline functions such as `setKnotPoint`, `setInVec`, `setOutVec`, `setKnotType`, `setSegmentType`, `close`, `open`, `reverse`, and `updateShape`. Use `splineOps` only when its selection-dependent behavior is explicitly prepared and verified.

## Verification

Return compact measured evidence rather than the entire node:

- node handle and exact name;
- base-object class;
- `numSplines`;
- `numKnots` and `isClosed` for every contour;
- node bounding box;
- source and working handles when modifiers are involved.

Then use `max_frame_selection`, `max_set_view`, and `max_capture_viewport` for visual verification.

Official Autodesk references:

- [SplineShape and spline methods](https://help.autodesk.com/cloudhelp/2025/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Editable-Meshes-Splines-Patches/SplineShape/GUID-6C6A35EB-DD5F-40C1-9869-0938849F6842.html)
- [Drawing a spline with `addNewSpline`, `addKnot`, and `updateShape`](https://help.autodesk.com/cloudhelp/2023/ENU/MAXScript-Help/files/How-To-Practical-Examples/GUID-0876DF46-FAA3-4131-838D-5739A67FF2C1.html)
- [Units and `units.decodeValue`](https://help.autodesk.com/cloudhelp/2027/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/Interacting-with-the-3ds-Max/Units/GUID-DB50F450-C3D1-47A5-98A2-A34601710034.html)

