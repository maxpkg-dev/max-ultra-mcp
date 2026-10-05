/*
 * Tests layer schemas, routing, validation, preview binding and response contracts without Max.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const { getMcpTools } = require("../core/tool-catalog");
const { validateSchema, errorCode } = require("../core/stdio-host");
const { invokeV1Tool } = require("../core/tool-runtime");
const { normalizeLayerRequest, generateLayerScript } = require("../core/layers");

async function main() {
  const instanceA = { instanceId: "mock-max-2022-22022" };
  const instanceB = { instanceId: "mock-max-2027-22027" };
  const ref = { handle: 101, instanceId: instanceA.instanceId, sceneId: "fixture-scene", name: "Fixture" };
  const calls = [];
  let maxResponse = { ok: true, changed: false, layers: [], total: 0, fingerprint: "initial-state", applied: [], unchanged: [], unsupported: [], warnings: [] };
  const bridge = {
    sceneRevisions: new Map([[instanceA.instanceId, 10], [instanceB.instanceId, 20]]),
    selectInstance(id, session) { return id === instanceB.instanceId || (!id && session.selectedInstanceId === instanceB.instanceId) ? instanceB : instanceA; },
    publicInstance(instance) { return instance; },
    async request(instanceId, action, source) { calls.push({ instanceId, action, source }); return { ok: true, result: JSON.stringify(maxResponse) }; },
  };
  const session = { selectedInstanceId: instanceA.instanceId };
  const call = (operation, args = {}, selectedSession = session) => invokeV1Tool(bridge, `max_layer_${operation}`, args, selectedSession);
  const tools = getMcpTools("core").filter(entry => entry.name.startsWith("max_layer_"));
  assert.equal(tools.length, 13);
  assert.equal(new Set(tools.map(entry => entry.name)).size, 13);
  for (const tool of tools) {
    assert.equal(tool.annotations.openWorldHint, false);
    assert.equal(tool.annotations.readOnlyHint, ["max_layer_list", "max_layer_get", "max_layer_get_nodes"].includes(tool.name));
  }
  const examples = {
    list: { parent: null, offset: 0, limit: 2 }, get: { layer: ref }, create: { name: "Fixture", parent: null },
    rename: { layer: ref, name: "Renamed" }, set_parent: { layer: ref, parent: null }, set_current: { layer: ref },
    set_properties: { layer: ref, properties: { isHidden: true, wireColor: [0, 128, 255] }, byLayer: { renderByLayer: true } },
    get_nodes: { layer: ref, includeDescendants: true, limit: 1 }, assign: { layer: ref, nodes: [{ handle: 7, sceneRevision: 10 }] },
    select_nodes: { layer: ref, mode: "add" }, delete: { layer: ref }, merge: { sources: [ref], destination: { name: "Destination" } }, remove_empty: { root: null },
  };
  for (const [operation, args] of Object.entries(examples)) {
    const schema = tools.find(entry => entry.name === `max_layer_${operation}`).inputSchema;
    validateSchema(args, schema);
    const result = await call(operation, args);
    assert.equal(result.instanceId, instanceA.instanceId);
    assert.equal(result.sceneRevision, 10);
    assert.equal(calls.at(-1).action, "execute");
    assert.equal(calls.at(-1).instanceId, instanceA.instanceId);
    assert.match(calls.at(-1).source, /local layerSceneEpoch/);
  }
  const invalidCases = [
    ["assign", { name: "MustNotExist", nodes: [{ handle: 7, sceneRevision: 9 }] }, /STALE_NODE_REF/],
    ["get", { layer: { ...ref, instanceId: instanceB.instanceId } }, /STALE_LAYER_REF/],
    ["get", { layer: { handle: 1 } }, /VALIDATION_FAILED/],
    ["get", { layer: null }, /VALIDATION_FAILED/],
    ["assign", { name: "One", layer: ref, nodes: [{ handle: 7 }] }, /VALIDATION_FAILED/],
    ["assign", { name: "One", nodes: [{ handle: -1, name: "Fallback" }] }, /VALIDATION_FAILED/],
    ["assign", { name: "One", nodes: [] }, /VALIDATION_FAILED/],
    ["assign", { name: "One", nodes: Array.from({ length: 2001 }, () => ({ handle: 7 })) }, /VALIDATION_FAILED/],
    ["rename", { layer: ref, name: "\nInvalid" }, /VALIDATION_FAILED/],
    ["create", { name: " " }, /VALIDATION_FAILED/],
    ["set_parent", { layer: ref }, /VALIDATION_FAILED/],
    ["set_properties", { layer: ref, properties: {} }, /VALIDATION_FAILED/],
    ["set_properties", { layer: ref, properties: { wireColor: [0, 256, 1] } }, /VALIDATION_FAILED/],
    ["set_properties", { layer: ref, properties: { visibility: NaN } }, /VALIDATION_FAILED/],
    ["set_properties", { layer: ref, properties: { isHidden: "false" } }, /VALIDATION_FAILED/],
    ["set_properties", { layer: ref, properties: { arbitraryProperty: true } }, /VALIDATION_FAILED/],
    ["select_nodes", { layer: ref, mode: "unknown" }, /VALIDATION_FAILED/],
    ["delete", { layer: ref, nodePolicy: "forceDelete" }, /VALIDATION_FAILED/],
    ["remove_empty", {}, /VALIDATION_FAILED/],
    ["list", { limit: 201 }, /VALIDATION_FAILED/],
    ["list", { offset: -1 }, /VALIDATION_FAILED/],
  ];
  for (const [operation, args, expected] of invalidCases) {
    const beforeCount = calls.length;
    await assert.rejects(call(operation, args), expected);
    assert.equal(calls.length, beforeCount, "Invalid requests must not reach Max");
  }
  const quoted = normalizeLayerRequest("max_layer_create", { name: 'Layer \\"; delete objects; --' }, instanceA.instanceId, 10);
  assert.match(generateLayerScript(quoted, instanceA.instanceId), /Layer \\\\\\"/);

  const preview = await call("delete", { layer: ref });
  assert.equal(preview.planToken.length, 64);
  assert.match(calls.at(-1).source, /local layerPreview = true/);
  await assert.rejects(call("delete", { layer: ref, preview: false, planToken: preview.planToken }, {}), /STALE_PLAN/);
  await assert.rejects(call("delete", { layer: ref, nodePolicy: "delete", preview: false, planToken: preview.planToken }), /STALE_PLAN/);
  const applied = await call("delete", { layer: ref, preview: false, planToken: preview.planToken });
  assert.match(calls.at(-1).source, /local layerExpectedFingerprint = "initial-state"/);
  assert.equal(applied.sceneRevision, 10);
  await assert.rejects(call("delete", { layer: ref, preview: false, planToken: preview.planToken }), /STALE_PLAN/);
  const stale = await call("remove_empty", { root: null });
  bridge.sceneRevisions.set(instanceA.instanceId, 11);
  await assert.rejects(call("remove_empty", { root: null, preview: false, planToken: stale.planToken }), /STALE_PLAN/);
  bridge.sceneRevisions.set(instanceA.instanceId, 10);
  const expired = await call("remove_empty", { root: null });
  session.layerPlans.get(expired.planToken).expiresAt = 0;
  await assert.rejects(call("remove_empty", { root: null, preview: false, planToken: expired.planToken }), /STALE_PLAN/);

  maxResponse = { ok: false, code: "STALE_PLAN", message: "Native membership changed" };
  await assert.rejects(call("get", { layer: ref }), /STALE_PLAN/);
  assert.equal(bridge.sceneRevisions.get(instanceA.instanceId), 10);
  maxResponse = { ok: true, changed: true, record: { layer: ref }, applied: ["name"], warnings: [] };
  const changed = await call("rename", { layer: ref, name: "Renamed" });
  assert.equal(changed.sceneRevision, 11);
  assert.equal(bridge.sceneRevisions.get(instanceB.instanceId), 20);
  maxResponse = { ok: true, changed: false, nodes: [{ node: { kind: "node", handle: 7, name: "FixtureNode" } }] };
  const nodes = await call("get_nodes", { layer: { name: "Fixture" }, instance_id: instanceB.instanceId });
  assert.deepEqual(nodes.nodes[0].node, { handle: 7, name: "FixtureNode", sceneRevision: 20 });
  assert.equal(calls.at(-1).instanceId, instanceB.instanceId);
  assert.equal(session.selectedInstanceId, instanceA.instanceId);
  for (const code of ["STALE_LAYER_REF", "LAYER_NOT_FOUND", "LAYER_CYCLE", "LAYER_CONFLICT", "LAYER_PROTECTED", "LAYER_NOT_EMPTY", "LAYER_XREF_UNSUPPORTED", "LAYER_PROPERTY_UNSUPPORTED", "LAYER_LIMIT_EXCEEDED", "LAYER_BOOTSTRAP_REQUIRED"]) assert.equal(errorCode(new Error(`${code}: fixture`)), code);
  console.log("Layer contract smoke passed: 13 core tools, schema/bounds, validation before dispatch, two-instance routing, revisions, preview expiry/binding/replay and structured errors. Native lifecycle is covered by the opt-in live fixture.");
}
if (require.main === module) main().catch(error => { console.error(error.stack); process.exitCode = 1; });
module.exports = { main };
