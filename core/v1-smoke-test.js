/* Contract and integration smoke tests for Max Ultra MCP v1. */

"use strict";

const assert = require("node:assert/strict");
const { MaxBridge } = require("./server");
const { MockMaxClient } = require("./mock-max-client");
const { BridgeControlClient } = require("./bridge-control-client");
const { StdioHost } = require("./stdio-host");
const { getMcpTools } = require("./tool-catalog");
const { generateFloorPlanScript, validateFloorPlan } = require("./floor-plan");
const EXAMPLE_PLAN = require("../examples/house-plan-from-image/expected-plan.json");

function assertBalancedGeneratedMaxScript(source) {
  const pairs = new Map([["(", ")"], ["[", "]"], ["{", "}"]]);
  const closing = new Set(pairs.values());
  const stack = [];
  let inString = false;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (character === '"') {
      let slashes = 0;
      for (let cursor = index - 1; cursor >= 0 && source[cursor] === "\\"; cursor -= 1) slashes += 1;
      if (slashes % 2 === 0) inString = !inString;
      continue;
    }
    if (inString) continue;
    if (pairs.has(character)) stack.push(pairs.get(character));
    else if (closing.has(character)) assert.equal(stack.pop(), character, `Unbalanced generated MaxScript at ${index}`);
  }
  assert.equal(inString, false, "Generated MaxScript contains an unterminated string");
  assert.deepEqual(stack, []);
}

function waitFor(predicate, timeoutMs = 3000) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const check = () => {
      if (predicate()) return resolve();
      if (Date.now() - started > timeoutMs) return reject(new Error("waitFor timed out"));
      setTimeout(check, 10);
    };
    check();
  });
}

async function rpc(host, message) {
  const responses = [];
  await host.handle(message, (response) => responses.push(response));
  assert.equal(responses.length, 1);
  return responses[0];
}

const PLAN = {
  units: "mm",
  origin: [0, 0],
  wallHeight: 3000,
  walls: [
    { id: "W1", start: [0, 0], end: [10000, 0], thickness: 300 },
    { id: "W2", start: [10000, 0], end: [10000, 8000], thickness: 300 },
    { id: "W3", start: [10000, 8000], end: [0, 8000], thickness: 300 },
    { id: "W4", start: [0, 8000], end: [0, 0], thickness: 300 },
  ],
  openings: [
    { id: "D1", wallId: "W1", type: "door", offsetFromStart: 1200, width: 900, height: 2100, sillHeight: 0 },
    { id: "WIN1", wallId: "W2", type: "window", offsetFromStart: 1800, width: 1800, height: 1400, sillHeight: 900 },
  ],
  floor: { enabled: true, thickness: 200, outline: [[0, 0], [10000, 0], [10000, 8000], [0, 8000]] },
};

async function run() {
  const coreTools = getMcpTools("core");
  const archvizTools = getMcpTools("archviz");
  const fullTools = getMcpTools("full");
  assert.ok(coreTools.length >= 40, `Expected a broad core profile, got ${coreTools.length}`);
  assert.ok(archvizTools.length > coreTools.length);
  assert.ok(fullTools.length > archvizTools.length);
  assert.equal(new Set(fullTools.map((entry) => entry.name)).size, fullTools.length);
  assert.equal(coreTools.some((entry) => entry.name === "max_viewport_screenshot"), false);
  assert.equal(archvizTools.some((entry) => entry.name === "max_validate_floor_plan"), true);
  assert.equal(fullTools.find((entry) => entry.name === "max_execute").annotations.openWorldHint, true);

  const validation = validateFloorPlan(PLAN);
  assert.equal(validation.validationToken.length, 64);
  assert.deepEqual(validation.counts, { walls: 4, openings: 2, doors: 1, windows: 1 });
  const changed = structuredClone(PLAN);
  changed.wallHeight = 3100;
  const exampleValidation = validateFloorPlan(EXAMPLE_PLAN);
  assert.deepEqual(exampleValidation.counts, { walls: 7, openings: 9, doors: 4, windows: 5 });
  const generatedExample = generateFloorPlanScript(exampleValidation.normalizedPlan, { prefix: "MCP", layer: "MCP_ARCHVIZ" });
  assertBalancedGeneratedMaxScript(generatedExample.script);
  assert.match(generatedExample.script, /units\.decodeValue/);
  assert.match(generatedExample.script, /Max Ultra MCP: Build floor plan/);
  assert.match(generatedExample.script, /dummy name:"MCP_Door_DOOR_MAIN"/);
  assert.doesNotMatch(generatedExample.script, /boolean|ProBoolean/i);

  assert.notEqual(validateFloorPlan(changed).validationToken, validation.validationToken);

  const bridge = new MaxBridge({ port: 0, requestTimeoutMs: 2000 });
  await bridge.start();
  const max2022 = new MockMaxClient({ port: bridge.port, maxVersion: "2022", pid: 22022, instanceId: "v1-max-2022" });
  const max2027 = new MockMaxClient({ port: bridge.port, maxVersion: "2027", pid: 22027, instanceId: "v1-max-2027" });
  const clientA = new BridgeControlClient({ port: bridge.port, timeoutMs: 5000 });
  const clientB = new BridgeControlClient({ port: bridge.port, timeoutMs: 5000 });
  const hostA = new StdioHost({ profile: "archviz", client: clientA });
  const hostB = new StdioHost({ profile: "core", client: clientB });
  try {
    await Promise.all([max2022.connect(), max2027.connect()]);
    await waitFor(() => bridge.listInstances().length === 2);

    const initialize = await rpc(hostA, { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } });
    assert.equal(initialize.result.serverInfo.version, "1.0.0");
    assert.match(initialize.result.instructions, /floor-plan images/);

    const list = await rpc(hostA, { jsonrpc: "2.0", id: 2, method: "tools/list" });
    assert.equal(list.result.tools.length, archvizTools.length);

    const ambiguous = await rpc(hostA, { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "max_health", arguments: {} } });
    assert.equal(ambiguous.result.isError, true);
    assert.equal(ambiguous.result.structuredContent.error.code, "INSTANCE_REQUIRED");

    const selectA = await rpc(hostA, { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "max_select_instance", arguments: { instance_id: "v1-max-2022" } } });
    const selectB = await rpc(hostB, { jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "max_select_instance", arguments: { instance_id: "v1-max-2027" } } });
    assert.equal(selectA.result.structuredContent.data.selected.instanceId, "v1-max-2022");
    assert.equal(selectB.result.structuredContent.data.selected.instanceId, "v1-max-2027");
    const healthA = await rpc(hostA, { jsonrpc: "2.0", id: 6, method: "tools/call", params: { name: "max_health", arguments: {} } });
    const healthB = await rpc(hostB, { jsonrpc: "2.0", id: 7, method: "tools/call", params: { name: "max_health", arguments: {} } });
    assert.equal(healthA.result.isError, false, JSON.stringify(healthA.result.structuredContent));
    assert.equal(healthB.result.isError, false, JSON.stringify(healthB.result.structuredContent));
    assert.equal(healthA.result.structuredContent.data.instance.instanceId, "v1-max-2022");
    assert.equal(healthB.result.structuredContent.data.instance.instanceId, "v1-max-2027");

    const box = await rpc(hostA, { jsonrpc: "2.0", id: 8, method: "tools/call", params: { name: "max_create_box", arguments: { name: "V1Box", position: [1, 2, 3], size: [10, 20, 30] } } });
    assert.equal(box.result.isError, false);
    assert.equal(box.result.structuredContent.data.box.name, "V1Box");
    assert.equal(box.result.structuredContent.sceneRevision, 1);
    assert.match(max2022.executeRequests.at(-1), /width:10 length:20 height:30/);
    const unchangedScene = await rpc(hostA, { jsonrpc: "2.0", id: 81, method: "tools/call", params: { name: "max_query_scene", arguments: { sinceRevision: 1 } } });
    assert.equal(unchangedScene.result.structuredContent.data.changed, false);
    const changedScene = await rpc(hostA, { jsonrpc: "2.0", id: 82, method: "tools/call", params: { name: "max_query_scene", arguments: { sinceRevision: 0 } } });
    assert.equal(changedScene.result.structuredContent.data.changed, true);
    assert.equal(changedScene.result.structuredContent.data.scene.objectCount, 3);


    const stale = await rpc(hostA, { jsonrpc: "2.0", id: 9, method: "tools/call", params: { name: "max_transform_object", arguments: { node: { name: "V1Box", sceneRevision: 0 }, position: [0, 0, 0] } } });
    assert.equal(stale.result.isError, true);
    assert.equal(stale.result.structuredContent.error.code, "STALE_NODE_REF");

    const validate = await rpc(hostA, { jsonrpc: "2.0", id: 10, method: "tools/call", params: { name: "max_validate_floor_plan", arguments: { plan: PLAN } } });
    const token = validate.result.structuredContent.data.validationToken;
    const build = await rpc(hostA, { jsonrpc: "2.0", id: 11, method: "tools/call", params: { name: "max_build_floor_plan", arguments: { plan: PLAN, validationToken: token } } });
    assert.equal(build.result.isError, false);
    assert.equal(build.result.structuredContent.data.counts.walls, 4);
    assert.match(max2022.executeRequests.at(-1), /Max Ultra MCP: Build floor plan/);
    assert.match(max2022.executeRequests.at(-1), /MCP_Door_D1/);

    const screenshot = await rpc(hostA, { jsonrpc: "2.0", id: 12, method: "tools/call", params: { name: "max_capture_viewport", arguments: { width: 64, height: 32 } } });
    assert.equal(screenshot.result.content[1].type, "image");
    assert.equal(screenshot.result.content[1].mimeType, "image/png");
    assert.equal(screenshot.result.structuredContent.data.screenshot.width, 64);
    assert.equal(screenshot.result.structuredContent.data.screenshot.height, 32);

    const renderStart = await rpc(hostA, { jsonrpc: "2.0", id: 13, method: "tools/call", params: { name: "max_render_start", arguments: { mode: "production" } } });
    const jobId = renderStart.result.structuredContent.data.jobId;
    assert.equal(typeof jobId, "string");
    await waitFor(() => max2022.executeRequests.some((script) => /local b=render\(\)/.test(script)));
    const renderWait = await rpc(hostA, { jsonrpc: "2.0", id: 14, method: "tools/call", params: { name: "max_render_wait", arguments: { jobId, timeout_ms: 1000 } } });
    assert.equal(renderWait.result.structuredContent.data.state, "completed");

    const regionStart = await rpc(hostA, { jsonrpc: "2.0", id: 15, method: "tools/call", params: { name: "max_render_start", arguments: { mode: "region", region: { x: 10, y: 20, width: 320, height: 180 } } } });
    const regionJobId = regionStart.result.structuredContent.data.jobId;
    await waitFor(() => max2022.executeRequests.some((script) => /rendRegionWidth=320/.test(script)));
    const regionWait = await rpc(hostA, { jsonrpc: "2.0", id: 16, method: "tools/call", params: { name: "max_render_wait", arguments: { jobId: regionJobId, timeout_ms: 1000 } } });
    assert.equal(regionWait.result.structuredContent.data.state, "completed");

    const invalidArgs = await rpc(hostA, { jsonrpc: "2.0", id: 17, method: "tools/call", params: { name: "max_create_box", arguments: { unexpected: true } } });
    assert.equal(invalidArgs.error.code, -32602);
  } finally {
    hostA.close();
    hostB.close();
    max2022.disconnect();
    max2027.disconnect();
    await bridge.stop();
  }

  process.stdout.write(`Max Ultra MCP v1 smoke passed: ${coreTools.length} core, ${archvizTools.length} archviz, ${fullTools.length} full tools\n`);
}

run().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
