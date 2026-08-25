/*
 * Verifies Max Ultra MCP discovery, semantic tools, routing, control, UI, and screenshots.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Developed by https://3dground.net (3DGROUND)
 */

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const { MaxBridge, handleRpcMessage, mcpTools } = require("./server");
const { MockMaxClient } = require("./mock-max-client");
const { BridgeControlClient } = require("./bridge-control-client");
const { AmbiguousMaxInventoryError } = require("./run-max-action");
const { TEST_BOX_NAME, createTestBox } = require("./example-create-box");

async function waitFor(predicate, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("Timed out waiting for bridge state");
}

function assertBalancedMaxScript(source) {
  const opening = new Map([["(", ")"], ["[", "]"], ["{", "}"]]);
  const closing = new Set(opening.values());
  const stack = [];
  let inString = false;
  let inVerbatimString = false;
  let inComment = false;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (inComment) {
      if (character === "\n") inComment = false;
      continue;
    }
    if (!inString && character === "-" && source[index + 1] === "-") {
      inComment = true;
      index += 1;
      continue;
    }
    if (character === '"') {
      if (!inString) {
        inString = true;
        inVerbatimString = source[index - 1] === "@";
      } else if (inVerbatimString) {
        inString = false;
        inVerbatimString = false;
      } else {
        let precedingBackslashes = 0;
        for (let cursor = index - 1; cursor >= 0 && source[cursor] === "\\"; cursor -= 1) precedingBackslashes += 1;
        if (precedingBackslashes % 2 === 0) inString = false;
      }
      continue;
    }
    if (inString) continue;
    if (opening.has(character)) stack.push({ expected: opening.get(character), offset: index });
    else if (closing.has(character)) assert.equal(character, stack.pop()?.expected, `Unbalanced MaxScript delimiter at offset ${index}`);
  }
  assert.equal(inString, false, "Unterminated MaxScript string");
  assert.deepEqual(stack, [], `Unclosed MaxScript delimiters: ${JSON.stringify(stack)}`);
}

async function runSmokeTest() {
  let shutdownRequests = 0;
  const bridge = new MaxBridge({ port: 0, requestTimeoutMs: 1000, shutdownHandler: () => { shutdownRequests += 1; } });
  await bridge.start();
  const max2022 = new MockMaxClient({ port: bridge.port, maxVersion: "2022", pid: 22022, instanceId: "test-max-2022" });
  const max2027 = new MockMaxClient({ port: bridge.port, maxVersion: "2027", pid: 22027, instanceId: "test-max-2027" });
  const controlClient = new BridgeControlClient({ port: bridge.port, timeoutMs: 1000 });
  const quietOutput = { write() {} };
  try {
    await Promise.all([max2022.connect(), max2027.connect()]);
    await waitFor(() => bridge.listInstances().length === 2 && bridge.listInstances().every((entry) => entry.scene));

    const discoveryResponse = await bridge.callTool("max_list_instances");
    assert.equal(discoveryResponse.count, 2);
    assert.equal(discoveryResponse.selectionRequired, true);
    assert.equal(discoveryResponse.selectedInstanceId, null);
    assert.deepEqual(discoveryResponse.instances.map((entry) => entry.maxVersion), ["2022", "2027"]);
    assert.equal("processStartedAt" in discoveryResponse.instances[0], false);
    assert.throws(() => bridge.selectInstance(), /max_select_instance/);

    await controlClient.connect();
    const probeResponse = await controlClient.probe();
    assert.equal(probeResponse.server, "max-ultra-mcp");
    assert.equal(probeResponse.wireVersion, "1");
    assert.equal(probeResponse.healthy, true);
    assert.equal(typeof probeResponse.pid, "number");
    const shutdownResponse = await controlClient.shutdownServer();
    assert.equal(shutdownResponse.server, "max-ultra-mcp");
    assert.equal(shutdownResponse.shuttingDown, true);
    await waitFor(() => shutdownRequests === 1);
    const controlInventory = await controlClient.listInstances();
    assert.equal(controlInventory.count, 2);
    await assert.rejects(createTestBox({ client: controlClient, output: quietOutput, throwOnError: true }), (error) => {
      assert.equal(error instanceof AmbiguousMaxInventoryError, true);
      assert.equal(error.inventory.count, 2);
      return true;
    });
    assert.equal(max2022.executeRequests.length, 0);
    assert.equal(max2027.executeRequests.length, 0);

    const healthResponse = await bridge.callTool("max_health", { instance_id: "test-max-2022" });
    assert.equal(healthResponse.health.mainThread, true);
    const snapshotResponse = await bridge.callTool("max_snapshot", { instance_id: "test-max-2027" });
    assert.equal(snapshotResponse.snapshot.scene.objectCount, 3);
    const summaryResponse = await bridge.callTool("max_scene_summary", { instance_id: "test-max-2022" });
    assert.equal(summaryResponse.scene.objectCount, 3);
    assert.equal("details" in summaryResponse, false);
    const logsResponse = await bridge.callTool("max_logs", { instance_id: "test-max-2022", tail: 5 });
    assert.equal(logsResponse.panelLog.available, true);
    assert.equal(logsResponse.panelLog.source, "Max Ultra MCP panel");
    const smokeResponse = await bridge.callTool("max_smoke", { instance_id: "test-max-2027" });
    assert.equal(smokeResponse.smoke.ok, true);

    await assert.rejects(bridge.request("test-max-2027", "never", "", 50), /queued work was cancelled/);
    await waitFor(() => max2027.cancelledRequests.size === 1);

    const executionResponse = await bridge.callTool("max_execute", {
      instance_id: "test-max-2022", script: "format \"mock-only\\n\"", timeout_ms: 1000,
    });
    assert.equal(executionResponse.execution.mainThread, true);
    assert.match(executionResponse.execution.result, /mock-only/);
    const panelResponse = await bridge.callTool("max_panel", { instance_id: "test-max-2027", action: "minimize" });
    assert.equal(panelResponse.panel.state, "minimize");

    const uiListResponse = await bridge.callTool("max_ui_list", {
      instance_id: "test-max-2022", scope: "max_window", max_depth: 3, limit: 20, class_contains: "Button",
    });
    assert.equal(uiListResponse.controls[1].className, "Button");
    assert.equal("rect" in uiListResponse.controls[1], false);
    const detailedUi = await bridge.callTool("max_ui_list", {
      instance_id: "test-max-2022", scope: "max_window", limit: 20, details: true,
    });
    assert.equal(detailedUi.ui.mainThread, true);
    assert.equal(detailedUi.ui.controls[1].rect, "[10,10,120,30]");
    const uiInvokeResponse = await bridge.callTool("max_ui_invoke", {
      instance_id: "test-max-2022", target_hwnd: "1001", action: "press_button",
      expected_text: "Mock Button", expected_class: "Button",
    });
    assert.equal(uiInvokeResponse.result, "mock-invoked");

    const expectedTools = [
      "max_list_instances", "max_select_instance", "max_scene_summary", "max_create_box", "max_health", "max_snapshot",
      "max_logs", "max_smoke", "max_execute", "max_panel", "max_ui_list", "max_ui_invoke", "max_viewport_screenshot",
    ];
    assert.deepEqual(mcpTools.map((toolInfo) => toolInfo.name), expectedTools);
    assert.equal(mcpTools.find((toolInfo) => toolInfo.name === "max_create_box").annotations.destructiveHint, true);
    assert.equal(mcpTools.find((toolInfo) => toolInfo.name === "max_execute").annotations.openWorldHint, true);

    const rpcResponses = [];
    const captureRpcResponse = (rpcResponse) => rpcResponses.push(rpcResponse);
    await handleRpcMessage(bridge, { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } }, captureRpcResponse);
    await handleRpcMessage(bridge, { jsonrpc: "2.0", id: 2, method: "tools/list" }, captureRpcResponse);
    await handleRpcMessage(bridge, { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "max_health", arguments: {} } }, captureRpcResponse);
    await handleRpcMessage(
      bridge,
      { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "max_viewport_screenshot", arguments: { instance_id: "test-max-2027" } } },
      captureRpcResponse,
    );
    assert.equal(rpcResponses[0].result.protocolVersion, "2025-06-18");
    assert.equal(rpcResponses[0].result.serverInfo.name, "max-ultra-mcp");
    assert.match(rpcResponses[0].result.instructions, /semantic tools first/);
    assert.equal(rpcResponses[1].result.tools.length, 13);
    assert.equal(rpcResponses[2].result.isError, true);
    assert.match(rpcResponses[2].result.content[0].text, /max_select_instance/);
    assert.equal(rpcResponses[3].result.content[1].type, "image");
    assert.equal(rpcResponses[3].result.content[1].mimeType, "image/png");
    assert.equal(rpcResponses[3].result.structuredContent.screenshot.temporaryFileRemoved, true);

    const selectionResponse = await bridge.callTool("max_select_instance", { instance_id: "test-max-2027" });
    assert.equal(selectionResponse.selected.instanceId, "test-max-2027");
    const selectedInventory = await bridge.callTool("max_list_instances");
    assert.equal(selectedInventory.selectionRequired, false);
    assert.equal(selectedInventory.selectedInstanceId, "test-max-2027");
    const selectedSummary = await bridge.callTool("max_scene_summary", {});
    assert.equal(selectedSummary.instanceId, "test-max-2027");

    const semanticBox = await bridge.callTool("max_create_box", {
      name: "SemanticBox", position: { x: 1, y: 2, z: 3 }, dimensions: { length: 10, width: 11, height: 12 }, select: false,
    });
    assert.deepEqual(semanticBox.box.position, { x: 1, y: 2, z: 3 });
    assert.deepEqual(semanticBox.box.dimensions, { length: 10, width: 11, height: 12 });
    assert.equal(semanticBox.box.selected, false);
    assert.equal("details" in semanticBox, false);
    assert.ok(JSON.stringify(semanticBox).length < 350);
    assert.match(max2027.executeRequests[0], /box name:"SemanticBox"/);
    assert.match(max2027.executeRequests[0], /pos:\[1,2,3\]/);
    assert.doesNotMatch(max2027.executeRequests[0], /save(MaxFile|Nodes|AsVersion)/i);
    await assert.rejects(bridge.callTool("max_create_box", { dimensions: { height: 0 } }), /positive finite number/);

    max2022.disconnect();
    await waitFor(() => bridge.listInstances().length === 1);
    const automaticSelection = await bridge.callTool("max_health", {});
    assert.equal(automaticSelection.instance.instanceId, "test-max-2027");

    const boxResponse = await createTestBox({ client: controlClient, output: quietOutput, throwOnError: true });
    assert.equal(boxResponse.instance.instanceId, "test-max-2027");
    const exampleScript = max2027.executeRequests.at(-1);
    assert.match(exampleScript, new RegExp(`box name:"${TEST_BOX_NAME}"`));
    assert.match(exampleScript, /pos:\[0,0,0\]/);
    assert.doesNotMatch(exampleScript, /save(MaxFile|Nodes|AsVersion)/i);

    assert.equal(fs.existsSync(require.resolve("./01_START_MAX_ULTRA_MCP_FIRST.ms")), true);
    assert.equal(fs.existsSync("./MaxUltraMcpBootstrap.ms"), false);
    const bootstrapSource = fs.readFileSync(require.resolve("./01_START_MAX_ULTRA_MCP_FIRST.ms"), "utf8");
    assertBalancedMaxScript(bootstrapSource);
    assert.match(bootstrapSource, /FIRST STEP: Run this file/);
    assert.match(bootstrapSource, /CSharpUtilities\.SynchronizingBackgroundWorker/);
    assert.match(bootstrapSource, /CONTROL\\t1\\tbootstrap-control\\t/);
    assert.match(bootstrapSource, /workerControlRequest workerHost workerPort "probe"/);
    assert.match(bootstrapSource, /workerControlRequest workerHost workerPort "shutdown"/);
    assert.match(bootstrapSource, /"System\.Threading\.Mutex" false workerMutexName/);
    assert.match(bootstrapSource, /ProcessStartInfo/);
    assert.match(bootstrapSource, /UseShellExecute = true/);
    assert.match(bootstrapSource, /--no-pause/);
    assert.match(bootstrapSource, /ConnectAsync workerHost workerPort/);
    assert.match(bootstrapSource, /retryDelays = #\(150, 250, 500, 750, 1000, 1500, 2000\)/);
    assert.match(bootstrapSource, /MAX_ULTRA_MCP_ROOT/);
    assert.match(bootstrapSource, /MaxUltraMcpActiveClient/);
    assert.match(bootstrapSource, /disposeForReload/);
    assert.doesNotMatch(bootstrapSource, /WaitForExit/);
    assert.match(bootstrapSource, /maximumInboundLinesPerTick = 16/);
    assert.match(bootstrapSource, /maximumRequestsPerTick = 1/);
    assert.equal((bootstrapSource.match(/\.Connect workerHost workerPort/g) || []).length, 1);
    assert.match(bootstrapSource, /System\.Windows\.Forms\.RichTextBox/);
    assert.doesNotMatch(bootstrapSource, /grpActivity|grpConnection|grpScene|lblEndpoint|lblIdentity|lblSceneStats|Recent activity \/ errors/);
    assert.match(bootstrapSource, /lblStatus .* pos: \[12,10\]/);
    assert.match(bootstrapSource, /lblContext .* pos: \[12,34\]/);
    assert.match(bootstrapSource, /rtbActivity .* pos: \[12,62\] width: 656 height: 386/);
    assert.match(bootstrapSource, /#style_resizing/);
    assert.match(bootstrapSource, /on MaxUltraMcpStatusDialog resized panelSize/);
    assert.match(bootstrapSource, /resizePanelControls panelSize/);
    assert.match(bootstrapSource, /rtbActivity\.width = contentWidth/);
    assert.match(bootstrapSource, /rtbActivity\.height = amax 260/);
    assert.match(bootstrapSource, /on MaxUltraMcpStatusDialog moved panelPosition/);
    assert.match(bootstrapSource, /persistPanelPosition panelPosition/);
    assert.match(bootstrapSource, /panelPositionIsVisible/);
    assert.match(bootstrapSource, /System\.Windows\.Forms\.Screen/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "panel" "x"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "panel" "x"/);
    assert.match(bootstrapSource, /pos: \(loadPanelPosition\(\)\)/);
    assert.match(bootstrapSource, /PrimaryScreen\.WorkingArea/);
    assert.match(bootstrapSource, /AccessibleName = "Max Ultra MCP color-coded activity log"/);
    assert.match(bootstrapSource, /maximumActivityEntries = 30/);
    assert.match(bootstrapSource, /MaxUltraMcpBridgeClient/);
    assert.doesNotMatch(bootstrapSource, /RuntimeMcp|Runtime MCP|MaxPkg-Runtime/);
    assert.match(bootstrapSource, /SelectionColor = activityEntryColor/);
    assert.match(bootstrapSource, /FromArgb 180 0 0/);
    assert.match(bootstrapSource, /FromArgb 145 105 0/);
    assert.match(bootstrapSource, /FromArgb 0 100 0/);
    assert.match(bootstrapSource, /AppendText activityEntry/);
    assert.match(bootstrapSource, /ScrollToCaret\(\)/);
    assert.match(bootstrapSource, /UIAccessor\.PressButton/);
    assert.match(bootstrapSource, /uiHandleBelongsToMax/);

    process.stdout.write("Max Ultra MCP smoke passed: 13 concise/advanced MCP tools, Max 2022 + 2027 routing, safe Box actions, diagnostics, panel, guarded UI, screenshot, cancellation, and bounded async transport\n");
  } finally {
    controlClient.close();
    max2022.disconnect();
    max2027.disconnect();
    await bridge.stop();
  }
}

runSmokeTest().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});