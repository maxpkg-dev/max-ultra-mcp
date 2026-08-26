# Required Production Use Cases

This document defines the next mandatory Max Ultra MCP workflows. They are acceptance requirements, not examples built on unrestricted `max_execute`.

## Shared workflow contract

Potentially destructive or long-running workflows use the same lifecycle:

```text
analyze -> operation plan -> planToken -> apply/start
                                      -> status/wait/cancel/result
                                      -> verification manifest
```

- A `planToken` binds the normalized request, selected instance, scene revision, discovered targets, and relevant capabilities.
- Apply rejects a stale token after the scene, renderer, files, or target set changes.
- Analysis never changes scene state.
- Apply supports `dryRun` where practical and returns an explicit post-state.
- Asset collection, batch export, and proxy conversion run as cancellable jobs.
- Renderer-specific behavior uses versioned Corona and V-Ray adapters. Unknown APIs return `RENDERER_UNSUPPORTED`.
- UI Automation is a last-resort fallback and is never presented as a successful semantic adapter.

The common job API is `max_job_status`, `max_job_wait`, `max_job_cancel`, and `max_job_result`.

## 1. Find and relink assets

Tools:

- `max_assets_scan`
- `max_assets_relink_plan`
- `max_assets_relink_apply`

The scan covers bitmap and procedural-map file inputs, HDRI/environment maps, IES files, LUT/OCIO files, Corona/V-Ray proxies, XRefs, point caches, Alembic files, simulation caches, and renderer-specific assets when discoverable.

Each asset record contains a stable asset id, kind, original path, resolved path, status, owners, candidates, and candidate-score reasons. Candidate matching considers the exact filename, relative path suffix, extension, file size, and optional SHA-256. Automatic selection is allowed only for an unambiguous candidate. Duplicate basenames require an explicit choice.

Apply changes paths only after candidate validation and then verifies file existence and every known asset owner.

## 2. Configure Corona or V-Ray

Tools:

- `max_renderer_capabilities`
- `max_renderer_configure_plan`
- `max_renderer_configure_apply`

Input describes the rendering task and constraints rather than an opaque preset: renderer, still/animation/interior/exterior intent, resolution, time budget, noise target, sample/pass limit, GI policy, denoising, displacement, output, and VFB behavior.

The plan expands the request into exact common Max settings and version-specific renderer properties. It reports `applied`, `unchanged`, `unsupported`, and `warnings` separately. Per-machine Corona system settings are excluded unless explicitly requested because they are not ordinary scene settings.

Acceptance requires deterministic preview and final-still presets plus explicit custom settings for supported Corona and V-Ray versions.

The implemented read-only `max_renderer_properties_get` tool and packaged `max-ultra-renderer-settings` skill provide the discovery-first foundation for this workflow. They inspect the actual active renderer class and properties before any mutation. The dedicated capability/plan/apply adapters listed above remain backlog and must not be presented as implemented.

## 3. Collect assets into one folder

Tools:

- `max_assets_collect_plan`
- `max_assets_collect_start`

Supported layouts are `preserve_relative`, `flatten`, and `by_asset_type`. Collision policies include `skip`, `overwrite_identical`, and `append_hash`. Different files with the same basename never silently overwrite one another.

The scene is repathed only after successful copies. The result manifest lists copied, skipped, missing, relinked, and failed assets, including source and destination hashes. Partial failure leaves original scene paths intact for failed files.

## 4. Automatic camera composition

Tools:

- `max_camera_analyze`
- `max_camera_compose_plan`
- `max_camera_compose_apply`

The subject can be the current selection, explicit NodeRefs, a layer, a group, or a reviewed semantic match. Composition rules include rule of thirds, golden ratio, centered, and diagonal. Constraints include interior/exterior/product shot type, lens range, preferred direction, elevation, safe-frame margin, aspect ratio, and vertical-correction policy.

The planner evaluates multiple camera candidates using subject coverage, clipping, empty space, horizon, and verticals. Apply updates or creates a camera, activates it, captures the viewport, and returns composition metrics and the camera NodeRef.

Until these dedicated semantic tools are implemented, the packaged `max-ultra-camera-composition` skill uses existing camera, transform, render-setting, script, and viewport tools. It requires the final render aspect, enables Safe Frame before composition decisions, and verifies every accepted camera through a maximized viewport screenshot.

## 5. Create tree masks and render elements

Tools:

- `max_render_masks_plan`
- `max_render_masks_apply`

Tree candidates are discovered from node, layer, group, material, object-class, and proxy-source names or supplied explicitly. The full candidate list is reviewed before mutation.

The planner allocates collision-free Object/G-Buffer IDs without overwriting existing assignments. Corona uses supported masking or Cryptomatte elements. V-Ray uses its renderer-specific Cryptomatte, Object ID, or MultiMatte elements. MultiMatte groups at most three IDs per element. Element names and IDs are verified after creation.

Standard 3ds Max render elements must not be substituted when the active renderer does not support them.

## 6. Find objects without valid materials

Implementation status: available and mock-tested in v1.1; real 3ds Max acceptance remains required.

Tool:

- `max_material_find_unassigned`

This read-only tool returns geometry NodeRefs grouped as `noMaterial`, `invalidMaterial`, `emptyMultiSubSlot`, `unsupportedMaterial`, and `materialMissingMaps`. Filters control hidden, frozen, XRef, and non-geometry nodes. Selection remains a separate `max_select_objects` operation so analysis has no hidden scene mutation.

## 7. Batch FBX and GLB export

Tools:

- `max_batch_export_plan`
- `max_batch_export_start`

Batch export uses a dedicated selected Max worker and refuses to replace an unsaved working scene without explicit authorization. The plan lists source MAX files, detected exporter capabilities, output paths, conflicts, version compatibility, and GLB availability.

Each scene is isolated by reset/open/export/cleanup boundaries. One corrupt scene or failed exporter does not stop the batch. Results are reported per source and format with output path, status, warnings, error, and duration. Exporter availability is detected from registered exporter classes; GLB is never assumed.

## 8. Analyze and optimize rendering performance

Tools:

- `max_scene_performance_analyze`
- `max_scene_optimize_plan`
- `max_scene_optimize_apply`

Analysis covers triangles and polygons, unique versus instanced meshes, texture dimensions and bit depth, estimated decoded texture memory, TurboSmooth/MeshSmooth viewport and render iterations, displacement, scatter/proxy sources, XRefs, caches, hidden-but-renderable objects, subdivision, and large environment maps.

RAM/VRAM values are explicitly estimates. Every issue has a stable id, severity, affected NodeRefs/assets, evidence, estimated impact, and safe actions. Apply accepts selected issue ids and never removes displacement, collapses modifiers, or simplifies geometry without a reviewed plan.

## 9. Automatic proxy conversion

Tools:

- `max_proxy_convert_plan`
- `max_proxy_convert_start`

Planning detects renderer and proxy support, unique geometry, instances, animation/deformation, unsupported modifiers, output conflicts, materials, transforms, hierarchy, layers, and visibility/render properties. Instances of the same unique mesh share one proxy asset when safe.

Conversion writes a temporary proxy, verifies that it exists and is non-empty, creates the proxy node, validates transform and bounding-box tolerance, restores supported properties, and moves originals to a hidden backup layer. Original nodes are not deleted by the conversion job. Deletion is a separate confirmed operation. Any export or validation failure leaves the original untouched.

## 10. AI-assisted material editing

Tools:

- `max_material_graph_query`
- `max_material_edit_plan`
- `max_material_edit_apply`

Natural-language interpretation happens in ChatGPT or Codex. Raw natural language is never evaluated as MaxScript. The model queries the material graph and submits explicit target NodeRefs/material handles plus structured operations such as `wrapMap`, `setScalar`, `setColor`, `replaceMapPath`, or `rename`.

The planner detects shared materials, shared maps, cycles, unsupported slots, and renderer-specific map classes. The default shared-material policy is `cloneForMatchedObjects`, preventing a request about trees from changing non-tree objects that use the same material. A Color Correction operation preserves the original Base Color/Diffuse map as the correction map input.

## Implementation order

1. Asset scan/relink, material diagnostics, and performance analysis.
2. Asset collection, renderer configuration, and material-graph editing.
3. Camera composition and renderer-specific masks.
4. Universal jobs and batch export.
5. Corona/V-Ray proxy adapters.

## Required acceptance fixtures

- 3ds Max 2022, 2024, 2026, and 2027 scenes.
- Multiple supported Corona and V-Ray versions with capability snapshots.
- Missing assets, duplicate basenames, mixed relative/absolute paths, and unavailable network paths.
- Shared materials across matched and unmatched objects.
- Trees represented by geometry, instances, Corona Proxy, V-Ray Proxy, and scatter systems.
- Corrupt MAX files, unavailable exporters, existing outputs, and partial batch failures.
- Animated, deformed, instanced, and unsupported proxy candidates.
- Heavy texture, subdivision, displacement, cache, and XRef fixtures.

## Primary API references

- Autodesk MAXScript bitmap enumeration: https://help.autodesk.com/cloudhelp/2024/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/File-Access/3ds-Max-Scene-Files-Access/GUID-C88ECB5F-F74F-4023-A02E-95E7A5485188.html
- Autodesk ATSOps: https://help.autodesk.com/cloudhelp/2021/ENU/3DSMax-MAXScript/files/GUID-F203ABBC-C3DF-4406-A449-CE6EDC011F55.htm
- Autodesk scene export API: https://help.autodesk.com/cloudhelp/2026/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/File-Access/3ds-Max-Scene-Files-Access/GUID-624D3D05-B15D-4A97-9F15-DA35CDB0DDD2.html
- Autodesk GLTF exporter API: https://help.autodesk.com/cloudhelp/2024/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Import-and-Export-Filters/GUID-47D7B030-1DB8-47E8-B462-C800D26480DA.html
- Corona render settings: https://docs.chaos.com/display/CRMAX/Render%2BSettings
- Corona supported features: https://docs.chaos.com/display/CRMAX/Supported%2BFeatures
- Corona Proxy: https://docs.chaos.com/display/CRMAX/Corona%2BProxy
- V-Ray render elements: https://docs.chaos.com/display/VMAX/Render%2BElements
