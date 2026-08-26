/* Contract and integration smoke tests for Max Ultra MCP v1. */

"use strict";

const assert = require("node:assert/strict");
const { MaxBridge } = require("../core/server");
const { MockMaxClient } = require("./helpers/mock-max-client");
const { BridgeControlClient } = require("../core/bridge-control-client");
const { StdioHost } = require("../core/stdio-host");
const { getMcpTools } = require("../core/tool-catalog");
const { generateFloorPlanScript, validateFloorPlan } = require("../core/floor-plan");
const { JobRegistry } = require("../core/job-registry");
const { generateMaterialDiagnosticsScript } = require("../core/material-diagnostics");
const { createPlanToken, verifyPlanToken } = require("../core/plan-token");
const { generatePolygonMeshScript, validatePolygonMesh } = require("../core/polygon-mesh");
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

const POLYGON_CUBE = {
  name: "AgentPolygonCube",
  units: "mm",
  vertices: [
    [-500, -500, -500], [500, -500, -500], [500, 500, -500], [-500, 500, -500],
    [-500, -500, 500], [500, -500, 500], [500, 500, 500], [-500, 500, 500],
  ],
  faces: [
    [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
    [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
  ],
  position: [0, 0, 500],
  layer: "MCP_MODELING",
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
  assert.equal(coreTools.some((entry) => entry.name === "max_validate_polygon_mesh"), true);
  assert.equal(coreTools.some((entry) => entry.name === "max_create_polygon_mesh"), true);
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
  assert.match(generatedExample.script, /splineShape name:sourceSplineName/);
  assert.match(generatedExample.script, /local wallMesh = copy wallPlanSource/);
  assert.match(generatedExample.script, /addModifier wallMesh \(Extrude/);
  assert.match(generatedExample.script, /convertToMesh wallMesh/);
  assert.match(generatedExample.script, /meshop\.deleteFaces wallMesh/);
  assert.match(generatedExample.script, /meshop\.setNumVerts wallMesh/);
  assert.match(generatedExample.script, /meshop\.setVert wallMesh/);
  assert.match(generatedExample.script, /meshop\.createPolygon targetMesh/);
  assert.match(generatedExample.script, /convertToPoly wallMesh/);
  assert.match(generatedExample.script, /wallPlanSource\.isHidden = true/);
  const sourceSplineIndex = generatedExample.script.indexOf("local wallPlanSource = splineShape");
  const copiedWallIndex = generatedExample.script.indexOf("local wallMesh = copy wallPlanSource");
  const extrudeIndex = generatedExample.script.indexOf("addModifier wallMesh (Extrude");
  const collapseIndex = generatedExample.script.indexOf("convertToMesh wallMesh");
  const meshOpIndex = generatedExample.script.indexOf("meshop.deleteFaces wallMesh");
  assert.ok(sourceSplineIndex < copiedWallIndex && copiedWallIndex < extrudeIndex && extrudeIndex < collapseIndex && collapseIndex < meshOpIndex);
  assert.doesNotMatch(generatedExample.script, /addModifier wallPlanSource|convertToMesh wallPlanSource|convertToPoly wallPlanSource/);
  assert.match(generatedExample.script, /dummy name:"MCP_Door_DOOR_MAIN"/);
  assert.doesNotMatch(generatedExample.script, /box name:/i);
  assert.doesNotMatch(generatedExample.script, /boolean|ProBoolean/i);
  assert.equal(generatedExample.sourceSplineName, "MCP_WallPlan_SOURCE");
  assert.equal(generatedExample.wallMeshName, "MCP_Walls");
  assert.equal(generatedExample.modelingWorkflow, "spline-copy-extrude-meshop");
  assert.ok(generatedExample.segmentCount > exampleValidation.counts.walls);

  assert.notEqual(validateFloorPlan(changed).validationToken, validation.validationToken);

  const polygonValidation = validatePolygonMesh(POLYGON_CUBE);
  assert.equal(polygonValidation.valid, true);
  assert.deepEqual(polygonValidation.blockers, []);
  assert.equal(polygonValidation.validationToken.length, 64);
  assert.deepEqual(polygonValidation.counts, {
    vertices: 8, faces: 6, edges: 12, boundaryEdges: 0,
    nonManifoldEdges: 0, isolatedVertices: 0, faceVertexReferences: 24,
  });
  assert.deepEqual(polygonValidation.boundingBox, { min: [-500, -500, -500], max: [500, 500, 500], size: [1000, 1000, 1000] });
  const polygonScript = generatePolygonMeshScript(polygonValidation.normalizedMesh).script;
  assertBalancedGeneratedMaxScript(polygonScript);
  assert.match(polygonScript, /units\.decodeValue "1mm"/);
  assert.match(polygonScript, /meshop\.createPolygon/);
  assert.match(polygonScript, /undo off/);
  assert.match(polygonScript, /convertToPoly createdNode/);
  assert.doesNotMatch(polygonScript, /\bexecute\b/i);
  const changedPolygon = structuredClone(POLYGON_CUBE);
  changedPolygon.position = [10, 0, 500];
  assert.notEqual(validatePolygonMesh(changedPolygon).validationToken, polygonValidation.validationToken);
  const invalidPolygon = structuredClone(POLYGON_CUBE);
  invalidPolygon.faces[0] = [0, 3, 2, 99];
  assert.match(validatePolygonMesh(invalidPolygon).blockers[0], /highest valid index is 7/);

  const planBinding = {
    operation: "fixture_operation",
    instanceId: "mock-max-2027-1",
    sceneRevision: 4,
    request: { targets: ["A", "B"] },
    targets: [{ handle: 1001 }, { handle: 1002 }],
    capabilities: { adapter: "generic" },
  };
  const planToken = createPlanToken(planBinding);
  assert.equal(planToken.length, 64);
  assert.equal(verifyPlanToken(planToken, structuredClone(planBinding)), true);
  assert.throws(() => verifyPlanToken(planToken, { ...planBinding, sceneRevision: 5 }), /STALE_PLAN/);

  const materialDiagnosticScript = generateMaterialDiagnosticsScript({ includeHidden: true, limit: 25 });
  assertBalancedGeneratedMaxScript(materialDiagnosticScript);
  assert.match(materialDiagnosticScript, /Max Ultra MCP: Find material diagnostics/);
  assert.match(materialDiagnosticScript, /getClassInstances Bitmaptexture/);
  assert.match(materialDiagnosticScript, /doesFileExist bitmapPath/);
  assert.doesNotMatch(materialDiagnosticScript, /select nodeValue|delete nodeValue/);

  const isolatedJobs = new JobRegistry({ maximumJobs: 10 });
  const isolatedJob = isolatedJobs.create({ type: "fixture", instanceId: "mock-max-2027-1" });
  isolatedJobs.start(isolatedJob, async () => ({ manifest: ["verified"] }));
  assert.equal((await isolatedJobs.wait(isolatedJob.jobId, 1000)).state, "completed");
  assert.deepEqual(isolatedJobs.getResult(isolatedJob.jobId).result, { manifest: ["verified"] });
  assert.equal(isolatedJobs.list({ type: "fixture" }).length, 1);

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
    assert.equal(initialize.result.serverInfo.version, "1.1.0");
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
    const infoA = await rpc(hostA, { jsonrpc: "2.0", id: 71, method: "tools/call", params: { name: "max_get_info", arguments: {} } });
    assert.deepEqual(infoA.result.structuredContent.data.info.units, { systemType: "Millimeters", systemScale: 1, displayType: "Metric" });

    const materialIssues = await rpc(hostA, { jsonrpc: "2.0", id: 72, method: "tools/call", params: { name: "max_material_find_unassigned", arguments: {} } });
    assert.equal(materialIssues.result.isError, false, JSON.stringify(materialIssues.result.structuredContent));
    assert.equal(materialIssues.result.structuredContent.data.matched, 2);
    assert.equal(materialIssues.result.structuredContent.data.counts.noMaterial, 1);
    assert.equal(materialIssues.result.structuredContent.data.counts.emptyMultiSubSlot, 1);
    assert.equal(materialIssues.result.structuredContent.data.categories.noMaterial[0].node.sceneRevision, 0);
    assert.equal(max2022.activityLabels.at(-1), "Find material issues");

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


    const validatePolygon = await rpc(hostA, { jsonrpc: "2.0", id: 83, method: "tools/call", params: { name: "max_validate_polygon_mesh", arguments: { mesh: POLYGON_CUBE } } });
    const polygonToken = validatePolygon.result.structuredContent.data.validationToken;
    const createPolygon = await rpc(hostA, { jsonrpc: "2.0", id: 84, method: "tools/call", params: { name: "max_create_polygon_mesh", arguments: { mesh: POLYGON_CUBE, validationToken: polygonToken } } });
    assert.equal(createPolygon.result.isError, false, JSON.stringify(createPolygon.result.structuredContent));
    assert.deepEqual(createPolygon.result.structuredContent.data.topology, { vertices: 8, edges: 12, faces: 6, openEdges: 0 });
    assert.equal(createPolygon.result.structuredContent.data.node.name, "AgentPolygonCube");
    assert.equal(createPolygon.result.structuredContent.data.node.sceneRevision, 2);
    assert.equal(createPolygon.result.structuredContent.data.baseObjectClass, "Editable_Poly");
    assert.match(max2022.executeRequests.at(-1), /Max Ultra MCP: Create polygon mesh/);
    const rejectedPolygon = structuredClone(POLYGON_CUBE);
    rejectedPolygon.position = [10, 0, 500];
    const stalePolygonPlan = await rpc(hostA, { jsonrpc: "2.0", id: 85, method: "tools/call", params: { name: "max_create_polygon_mesh", arguments: { mesh: rejectedPolygon, validationToken: polygonToken } } });
    assert.equal(stalePolygonPlan.result.structuredContent.error.code, "VALIDATION_FAILED");
    const stale = await rpc(hostA, { jsonrpc: "2.0", id: 9, method: "tools/call", params: { name: "max_transform_object", arguments: { node: { name: "V1Box", sceneRevision: 0 }, position: [0, 0, 0] } } });
    assert.equal(stale.result.isError, true);
    assert.equal(stale.result.structuredContent.error.code, "STALE_NODE_REF");

    const validate = await rpc(hostA, { jsonrpc: "2.0", id: 10, method: "tools/call", params: { name: "max_validate_floor_plan", arguments: { plan: PLAN } } });
    const token = validate.result.structuredContent.data.validationToken;
    const build = await rpc(hostA, { jsonrpc: "2.0", id: 11, method: "tools/call", params: { name: "max_build_floor_plan", arguments: { plan: PLAN, validationToken: token } } });
    assert.equal(build.result.isError, false);
    assert.equal(build.result.structuredContent.data.counts.walls, 4);
    assert.equal(build.result.structuredContent.data.sourceSplineName, "MCP_WallPlan_SOURCE");
    assert.equal(build.result.structuredContent.data.wallMeshName, "MCP_Walls");
    assert.equal(build.result.structuredContent.data.modelingWorkflow, "spline-copy-extrude-meshop");
    assert.match(max2022.executeRequests.at(-1), /Max Ultra MCP: Build floor plan/);
    assert.match(max2022.executeRequests.at(-1), /local wallMesh = copy wallPlanSource/);
    assert.match(max2022.executeRequests.at(-1), /meshop\.createPolygon targetMesh/);
    assert.match(max2022.executeRequests.at(-1), /MCP_Door_D1/);

    const screenshot = await rpc(hostA, { jsonrpc: "2.0", id: 12, method: "tools/call", params: { name: "max_capture_viewport", arguments: { width: 64, height: 32 } } });
    assert.equal(screenshot.result.content[1].type, "image");
    assert.equal(screenshot.result.content[1].mimeType, "image/png");
    assert.equal(screenshot.result.structuredContent.data.screenshot.width, 64);
    assert.equal(screenshot.result.structuredContent.data.screenshot.height, 32);

    const frameSelection = await rpc(hostA, { jsonrpc: "2.0", id: 121, method: "tools/call", params: { name: "max_frame_selection", arguments: {} } });
    assert.equal(frameSelection.result.isError, false, JSON.stringify(frameSelection.result.structuredContent));
    assert.match(max2022.executeRequests.at(-1), /max zoomext sel;/);
    assert.doesNotMatch(max2022.executeRequests.at(-1), /max zoomext sel all/);

    const zoomExtents = await rpc(hostA, { jsonrpc: "2.0", id: 122, method: "tools/call", params: { name: "max_zoom_extents", arguments: {} } });
    assert.equal(zoomExtents.result.isError, false, JSON.stringify(zoomExtents.result.structuredContent));
    assert.match(max2022.executeRequests.at(-1), /max tool zoomextents;/);
    assert.doesNotMatch(max2022.executeRequests.at(-1), /max zoomext all|zoomextents all/);

    const renderStart = await rpc(hostA, { jsonrpc: "2.0", id: 13, method: "tools/call", params: { name: "max_render_start", arguments: { mode: "production" } } });
    const jobId = renderStart.result.structuredContent.data.jobId;
    assert.equal(typeof jobId, "string");
    await waitFor(() => max2022.executeRequests.some((script) => /local b=render\(\)/.test(script)));
    const renderWait = await rpc(hostA, { jsonrpc: "2.0", id: 14, method: "tools/call", params: { name: "max_render_wait", arguments: { jobId, timeout_ms: 1000 } } });
    assert.equal(renderWait.result.structuredContent.data.state, "completed");
    const commonJobStatus = await rpc(hostA, { jsonrpc: "2.0", id: 141, method: "tools/call", params: { name: "max_job_status", arguments: { jobId } } });
    assert.equal(commonJobStatus.result.structuredContent.data.type, "render");
    assert.equal(commonJobStatus.result.structuredContent.data.state, "completed");
    const commonJobList = await rpc(hostA, { jsonrpc: "2.0", id: 142, method: "tools/call", params: { name: "max_job_list", arguments: { type: "render" } } });
    assert.equal(commonJobList.result.structuredContent.data.jobs.some((entry) => entry.jobId === jobId), true);
    const commonJobResult = await rpc(hostA, { jsonrpc: "2.0", id: 143, method: "tools/call", params: { name: "max_job_result", arguments: { jobId } } });
    assert.equal(commonJobResult.result.content[1]?.type, "image", JSON.stringify(commonJobResult));
    assert.equal(commonJobResult.result.structuredContent.data.result.mode, "production");
    const foreignJob = await rpc(hostB, { jsonrpc: "2.0", id: 144, method: "tools/call", params: { name: "max_job_status", arguments: { jobId } } });
    assert.equal(foreignJob.result.structuredContent.error.code, "JOB_NOT_FOUND");

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
