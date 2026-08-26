# MaxScript Escape-Hatch Reference

Read this reference only when a semantic MCP tool, registered macro/action, or script file cannot perform the requested operation.

## Execution choice

| Need | Preferred tool |
| --- | --- |
| Existing `.ms` or `.mse` file | `max_run_script_file` |
| Registered MacroScript | `max_run_macro` |
| Known Action Table command | `max_run_action` |
| Small reviewable script with a returned value | `max_run_script` |
| Advanced unrestricted escape hatch | `max_execute` |

All arbitrary MaxScript execution is open-world and potentially destructive. Client approval is not a sandbox. Execute only the reviewed operation and return evidence that can be checked afterward.

## Script shape

Use one block, descriptive locals, a bounded undo transaction for scene writes, and a compact final value:

```maxscript
(
    local targetNode = maxOps.getNodeByHandle 12345
    if (not (isValidNode targetNode)) do throw "Target node no longer exists"

    undo "Max Ultra MCP: Update target" on (
        targetNode.pos.x += units.decodeValue "100mm"
    )

    #("handle", targetNode.handle, "position", targetNode.pos)
)
```

- Do not add globals, callbacks, timers, persistent rollouts, startup scripts, or scene event handlers unless the user explicitly requests persistent behavior.
- Do not catch and discard an operational exception. Let the bridge return the failure or return an explicit structured failure value.
- Keep loops bounded. Do not enumerate large scenes repeatedly when one pass can collect the required nodes.
- All code invoked through Max Ultra MCP already runs on the 3ds Max main thread. Do not move scene or UI API calls into a .NET worker thread.

## Stable command patterns

| Purpose | MAXScript pattern | Notes |
| --- | --- | --- |
| Resolve a node handle | `maxOps.getNodeByHandle handleValue` | Verify with `isValidNode` immediately before mutation. |
| Resolve a reviewed name | `getNodeByName nodeName exact:true` | Names are fallback identifiers and may not be unique over time. |
| Inspect selection | `selection as array` | Do not change selection during analysis unless requested. |
| Select nodes | `select nodeArray` / `clearSelection()` | Prefer `max_select_objects` when available. |
| Create primitives | `box`, `sphere`, `cylinder`, `plane` | Prefer semantic creation tools for validation and NodeRef output. |
| Add a modifier | `addModifier targetNode modifierInstance` | Detect class availability before construction. |
| Delete nodes | `delete nodeArray` | Keep deletion inside one named undo transaction. |
| Convert a physical value | `units.decodeValue "250mm"` | Preserve the existing system and display unit settings. |
| Redraw viewports | `redrawViews()` | Prefer `max_redraw_viewports`. |
| Zoom extents in the active viewport | `max tool zoomextents` | Prefer `max_zoom_extents`. Do not use the nonexistent `max zoomext all` command. |
| Zoom extents in every viewport | `max tool zoomextents all` | Use only when changing every viewport is explicitly intended. |
| Orbit active viewport | `viewport.rotate rotationQuat` | Perspective/user views only; use the reviewed pattern below. |
| Capture active viewport | `viewport.getViewportDib()` | Prefer `max_capture_viewport`, which maximizes first and returns MCP image content. |
| Run a MacroScript | `macros.run categoryName macroName` | Prefer `max_run_macro`. |
| Run an Action Table item | `actionMan.executeAction tableId persistentId` | Use only verified IDs; prefer `max_run_action`. |
| Run a script file | `executeScriptFile absolutePath errormessage:&errorText` | Prefer `max_run_script_file`; use an approved absolute path. |

## Orbit before capture

Use `max_set_view` for standard top/front/side/perspective views and `max_activate_camera` for a camera. When a free perspective angle is necessary, first frame the subject, then run a small reviewed orbit:

```maxscript
(
    if (viewport.getType() != #view_persp_user and viewport.getType() != #view_iso_user) do (
        if (not (viewport.setType #view_persp_user)) do throw "Could not activate a perspective viewport"
    )

    local yawDegrees = 15.0
    local pitchDegrees = -10.0
    if (not (viewport.rotate (quat yawDegrees [0,0,1]))) do throw "Viewport yaw failed"
    local viewRightAxis = normalize (viewport.getTM()).row1
    if (not (viewport.rotate (quat pitchDegrees viewRightAxis))) do throw "Viewport pitch failed"
    completeRedraw()
    true
)
```

Positive/negative values turn in opposite directions. Keep each change small, call `max_capture_viewport`, inspect the image, and repeat if needed. `viewport.rotate` does not operate on camera/light object views; transform the camera or light intentionally instead. Do not use mouse coordinates or UI Automation for normal viewport orbiting.

## Values, strings, and paths

- Use locale-independent numeric literals with a period as the decimal separator.
- Escape externally supplied string content before embedding it in a script. Do not concatenate raw names, paths, or user prose into executable source.
- Use verbatim literals such as `@"C:\Example\Asset.png"` for reviewed static Windows paths. When generating source dynamically, escape quotes and do not assume a verbatim literal can contain arbitrary content safely.
- Return simple MAXScript values that the bridge can describe: booleans, numbers, strings, names, points, arrays, or a compact property list. Return handles and measured post-state instead of entire scene objects.

## Dynamic execution

Avoid `execute` and `fileIn` inside arbitrary scripts when the MCP tool can execute the intended text or file directly. `safeExecute` is not a substitute for the product's approval and validation boundary, and unrestricted `max_execute` intentionally remains powerful.

## Rendering and UI

Do not call a blocking raw `render()` when the user needs status, cancellation, or image retrieval; use the asynchronous render tools. Do not use MaxScript mouse coordinates to operate plugin dialogs. Use process-scoped UI Automation with a freshly inspected selector.

## Official Autodesk references

- [MAXScript context expressions and undo](https://help.autodesk.com/cloudhelp/2027/ENU/MAXScript-Help/files/MAXScript-Language-Reference/Names-Literal-Constants-and/GUID-E672728A-EE15-4197-9EDD-487781167B01.html)
- [Units struct and `units.decodeValue`](https://help.autodesk.com/cloudhelp/2027/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/Interacting-with-the-3ds-Max/Units/GUID-DB50F450-C3D1-47A5-98A2-A34601710034.html)
- [`maxOps.getNodeByHandle`](https://help.autodesk.com/cloudhelp/2027/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Interfaces/Core-Interfaces/Core-Interfaces-Documentation/M/GUID-48C5E2F2-DE34-4EA3-A84C-4DBD463DBF90.html)
- [MacroScript execution](https://help.autodesk.com/cloudhelp/2023/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/Interacting-with-the-3ds-Max/Macro-Scripts/GUID-3DC75DDE-E4BC-4033-ABA9-A42063036CB9.html)
- [Action Manager](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/Interacting-with-the-3ds-Max/Action-Manager-and-Shortcut/GUID-38CB8317-6EB2-49D1-A086-B06BA2A141AE.html)
- [Running script files](https://help.autodesk.com/cloudhelp/2026/ENU/MAXScript-Help/files/MAXScript-Introduction/Accessing-MAXScript/GUID-86D82FCE-B88F-4487-9B34-B6222EDA1C71.html)
- [Viewport bitmap capture](https://help.autodesk.com/cloudhelp/2024/ENU/MAXScript-Help/files/MAXScript-Language-Reference/Values/Bitmap-Values/GUID-9F6ABEE1-0728-4B39-8903-D909634C1304.html)
- [Active viewport transforms and `viewport.rotate`](https://help.autodesk.com/cloudhelp/2023/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/Interacting-with-the-3ds-Max/Viewports/GUID-8AA71F9E-F4F0-4437-A44E-9683619E89DE.html)
- [3ds Max commands](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/Interacting-with-the-3ds-Max/GUID-A96857E7-73FE-4F42-BE71-E8185356F4C9.html)
- [String and path literals](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/MAXScript-Language-Reference/Names-Literal-Constants-and/Literal-Constants/GUID-7F17449E-C377-445C-AC15-CD3BA88A975B.html)
