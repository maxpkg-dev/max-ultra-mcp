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
const net = require("node:net");
const os = require("node:os");
const { spawn } = require("node:child_process");
const { MaxBridge, handleRpcMessage, mcpTools } = require("../core/server");
const { version: PACKAGE_VERSION } = require("../core/package.json");
const { MockMaxClient } = require("./helpers/mock-max-client");
const { BridgeControlClient } = require("../core/bridge-control-client");
const { getMcpTools } = require("../core/tool-catalog");
const { activityLabelForTool } = require("../core/tool-runtime");
const { MCP_TITLE_OBJECT_NAME, MCP_TITLE_TEXT, createSplineTextExample } = require("../examples/example-create-spline-text/example-create-spline-text");
const { TEST_BOX_NAME, createTestBox } = require("../examples/example-create-test-box/example-create-test-box");
const { healthCheckExample } = require("../examples/example-health-check/example-health-check");
const { getMaxInfoExample } = require("../examples/example-get-max-info/example-get-max-info");
const { listInstancesExample } = require("../examples/example-list-instances/example-list-instances");
const { QUICK_RENDER_MAXSCRIPT, pressRenderButtonExample } = require("../examples/example-press-render-button/example-press-render-button");
const { sceneSummaryExample } = require("../examples/example-scene-summary/example-scene-summary");
const {
  captureViewportScreenshotExample,
} = require("../examples/example-viewport-screenshot/example-viewport-screenshot");
const PROJECT_ROOT = path.resolve(__dirname, "..");

async function waitFor(predicate, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("Timed out waiting for bridge state");
}

async function reserveLoopbackPort() {
  const reservation = net.createServer();
  await new Promise((resolve, reject) => {
    reservation.once("error", reject);
    reservation.listen(0, "127.0.0.1", resolve);
  });
  const port = reservation.address().port;
  await new Promise((resolve, reject) => reservation.close((error) => (error ? reject(error) : resolve())));
  return port;
}

async function runCommandBat(batchPath, argumentsList, cwd) {
  const quote = (value) => '"' + String(value).replace(/"/g, '""') + '"';
  const commandLine = 'call ' + quote(batchPath) + ' ' + argumentsList.map(quote).join(' ');
  const child = spawn("cmd.exe", ["/d", "/c", commandLine], {
    cwd,
    windowsHide: true,
    windowsVerbatimArguments: true,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  child.stdout.on("data", (chunk) => { output += chunk.toString(); });
  child.stderr.on("data", (chunk) => { output += chunk.toString(); });
  const exitCode = await Promise.race([
    new Promise((resolve) => child.once("exit", resolve)),
    new Promise((resolve) => setTimeout(() => resolve("timeout"), 20000)),
  ]);
  if (exitCode === "timeout" && child.exitCode === null) child.kill();
  return { exitCode, output };
}

async function runBatDetachedShutdownTest() {
  if (process.platform !== "win32") return;
  const port = await reserveLoopbackPort();
  const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-mcp-owner-"));
  const ownershipFile = path.join(temporaryDirectory, "max-ultra-mcp-owned-" + String(port) + ".json");
  const tokenFile = path.join(temporaryDirectory, "control-token");
  const previousTokenFile = process.env.MAX_ULTRA_MCP_TOKEN_FILE;
  process.env.MAX_ULTRA_MCP_TOKEN_FILE = tokenFile;
  const ownerToken = "smoke-" + process.pid + "-" + Date.now();
  const launcherPath = path.join(PROJECT_ROOT, "scripts", "start-server.bat");
  const helperPath = path.join(PROJECT_ROOT, "scripts", "stop-owned-server.bat");
  const commandLine = 'call "' + launcherPath + '" --no-pause --port ' + String(port) +
    ' --owner-file "' + ownershipFile + '" --owner-token "' + ownerToken + '" --owner-max-pid 22022';
  const child = spawn("cmd.exe", ["/d", "/c", commandLine], {
    cwd: PROJECT_ROOT,
    windowsHide: true,
    windowsVerbatimArguments: true,
    stdio: ["pipe", "pipe", "pipe"],
  });
  let output = "";
  child.stdout.on("data", (chunk) => { output += chunk.toString(); });
  child.stderr.on("data", (chunk) => { output += chunk.toString(); });
  let controlClient;
  try {
    const deadline = Date.now() + 20000;
    let probeResponse;
    let lastConnectError;
    while (Date.now() < deadline && (!probeResponse || !fs.existsSync(ownershipFile))) {
      controlClient = new BridgeControlClient({ port, timeoutMs: 500 });
      try {
        await controlClient.connect();
        probeResponse = await controlClient.probe();
        if (!fs.existsSync(ownershipFile)) {
          controlClient.close();
          controlClient = undefined;
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      } catch (error) {
        lastConnectError = error;
        controlClient.close();
        controlClient = undefined;
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }
    assert.ok(probeResponse, "BAT-launched server did not become healthy (" + (lastConnectError && lastConnectError.message) + "): " + output);
    assert.equal(fs.existsSync(ownershipFile), true, "BAT-launched server did not write its ownership record");
    controlClient.close();
    controlClient = undefined;

    const staleOwnerResult = await runCommandBat(helperPath, [
      "-OwnershipFile", ownershipFile,
      "-Port", String(port),
      "-OwnerToken", ownerToken + "-stale",
      "-ClosingMaxPid", "22022",
      "-MaxProcessCountOverride", "1",
    ], PROJECT_ROOT);
    assert.equal(staleOwnerResult.exitCode, 3, staleOwnerResult.output);
    assert.match(staleOwnerResult.output, /Ownership record does not match/);

    controlClient = new BridgeControlClient({ port, timeoutMs: 1000 });
    await controlClient.connect();
    await controlClient.probe();
    controlClient.close();
    controlClient = undefined;

    const multiMaxResult = await runCommandBat(helperPath, [
      "-OwnershipFile", ownershipFile,
      "-Port", String(port),
      "-OwnerToken", ownerToken,
      "-ClosingMaxPid", "22022",
      "-MaxProcessCountOverride", "2",
    ], PROJECT_ROOT);
    assert.equal(multiMaxResult.exitCode, 0, multiMaxResult.output);
    assert.match(multiMaxResult.output, /Found 2 live 3ds Max processes/);

    controlClient = new BridgeControlClient({ port, timeoutMs: 1000 });
    await controlClient.connect();
    await controlClient.probe();
    controlClient.close();
    controlClient = undefined;

    const singleMaxResult = await runCommandBat(helperPath, [
      "-OwnershipFile", ownershipFile,
      "-Port", String(port),
      "-OwnerToken", ownerToken,
      "-ClosingMaxPid", "22022",
      "-MaxProcessCountOverride", "1",
    ], PROJECT_ROOT);
    assert.equal(singleMaxResult.exitCode, 0, singleMaxResult.output);
    assert.match(singleMaxResult.output, /Terminated verified Max Ultra MCP server PID/);
    assert.equal(fs.existsSync(ownershipFile), false, "Detached helper did not remove the consumed ownership record");

    const launcherExitCode = child.exitCode !== null ? child.exitCode : await Promise.race([
      new Promise((resolve) => child.once("exit", resolve)),
      new Promise((resolve) => setTimeout(() => resolve("timeout"), 5000)),
    ]);
    assert.notEqual(launcherExitCode, "timeout", "Detached helper did not release the owned BAT launcher: " + output);
    const stoppedClient = new BridgeControlClient({ port, timeoutMs: 500 });
    await assert.rejects(stoppedClient.connect(), /ECONNREFUSED|closed|connect/i);
    stoppedClient.close();
  } finally {
    if (controlClient) controlClient.close();
    if (child.exitCode === null) child.kill();
    if (previousTokenFile === undefined) delete process.env.MAX_ULTRA_MCP_TOKEN_FILE;
    else process.env.MAX_ULTRA_MCP_TOKEN_FILE = previousTokenFile;
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }
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

function sourceSection(source, startMarker, endMarker, label) {
  const start = source.indexOf(startMarker);
  assert.notEqual(start, -1, `${label}: missing start marker ${startMarker}`);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert.notEqual(end, -1, `${label}: missing end marker ${endMarker}`);
  assert.ok(end > start, `${label}: end marker must follow start marker`);
  return source.slice(start, end);
}

async function runSmokeTest() {
  assert.throws(() => activityLabelForTool("max_run_script", { script: 'box name:"ActivityBox"' }), /activity must be a specific/);
  assert.throws(() => activityLabelForTool("max_run_script", { script: "delete selection", activity: "Custom scene operation" }), /activity must be a specific/);

  assert.equal(activityLabelForTool("max_execute", { script: "1 + 1", activity: "Inspect scene state" }), "Inspect scene state via MaxScript");
  assert.throws(() => activityLabelForTool("max_execute", { script: 'box name:"PrivateBox"', activity: "Create box <PROJECT_ROOT>\\private.ms" }), /activity must be a specific/);
  assert.equal(activityLabelForTool("max_run_script_file", { filePath: "<PROJECT_ROOT>\\tool.ms", activity: "Open tool rollout" }), "Open tool rollout via MaxScript");
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
    const controlInventory = await listInstancesExample({ client: controlClient, output: quietOutput });
    assert.equal(controlInventory.count, 2);
    await assert.rejects(controlClient.callTool("not_a_real_tool", {}), /Control client cannot call/);
    await assert.rejects(
      createTestBox({ client: controlClient, output: quietOutput }),
      /Multiple 3ds Max instances|max_select_instance/,
    );
    assert.equal(max2022.executeRequests.length, 0);
    assert.equal(max2027.executeRequests.length, 0);

    const healthResponse = await bridge.callTool("max_health", { instance_id: "test-max-2022" });
    assert.equal(healthResponse.health.mainThread, true);
    const getInfoResponse = await bridge.callTool("max_get_info", { instance_id: "test-max-2027" });
    assert.equal(getInfoResponse.info.action, "get_info");
    assert.equal(getInfoResponse.info.scene.objectCount, 3);
    assert.equal(getInfoResponse.info.scene.statistics.objects.geometry, 2);
    assert.equal(getInfoResponse.info.scene.statistics.geometry.polygons, 24);
    assert.equal(getInfoResponse.info.scene.statistics.geometry.vertices, 16);
    assert.equal(getInfoResponse.info.scene.statistics.geometry.countingMode, "evaluatedMesh/getPolygonCount");
    const summaryResponse = await bridge.callTool("max_scene_summary", { instance_id: "test-max-2022" });
    assert.equal(summaryResponse.scene.objectCount, 3);
    assert.equal("details" in summaryResponse, false);
    const logsResponse = await bridge.callTool("max_logs", { instance_id: "test-max-2022", tail: 5 });
    assert.equal(logsResponse.panelLog.available, true);
    assert.equal(logsResponse.panelLog.source, "Max Ultra MCP panel");
    const smokeResponse = await bridge.callTool("max_smoke", { instance_id: "test-max-2027" });
    assert.equal(smokeResponse.smoke.ok, true);

    await assert.rejects(bridge.request("test-max-2027", "never", "", 50), /already-running work may still complete/);
    await waitFor(() => max2027.cancelledRequests.size === 1);

    const executionResponse = await bridge.callTool("max_execute", {
      instance_id: "test-max-2022", script: "format \"mock-only\\n\"", activity: "Write mock output", timeout_ms: 1000,
    });
    assert.equal(executionResponse.execution.mainThread, true);
    assert.match(executionResponse.execution.result, /mock-only/);
    assert.equal(max2022.activityLabels.at(-1), "Write mock output via MaxScript");
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
      "max_list_instances", "max_select_instance", "max_scene_summary", "max_create_box", "max_health", "max_get_info",
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

    const exampleHealth = await healthCheckExample({ client: controlClient, output: quietOutput });
    assert.equal(exampleHealth.health.mainThread, true);
    const exampleSummary = await sceneSummaryExample({ client: controlClient, output: quietOutput });
    assert.equal(exampleSummary.scene.objectCount, 3);
    const exampleMaxInfo = await getMaxInfoExample({ client: controlClient, output: quietOutput });
    assert.equal(exampleMaxInfo.info.scene.objectCount, 3);
    assert.equal(exampleMaxInfo.info.scene.statistics.geometry.polygons, 24);

    const screenshotOutputDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-mcp-example-screenshot-"));
    try {
      const exampleScreenshot = await captureViewportScreenshotExample({
        client: controlClient,
        output: quietOutput,
        outputDirectory: screenshotOutputDirectory,
        openImage: false,
      });
      assert.equal(exampleScreenshot.screenshot.mimeType, "image/png");
      assert.equal(exampleScreenshot.opened, false);
      assert.equal(fs.existsSync(exampleScreenshot.savedFilePath), true);
      assert.equal(path.dirname(exampleScreenshot.savedFilePath), screenshotOutputDirectory);
      assert.equal(path.basename(exampleScreenshot.savedFilePath), "viewport-current.png");
    } finally {
      fs.rmSync(screenshotOutputDirectory, { recursive: true, force: true });
    }

    const renderButtonResponse = await pressRenderButtonExample({ client: controlClient, output: quietOutput });
    assert.equal(renderButtonResponse.instance.instanceId, "test-max-2027");
    assert.equal(max2027.executeRequests.at(-1), QUICK_RENDER_MAXSCRIPT);
    assert.equal(QUICK_RENDER_MAXSCRIPT, "max quick render");
    assert.equal(max2027.activityLabels.at(-1), "Start production render via MaxScript");

    const boxResponse = await createTestBox({ client: controlClient, output: quietOutput });
    assert.equal(boxResponse.instanceId, "test-max-2027");
    const exampleScript = max2027.executeRequests.at(-1);
    assert.match(exampleScript, new RegExp(`box name:"${TEST_BOX_NAME}"`));
    assert.match(exampleScript, /pos:\[0,0,0\]/);
    assert.doesNotMatch(exampleScript, /save(MaxFile|Nodes|AsVersion)/i);

    const titleResponse = await createSplineTextExample({ client: controlClient, output: quietOutput });
    assert.equal(titleResponse.instance.instanceId, "test-max-2027");
    assert.equal(max2027.activityLabels.at(-1), "Create spline title via MaxScript");
    const titleScript = max2027.executeRequests.at(-1);
    assert.ok(titleScript.includes(MCP_TITLE_OBJECT_NAME));
    assert.ok(titleScript.includes(MCP_TITLE_TEXT));
    assert.match(titleScript, /local titleShape = text name:/);
    assert.match(titleScript, /addModifier titleShape \(Extrude amount: 2\.0\)/);
    assert.match(titleScript, /select titleShape/);
    assert.match(titleScript, /max tool zoomextents/);
    assert.doesNotMatch(titleScript, /\bbox\b|save(MaxFile|Nodes|AsVersion)/i);

    assert.equal(fs.existsSync(path.join(PROJECT_ROOT, "01_START_MAX_ULTRA_MCP_FIRST.ms")), true);
    const rootReadme = fs.readFileSync(path.join(PROJECT_ROOT, "README.md"), "utf8");
    const detailedReadmePath = path.join(PROJECT_ROOT, "docs", "README.md");
    const detailedReadme = fs.readFileSync(detailedReadmePath, "utf8");
    assert.match(rootReadme, /docs\/UI_DESIGN\.md/, "Root README links to the current Qt interface contract");
    assert.match(detailedReadme, /UI_DESIGN\.md/, "Detailed documentation delegates UI specifics to the canonical design guide");
    assert.match(rootReadme, /\[V1 architecture, MCP integration, and tool behavior\]\(docs\/V1\.md\)/);
    assert.match(rootReadme, /\[Privacy and data sanitization policy\]\(docs\/PRIVACY\.md\)/);
    assert.match(rootReadme, /\[Instructions for AI coding agents\]\(AGENTS\.md\)/);
    assert.equal(fs.existsSync(detailedReadmePath), true);
    assert.match(rootReadme, /PowerShell 7 is not required/);
    assert.match(rootReadme, /Windows PowerShell 5\.1/);
    assert.match(rootReadme, /scripts\\install-chatgpt-codex\.bat/);
    assert.match(rootReadme, /scripts\\run-smoke\.ps1/);
    assert.match(rootReadme, /runtime\\win-x64\\node\.exe/);
    assert.match(detailedReadme, /Node\.js/);
    const nodeRunnerSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "run-node-script.ps1"), "utf8");
    assert.match(nodeRunnerSource, /Get-Command node -CommandType Application/);
    assert.match(nodeRunnerSource, /runtime\\win-x64\\node\.exe/);
    assert.match(nodeRunnerSource, /\$candidateVersion\.Major -ge 22/);
    assert.match(nodeRunnerSource, /Test-Path -LiteralPath \$resolvedScriptPath -PathType Leaf/);
    assert.match(nodeRunnerSource, /& \$nodeExecutable \$resolvedScriptPath @scriptArguments/);
    assert.doesNotMatch(nodeRunnerSource, /Invoke-Expression|Start-Process|cmd\.exe/i);
    const examplesRoot = path.join(PROJECT_ROOT, "examples");
    const expectedExampleNames = [
      "example-create-spline-text",
      "example-create-test-box",
      "example-get-max-info",
      "example-health-check",
      "example-list-instances",
      "example-press-render-button",
      "example-scene-summary",
      "example-viewport-screenshot",
    ];
    const rootExampleFiles = fs.readdirSync(examplesRoot, { withFileTypes: true })
      .filter((entry) => entry.isFile())
      .map((entry) => entry.name)
      .sort();
    assert.deepEqual(rootExampleFiles, expectedExampleNames.map((name) => name + ".bat"));
    assert.equal(fs.existsSync(path.join(examplesRoot, "_shared")), false);
    for (const exampleName of expectedExampleNames) {
      const implementationPath = path.join(examplesRoot, exampleName, exampleName + ".js");
      assert.equal(fs.existsSync(implementationPath), true, exampleName + " must have a matching implementation folder");
      const implementationSource = fs.readFileSync(implementationPath, "utf8");
      assert.match(implementationSource, /\.\.\/\.\.\/core\/bridge-control-client/);
      assert.doesNotMatch(implementationSource, /_shared|run-max-action/);
      assert.doesNotMatch(implementationSource, /save(MaxFile|Nodes|AsVersion)/i);
    }
    const thinNodeLaunchers = [
      ["examples/example-create-spline-text.bat", "examples\\example-create-spline-text\\example-create-spline-text.js"],
      ["examples/example-create-test-box.bat", "examples\\example-create-test-box\\example-create-test-box.js"],
      ["examples/example-get-max-info.bat", "examples\\example-get-max-info\\example-get-max-info.js"],
      ["examples/example-health-check.bat", "examples\\example-health-check\\example-health-check.js"],
      ["examples/example-list-instances.bat", "examples\\example-list-instances\\example-list-instances.js"],
      ["examples/example-press-render-button.bat", "examples\\example-press-render-button\\example-press-render-button.js"],
      ["examples/example-scene-summary.bat", "examples\\example-scene-summary\\example-scene-summary.js"],
      ["examples/example-viewport-screenshot.bat", "examples\\example-viewport-screenshot\\example-viewport-screenshot.js"],
      ["scripts/start-server.bat", "core\\server.js"],
      ["scripts/start-server.ps1", "core\\server.js"],
      ["scripts/run-smoke.ps1", "tests\\smoke-test.js"],
    ];
    for (const [relativeLauncherPath, expectedScriptPath] of thinNodeLaunchers) {
      const launcherSource = fs.readFileSync(path.join(PROJECT_ROOT, ...relativeLauncherPath.split("/")), "utf8");
      assert.match(launcherSource, /run-node-script\.ps1/);
      assert.ok(launcherSource.includes(expectedScriptPath), relativeLauncherPath + " must name only its requested Node.js script");
      assert.doesNotMatch(launcherSource, /Get-Command\s+node|codex-runtimes|process\.versions\.node/);
    }
    const screenshotExampleSource = fs.readFileSync(path.join(examplesRoot, "example-viewport-screenshot", "example-viewport-screenshot.js"), "utf8");
    assert.match(screenshotExampleSource, /path\.join\(outputDirectory, "viewport-current\.png"\)/);
    assert.match(screenshotExampleSource, /fs\.copyFileSync\(sourceFilePath, savedFilePath\)/);
    assert.doesNotMatch(screenshotExampleSource, /cleanup-after-process|startCleanupWatcher|removeScreenshotAfterProcessExit/);
    const bootstrapSource = fs.readFileSync(path.join(PROJECT_ROOT, "01_START_MAX_ULTRA_MCP_FIRST.ms"), "utf8");
    assertBalancedMaxScript(bootstrapSource);
    assert.match(bootstrapSource, /python\.ExecuteFile pythonBootstrap/);
    assert.doesNotMatch(bootstrapSource, /dotNet|System\.Windows\.Forms/);
    require("./python-source-contract").verify(PROJECT_ROOT);

    const serverSource = fs.readFileSync(path.join(PROJECT_ROOT, "core", "server.js"), "utf8");
    const stdioHostSource = fs.readFileSync(path.join(PROJECT_ROOT, "core", "stdio-host.js"), "utf8");
    const bridgeControlClientSource = fs.readFileSync(path.join(PROJECT_ROOT, "core", "bridge-control-client.js"), "utf8");
    const shutdownHelperSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "stop-owned-server.ps1"), "utf8");
    const shutdownHelperBatSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "stop-owned-server.bat"), "utf8");
    const agentIntegrationSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "agent-integration.ps1"), "utf8");
    const localAuthSource = fs.readFileSync(path.join(PROJECT_ROOT, "core", "local-auth.js"), "utf8");
    const maxPkgFilesSource = fs.readFileSync(path.join(PROJECT_ROOT, "maxpkg-files.txt"), "utf8");
    const maxPkgPrepareSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "prepare-maxpkg.ps1"), "utf8");
    const maxPkgSyncSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "sync-maxpkg-tooling.ps1"), "utf8");
    const maxPkgUpstreamSkillSource = fs.readFileSync(path.join(PROJECT_ROOT, "skills", "max-ultra-maxpkg-packaging", "scripts", "get-maxpkg-upstream.ps1"), "utf8");
    const maxPkgUninstallSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "maxpkg-uninstall.ps1"), "utf8");
    const maxPkgUninstallHookSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "maxpkg-uninstall.ms"), "utf8");
    const maxPkgIconSource = fs.readFileSync(path.join(PROJECT_ROOT, "maxpkg-icon.svg"), "utf8");
    const refreshIconPng = fs.readFileSync(path.join(PROJECT_ROOT, "assets", "icons", "refresh-cw.png"));
    const donateIconPng = fs.readFileSync(path.join(PROJECT_ROOT, "assets", "icons", "heart.png"));
    const hideIconPng = fs.readFileSync(path.join(PROJECT_ROOT, "assets", "icons", "panel-top-close.png"));
    const settingsIconPng = fs.readFileSync(path.join(PROJECT_ROOT, "assets", "icons", "settings.png"));
    const reconnectIconPng = fs.readFileSync(path.join(PROJECT_ROOT, "assets", "icons", "plug-zap.png"));
    const stopIconPng = fs.readFileSync(path.join(PROJECT_ROOT, "assets", "icons", "power.png"));
    const gitIgnoreSource = fs.readFileSync(path.join(PROJECT_ROOT, ".gitignore"), "utf8");
    const githubReleaseSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "publish-github-release.ps1"), "utf8");
    const releaseVersionSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "release-mzp-utils.ps1"), "utf8");
    const githubReleaseBatSource = fs.readFileSync(path.join(PROJECT_ROOT, "RELEASE_MZP_TO_GITHUB.bat"), "utf8");
    const prepareReleaseSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "prepare-release.ps1"), "utf8");
    const prepareReleaseBatSource = fs.readFileSync(path.join(PROJECT_ROOT, "PREPARE_RELEASE.bat"), "utf8");
    const portableNodePrepareSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "prepare-portable-node.ps1"), "utf8");
    const updateManagerSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "update-manager.ps1"), "utf8");
    const uiAutomationSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "max-ui-automation.ps1"), "utf8");
    const versionIniSource = fs.readFileSync(path.join(PROJECT_ROOT, "version.ini"), "utf8");
    const changelogSource = fs.readFileSync(path.join(PROJECT_ROOT, "CHANGELOG.md"), "utf8");
    const releaseRulesSource = fs.readFileSync(path.join(PROJECT_ROOT, ".agents", "release-rules.md"), "utf8");
    const agentsSource = fs.readFileSync(path.join(PROJECT_ROOT, "AGENTS.md"), "utf8");
    const claudeSource = fs.readFileSync(path.join(PROJECT_ROOT, "CLAUDE.md"), "utf8");
    const agentInteropSource = fs.readFileSync(path.join(PROJECT_ROOT, ".agents", "agent-interop.md"), "utf8");
    const codexSkillAdapterSource = fs.readFileSync(path.join(PROJECT_ROOT, ".agents", "skills", "max-ultra-mcp", "SKILL.md"), "utf8");
    const claudeSkillAdapterSource = fs.readFileSync(path.join(PROJECT_ROOT, ".claude", "skills", "max-ultra-mcp", "SKILL.md"), "utf8");
    const skillsRoot = path.join(PROJECT_ROOT, "skills");
    const pluginRoot = path.join(PROJECT_ROOT, "plugins", "max-ultra-mcp");
    const pluginSkillsRoot = path.join(pluginRoot, "skills");
    const pluginManifest = JSON.parse(fs.readFileSync(path.join(pluginRoot, ".codex-plugin", "plugin.json"), "utf8"));
    const pluginMarketplace = JSON.parse(fs.readFileSync(path.join(PROJECT_ROOT, ".agents", "plugins", "marketplace.json"), "utf8"));
    const skillNames = fs.readdirSync(skillsRoot, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && fs.existsSync(path.join(skillsRoot, entry.name, "SKILL.md")))
      .map((entry) => entry.name)
      .sort();
    assert.deepEqual(skillNames, ["max-ultra-armchair-modeling", "max-ultra-camera-composition", "max-ultra-character-object-modeling", "max-ultra-floor-plan", "max-ultra-maxpkg-packaging", "max-ultra-mcp", "max-ultra-renderer-settings", "max-ultra-small-house-detailing", "max-ultra-spline-modeling"]);
    assert.equal(pluginManifest.name, "max-ultra-mcp");
    assert.equal(pluginManifest.version, versionIniSource.match(/^Version=(.+)$/m)[1].trim());
    assert.equal(pluginManifest.skills, "./skills/");
    assert.ok(Array.isArray(pluginManifest.interface.defaultPrompt));
    assert.ok(pluginManifest.interface.defaultPrompt.some((prompt) => /teapot.+3ds Max/i.test(prompt)));
    assert.equal(pluginMarketplace.name, "3dground-max-ultra-mcp");
    assert.equal(pluginMarketplace.plugins[0].name, "max-ultra-mcp");
    assert.equal(pluginMarketplace.plugins[0].source.path, "./plugins/max-ultra-mcp");
    const relativeFilesBelow = (root) => {
      const files = [];
      const visit = (directory, prefix = "") => {
        for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
          const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
          if (entry.isDirectory()) visit(path.join(directory, entry.name), relative);
          else files.push(relative);
        }
      };
      visit(root);
      return files.sort();
    };
    const canonicalSkillFiles = relativeFilesBelow(skillsRoot);
    assert.deepEqual(relativeFilesBelow(pluginSkillsRoot), canonicalSkillFiles);
    for (const relativeSkillFile of canonicalSkillFiles) {
      assert.deepEqual(
        fs.readFileSync(path.join(pluginSkillsRoot, ...relativeSkillFile.split("/"))),
        fs.readFileSync(path.join(skillsRoot, ...relativeSkillFile.split("/"))),
        `Plugin skill copy is stale: ${relativeSkillFile}`,
      );
      assert.match(maxPkgFilesSource, new RegExp(`^plugins/max-ultra-mcp/skills/${relativeSkillFile.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`, "m"));
    }
    assert.match(maxPkgFilesSource, /^\.agents\/plugins\/marketplace\.json$/m);
    assert.match(maxPkgFilesSource, /^plugins\/max-ultra-mcp\/\.codex-plugin\/plugin\.json$/m);
    const skillReferenceNamesBySkill = new Map();
    const skillDocumentationParts = [];
    for (const skillName of skillNames) {
      const skillRoot = path.join(skillsRoot, skillName);
      const skillSource = fs.readFileSync(path.join(skillRoot, "SKILL.md"), "utf8");
      const skillReferenceRoot = path.join(skillRoot, "references");
      const skillReferenceNames = fs.existsSync(skillReferenceRoot)
        ? fs.readdirSync(skillReferenceRoot).filter((entryName) => entryName.endsWith(".md")).sort()
        : [];
      const linkedSkillReferences = [...skillSource.matchAll(/\]\(references\/([a-z0-9-]+\.md)\)/g)].map((entry) => entry[1]).sort();
      assert.deepEqual(linkedSkillReferences, skillReferenceNames, `Every ${skillName} reference must be linked exactly once from SKILL.md`);
      assert.match(skillSource, new RegExp(`^---\\r?\\nname: ${skillName}\\r?\\ndescription: .+\\r?\\n---\\r?\\n`));
      const currentSkillDocumentation = [
        skillSource,
        ...skillReferenceNames.map((entryName) => fs.readFileSync(path.join(skillReferenceRoot, entryName), "utf8")),
      ].join("\n");
      for (const scriptBlock of currentSkillDocumentation.matchAll(/```maxscript\r?\n([\s\S]*?)```/g)) assertBalancedMaxScript(scriptBlock[1]);
      skillReferenceNamesBySkill.set(skillName, skillReferenceNames);
      skillDocumentationParts.push(currentSkillDocumentation);
    }
    const skillDocumentation = skillDocumentationParts.join("\n");
    const cameraSkillDocumentation = skillDocumentationParts[skillNames.indexOf("max-ultra-camera-composition")];
    assert.match(cameraSkillDocumentation, /displaySafeFrames = true/);
    assert.match(cameraSkillDocumentation, /single-object framing/i);
    assert.match(cameraSkillDocumentation, /world bounding box/i);
    assert.match(cameraSkillDocumentation, /maximized[\s\S]*Safe Frame/i);
    const modelingSkillDocumentation = skillDocumentationParts[skillNames.indexOf("max-ultra-character-object-modeling")];
    assert.match(modelingSkillDocumentation, /Do not call `max_create_primitive`/);
    assert.match(modelingSkillDocumentation, /quad-dominant/i);
    assert.match(modelingSkillDocumentation, /TurboSmooth[\s\S]*one iteration/i);
    assert.match(modelingSkillDocumentation, /Do not collapse/i);
    assert.match(modelingSkillDocumentation, /overlay Elements/i);
    assert.match(modelingSkillDocumentation, /coplanar[\s\S]*z-fighting/i);
    const rendererSkillDocumentation = skillDocumentationParts[skillNames.indexOf("max-ultra-renderer-settings")];
    assert.match(rendererSkillDocumentation, /max_renderer_properties_get/);
    assert.match(rendererSkillDocumentation, /show renderers\.current/);
    assert.match(rendererSkillDocumentation, /read-back/i);
    assert.match(rendererSkillDocumentation, /applied[\s\S]*unchanged[\s\S]*unsupported[\s\S]*warnings/i);
    const maxPkgSkillDocumentation = skillDocumentationParts[skillNames.indexOf("max-ultra-maxpkg-packaging")];
    assert.match(maxPkgSkillDocumentation, /get-maxpkg-upstream\.ps1/);
    assert.match(maxPkgSkillDocumentation, /Both hooks are mandatory/i);
    assert.match(maxPkgSkillDocumentation, /<slug>@<major\.minor\.patch>@<guid>\.mzp/);
    assert.match(maxPkgSkillDocumentation, /original `maxpkg-packager\.ms`/i);
    assert.match(maxPkgSkillDocumentation, /MaxPkgPackerApi\.ping\(\)/);
    assert.match(maxPkgSkillDocumentation, /MaxPkgPackerApi\.validate\(\)/);
    assert.match(maxPkgSkillDocumentation, /MaxPkgPackerApi\.build\(\)/);
    assert.match(maxPkgSkillDocumentation, /data\.exists == true/);
    assert.match(maxPkgSkillDocumentation, /compatibility fallback[\s\S]*older packager/i);
    assert.match(maxPkgSkillDocumentation, /maxpkg-marketplace-listing\.md/);
    assert.match(maxPkgSkillDocumentation, /long description must not contain an H1/i);
    assert.match(maxPkgSkillDocumentation, /FAQ must not use Markdown headings/i);
    assert.match(maxPkgSkillDocumentation, /GUID is private identity metadata/i);
    assert.equal(fs.existsSync(path.join(skillsRoot, "max-ultra-maxpkg-packaging", "references", "maxpkg-adaptation-prompt.md")), false);
    assert.equal(fs.existsSync(path.join(skillsRoot, "max-ultra-maxpkg-packaging", "references", "maxpkg-full-onboarding-prompt.md")), false);
    assert.match(maxPkgUpstreamSkillSource, /api\.github\.com\/repos\/maxpkg-dev\/max-dev-tool\/commits\/HEAD/);
    assert.match(maxPkgUpstreamSkillSource, /maxpkg-adaptation-prompt\.md/);
    assert.match(maxPkgUpstreamSkillSource, /maxpkg-api\.md/);
    assert.match(maxPkgUpstreamSkillSource, /apiDocumentationPath/);
    assert.match(maxPkgUpstreamSkillSource, /maxpkg-full-onboarding-prompt\.md/);
    assert.match(maxPkgUpstreamSkillSource, /toolingFiles = @\('maxpkg-packager\.ms', '_install\.ms', '_uninstall\.ms'\)/);
    assert.match(maxPkgUpstreamSkillSource, /ConfirmProjectWrite/);
    assert.match(maxPkgFilesSource, /skills\/max-ultra-maxpkg-packaging\/scripts\/get-maxpkg-upstream\.ps1/);
    assert.match(maxPkgFilesSource, /skills\/max-ultra-maxpkg-packaging\/references\/marketplace-publishing\.md/);
    const generalSkillDocumentation = skillDocumentationParts[skillNames.indexOf("max-ultra-mcp")];
    assert.match(generalSkillDocumentation, /references\/code-rules\.md/);
    assert.match(generalSkillDocumentation, /Define every helper before/i);
    assert.match(generalSkillDocumentation, /explicit `return`/i);
    assert.match(generalSkillDocumentation, /enableAccelerators/);
    assert.match(generalSkillDocumentation, /never bind the same event repeatedly/i);
    assert.match(maxPkgFilesSource, /skills\/max-ultra-mcp\/references\/code-rules\.md/);
    assert.match(agentsSource, /agent-interop\.md/);
    assert.match(claudeSource, /^@AGENTS\.md/m);
    assert.match(agentInteropSource, /exactly one short question/);
    assert.match(agentInteropSource, /Do not use hooks to select a 3ds Max instance/);
    assert.match(codexSkillAdapterSource, /^---\r?\nname: max-ultra-mcp\r?\ndescription: .+\r?\n---\r?\n/);
    assert.match(claudeSkillAdapterSource, /^---\r?\nname: max-ultra-mcp\r?\ndescription: .+\r?\n---\r?\n/);
    assert.match(codexSkillAdapterSource, /skills\/max-ultra-mcp\/SKILL\.md/);
    assert.match(claudeSkillAdapterSource, /skills\/max-ultra-mcp\/SKILL\.md/);
    assert.match(maxPkgFilesSource, /^CLAUDE\.md$/m);
    assert.match(maxPkgFilesSource, /^\.agents\/agent-interop\.md$/m);
    assert.match(maxPkgFilesSource, /^\.agents\/skills\/max-ultra-mcp\/SKILL\.md$/m);
    assert.match(maxPkgFilesSource, /^\.claude\/skills\/max-ultra-mcp\/SKILL\.md$/m);
    assert.match(stdioHostSource, /ask exactly one short question/);
    assert.match(stdioHostSource, /UI_CAPTURE_FAILED/);
    assert.match(stdioHostSource, /max_ui_diagnostics/);
    assert.doesNotMatch(stdioHostSource, /max_ui_diagnose_window/);
    const implementedToolNames = new Set(getMcpTools("full").map((tool) => tool.name));
    const documentedToolNames = new Set([...skillDocumentation.matchAll(/\bmax_[a-z0-9_]+\b/g)].map((entry) => entry[0]));
    for (const documentedToolName of documentedToolNames) {
      assert.equal(implementedToolNames.has(documentedToolName), true, `Skill references unavailable tool ${documentedToolName}`);
    }

    assertBalancedMaxScript(maxPkgUninstallHookSource);
    assert.match(maxPkgUninstallHookSource, /python\.ExecuteFile helperPath/);
    const uiRolloutSource = fs.readFileSync(path.join(PROJECT_ROOT, "tests", "fixtures", "ui-automation-rollout", "test-ui-rollout.ms"), "utf8");
    assertBalancedMaxScript(uiRolloutSource);
    assert.match(uiRolloutSource, /Max Ultra MCP UI Automation Test/);
    assert.match(uiRolloutSource, /button applyButton "Apply with MCP"/);
    assert.match(uiAutomationSource, /function Convert-ToSafeInt32/);
    assert.match(uiAutomationSource, /\[double\]::IsInfinity\(\$number\)/);
    assert.match(uiAutomationSource, /x = Convert-ToSafeInt32 \$rectangle\.X/);
    assert.match(uiAutomationSource, /controls = \$controls\.ToArray\(\)/);
    assert.match(uiAutomationSource, /function Assert-OwnedHandle\(\[IntPtr\]\$Handle\)/);
    assert.match(uiAutomationSource, /GetWindowThreadProcessId\(\$Handle, \[ref\]\$ownerPid\)/);
    assert.match(uiAutomationSource, /function Resolve-WindowContext\(\$Selector\)/);
    assert.match(uiAutomationSource, /source = 'hwnd'/);
    assert.match(uiAutomationSource, /PrintWindow\(\$Handle, \$deviceContext, 2\)/);
    assert.match(uiAutomationSource, /captureMethod = 'screenCopyFallback'/);
    assert.match(uiAutomationSource, /UI_ELEMENT_NOT_FOUND: the HWND/);
    assert.match(uiAutomationSource, /UI_CAPTURE_FAILED:/);
    assert.match(uiAutomationSource, /function Get-NativeTree/);
    assert.match(uiAutomationSource, /isWinForms = \$className\.StartsWith/);
    assert.match(uiAutomationSource, /AccessibleObjectFromWindow/);
    assert.match(uiAutomationSource, /clientWidth = Convert-ToNullableInt32/);
    assert.match(uiAutomationSource, /devicePixelRatio/);
    const legacyInfoTerm = "snap" + "shot";

    assert.equal(serverSource.includes("max_" + legacyInfoTerm), false);
    assert.equal(serverSource.includes(`"${legacyInfoTerm}"`), false);
    assert.equal(serverSource.includes(legacyInfoTerm + ":"), false);

    assert.match(serverSource, /name: "max_get_info"/);

    const dotNetButtonNames = [
      "btnAiStatus", "btnRefreshAgents", "btnHide",
      "btnReconnect", "btnStop", "btnSettings", "btnDonate", "btnCheckUpdates", "btnAgentSetup", "btnAboutDonate",
      "btnOpenAI", "btnClaudeCode", "btnAntigravity", "btnRefreshManual", "btnCopyManual", "btnCopyTestPrompt",
    ];

    const panelRolloutNames = ["statusDialog", "serverStatusDialog", "activityDialog", "supportDialog"];

    let previousRolloutOffset = -1;

    assert.match(agentIntegrationSource, /Write-CliInstallProgress 'Setup CLI installed and verified\.' 'success'/);

    for (const logoName of ["codex", "claude", "antigravity"]) {
      const logoBytes = fs.readFileSync(path.join(PROJECT_ROOT, "assets", "client-logos", logoName + ".png"));
      assert.equal(logoBytes.subarray(1, 4).toString(), "PNG");
      assert.equal(logoBytes.readUInt32BE(16), 48);
      assert.equal(logoBytes.readUInt32BE(20), 48);
      for (let offset = 8; offset < logoBytes.length;) {
        const length = logoBytes.readUInt32BE(offset);
        const chunk = logoBytes.subarray(offset + 4, offset + 8).toString();
        assert.ok(!["tEXt", "iTXt", "zTXt", "eXIf"].includes(chunk), "Client logos must not carry identifying metadata");
        offset += length + 12;
      }
    }

    assert.match(agentIntegrationSource, /\[ValidateSet\('Status','Install','InstallCli'\)\]/);
    assert.match(agentIntegrationSource, /Get-ClientStatus 'openai' 'ChatGPT Desktop \/ Codex' 'codex'/);
    assert.match(agentIntegrationSource, /Get-ClientStatus 'claudeCode' 'Claude Code' 'claude'/);
    assert.match(agentIntegrationSource, /'mcp','add',\$serverName,'--scope','user'/);
    assert.match(agentIntegrationSource, /MAX_ULTRA_MCP_TOOL_PROFILE=\$Profile/);
    assert.match(agentIntegrationSource, /Move-Item -LiteralPath \$temporaryPath -Destination \$resolvedResultPath -Force/);
    assert.match(agentIntegrationSource, /OpenAI\\Codex\\bin/);
    assert.match(agentIntegrationSource, /.cache\\codex-runtimes\\codex-primary-runtime/);
    assert.doesNotMatch(agentIntegrationSource, /'Installation failed: ' \+ \$install\.Output/);
    assert.match(agentIntegrationSource, /Select-String -LiteralPath \$codexConfigPath/);
    assert.match(agentIntegrationSource, /function Test-StdioHostRestartRequired/);
    assert.match(agentIntegrationSource, /'restart_required'/);
    assert.match(fs.readFileSync(path.join(PROJECT_ROOT, "core", "bridge-control-client.js"), "utf8"), /const currentControlToken = readControlToken\(\)/);
    assert.match(localAuthSource, /process\.env\.LOCALAPPDATA/);
    assert.match(localAuthSource, /"3DGROUND", "MaxUltraMCP", "runtime", "state", "control-token"/);
    assert.match(localAuthSource, /path\.resolve\(__dirname, "\.\.", "runtime", "state", "control-token"\)/);
    assert.match(maxPkgFilesSource, /runtime\/win-x64\/node\.exe/);
    assert.match(maxPkgFilesSource, /core\/job-registry\.js/);
    assert.match(maxPkgFilesSource, /core\/material-diagnostics\.js/);
    assert.match(maxPkgFilesSource, /core\/plan-token\.js/);
    for (const skillName of skillNames) {
      assert.ok(maxPkgFilesSource.includes(`skills/${skillName}/SKILL.md`));
      for (const skillReferenceName of skillReferenceNamesBySkill.get(skillName)) {
        assert.ok(maxPkgFilesSource.includes(`skills/${skillName}/references/${skillReferenceName}`));
      }
    }
    assert.doesNotMatch(maxPkgFilesSource, /smoke-test|mock-max-client|runtime\/state/);
    assert.doesNotMatch(maxPkgFilesSource, /publish-github-release|release-mzp-utils|RELEASE_MZP_TO_GITHUB/);
    assert.match(gitIgnoreSource, /^dist\/$/m);
    assert.match(githubReleaseBatSource, /scripts\\publish-github-release\.ps1/);
    assert.match(githubReleaseSource, /Read-Host "Publish \$releaseTag to GitHub\? \[Y\/N\]"/);
    assert.match(githubReleaseSource, /\.Trim\(\)\.ToUpperInvariant\(\) -ne \x27Y\x27/);
    assert.doesNotMatch(githubReleaseSource, /Type RELEASE/);
    assert.match(versionIniSource, /\[MaxUltraMCP\][\s\S]*Version=\d+\.\d+\.\d+[\s\S]*Channel=(?:stable|beta)/);
    assert.match(changelogSource, /^## Unreleased/m);
    assert.match(releaseRulesSource, /authorizes local release-metadata preparation and verification only/i);
    assert.match(prepareReleaseSource, /Get-MaxUltraProjectVersionInfo/);
    assert.match(prepareReleaseSource, /\$releaseVersion = if \(\[string\]::IsNullOrWhiteSpace\(\$Version\)\)/);
    assert.match(prepareReleaseSource, /\$currentInfo\.Version/);
    assert.doesNotMatch(prepareReleaseSource, /Parameter\(Mandatory = \$true\)/);
    assert.match(prepareReleaseBatSource, /version\.ini by default/);
    assert.match(prepareReleaseSource, /CHANGELOG\.md Unreleased is empty/);
    assert.match(prepareReleaseSource, /\$isPreparedRetry/);
    assert.match(prepareReleaseSource, /\$packageVersionMatches/);
    assert.doesNotMatch(prepareReleaseSource, /\$bootstrapPath|lblAboutVersion|MaxUltraMcpStatusDialog/);
    assert.match(maxPkgPrepareSource, /\$settingsLines\.Add\(\x27license=Free\x27\)/);
    assert.doesNotMatch(maxPkgPrepareSource, /\$License/);
    for (const hashingScriptSource of [maxPkgSyncSource, portableNodePrepareSource, updateManagerSource, githubReleaseSource]) {
      assert.match(hashingScriptSource, /function Get-MaxUltraSha256Hash/);
      assert.match(hashingScriptSource, /SHA256\]::Create\(\)[\s\S]*ComputeHash/);
      assert.doesNotMatch(hashingScriptSource, /Get-FileHash/);
    }
    assert.match(updateManagerSource, /api\.github\.com\/repos\/\$expectedRepository\/releases\/latest/);
    assert.match(updateManagerSource, /function Get-CurlExecutable/);
    assert.match(updateManagerSource, /CreateNoWindow = \$true/);
    assert.match(updateManagerSource, /Remove-StaleUpdateTemporaryFiles[\s\S]*AddHours\(-6\)/);
    assert.doesNotMatch(updateManagerSource, /Invoke-(?:RestMethod|WebRequest)/);

    assert.match(updateManagerSource, /Get-MaxUltraSha256Hash[\s\S]*temporaryPackagePath/);
    assert.match(maxPkgFilesSource, /version\.ini/);
    assert.match(maxPkgFilesSource, /CHANGELOG\.md/);
    assert.match(maxPkgFilesSource, /^core\/package\.json$/m);
    assert.match(maxPkgFilesSource, /^AGENTS\.md$/m);
    assert.match(maxPkgFilesSource, /^\.agents\/coding-rules\.md$/m);
    assert.match(maxPkgFilesSource, /^\.agents\/release-rules\.md$/m);
    assert.match(maxPkgFilesSource, /^docs\/MAXPKG\.md$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/refresh-cw\.svg$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/heart\.svg$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/panel-top-close\.svg$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/plug-zap\.svg$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/power\.svg$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/settings\.svg$/m);
    assert.equal(refreshIconPng.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
    assert.equal(refreshIconPng.readUInt32BE(16), 16);
    assert.equal(refreshIconPng.readUInt32BE(20), 16);
    assert.equal(donateIconPng.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
    assert.equal(donateIconPng.readUInt32BE(16), 16);
    assert.equal(donateIconPng.readUInt32BE(20), 16);
    for (const iconPng of [hideIconPng, settingsIconPng, reconnectIconPng, stopIconPng]) {
      assert.equal(iconPng.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
      assert.equal(iconPng.readUInt32BE(16), 16);
      assert.equal(iconPng.readUInt32BE(20), 16);
    }
    const productionPaths = maxPkgFilesSource.split(/\r?\n/).map((line) => line.trim()).filter((line) => line && !line.startsWith("#"));
    assert.equal(new Set(productionPaths).size, productionPaths.length, "Production paths must be unique");
    for (const productionPath of productionPaths) {
      assert.doesNotMatch(productionPath, /^(?:tests|diagnostics|dist)\//, "Development artifacts must stay out of the package");
      assert.doesNotMatch(productionPath, /(?:^|\/)(?:maxpkg-packager\.ini|runtime\/state)(?:\/|$)/);
    }
    for (const coreFile of fs.readdirSync(path.join(PROJECT_ROOT, "core"))) {
      if (/\.(?:js|json)$/.test(coreFile)) assert.ok(productionPaths.includes("core/" + coreFile), "Missing runtime file: " + coreFile);
    }
    assert.match(maxPkgFilesSource, /scripts\/update-manager\.ps1/);
    assert.match(maxPkgFilesSource, /scripts\/project-version\.ps1/);
    assert.match(releaseVersionSource, /max-ultra-mcp@\(\?<version>/);
    assert.match(githubReleaseSource, /Assert-MzpArchive/);
    assert.match(githubReleaseSource, /git[\s\S]*ls-remote/);
    assert.match(githubReleaseSource, /release create \$releaseTag \$releasePackage\.FullName \$checksumPath/);
    assert.match(githubReleaseSource, /--target \$headCommit/);
    assert.match(githubReleaseSource, /--generate-notes/);
    assert.doesNotMatch(githubReleaseSource, /--clobber|release delete|tag -d|push --force/);
    assert.match(maxPkgPrepareSource, /packageGuid = 'c6977570-25a6-41b0-b9bb-b3be8101123c'/);
    assert.match(maxPkgPrepareSource, /entry=01_START_MAX_ULTRA_MCP_FIRST\.ms/);
    assert.match(maxPkgPrepareSource, /compileEntry=false/);
    assert.match(maxPkgPrepareSource, /customUninstallScript=/);
    assert.match(maxPkgSyncSource, /3727cfd6fe98f8fa6bfd31b900f44ee0c37d9417/);
    assert.match(maxPkgSyncSource, /if \(-not \$Force -and \(Test-Path[^\r\n]+\)\) \{[\s\S]*\$preservedFiles\.Add\(\$fileName\)[\s\S]*continue/);
    assert.doesNotMatch(maxPkgSyncSource, /existingHash|differs from pinned/);
    assert.match(maxPkgSyncSource, /Get-MaxUltraSha256Hash -LiteralPath \$temporaryPath/);
    assert.doesNotMatch(maxPkgPrepareSource, /Copy-Item[^\r\n]+maxpkg-icon/i);
    assert.doesNotMatch(maxPkgPrepareSource, /sourceIconPath/);
    assert.match(maxPkgUninstallSource, /function Get-PackageOwnedNodeProcesses/);
    assert.match(maxPkgUninstallSource, /function Stop-PackageOwnedNodeProcess/);
    assert.match(maxPkgUninstallSource, /Close ChatGPT Desktop, Codex, and Claude Code/);
    assert.match(maxPkgUninstallSource, /\[Console\]::Error\.WriteLine\(\$_\.Exception\.Message\)/);
    assert.match(maxPkgUninstallSource, /\[Regex\]::IsMatch\(\[string\]\$currentProcess\.CommandLine, \$escapedServerPath/);
    assert.match(maxPkgIconSource, /<svg\b/i);
    assert.doesNotMatch(maxPkgIconSource, /<script\b|javascript:|onload\s*=|onclick\s*=|onerror\s*=|<foreignObject\b/i);

    // MAXScript resolves bare forward method references as undefined; use the struct receiver.

    // Preview navigation must not bind HtmlWindow/DOM events that fail in Max 2027.

    assert.match(getMcpTools("core").find((toolDefinition) => toolDefinition.name === "max_run_script").description, /500,000 characters/);

    assert.match(shutdownHelperBatSource, /stop-owned-server\.ps1/);
    assert.match(shutdownHelperSource, /Get-Process -Name 3dsmax/);
    assert.match(shutdownHelperSource, /\$liveMaxCount -ne 1/);
    assert.match(shutdownHelperSource, /Get-CimInstance Win32_Process/);
    assert.match(shutdownHelperSource, /Test-CreationTime/);
    assert.match(shutdownHelperSource, /Test-CommandLineContains/);
    assert.match(shutdownHelperSource, /Stop-Process -Id \$ownedNodePid -Force/);
    assert.match(shutdownHelperSource, /Stop-Process -Id \$ownedLauncherPid -Force/);
    assert.doesNotMatch(shutdownHelperSource, /TcpClient|CONTROL|shutdown_owned|Invoke-WebRequest/);

    assert.match(serverSource, /MAX_ULTRA_MCP_OWNER_FILE/);
    assert.match(serverSource, /processStartedAtUtc/);
    assert.match(serverSource, /launcherStartedAtUtc/);
    assert.match(serverSource, /fs\.renameSync\(temporaryFile, ownerFile\)/);

    assert.match(bridgeControlClientSource, /this\.connectPromise = null/);
    assert.match(bridgeControlClientSource, /if \(this\.socket !== socket\) return/);
    assert.match(bridgeControlClientSource, /this\.buffer = ""/);
    assert.match(stdioHostSource, /const DEFAULT_RECONNECT_GRACE_MS = 10000/);
    assert.match(stdioHostSource, /this\.reconnectPromise/);
    assert.match(stdioHostSource, /new StdioHost\(\)/);
    assert.doesNotMatch(stdioHostSource, /onBridgeDisconnect: shutdown/);
    assert.match(stdioHostSource, /input\.on\("close", shutdown\)/);

    const mismatchedIdentity = { ...probeResponse, startedAt: "not-the-running-server" };
    await assert.rejects(controlClient.shutdownOwnedServer(mismatchedIdentity), /ownership identity does not match/);
    assert.equal(shutdownRequests, 1, "Mismatched immediate ownership must never stop a server");
    const ownedShutdownResponse = await controlClient.shutdownOwnedServer(probeResponse);
    assert.equal(ownedShutdownResponse.server, "max-ultra-mcp");
    assert.equal(ownedShutdownResponse.shuttingDown, true);
    assert.equal(ownedShutdownResponse.ownerMatched, true);
    await waitFor(() => shutdownRequests === 2);
    await assert.rejects(controlClient.shutdownOwnedWhenIdle(mismatchedIdentity), /ownership identity does not match/);
    assert.equal(shutdownRequests, 2, "Mismatched idle ownership must never stop a server");
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
    assert.equal(shutdownRequests, 2, "Arming idle shutdown must not stop a server with a connected Max");
    max2027.disconnect();
    await waitFor(() => shutdownRequests === 3);
    await runBatDetachedShutdownTest();

    process.stdout.write("Max Ultra MCP smoke passed: 13 tools, Max 2022 + 2027 routing, guarded UI/transport, and detached ownership-verified shutdown\n");
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
