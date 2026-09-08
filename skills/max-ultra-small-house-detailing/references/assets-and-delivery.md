# Assets, Fitting, and Delivery

## Import and replacement

Check `max_capabilities` and the live tool schemas first. `max_import_file` and `max_export_file` are full-profile generic file operations, not Cosmos or renderer-conversion adapters. Dedicated asset collection, proxy conversion, and batch-export workflows remain backlog unless discovered in the live surface. Common jobs do not automatically make a raw plugin import cancellable.

Use available, licensed assets chosen by the user. For Cosmos, inspect the installed interface/API and downloaded asset availability. A UI action or true return is not proof that an asynchronous import finished. Record the pre-import handles, then use bounded checks to identify new nodes and inspect geometry, materials, and bounds. Do not guess suffixes or retry an import while its outcome is unknown. If still pending, report it and leave the existing scene intact.

The supplied Max 2027 / Corona 15 Hotfix 2 session reported an import UI failure, delayed import completion, lost extracted-proxy material assignments, texture-class differences, and a converter access violation. These are session observations, not universal bugs. Do not copy an old importer identifier or invoke a conversion method just because it appeared in those notes. Inspect current capabilities and source inputs. Stop repeating a failing conversion, especially after an access violation; preserve originals and use a verified supported path or report the limitation.

Before extracting supported proxy geometry, preserve the source material references, transforms, hierarchy, and UVs. Inspect the extracted result before replacing anything. Keep originals recoverable in a backup layer; delete only an explicitly authorized, verified set after replacement checks. Never delete by a broad name substring.

## Fit components without distortion

Measure actual occupied geometry where proxy bounds are approximate. Fit kitchen modules, carcasses, fronts, worktops, and handles independently so handle shape and panel thickness survive resizing. Check working/seat height, overhangs, cabinet depth, wall fit, door clearance, and circulation.

Determine chair facing from visible geometry, not just an object axis. Measure leg footprint as well as seat width. If the requested seating arrangement does not fit, report the conflict instead of silently changing the seat count or layout. Use positive-scale orientation changes where possible and inspect affected normals after vertex edits. A material swap from glass to wood may also require reference-appropriate thickness and supports.

## Verify saved output

Use the general skill's scene-files reference before saving or exporting. Restore the intended camera and temporary isolation state unless the user wants them retained. Resolve the exact requested destination and collision policy before a write; do not substitute a similarly named scene.

For `max_scene_save`, inspect the inner execution result as well as the outer tool envelope, read back the scene path, and verify destination existence, nonzero size, and an update corresponding to this save. A pre-existing file alone does not prove success. After a timeout or disconnect, inspect state before retrying an overwrite. Report incomplete or uncertain saves; do not open/reset the working scene merely to test the file.

For authorized exports, verify the exported file and its intended content using a suitable reader or isolated inspection. Record selection, format, destination, and dependencies; do not claim a standalone portable asset until references resolve. Copy assets successfully before repathing, handle basename collisions explicitly, and provide a manifest for collection/export work. Preserve the working scene during batch tasks.

For review images, preserve the requested beauty background/sky and effective tone mapping. Inspect the saved image rather than assuming it matches the VFB. JPEG requires RGB without alpha; flatten against the intended background. Do not add poster layouts, archives, generated replacement images, or reusable procedural systems unless requested.
