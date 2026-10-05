# Layer workflows

Use the thirteen semantic layer tools in the core profile for layer organization, starting with `max_layer_list`. Do not generate LayerManager scripts or drive Layer Explorer for an operation already exposed by these tools.

1. Discover/select the intended Max instance. Read `max_layer_list` with a bounded page and the smallest parent/name scope. Follow `nextOffset` when necessary. Records are flat with parent references; counts are direct, not branch totals.
2. Keep returned `LayerRef` values (`handle`, `instanceId`, `sceneId`, `name`). They survive rename, but not scene replacement. Never replace a stale reference with a same-named layer automatically. Re-query after `STALE_LAYER_REF`.
3. Use `max_layer_create`, `rename`, `set_parent`, or `set_current` for organization. Top-level parenting is `parent: null`. Layer 0 cannot be renamed, parented or deleted. Cycles and name conflicts must be resolved before changes.
4. Use `max_layer_get_nodes` for paginated NodeRefs, `assign` for bulk membership, and `select_nodes` for explicit replace/add/remove. Assignment does not enable By Layer flags. Retain fresh revision-bound NodeRefs; node INode handles and layer AnimHandles are different identifier types.
5. Use `max_layer_set_properties` for hidden/frozen, wire color, visibility and rendering/display properties. Descendants require `includeDescendants: true`. Set object inheritance only through explicit `byLayer` flags when requested. Inspect effective node flags and the viewport before claiming visible/renderable results from a layer setting.
6. `delete`, `merge`, and `remove_empty` return a preview by default. Inspect effect counts and `hierarchyBefore`, then apply the same arguments with `preview: false` and `planToken`. Re-preview after any `STALE_PLAN`. Tokens are session/instance/state bound and expire after five minutes.

Deletion rejects children and contents by default. Explicitly choose whether to move or delete nodes and whether to reparent or delete descendants. `childParent: null` reparents to roots. Deleting the current layer requires `replacementCurrent`. Merge uses `childPolicy: "reparent"` to retain child layers or `"flatten"` to absorb their contents. Remove-empty requires an explicit `root`, with null meaning scene. Never interpret native forceDelete as permission to delete geometry.

Native `setParent` does not reliably participate in Undo: a single undo hold does not guarantee hierarchy restoration. Retain `hierarchyBefore` and restore parents explicitly if required. Report this limit before a hierarchy reorganization when Undo matters to the user. On a reported rollback failure, inspect the scene before retrying.

All mutations support `dryRun`. Pages allow up to 200 records; node batches up to 2,000; layer mutation categories up to 500; merge sources up to 100. Narrow scope on limit errors. XRef hierarchies/nodes are conservatively protected; do not bypass that protection with raw scripts. A missing bootstrap epoch requires restarting the updated bootstrap before using layer references.
