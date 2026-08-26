# Prompt for ChatGPT or Codex

Attach `plan-example.png` to the conversation and send the following prompt:

```text
Analyze the attached dimensioned house-plan image and build it in the open
Autodesk 3ds Max instance through Max Ultra MCP.

1. Identify the exterior outline, interior walls, doors, and windows.
2. Use millimeters. Do not change the system units of the existing scene.
3. Treat readable dimensions, dimension chains, legends, and scale marks printed
   in the attached plan as the source of truth unless this prompt explicitly
   overrides a value. Do not replace a readable label with a pixel estimate.
4. If a critical dimension is unreadable, cropped, conflicting, or cannot be
   derived unambiguously from labelled dimensions, do not guess it. Ask me one
   specific question first.
5. Use these defaults only when the value is absent from both this prompt and
   the attached plan:
   wall height: 3000 mm;
   exterior wall thickness: 300 mm;
   interior wall thickness: 150 mm;
   door height: 2100 mm;
   window sill height: 900 mm;
   window height: 1400 mm;
   floor slab thickness: 200 mm.
6. Represent the recognized plan using the max_validate_floor_plan schema.
7. Call max_validate_floor_plan first and report only actual blockers.
8. If there are no blockers, call max_build_floor_plan with the unchanged plan
   and the returned validationToken.
9. Call max_set_view for a top view, then call max_capture_viewport.
10. Switch to a perspective view, call max_zoom_extents, and capture the viewport again.
11. Check that wall faces are consistently visible, corners are clean, branch
    walls stop at receiving wall faces, and the floor reaches the outside wall edges.
12. If the walls appear globally inside-out, call max_add_normal_modifier with
    flip:true on the wall mesh and capture the exact same perspective view.
    Immediately call max_undo after that comparison. Reapply the modifier only
    when the flipped version is consistently correct on exterior, interior, and
    opening faces.
13. Compare the accepted screenshots with the source plan. If there is a clear
    geometry error, call max_undo, correct the structured plan, validate it again,
    and rebuild it.
14. Finally, report the model bounds, wall/door/window/segment counts, normal
    orientation result, junction counts, confirm that no opening helpers remain,
    and identify which dimensions came from prompt overrides, drawing labels,
    derived dimension chains, or defaults.
```

The model analyzes the image itself. MCP does not receive the source image bytes;
only the normalized plan JSON is sent to the server.
