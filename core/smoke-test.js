/*
 * Verifies Max Ultra MCP discovery, lifecycle, semantic tools, routing, UI, and screenshots.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { MaxBridge, handleRpcMessage, mcpTools } = require("./server");
const { MockMaxClient } = require("./mock-max-client");
const { BridgeControlClient } = require("./bridge-control-client");
const { AmbiguousMaxInventoryError } = require("../examples/run-max-action");
const { TEST_BOX_NAME, createTestBox } = require("../examples/example-create-box");
const PROJECT_ROOT = path.resolve(__dirname, "..");

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

    assert.equal(fs.existsSync(path.join(PROJECT_ROOT, "01_START_MAX_ULTRA_MCP_FIRST.ms")), true);
    const rootReadme = fs.readFileSync(path.join(PROJECT_ROOT, "README.md"), "utf8");
    const detailedReadmePath = path.join(PROJECT_ROOT, "docs", "README.md");
    const detailedReadme = fs.readFileSync(detailedReadmePath, "utf8");
    assert.ok(rootReadme.length < detailedReadme.length, "Root README must remain the concise primary entry point");
    assert.match(rootReadme, /\[the detailed documentation\]\(docs\/README\.md\)/);
    assert.equal(fs.existsSync(detailedReadmePath), true);
    assert.match(rootReadme, /PowerShell 7 .* is \*\*not required\*\*/);
    assert.match(rootReadme, /Windows PowerShell 5\.1 .*powershell\.exe/);
    assert.match(rootReadme, /powershell\.exe -NoProfile -Command/);
    assert.match(rootReadme, /pwsh -NoProfile -Command/);
    const bootstrapSource = fs.readFileSync(path.join(PROJECT_ROOT, "01_START_MAX_ULTRA_MCP_FIRST.ms"), "utf8");
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
    assert.match(bootstrapSource, /scripts\\\\start-server\.bat/);
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
    assert.match(bootstrapSource, /pnlLogOutline .* pos: \[4,62\] width: 672 height: 386/);
    assert.match(bootstrapSource, /rtbActivity .* pos: \[5,63\] width: 670 height: 384/);
    assert.match(bootstrapSource, /#style_resizing/);
    assert.match(bootstrapSource, /on MaxUltraMcpStatusDialog resized panelSize/);
    assert.match(bootstrapSource, /pnlLogOutline\.width = panelWidth - 8/);
    assert.match(bootstrapSource, /rtbActivity\.width = panelWidth - 10/);
    assert.match(bootstrapSource, /rtbActivity\.height = logHeight - 2/);
    assert.doesNotMatch(bootstrapSource, /on MaxUltraMcpStatusDialog moved panelPosition/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler panelForm "FormClosing" handlePanelFormClosing/);
    assert.match(bootstrapSource, /local finalLocation = formSender\.Location/);
    assert.match(bootstrapSource, /persistPanelPosition \[finalLocation\.X as integer, finalLocation\.Y as integer\]/);
    const formClosingBody = bootstrapSource.slice(bootstrapSource.indexOf("fn handlePanelFormClosing"), bootstrapSource.indexOf("fn attachPanelFormClosing"));
    assert.match(formClosingBody, /pollTimer\.Stop\(\)[\s\S]*pollTimer\.Dispose\(\)/);
    assert.ok(formClosingBody.indexOf("persistPanelPosition") < formClosingBody.indexOf("CancelAsync"), "Final panel position must be saved before transport cleanup");
    assert.match(bootstrapSource, /panelPositionIsVisible/);
    assert.match(bootstrapSource, /System\.Windows\.Forms\.Screen/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "panel" "x"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "panel" "x" panelXString/);
    assert.doesNotMatch(bootstrapSource, /as integer\s+as string/);
    assert.match(bootstrapSource, /pos: \(loadPanelPosition\(\)\)/);
    assert.match(bootstrapSource, /PrimaryScreen\.WorkingArea/);
    assert.match(bootstrapSource, /colorMan\.getColor themeColorKey/);
    assert.match(bootstrapSource, /fn lighterThemeSurface/);
    assert.match(bootstrapSource, /local panelThemeBackground = themeDrawingColor #background 68 68 68/);
    assert.match(bootstrapSource, /lblStatus\.BackColor = panelThemeBackground/);
    assert.match(bootstrapSource, /lblContext\.BackColor = panelThemeBackground/);
    assert.doesNotMatch(bootstrapSource, /lbl(?:Status|Context)\.BackColor = statusDialog\.rtbActivity\.BackColor/);
    assert.match(bootstrapSource, /rtbActivity\.BackColor = lighterThemeSurface\(\)/);
    assert.match(bootstrapSource, /\* 0\.14\) as integer/);
    assert.match(bootstrapSource, /pnlLogOutline\.BackColor = \(dotNetClass "System\.Drawing\.Color"\)\.Black/);
    assert.match(bootstrapSource, /rtbActivity\.BorderStyle = \(dotNetClass "System\.Windows\.Forms\.BorderStyle"\)\.None/);
    assert.match(bootstrapSource, /FontStyle"\)\.Bold/);
    assert.match(bootstrapSource, /AccessibleName = "Max Ultra MCP connection status"/);
    assert.match(bootstrapSource, /maximumActivityEntries = 30/);
    assert.match(bootstrapSource, /SelectionColor = activityEntryColor/);
    assert.match(bootstrapSource, /FromArgb 255 125 125/);
    assert.match(bootstrapSource, /FromArgb 255 195 80/);
    assert.match(bootstrapSource, /FromArgb 120 225 150/);
    assert.match(bootstrapSource, /FromArgb 110 205 235/);
    assert.match(bootstrapSource, /FromArgb 20 90 145/);
    assert.match(bootstrapSource, /AppendText activityEntry/);
    assert.match(bootstrapSource, /ScrollToCaret\(\)/);
    assert.match(bootstrapSource, /fn showRestoreBubble/);
    assert.match(bootstrapSource, /FormBorderStyle"\)\.None/);
    assert.match(bootstrapSource, /ShowInTaskbar = false/);
    assert.match(bootstrapSource, /workingArea\.Bottom - restoreBubbleForm\.Height - 12/);
    assert.match(bootstrapSource, /restoreBubbleButton\.AccessibleName = "Restore Max Ultra MCP panel"/);
    const hidePanelBody = bootstrapSource.slice(bootstrapSource.indexOf("fn hidePanel"), bootstrapSource.indexOf("fn closeForLifecycle"));
    assert.match(hidePanelBody, /persistPanelPosition/);
    assert.match(hidePanelBody, /panelForm\.Hide\(\)/);
    assert.match(hidePanelBody, /showRestoreBubble\(\)/);
    assert.doesNotMatch(hidePanelBody, /CancelAsync|shutdown_when_idle|destroyDialog|handleViewportScreenshot|disposeForReload/);
    assert.match(bootstrapSource, /ProcessWindowStyle"\)\.Minimized/);
    assert.match(bootstrapSource, /workerControlRequest workerHost workerPort "shutdown_owned_when_idle"/);
    assert.match(bootstrapSource, /ownerMatched/);
    assert.match(bootstrapSource, /startTransport allowServerLaunch: true/);
    assert.match(bootstrapSource, /startTransport allowServerLaunch: false/);
    assert.match(bootstrapSource, /workerOwnedIdentity = probeReply\.responsePayload/);
    assert.doesNotMatch(bootstrapSource, /workerArguments\.Item\[11\] = probeReply\.responsePayload/);
    assert.ok(bootstrapSource.indexOf("workerOwnedIdentity = probeReply.responsePayload") < bootstrapSource.indexOf("workerClient.Connect workerHost workerPort"), "Launched-server identity must be captured locally before TCP registration");
    assert.match(bootstrapSource, /if \(workerSender\.CancellationPending\) do throw "Server startup cancelled"[\s\S]*workerLaunchServer/);
    assert.doesNotMatch(bootstrapSource, /mod tickCount 20[^\n]*startTransport/);
    const timerBody = bootstrapSource.slice(bootstrapSource.indexOf("fn handleTimerTick"), bootstrapSource.indexOf("fn startBridge"));
    assert.match(timerBody, /pendingConnectOnly/);
    assert.doesNotMatch(timerBody, /workerLaunchServer/);
    assert.match(formClosingBody, /shutdownIdentity/);
    assert.match(formClosingBody, /transportWorkerArguments\.Item\[8\] = true/);
    assert.match(formClosingBody, /if \(shutdownIdentity != ""\) do transportWorkerArguments\.Item\[11\] = shutdownIdentity/);
    assert.doesNotMatch(formClosingBody, /transportWorkerArguments\.Item\[8\] = shutdownIdentity != ""/);
    assert.match(formClosingBody, /Item\[8\] = true[\s\S]*CancelAsync\(\)/);
    assert.match(formClosingBody, /transportWorkerArguments\.Item\[9\] = true/);
    assert.match(formClosingBody, /RunWorkerAsync transportWorkerArguments/);
    assert.match(bootstrapSource, /if \(workerArguments\.Count >= 12 and workerArguments\.Item\[8\]\) do workerRequestOwnedIdleShutdown workerInboundQueue workerHost workerPort workerOwnedIdentity/);
    assert.match(bootstrapSource, /hasConnectedThisSession = true/);
    assert.match(bootstrapSource, /if \(hasConnectedThisSession\) then/);
    assert.match(bootstrapSource, /else if \(connectionError == ""\) do/);
    assert.match(bootstrapSource, /Initial server connection ended before this Max registered/);
    assert.match(bootstrapSource, /Server connection ended\. Run 01_START_MAX_ULTRA_MCP_FIRST\.ms to start it again\./);
    assert.match(bootstrapSource, /Connect-only retry requested; a stopped server will not be launched/);
    assert.match(bootstrapSource, /restartServerForReload = true/);
    assert.match(bootstrapSource, /#preSystemShutdown/);
    assert.match(bootstrapSource, /workerFindFreeFallbackPort/);
    assert.match(bootstrapSource, /#legacyCandidate/);
    assert.match(bootstrapSource, /"port_changed"/);
    assert.equal((bootstrapSource.match(/fn refreshUserInterface = \(/g) || []).length, 1);
    assert.match(bootstrapSource, /UIAccessor\.PressButton/);
    assert.match(bootstrapSource, /uiHandleBelongsToMax/);

    const mismatchedIdentity = { ...probeResponse, startedAt: "not-the-running-server" };
    await assert.rejects(controlClient.shutdownOwnedWhenIdle(mismatchedIdentity), /ownership identity does not match/);
    assert.equal(shutdownRequests, 1, "Mismatched ownership must never stop a server");
    assert.equal(bridge.shutdownWhenIdle, false, "Mismatched ownership must not arm idle shutdown");
    const ownedIdleShutdownResponse = await controlClient.shutdownOwnedWhenIdle(probeResponse);
    assert.equal(ownedIdleShutdownResponse.server, "max-ultra-mcp");
    assert.equal(ownedIdleShutdownResponse.armed, true);
    assert.equal(ownedIdleShutdownResponse.ownerMatched, true);
    assert.equal(ownedIdleShutdownResponse.connected, 1);
    const idleShutdownResponse = await controlClient.shutdownWhenIdle();
    assert.equal(idleShutdownResponse.server, "max-ultra-mcp");
    assert.equal(idleShutdownResponse.armed, true);
    assert.equal(idleShutdownResponse.connected, 1);
    assert.equal(shutdownRequests, 1, "Arming idle shutdown must not stop a server with a connected Max");
    max2027.disconnect();
    await waitFor(() => shutdownRequests === 2);

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
