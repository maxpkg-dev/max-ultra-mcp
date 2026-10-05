# Semantic layers

All thirteen `max_layer_*` tools belong to the `core` profile. They use the selected MCP session's instance and the ordinary bounded Max main-thread queue. No Layer Explorer focus or coordinate clicks are required.

## Identity and scope

Read layers with `max_layer_list`, then retain the returned `LayerRef`: `handle`, `instanceId`, `sceneId`, and informational `name`. Its layer AnimHandle survives rename. References are checked against current LayerManager membership and a bootstrap scene epoch; new/reset/open invalidates previous references. Restart the updated bootstrap before using these tools. An explicit `{ "name": "Furniture" }` selector looks up a current name; a stale handle never falls back to that name. NodeRefs use INode handles (`node.handle` / `maxOps.getNodeByHandle`), not layer AnimHandles.

Layer lists return flat records with parent references, direct node/child counts, own properties and current-layer state. `parent: null` lists top-level layers; a parent reference lists immediate children. `includeDescendants: true` expands that scope. Omitted parent lists all layers. The optional `filter` is a case-insensitive name substring. Read pages default to 100 and allow at most 200 records, with `total` and `nextOffset`.

## Tools

| Tool | Behavior |
| --- | --- |
| `max_layer_list` | Paginated hierarchy records, parent scope and name filter. |
| `max_layer_get` | Identity, parent, own properties and counts for one layer. |
| `max_layer_create` | Create by name with optional parent; an existing layer must match an explicitly supplied parent. |
| `max_layer_rename` | Rename while preserving identity; reject conflicting names. |
| `max_layer_set_parent` | Reparent; `parent: null` moves to top level. Reject self-parenting and cycles. |
| `max_layer_set_current` | Set current without changing object selection. |
| `max_layer_set_properties` | Set whitelisted properties, optionally descendants and explicit node By Layer flags. |
| `max_layer_get_nodes` | Paginated NodeRefs, node hidden/frozen state and display/render/color By Layer flags. |
| `max_layer_assign` | Bulk assignment after validating every node. Use `layer` for an existing target or legacy `name` to create it if missing. |
| `max_layer_select_nodes` | Replace, add or remove the specified layer's nodes from selection; descendants are opt-in. |
| `max_layer_delete` | Preview and apply explicit node/child policies. |
| `max_layer_merge` | Preview moving source contents to a destination, then remove verified empty sources. |
| `max_layer_remove_empty` | Preview removing wholly empty branches/leaves within explicit `root` scope; `null` means scene. |

All mutations accept `dryRun: true`. Batches are bounded to 2,000 nodes, 500 layers per mutation category, and 100 merge sources. Scene hierarchy inspection is limited to 5,000 layers. Narrow the scope after `LAYER_LIMIT_EXCEEDED`.

## Properties and inheritance

Own layer properties include hidden/frozen, wire color, visibility, renderable, primary/secondary visibility, shadow, atmospheric, display and GI flags. `properties.wireColor` is three integers from 0 to 255; `visibility` is 0 to 1. The catalog defines the complete whitelist. Unsupported native properties abort before any write.

Changing a layer never silently turns on object inheritance. Explicit `byLayer` flags are `displayByLayer`, `renderByLayer`, `colorByLayer`, `motionByLayer`, and `globalIlluminationByLayer`. Descendant changes require `includeDescendants: true`. Layer properties alone do not establish final viewport/render visibility: object flags, ancestor layers and viewport state also matter. Re-read node flags and inspect the viewport for a visual request.

## Preview and destructive policies

Delete, merge and remove-empty default to preview. Repeat identical arguments with `preview: false` and the returned `planToken` to apply. Tokens belong to that MCP session and instance, expire after five minutes, are consumed on apply, and bind the scene revision and a native state fingerprint. Manual changes to hierarchy, properties, current layer or affected membership invalidate the preview. Re-preview after `STALE_PLAN`; do not reuse a token with changed arguments.

Deletion defaults to rejecting nonempty layers and layers with children. Choose `nodePolicy: "move"` plus `destination`, or explicitly choose `nodePolicy: "delete"` to delete geometry. Choose `childPolicy: "reparent"` plus `childParent` (null for roots), or `"deleteBranch"`. Native `deleteLayerHierarchy forceDelete` is never used as a geometry-deletion shortcut. Groups, nodes with children outside the deletion set, and external camera/light targets are rejected for content deletion.

Merge moves direct source contents by default and rejects children. `childPolicy: "reparent"` retains children under the destination; `"flatten"` moves all descendant contents and removes the source branches. Reject overlapping sources and destinations scheduled for deletion. Removal of the current layer requires explicit `replacementCurrent`. Layer 0 cannot be renamed, parented or removed. Mutations of scene-XRef hierarchies and direct mutations of XRef nodes are conservatively unsupported.

Responses include `applied`, `unchanged`, `unsupported`, `warnings`, effect counts, and `hierarchyBefore`. A changed operation advances the selected instance's scene revision; previews and no-ops do not. Reacquire revision-bound NodeRefs after changes.

## Undo and verification

Operations use one native undo hold and verify post-state. Native `LayerProperties.setParent` does not create an undo record on the tested Max 2022 build. Undo can restore nodes/layers without restoring parent hierarchy. Preserve `hierarchyBefore` and explicitly restore parents when necessary; do not promise complete hierarchy Undo. Error recovery cancels the hold and attempts explicit parent/current-layer restoration. A rollback error requires inspection before retrying.

`node tests/layers-test.js` covers schemas, bounds, request validation, two-instance routing, revision isolation, preview binding/expiry/replay and stable errors. The v1 suite verifies layer reads through authenticated control and STDIO envelopes on both mock endpoints. These run in the complete smoke suite.

For native acceptance, explicitly authorize an empty, untitled instance and run `node tests/layers-live-test.js <INSTANCE_ID>`. The opt-in fixture refuses named/nonempty scenes, exercises all thirteen tools and selected native Undo operations, and removes only its recorded objects/layers. It does not reset or save a scene; the modified flag and undo history can contain fixture activity. This is separate from automated mock tests and must never target a working user scene. Native acceptance has passed with 62 assertions on each of Max 2022 and Max 2027. Versions 2023 through 2026 and real XRef fixtures remain separate acceptance requirements. Scene-transition callback registration is implemented, but reset/open tests must run in a dedicated fixture, not a working scene.
