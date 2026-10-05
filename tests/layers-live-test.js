/*
 * Opt-in native layer acceptance fixture; refuses nonempty or named scenes.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { BridgeControlClient } = require("../core/bridge-control-client");
const { getMcpTools } = require("../core/tool-catalog");
const { validateSchema } = require("../core/stdio-host");
const { invokeV1Tool } = require("../core/tool-runtime");

async function run(instanceId) {
  if (!instanceId) throw new Error("Supply the instance id of an explicitly authorized empty Max fixture. This test never launches, resets or saves a scene.");
  const client = new BridgeControlClient({ timeoutMs: 60000 });
  await client.connect();
  const prefix = `MCP_LayerFixture_${randomUUID().slice(0, 8)}_`;
  const createdNames = [];
  const createdNodes = [];
  let assertions = 0;
  const sourceSession = {};
  const sourceBridge = {
    sceneRevisions: new Map([[instanceId, 0]]),
    selectInstance: () => ({ instanceId }),
    publicInstance: instance => instance,
    request: async (id, action, source) => (await client.callTool("max_run_script", { instance_id: id, activity: "Verify isolated layer acceptance fixture", script: source })).execution,
  };
  const check = (actual, expected) => { assert.deepEqual(actual, expected); assertions += 1; };
  const call = async (operation, args = {}) => {
    const name = `max_layer_${operation}`;
    validateSchema(args, getMcpTools("core").find(entry => entry.name === name).inputSchema);
    // Execute the checkout's generator, not a daemon's older cached JS module.
    // Transport/authentication and native execution still use the regular live bridge.
    return invokeV1Tool(sourceBridge, name, args, sourceSession);
  };
  const script = async source => (await client.callTool("max_run_script", { instance_id: instanceId, activity: "Verify isolated layer acceptance fixture", script: source })).execution.result;
  const get = async layer => (await call("get", { layer })).record;
  const create = async (suffix, parent) => {
    const name = prefix + suffix; createdNames.push(name);
    return (await call("create", { name, ...(parent === undefined ? {} : { parent }) })).record.layer;
  };
  const apply = async (operation, args) => {
    const preview = await call(operation, args);
    check(preview.changed, false);
    return call(operation, { ...args, preview: false, planToken: preview.planToken });
  };
  const rejects = async (operation, args, pattern) => { await assert.rejects(call(operation, args), pattern); assertions += 1; };
  let fixtureStarted = false;
  try {
    check(await script('(maxFileName == "" and objects.count == 0 and selection.count == 0 and LayerManager.count == 1) as string'), "true");
    const initial = await call("list");
    check(initial.total, 1);
    const zero = initial.layers[0].layer;
    fixtureStarted = true;
    const root = await create("Root");
    const child = await create("Child", root);
    const destination = await create("Destination");
    check((await get(child)).parent.handle, root.handle);
    check((await call("list", { parent: root })).total, 1);
    check((await call("list", { parent: null, filter: prefix, limit: 1 })).nextOffset, 1);
    check((await call("create", { name: prefix + "Root" })).changed, false);
    check((await call("create", { name: prefix + "PreviewOnly", dryRun: true })).changed, false);
    check((await call("list", { filter: prefix + "PreviewOnly" })).total, 0);
    await rejects("create", { name: prefix + "Child", parent: destination }, /LAYER_CONFLICT/);
    await rejects("set_parent", { layer: root, parent: child }, /LAYER_CYCLE/);
    await rejects("set_parent", { layer: root, parent: root }, /LAYER_CYCLE/);
    await rejects("rename", { layer: root, name: prefix + "Child" }, /LAYER_CONFLICT/);
    await rejects("rename", { layer: zero, name: prefix + "Zero" }, /LAYER_PROTECTED/);
    await rejects("delete", { layer: zero }, /LAYER_PROTECTED/);
    await rejects("get", { layer: { ...child, instanceId: "other-instance" } }, /STALE_LAYER_REF/);
    await rejects("get", { layer: { ...child, sceneId: "old-scene" } }, /STALE_LAYER_REF/);
    const renamedName = prefix + "Renamed"; createdNames.push(renamedName);
    await call("rename", { layer: child, name: renamedName });
    check((await get(child)).layer.name, renamedName);
    await script("max undo");
    check((await get(child)).layer.name, prefix + "Child");
    await call("set_parent", { layer: child, parent: null });
    check((await get(child)).parent, null);
    // Native LayerProperties.setParent does not create an undo record on Max 2022.
    // Do not undo an unrelated earlier transaction to test this operation.
    await call("set_parent", { layer: child, parent: root });
    check((await get(child)).parent.handle, root.handle);
    await call("set_current", { layer: child });
    check((await get(child)).current, true);
    await rejects("delete", { layer: child }, /replacementCurrent/);
    await call("set_current", { layer: zero });
    const fixtureBox = await invokeV1Tool(sourceBridge, "max_create_box", { name: prefix + "Box", size: [10, 10, 10], select: false }, sourceSession);
    const nodeHandle = fixtureBox.node.handle;
    assert.ok(Number.isSafeInteger(nodeHandle) && nodeHandle > 0);
    createdNodes.push(nodeHandle);
    await rejects("assign", { name: prefix + "MustNotExist", nodes: [{ handle: nodeHandle }, { handle: 4294967294 }] }, /STALE_NODE_REF/);
    check((await call("list", { filter: prefix + "MustNotExist" })).total, 0);
    check((await get(zero)).nodeCount, 1);
    await call("assign", { layer: child, nodes: [fixtureBox.node] });
    check((await get(child)).nodeCount, 1);
    check((await get(zero)).nodeCount, 0);
    const nodePage = await call("get_nodes", { layer: root, includeDescendants: true, limit: 1 });
    check(nodePage.total, 1);
    check(nodePage.nodes[0].node.handle, nodeHandle);
    await script("max undo");
    check((await get(zero)).nodeCount, 1);
    await call("assign", { layer: child, nodes: [{ handle: nodeHandle }] });
    await rejects("assign", { layer: child, nodes: [nodePage.nodes[0].node] }, /STALE_NODE_REF/);
    await call("set_properties", { layer: child, properties: { isHidden: true, renderable: false, wireColor: [12, 34, 56], visibility: 0.5 }, byLayer: { colorByLayer: true } });
    const properties = (await get(child)).properties;
    check(properties.isHidden, true); check(properties.renderable, false); check(properties.wireColor, [12, 34, 56]);
    check((await call("get_nodes", { layer: child })).nodes[0].colorByLayer, true);
    await script("max undo");
    check((await get(child)).properties.isHidden, false);
    await call("set_properties", { layer: root, properties: { isFrozen: true }, includeDescendants: true });
    check((await get(child)).properties.isFrozen, true);
    await call("set_properties", { layer: root, properties: { isFrozen: false }, includeDescendants: true });
    await call("select_nodes", { layer: root, includeDescendants: true, mode: "replace" });
    check(await script("selection.count as string"), "1");
    await call("select_nodes", { layer: child, mode: "remove" });
    check(await script("selection.count as string"), "0");
    await call("select_nodes", { layer: child, mode: "add" });
    check(await script("selection.count as string"), "1");
    await rejects("delete", { layer: root }, /LAYER_NOT_EMPTY/);
    await rejects("delete", { layer: child }, /LAYER_NOT_EMPTY/);
    const stalePlan = await call("delete", { layer: child, nodePolicy: "move", destination });
    await script(`(LayerManager.getLayerFromName "${prefix}Child").wireColor = color 7 8 9`);
    await rejects("delete", { layer: child, nodePolicy: "move", destination, preview: false, planToken: stalePlan.planToken }, /STALE_PLAN/);
    await apply("delete", { layer: child, nodePolicy: "move", destination });
    check((await get(destination)).nodeCount, 1);
    await rejects("get", { layer: child }, /STALE_LAYER_REF/);
    await script("max undo");
    check((await get(child)).nodeCount, 1);
    const grandchild = await create("Grandchild", child);
    await apply("merge", { sources: [child], destination, childPolicy: "reparent" });
    check((await get(destination)).nodeCount, 1);
    check((await get(grandchild)).parent.handle, destination.handle);
    const branch = await create("Branch");
    const leaf = await create("Leaf", branch);
    await call("assign", { layer: leaf, nodes: [{ handle: nodeHandle }] });
    await apply("merge", { sources: [branch], destination, childPolicy: "flatten" });
    check((await get(destination)).nodeCount, 1);
    await rejects("get", { layer: leaf }, /STALE_LAYER_REF/);
    const reparentRoot = await create("ReparentRoot");
    const reparentChild = await create("ReparentChild", reparentRoot);
    await apply("delete", { layer: reparentRoot, childPolicy: "reparent", childParent: null });
    check((await get(reparentChild)).parent, null);
    const empty = await create("Empty");
    const emptyLeaf = await create("EmptyLeaf", empty);
    const emptyPlan = await call("remove_empty", { root: empty });
    check(emptyPlan.effect.layersToRemove.length, 2);
    await call("remove_empty", { root: empty, preview: false, planToken: emptyPlan.planToken });
    await rejects("get", { layer: emptyLeaf }, /STALE_LAYER_REF/);
    const nonemptyPlan = await call("remove_empty", { root: destination });
    check(nonemptyPlan.effect.layersToRemove.some(ref => ref.handle === destination.handle), false);
    const deletePlan = await call("delete", { layer: destination, nodePolicy: "delete", childPolicy: "deleteBranch" });
    check(deletePlan.effect.nodesToDelete, 1);
    await call("delete", { layer: destination, nodePolicy: "delete", childPolicy: "deleteBranch", preview: false, planToken: deletePlan.planToken });
    check(await script("objects.count as string"), "0");
    await script("max undo");
    check(await script("objects.count as string"), "1");
    check((await get(destination)).nodeCount, 1);
    console.log(`Native layer acceptance passed: ${assertions} assertions; explicit instance fixture; create/rename/parent/current/properties/selection/delete/merge/cleanup/Undo.`);
  } finally {
    try {
      if (fixtureStarted) {
        // Only nodes and names recorded by this fixture; never reset or save a scene.
        const cleanup = `(local fixtureHandles=#(${createdNodes.join(",")}); local fixtureNames=#(${createdNames.map(name => JSON.stringify(name)).join(",")}); local fixtureNodes=for fixtureHandle in fixtureHandles collect (maxOps.getNodeByHandle fixtureHandle); fixtureNodes=for fixtureNode in fixtureNodes where (isValidNode fixtureNode) collect fixtureNode; delete fixtureNodes; (LayerManager.getLayer 0).current=true; for passIndex in 1 to fixtureNames.count do (for fixtureName in fixtureNames do (local fixtureLayer=LayerManager.getLayerFromName fixtureName; if (fixtureLayer != undefined and fixtureLayer.getNumNodes()==0 and fixtureLayer.getNumChildren()==0) do LayerManager.deleteLayerByName fixtureName)); (objects.count==0 and LayerManager.count==1) as string)`;
        check(await script(cleanup), "true");
        console.log("Owned fixture objects/layers removed; scene was not reset or saved. Undo history and modified flag may contain fixture activity.");
      }
    } finally { client.close(); }
  }
}
if (require.main === module) run(process.argv[2]).catch(error => { console.error(error.stack); process.exitCode = 1; });
module.exports = { run };
