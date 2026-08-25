# Prompt for ChatGPT or Codex

Attach `plan-example.png` to the conversation and send the following prompt:

```text
Analyze the attached dimensioned house-plan image and build it in the open
Autodesk 3ds Max instance through Max Ultra MCP.

1. Identify the exterior outline, interior walls, doors, and windows.
2. Use millimeters. Do not change the system units of the existing scene.
3. If a critical dimension cannot be determined reliably, do not guess it.
   Ask me one specific question first.
4. Use these defaults:
   wall height: 3000 mm;
   exterior wall thickness: 300 mm;
   interior wall thickness: 150 mm;
   door height: 2100 mm;
   window sill height: 900 mm;
   window height: 1400 mm;
   floor slab thickness: 200 mm.
5. Represent the recognized plan using the max_validate_floor_plan schema.
6. Call max_validate_floor_plan first and report only actual blockers.
7. If there are no blockers, call max_build_floor_plan with the unchanged plan
   and the returned validationToken.
8. Call max_set_view for a top view, then call max_capture_viewport.
9. Switch to a perspective view, call max_zoom_extents, and capture the viewport again.
10. Compare both screenshots with the source plan. If there is a clear error,
    call max_undo, correct the structured plan, validate it again, and rebuild it.
11. Finally, report the model bounds and the number of walls, doors, windows,
    and generated wall segments.
```

The model analyzes the image itself. MCP does not receive the source image bytes;
only the normalized plan JSON is sent to the server.
