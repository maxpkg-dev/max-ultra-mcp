# Scene, File, XRef, and Script Workflows

Read this reference for scene lifecycle operations, persistent MAXScript files, XRefs, and File > Properties. Paths and filesystem mutations are open-world. Use an explicit reviewed path and do not infer overwrite or discard permission.

## Scene lifecycle

Always call `max_scene_summary` before an operation that can replace the current scene. Record the current file path, untitled state, dirty/save-required state, object count, and scene revision.

| User intent | Preferred operation | Required guard |
| --- | --- | --- |
| Start a new empty scene | `max_scene_new` | Resolve unsaved work first. |
| Reset the current scene | `max_scene_reset` | Treat as destructive even when the scene looks empty. |
| Open a MAX file | `max_scene_open` | Require an explicit existing `.max` path and resolve unsaved work first. |
| Save the current scene | `max_scene_save` without a path | Use only when the scene already has a current MAX path. |
| Save As | `max_scene_save` with a path | Require an explicit `.max` destination and overwrite approval when it exists. |
| Merge another scene | `max_scene_merge` | Preserve the current scene and verify imported counts/names afterward. |

Use `dryRun:true` first when the semantic tool supports it and the destination or destructive effect benefits from review. A user request to open, reset, or create a scene does not by itself authorize discarding a dirty scene. Ask whether to save or discard unless the same request explicitly resolves the current work.

For `max_scene_open`, keep `useFileUnits:true` unless the user explicitly requests another unit-handling policy. Opening a file may replace the in-memory scene but must not silently change the user's persistent system-unit preference.

After every lifecycle operation:

1. Call `max_scene_summary` again.
2. Verify the current path or untitled state, object count, dirty state, and new scene revision.
3. Call `max_get_info` when units, renderer, plugins, or detailed counts matter.
4. Capture the viewport only when visual scene content is relevant.

Do not rely on Undo to recover from open, reset, or file replacement. Do not save merely because a scene operation completed successfully.

## Basic file operations

- Use `max_scene_merge`, `max_import_file`, and `max_export_file` when those semantic tools are advertised by the active profile.
- Normalize the requested path, verify the extension and parent directory, and distinguish a read source from a write destination.
- Never discover a file by scanning broad user folders when the user can provide or approve a bounded root.
- Never overwrite a different existing MAX, export, render, or script file without an explicit collision decision.
- Use the AI client's normal filesystem tools for generic copy, rename, move, or delete operations. Use MaxScript filesystem functions only when the operation must run in the selected Max process and the user explicitly approves the exact sources and destinations.
- Do not move, rename, or delete the current scene file, an active XRef source, or a referenced asset while it is in use. Save or detach safely first and verify the resulting references.
- After a merge, query the scene rather than assuming original names survived duplicate-name handling.
- A backup copy that must not become the current scene file has no dedicated semantic tool in v1. Use a narrow reviewed `max_run_script` fallback only when the user explicitly requests it; `saveMaxFile destination useNewFile:false clearNeedSaveFlag:false quiet:true` preserves the current scene identity and dirty flag.
- Batch file replacement is not an extension of a single-file request. Use a dedicated job workflow when available and obtain separate authorization for the source root, destination root, overwrite policy, and treatment of the current unsaved scene.

## XRef scenes and objects

No dedicated semantic XRef tool is present in v1. Confirm the live tool list first. When it remains unavailable, use one bounded `max_run_script` operation and return verifiable counts, source paths, unresolved references, and the created record state.

Choose the XRef type deliberately:

- Use an XRef Scene for the complete contents of another MAX file used as external context.
- Use Object XRefs when only reviewed source objects are needed. Inspect available source object names first and use `objXRefMgr`, Autodesk's preferred Object XRef interface.
- Do not merge when the user asked to keep a live external reference. Do not XRef when the user asked for editable local geometry.

A whole-scene XRef fallback can use this shape after replacing the placeholder with an approved path:

```maxscript
(
    local sourceFile = @"<ASSET_ROOT>\ExampleContext.max"
    if (not (doesFileExist sourceFile)) do throw "XRef source file does not exist"

    local countBefore = xrefs.getXRefFileCount()
    local sceneReference = xrefs.addNewXRefFile sourceFile
    if (sceneReference == undefined) do throw "3ds Max did not create the XRef Scene"

    local countAfter = xrefs.getXRefFileCount()
    local unresolvedFiles = xrefs.findUnresolvedXRefs()
    if (countAfter != countBefore + 1) do throw "XRef Scene count did not increase"

    #(countBefore, countAfter, unresolvedFiles, sceneReference.overlay, sceneReference.disabled)
)
```

Set `overlay`, `autoUpdate`, ignore flags, parent, proxy behavior, or deferred loading only when the user specifies the intended policy. For Object XRefs, call `objXRefMgr.AddXRefItemsFromFile` with `promptObjNames:false` and an explicit reviewed `objNames` or handles array. Never mix `objXRefMgr` operations with legacy `XRefObject` mutation in the same workflow.

Before updating, deleting, merging, rebinding, or changing the source of an existing XRef, enumerate the current records again. A numeric XRef index is transient; do not reuse it after another XRef mutation. Verify unresolved references with `xrefs.findUnresolvedXRefs()` and do not report success merely because `xrefs.addNewXRefFile` returned a value.

## File Properties

File > Properties is exposed through `fileProperties`; do not automate the dialog when a bounded script can operate on the data directly.

- `#summary` contains Title, Subject, Author, Keywords, and Comments.
- `#contents` contains Manager, Company, Category, and generated scene-content headers.
- `#custom` contains user-defined fields.

Read with `getNumProperties`, `getPropertyName`, `getPropertyValue`, and `findProperty`. Write or replace a value with `fileProperties.addProperty`; Autodesk does not provide a separate setter. Delete only the named reviewed field with `fileProperties.deleteProperty`.

Before changing a property, return its set, name, index, value, and type. After changing it, find and read it again. Property changes modify the scene but do not authorize saving the MAX file. Generated `#contents` statistics are refreshed when the scene is saved; do not trigger a save or Hold solely to refresh them unless the user explicitly asks.

Do not write user identity, local paths, machine names, customer data, or other sensitive values into scene metadata unless the user explicitly supplies and requests that exact metadata.

## Creating persistent MAXScript files

Create and save a script file only when the user explicitly asks for a reusable artifact or requests later execution. A one-off operation should normally remain a reviewed `max_run_script` call.

1. Agree on the exact `.ms` destination. Do not author plain source with an `.mse` extension.
2. Inspect an existing destination before replacement. Default to refusing overwrite.
3. Prefer the AI client's normal filesystem tools to write UTF-8 source. This keeps file creation separate from scene execution and makes the exact diff reviewable.
4. When no client filesystem tool is available, use one reviewed `max_run_script` FileStream writer with `createFile ... encoding:#utf8 writeBOM:false`. Escape every embedded string, close the stream on success and failure, and verify that the file exists.
5. Keep the script self-contained. Avoid globals, startup registration, callbacks, timers, persistent rollouts, external downloads, and environment discovery unless the user explicitly requests them.
6. Show or summarize the saved path, purpose, parameters, scene effects, and overwrite decision before execution.
7. Execute an approved `.ms` or `.mse` with `max_run_script_file`; use a bounded timeout and inspect the returned value or exception.
8. Verify resulting scene state and capture the viewport when visual changes were expected. Save the scene only under a separate explicit request.

If the script opens a rollout, continue with the Script rollout and UI Automation workflow in [workflows.md](workflows.md). Creating a script does not authorize installing it into startup folders, registering a MacroScript, running it immediately, deleting it afterward, or adding it to the Max Ultra MCP repository.

## Official Autodesk references

- [3ds Max file loading, saving, merging, import, and export](https://help.autodesk.com/cloudhelp/2027/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/File-Access/3ds-Max-Scene-Files-Access/GUID-624D3D05-B15D-4A97-9F15-DA35CDB0DDD2.html)
- [XRefScene values and the `xrefs` methods](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Node-MAXWrapper/XRef-Objects-and-Scenes/GUID-090B28AB-5710-45BB-B324-8B6FD131A3C8.html)
- [`objXRefMgr` Object XRef interface](https://help.autodesk.com/cloudhelp/2026/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Interfaces/Core-Interfaces/Core-Interfaces-Documentation/N-O/GUID-4822E768-D5EF-44EF-89E7-5BF5404861A2.html)
- [MAX scene File Properties](https://help.autodesk.com/cloudhelp/2026/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/File-Access/3ds-Max-Scene-Files-Access/GUID-A8663B8E-7E30-474E-B3DB-E21585F125B1.html)
- [MAXScript FileStream values](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/MAXScript-Language-Reference/Values/Stream-Values/GUID-BB041082-3EEF-4576-9D69-5B258A59065E.html)
