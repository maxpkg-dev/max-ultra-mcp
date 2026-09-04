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

    await assert.rejects(bridge.request("test-max-2027", "never", "", 50), /queued work was cancelled/);
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
    assert.ok(rootReadme.length < detailedReadme.length, "Root README must remain the concise primary entry point");
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
    assert.match(bootstrapSource, /findString normalizedEntry " \[system"/);
    assert.match(bootstrapSource, /Initializing Max Ultra MCP services/);
    assert.match(bootstrapSource, /Local MCP server health check passed/);
    assert.match(bootstrapSource, /Connected to local MCP server at/);
    assert.match(bootstrapSource, /Update check completed: version/);
    assert.match(bootstrapSource, /addActivity "success" \("Connected to local MCP server at "/);
    assert.match(bootstrapSource, /"server_ready": addActivity "success" "Local MCP server health check passed"/);
    assert.match(bootstrapSource, /addActivity "system" "Initializing Max Ultra MCP services"/);
    assert.doesNotMatch(bootstrapSource, /Custom scene operation|Max Ultra MCP is current|Healthy Max Ultra MCP server already running/);
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
    assert.deepEqual(skillNames, ["max-ultra-camera-composition", "max-ultra-character-object-modeling", "max-ultra-floor-plan", "max-ultra-maxpkg-packaging", "max-ultra-mcp", "max-ultra-renderer-settings", "max-ultra-spline-modeling"]);
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
    assert.match(bootstrapSource, /bootstrapFilePath = getThisScriptFileName\(\)/);
    assert.doesNotMatch(bootstrapSource, /bootstrapFilePath = getSourceFileName\(\)/);
    assertBalancedMaxScript(bootstrapSource);
    assertBalancedMaxScript(maxPkgUninstallHookSource);
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
    assert.equal(bootstrapSource.includes("build" + "Snap" + "shotJson"), false);
    assert.equal(bootstrapSource.includes(`"${legacyInfoTerm}"`), false);
    assert.equal(serverSource.includes("max_" + legacyInfoTerm), false);
    assert.equal(serverSource.includes(`"${legacyInfoTerm}"`), false);
    assert.equal(serverSource.includes(legacyInfoTerm + ":"), false);
    assert.match(bootstrapSource, /"get_info": \([\s\S]*buildGetInfoJson\(\)/);
    assert.match(bootstrapSource, /getPolygonCount sceneNode/);
    assert.match(bootstrapSource, /units\.SystemType/);
    assert.match(bootstrapSource, /units\.SystemScale/);
    assert.match(bootstrapSource, /units\.DisplayType/);
    assert.match(bootstrapSource, /unitsFragment/);
    assert.match(bootstrapSource, /\\"polygons\\"/);
    assert.match(bootstrapSource, /\\"vertices\\"/);
    assert.match(serverSource, /name: "max_get_info"/);
    assert.match(bootstrapSource, /FIRST STEP: Run this file/);
    assert.match(bootstrapSource, /CSharpUtilities\.SynchronizingBackgroundWorker/);
    assert.match(bootstrapSource, /CONTROL\\t1\\tbootstrap-control\\t/);
    assert.match(bootstrapSource, /workerControlRequest workerHost workerPort "probe"/);
    assert.match(bootstrapSource, /"System\.Threading\.Mutex" false workerMutexName/);
    assert.match(bootstrapSource, /ProcessStartInfo/);
    assert.match(bootstrapSource, /UseShellExecute = true/);
    assert.match(bootstrapSource, /--no-pause/);
    assert.match(bootstrapSource, /ConnectAsync workerHost workerPort/);
    assert.match(bootstrapSource, /retryDelays = #\(150, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000\)/);
    assert.match(bootstrapSource, /workerLauncherExitCode launchedServerProcess/);
    assert.match(bootstrapSource, /launcher exited with code/);
    assert.match(bootstrapSource, /run scripts\\\\start-server\.bat to view the launcher error/);
    assert.match(bootstrapSource, /MAX_ULTRA_MCP_ROOT/);
    assert.match(bootstrapSource, /scripts\\\\start-server\.bat/);
    assert.match(bootstrapSource, /MaxUltraMcpActiveClient/);
    assert.match(bootstrapSource, /disposeForReload/);
    assert.doesNotMatch(bootstrapSource, /WaitForExit/);
    assert.match(bootstrapSource, /maximumInboundLinesPerTick = 16/);
    assert.match(bootstrapSource, /maximumRequestsPerTick = 1/);
    assert.equal((bootstrapSource.match(/\.Connect workerHost workerPort/g) || []).length, 1);
    assert.match(bootstrapSource, /System\.Windows\.Forms\.RichTextBox/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpAiStatusDialog ""/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpServerStatusDialog ""/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpActivityDialog ""/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpSupportDialog "" width: 720 height: 44/);
    const dotNetButtonNames = [
      "btnAiStatus", "btnRefreshAgents", "btnHide",
      "btnReconnect", "btnStop", "btnSettings", "btnDonate", "btnCheckUpdates", "btnAgentSetup", "btnAboutDonate",
      "btnInstallAgents", "btnCopyManual", "btnCopyTestPrompt",
    ];
    for (const buttonName of dotNetButtonNames) {
      assert.match(bootstrapSource, new RegExp(`dotNetControl ${buttonName} "System\\.Windows\\.Forms\\.Button"`));
    }
    for (const linkName of ["lnkMaxPkg", "lnk3DGround"]) {
      assert.match(bootstrapSource, new RegExp(`dotNetControl ${linkName} "System\\.Windows\\.Forms\\.LinkLabel"`));
    }
    assert.doesNotMatch(bootstrapSource, /(?:button|dotNetControl)\s+btn(?:ConnectOnly|Start)\b|["']Connect only["']/i);
    assert.doesNotMatch(bootstrapSource, /dotNetControl btnAgents\b|on btnAgents Click|statusDialog\.btnAgents/);
    assert.match(bootstrapSource, /on btnAiStatus Click[\s\S]*showOnboardingDialog refreshStatus: false/);
    assert.doesNotMatch(bootstrapSource, /btnOpenAIStatus|btnClaudeCodeStatus/);
    assert.match(bootstrapSource, /on btnRefreshAgents Click[\s\S]*refreshAgentIntegrationStatus\(\)/);
    assert.match(bootstrapSource, /on btnHide Click[\s\S]*hidePanel\(\)/);
    assert.match(bootstrapSource, /on btnReconnect Click[\s\S]*reconnectBridge\(\)/);
    assert.match(bootstrapSource, /on btnStop Click[\s\S]*closeForLifecycle reason: "Stop \/ Exit pressed"/);
    assert.match(bootstrapSource, /on btnSettings Click[\s\S]*showSettingsDialog\(\)/);
    assert.match(bootstrapSource, /statusDialog\.btnAiStatus\.Text = "AI client \| Waiting\.\.\."/);
    assert.match(bootstrapSource, /statusDialog\.btnRefreshAgents\.AccessibleName = "Refresh AI client readiness"/);
    assert.match(bootstrapSource, /fn createPngIcon pngFilePath = \([\s\S]*System\.Drawing\.Bitmap" pngFilePath[\s\S]*System\.Drawing\.Bitmap" temporaryBitmap[\s\S]*temporaryBitmap\.Dispose\(\)/);
    assert.doesNotMatch(bootstrapSource, /GetPixel|SetPixel|createRefreshIcon|createDonateIcon|createSvgIcon|PresentationCore|System\.Windows\.Media|GraphicsPath|DrawArc iconPen/);
    assert.match(bootstrapSource, /fn uiIconAssetPath iconFileName = \([\s\S]*doesFileExist iconPath/);
    assert.ok(bootstrapSource.includes('@"assets\\icons\\"'));
    assert.match(bootstrapSource, /createPngIcon \(uiIconAssetPath "refresh-cw\.png"\)[\s\S]*createPngIcon \(uiIconAssetPath "heart\.png"\)[\s\S]*createPngIcon \(uiIconAssetPath "panel-top-close\.png"\)[\s\S]*createPngIcon \(uiIconAssetPath "settings\.png"\)[\s\S]*createPngIcon \(uiIconAssetPath "power\.png"\)[\s\S]*createPngIcon \(uiIconAssetPath "plug-zap\.png"\)/);
    assert.match(bootstrapSource, /statusDialog\.btnRefreshAgents\.Text = if \(refreshIconImage == undefined\) then \(\(dotNetClass "System\.Char"\)\.ConvertFromUtf32 0x21BB\) else ""/);
    assert.match(bootstrapSource, /statusDialog\.btnRefreshAgents\.Image = refreshIconImage[\s\S]*ImageAlign = \(dotNetClass "System\.Drawing\.ContentAlignment"\)\.MiddleCenter/);
    assert.match(bootstrapSource, /statusDialog\.btnAiStatus\.AccessibleName = "AI client readiness and setup"/);
    assert.match(bootstrapSource, /panelToolTip\.SetToolTip statusDialog\.btnRefreshAgents "Refresh AI client readiness"/);
    assert.match(bootstrapSource, /panelToolTip\.SetToolTip statusDialog\.btnAiStatus "Open AI Client Setup"/);
    const aiStatusRefreshBody = sourceSection(bootstrapSource, "fn refreshAiStatusControls", "fn manualAgentConfigurationText", "aggregate AI readiness display");
    assert.match(aiStatusRefreshBody, /integrationEffectiveState "openai"[\s\S]*integrationEffectiveState "claudeCode"/);
    assert.match(aiStatusRefreshBody, /readyClientText = "ChatGPT \/ Codex"[\s\S]*readyClientText \+ " \+ Claude Code"/);
    assert.match(aiStatusRefreshBody, /combinedStatusText = readyClientText \+ " \| MCP ready"[\s\S]*combinedStatusState = #pass/);
    assert.match(aiStatusRefreshBody, /combinedStatusText = "Click to set up AI agent"[\s\S]*combinedStatusState = #warning/);
    assert.match(aiStatusRefreshBody, /combinedStatusText = "AI status \| Check failed"[\s\S]*combinedStatusState = #issue/);
    assert.match(aiStatusRefreshBody, /styleButton statusDialog\.btnAiStatus baseColorValue: combinedStatusColor/);
    assert.match(aiStatusRefreshBody, /combinedStatusDescription = "ChatGPT \/ Codex: "[\s\S]*" \| Claude Code: "/);
    assert.match(aiStatusRefreshBody, /btnAiStatus\.AccessibleDescription = combinedStatusDescription[\s\S]*SetToolTip statusDialog\.btnAiStatus combinedStatusDescription/);
    assert.match(bootstrapSource, /on btnDonate Click[\s\S]*shellLaunch "https:\/\/store\.payproglobal\.com\/checkout\?products\[1\]\[id\]=137366"/);
    assert.match(bootstrapSource, /on lnkMaxPkg LinkClicked[\s\S]*shellLaunch "https:\/\/maxpkg\.dev\/catalog\/max-ultra-mcp"/);
    assert.match(bootstrapSource, /on lnk3DGround LinkClicked[\s\S]*shellLaunch "https:\/\/3dground\.net"/);
    const createPanelBody = sourceSection(bootstrapSource, "fn createPanelFloater", "fn restoreHiddenPanel", "main rollout floater creation");
    assert.match(createPanelBody, /newRolloutFloater \(productWindowTitle\(\)\) resolvedSize\.x resolvedSize\.y lockWidth: true lockHeight: true autoLayoutOnResize: false scrollBar: #off/);
    assert.equal((createPanelBody.match(/configureMainPanelControls\(\)/g) || []).length, 1);
    const showPanelConfigureBody = sourceSection(bootstrapSource, "fn showPanel", "fn hidePanel", "main panel display configuration");
    assert.doesNotMatch(showPanelConfigureBody, /configureMainPanelControls\(\)/);
    const panelRolloutNames = ["statusDialog", "serverStatusDialog", "activityDialog", "supportDialog"];
    assert.equal((createPanelBody.match(/addRollout \w+ panelFloater rolledUp: false border: false/g) || []).length, 4);
    let previousRolloutOffset = -1;
    for (const rolloutName of panelRolloutNames) {
      const rolloutStatement = `addRollout ${rolloutName} panelFloater rolledUp: false border: false`;
      const rolloutOffset = createPanelBody.indexOf(rolloutStatement);
      assert.ok(rolloutOffset > previousRolloutOffset, `${rolloutName} must be added in the expected borderless rollout order`);
      previousRolloutOffset = rolloutOffset;
    }
    assert.match(bootstrapSource, /panelForm\.MinimumSize = MaxUltraMcpUiKit\.size 680 600/);
    const panelWindowChromeBody = sourceSection(bootstrapSource, "fn configurePanelWindowChrome", "fn attachPanelFormClosing", "toolbox window chrome");
    assert.match(panelWindowChromeBody, /FormBorderStyle"\)\.FixedToolWindow[\s\S]*ControlBox = true[\s\S]*MinimizeBox = false[\s\S]*MaximizeBox = false[\s\S]*ShowIcon = false/);
    assert.match(bootstrapSource, /panelForm = \(dotNetClass "System\.Windows\.Forms\.Control"\)\.FromHandle dialogHandle[\s\S]*configurePanelWindowChrome panelForm[\s\S]*detachPanelFormEvents panelForm/);
    assert.equal((bootstrapSource.match(/on MaxUltraMcp\w+ resized panelSize/g) || []).length, 1);
    assert.match(bootstrapSource, /on MaxUltraMcpAiStatusDialog resized panelSize do if \(bridgeClient != undefined\) do bridgeClient\.handlePanelResized panelSize/);
    assert.match(bootstrapSource, /on MaxUltraMcpAiStatusDialog close do \([\s\S]*enableAccelerators = true[\s\S]*handlePanelRolloutClosed/);
    const panelResizeBody = sourceSection(bootstrapSource, "fn resizePanelControls", "fn requestedPanelSize", "main panel resizing");
    assert.match(panelResizeBody, /panelLayoutInProgress/);
    assert.match(panelResizeBody, /resolvedPanelSize\.x < 680 or resolvedPanelSize\.y < 600/);
    assert.match(panelResizeBody, /panelForm\.ClientSize\.Width[\s\S]*measuredChromeHeight[\s\S]*panelForm\.ClientSize\.Height/);
    assert.match(panelResizeBody, /statusDialog\.width = panelWidth[\s\S]*serverStatusDialog\.width = panelWidth[\s\S]*activityDialog\.width = panelWidth[\s\S]*supportDialog\.width = panelWidth/);
    assert.match(panelResizeBody, /statusDialog\.height = aiZoneHeight[\s\S]*serverStatusDialog\.height = serverZoneHeight[\s\S]*activityDialog\.height = activityZoneHeight[\s\S]*supportDialog\.height = supportZoneHeight[\s\S]*updateRolloutLayout panelFloater forceUpdate: true/);
    assert.match(panelResizeBody, /local horizontalGap = 10/);
    assert.match(panelResizeBody, /local statusButtonWidth = 444[\s\S]*local refreshButtonX = 8 \+ statusButtonWidth \+ horizontalGap[\s\S]*statusDialog\.btnAiStatus\.width = statusButtonWidth/);
    assert.doesNotMatch(panelResizeBody, /statusesRight|amax 260 \(statusesRight - 8\)|setupButtonWidth|setupButtonX/);
    assert.match(panelResizeBody, /local activityTopPadding = 5[\s\S]*pnlActivityOutline\.pos = \[0,activityTopPadding\][\s\S]*actionButtonY = activityTopPadding \+ logHeight \+ 8/);
    assert.match(panelResizeBody, /activityDialog\.rtbActivity\.Size = MaxUltraMcpUiKit\.size \(amax 1 \(panelWidth - 2\)\) \(amax 1 \(logHeight - 2\)\)/);
    assert.match(panelResizeBody, /activityDialog\.btnSettings\.pos = \[panelWidth - 128,actionButtonY\]/);
    assert.match(panelResizeBody, /supportDialog\.lnkMaxPkg\.pos = \[8,7\][\s\S]*supportDialog\.lnk3DGround\.pos = \[104,7\][\s\S]*supportDialog\.btnDonate\.pos = \[panelWidth - 128,7\]/);
    assert.doesNotMatch(panelResizeBody, /supportDialog\.(?:lnkMaxPkg|lnk3DGround|btnDonate)\.Location/);
    assert.doesNotMatch(bootstrapSource, /pnlFooterSurface/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpSettingsDialog "Max Ultra MCP Settings"/);
    assert.match(bootstrapSource, /groupBox grpAutostart "Autostart" pos: \[12,10\] width: 356 height: 58/);
    assert.match(bootstrapSource, /groupBox grpUpdates "Updates" pos: \[12,146\] width: 356 height: 94/);
    assert.match(bootstrapSource, /checkbox chkAutomaticUpdates "Check and install updates automatically"/);
    assert.match(bootstrapSource, /settingsDialog\.btnCheckUpdates\.Text = "Check now"/);
    assert.match(bootstrapSource, /groupBox grpAbout "About" pos: \[12,320\] width: 356 height: 184/);
    assert.match(bootstrapSource, /label lblAboutProduct "3DGROUND - Max Ultra MCP" pos: \[24,342\] width: 332 height: 18 align: #center/);
    assert.match(bootstrapSource, /label lblAboutVersion "Unknown" pos: \[24,362\] width: 332 height: 18 align: #center/);
    assert.match(bootstrapSource, /label lblAboutAuthor "Lukianenko Vasyl" pos: \[24,382\] width: 332 height: 18 align: #center/);
    assert.match(bootstrapSource, /hyperLink lnkAboutWebsite "3dground\.net" address: "https:\/\/3dground\.net" pos: \[24,406\] width: 332 height: 18 align: #center color: orange hoverColor: orange visitedColor: orange/);
    assert.match(bootstrapSource, /hyperLink lnkAboutPackageManager "maxpkg\.dev" address: "https:\/\/maxpkg\.dev" pos: \[24,428\] width: 332 height: 18 align: #center color: orange hoverColor: orange visitedColor: orange/);
    assert.doesNotMatch(bootstrapSource, /dotNetControl lnkAbout(?:Website|PackageManager)/);
    assert.match(bootstrapSource, /dotNetControl btnAboutDonate "System\.Windows\.Forms\.Button" pos: \[130,458\] width: 120 height: 30/);
    assert.match(bootstrapSource, /readIniValueWithoutMutation manifestFilePath "package" "version"/);
    assert.match(bootstrapSource, /readIniValueWithoutMutation versionFilePath "MaxUltraMCP" "Version"/);
    assert.match(bootstrapSource, /\(dotNetClass "System\.IO\.File"\)\.ReadAllText filePath/);
    assert.doesNotMatch(bootstrapSource, /getINISetting (manifestFilePath|versionFilePath)/);
    assert.match(bootstrapSource, /settingsDialog\.lblAboutVersion\.caption = productVersion/);
    assert.match(bootstrapSource, /local activityLabel = if \(wireFields\.count >= 5\) then decodeWireField\(wireFields\[5\]\) else ""/);
    assert.match(bootstrapSource, /operationLabel \+ " \[" \+ shortRequestId \+ "\]"/);
    assert.doesNotMatch(bootstrapSource, /Executing MaxScript request/);
    assert.match(bootstrapSource, /MaxUltraMcpUiKit\.styleButton settingsDialog\.btnAboutDonate baseColorValue: MaxUltraMcpTheme\.linkColor/);
    assert.match(bootstrapSource, /settingsDialog\.btnAboutDonate\.Text = if \(donateIconImage == undefined\) then "Donate" else "  Donate"[\s\S]*settingsDialog\.btnAboutDonate\.Image = donateIconImage[\s\S]*TextImageRelation"\)\.ImageBeforeText/);
    assert.match(bootstrapSource, /on btnAboutDonate Click eventSender eventArgs do try \(shellLaunch "https:\/\/store\.payproglobal\.com\/checkout\?products\[1\]\[id\]=137366" ""\) catch \(\)/);
    assert.match(bootstrapSource, /checkbox chkAutostart "Autostart with 3ds Max"/);
    assert.match(bootstrapSource, /on chkAutostart changed isChecked do if \(bridgeClient != undefined\) do bridgeClient\.handleAutostartSettingChanged isChecked/);
    assert.match(bootstrapSource, /groupBox grpServerConsole "Server console" pos: \[12,78\] width: 356 height: 58/);
    assert.match(bootstrapSource, /checkbox chkShowServerConsole "Show server console when starting"/);
    assert.match(bootstrapSource, /on chkShowServerConsole changed isChecked do if \(bridgeClient != undefined\) do bridgeClient\.handleServerConsoleVisibilityChanged isChecked/);
    assert.doesNotMatch(bootstrapSource, /btnSave|on btnSave pressed|btnClose|on btnClose pressed/);
    assert.match(bootstrapSource, /createDialog settingsDialog width: 380 height: 516/);
    assert.match(bootstrapSource, /settingsDialog\.btnAgentSetup\.Text = "Open AI client setup\.\.\."/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpOnboardingTabsDialog ""/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpOnboardingSetupDialog ""/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpOnboardingTestDialog ""/);
    assert.match(bootstrapSource, /dotNetControl dncPages "System\.Windows\.Forms\.TabControl"/);
    assert.match(bootstrapSource, /checkbox chkOpenAI "ChatGPT Desktop \/ Codex"/);
    assert.match(bootstrapSource, /checkbox chkClaudeCode "Claude Code"/);
    assert.match(bootstrapSource, /onboardingTestDialog\.btnCopyTestPrompt\.Text = "Copy test prompt"/);
    assert.match(bootstrapSource, /dotNetControl txtTestPrompt "System\.Windows\.Forms\.TextBox"/);
    assert.match(bootstrapSource, /txtTestPrompt\.Text = onboardingTestPromptText\(\)/);
    assert.match(bootstrapSource, /newRolloutFloater "Max Ultra MCP - AI Client Setup"/);
    assert.match(bootstrapSource, /addRollout onboardingTabsDialog onboardingFloater rolledUp: false border: false/);
    assert.match(bootstrapSource, /addRollout onboardingTestDialog onboardingFloater rolledUp: false border: false/);
    assert.match(bootstrapSource, /addRollout onboardingSetupDialog onboardingFloater rolledUp: false border: false/);
    assert.match(bootstrapSource, /removeRollout onboardingSetupDialog onboardingFloater/);
    assert.doesNotMatch(bootstrapSource, /btnSetupPage|btnTestPage|txtTestPrompt\.Visible|txtTestPrompt\.BringToFront/);
    assert.match(bootstrapSource, /local rolloutBackground = MaxUltraMcpTheme\.backgroundColor/);
    assert.match(bootstrapSource, /lblOpenAIStatus\.BackColor = rolloutBackground/);
    assert.match(bootstrapSource, /clipboardFeedbackButton\.text = "Copied"/);
    assert.match(bootstrapSource, /clipboardFeedbackTimer\.Interval = 1600/);
    assert.match(bootstrapSource, /fn onboardingTestPromptText/);
    assert.match(bootstrapSource, /Call max_health and max_scene_summary/);
    assert.match(bootstrapSource, /Do not run arbitrary MaxScript, change the scene, start a render, or save any file/);
    assert.match(bootstrapSource, /restart or reconnect this AI client so it reloads the MCP host/);
    assert.match(bootstrapSource, /onboardingSetupDialog\.btnInstallAgents\.Text = "Install selected"/);
    assert.match(bootstrapSource, /onboardingSetupDialog\.btnCopyManual\.Text = "Copy manual setup"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "onboarding" "dismissed"/);
    assert.match(bootstrapSource, /fn beginAutomaticOnboardingCheck/);
    assert.match(bootstrapSource, /beginAutomaticOnboardingCheck\(\)/);
    assert.match(bootstrapSource, /pollIntegrationOperation\(\)/);
    const automaticAgentCheckBody = sourceSection(
      bootstrapSource,
      "fn beginAutomaticOnboardingCheck",
      "fn defaultRestoreBubblePosition",
      "delayed automatic AI readiness check",
    );
    assert.match(automaticAgentCheckBody, /integrationAutomaticCheckPending = true[\s\S]*UtcNow\.AddSeconds 2\.0/);
    assert.match(automaticAgentCheckBody, /not integrationAutomaticCheckPending or integrationAutomaticCheckDueAt == undefined or integrationBusy/);
    assert.match(automaticAgentCheckBody, /return startIntegrationOperation #status automaticCheck: true/);
    assert.doesNotMatch(automaticAgentCheckBody, /loadOnboardingDismissed|showOnboardingDialog/);
    const manualAgentRefreshBody = sourceSection(
      bootstrapSource,
      "fn refreshAgentIntegrationStatus",
      "fn installSelectedAgentIntegrations",
      "manual AI readiness refresh",
    );
    assert.match(manualAgentRefreshBody, /integrationAutomaticCheckPending = false[\s\S]*integrationAutomaticCheckDueAt = undefined[\s\S]*startIntegrationOperation #status automaticCheck: false/);
    const integrationOperationBody = sourceSection(
      bootstrapSource,
      "fn startIntegrationOperation",
      "fn pollIntegrationOperation",
      "AI integration operation startup",
    );
    assert.match(integrationOperationBody, /if \(isDisposed or integrationBusy\) do return false/);
    assert.match(integrationOperationBody, /integrationOperationTimeoutSeconds = if \(actionName == #install\) then 90 else 30/);
    const integrationPollBody = sourceSection(
      bootstrapSource,
      "fn pollIntegrationOperation",
      "fn copyOnboardingTestPrompt",
      "AI integration operation polling",
    );
    assert.match(integrationPollBody, /elapsedTime\.TotalSeconds >= integrationOperationTimeoutSeconds/);
    assert.match(integrationPollBody, /integrationLastCheckFailed = true[\s\S]*timed out after/);
    assert.match(integrationPollBody, /refreshOnboardingDialog\(\)[\s\S]*if \(wasAutomaticCheck[\s\S]*not \(loadOnboardingDismissed\(\)\)\) do showOnboardingDialog refreshStatus: false/);
    assert.match(integrationPollBody, /local conclusiveStates = #\("configured", "not_configured", "restart_required", "cli_missing", "runtime_missing"\)/);
    assert.match(integrationPollBody, /automaticCheckConclusive[\s\S]*if \(wasAutomaticCheck and helperExitCode == 0 and automaticCheckConclusive/);
    assert.doesNotMatch(integrationPollBody.match(/local conclusiveStates = #[^\n]+/)?.[0] || "", /check_failed/);
    assert.match(bootstrapSource, /fn integrationEffectiveState[\s\S]*integrationValueIsTrue "runtime" "ready"[\s\S]*return "runtime_missing"/);
    assert.match(bootstrapSource, /"check_failed": "Check failed - refresh status to retry"/);
    assert.match(bootstrapSource, /"check_failed": "Check failed"/);
    assert.match(bootstrapSource, /"check_failed": #issue/);
    assert.match(bootstrapSource, /MaxUltraMcpUiKit\.updateButtonState statusDialog\.btnRefreshAgents \(not integrationBusy\)/);
    assert.match(bootstrapSource, /UseShellExecute = false/);
    assert.match(bootstrapSource, /CreateNoWindow = true/);
    assert.match(bootstrapSource, /scripts\\agent-integration\.ps1/);
    assert.match(bootstrapSource, /onboardingTabsDialog: MaxUltraMcpOnboardingTabsDialog onboardingSetupDialog: MaxUltraMcpOnboardingSetupDialog onboardingTestDialog: MaxUltraMcpOnboardingTestDialog/);
    assert.match(agentIntegrationSource, /\[ValidateSet\('Status','Install'\)\]/);
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
    assert.match(versionIniSource, /\[MaxUltraMCP\][\s\S]*Version=\d+\.\d+\.\d+[\s\S]*Channel=stable/);
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
    assert.match(bootstrapSource, /fileIn pendingPackagePath quiet: true[\s\S]*fileIn restartBootstrapPath quiet: true/);
    assert.match(bootstrapSource, /updateProcess = \(dotNetClass "System\.Diagnostics\.Process"\)\.Start startInfo/);
    assert.ok(
      bootstrapSource.indexOf("fn quoteProcessArgument") < bootstrapSource.indexOf("fn startUpdateCheck"),
      "Update process arguments must be quoted by a helper defined before startUpdateCheck",
    );
    assert.match(bootstrapSource, /trailingBackslashCount[\s\S]*argumentContent \+= "\\\\"/);
    assert.match(bootstrapSource, /Update helper exited before writing a result \(exit code/);
    assert.doesNotMatch(bootstrapSource, /rolloutBackground = themeDrawingColor #rollupTitleFace/);
    assert.match(updateManagerSource, /Get-MaxUltraSha256Hash[\s\S]*temporaryPackagePath/);
    assert.match(maxPkgFilesSource, /version\.ini/);
    assert.match(maxPkgFilesSource, /CHANGELOG\.md/);
    assert.match(maxPkgFilesSource, /^core\/package\.json$/m);
    assert.match(maxPkgFilesSource, /^AGENTS\.md$/m);
    assert.match(maxPkgFilesSource, /^\.agents\/coding-rules\.md$/m);
    assert.match(maxPkgFilesSource, /^\.agents\/release-rules\.md$/m);
    assert.match(maxPkgFilesSource, /^docs\/MAXPKG\.md$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/refresh-cw\.png$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/heart\.png$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/panel-top-close\.png$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/plug-zap\.png$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/power\.png$/m);
    assert.match(maxPkgFilesSource, /^assets\/icons\/settings\.png$/m);
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
    assert.match(maxPkgUninstallHookSource, /WaitForExit 30000/);
    assert.match(maxPkgUninstallHookSource, /RedirectStandardError = true/);
    assert.match(maxPkgUninstallHookSource, /cleanup failed: /);
    assert.match(maxPkgUninstallHookSource, /maxpkg-uninstall\.ps1/);
    assert.match(maxPkgUninstallHookSource, /fn maxUltraMcpQuoteUninstallArgument/);
    assert.match(maxPkgUninstallHookSource, /trailingBackslashCount/);
    assert.match(maxPkgUninstallHookSource, /maxUltraMcpQuoteUninstallArgument packageRoot/);
    assert.match(maxPkgIconSource, /<svg\b/i);
    assert.doesNotMatch(maxPkgIconSource, /<script\b|javascript:|onload\s*=|onclick\s*=|onerror\s*=|<foreignObject\b/i);
    assert.match(bootstrapSource, /getDir #userStartupScripts/);
    assert.match(bootstrapSource, /3DGROUND-Max-Ultra-MCP-Autostart\.ms/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "settings" "autostart"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "settings" "autostart"/);
    assert.match(bootstrapSource, /fn handleAutostartSettingChanged isEnabled/);
    assert.match(bootstrapSource, /if \(settingsRefreshInProgress\) do return true/);
    assert.match(bootstrapSource, /if \(setAutostartEnabled isEnabled\) do return true/);
    assert.match(bootstrapSource, /createFile autostartFilePath/);
    assert.match(bootstrapSource, /if \(storedSetting == "false" and autostartFileExists\)[\s\S]*persistAutostartSetting true/);
    assert.match(bootstrapSource, /fileIn maxUltraMcpBootstrapPath quiet: true/);
    assert.match(bootstrapSource, /if \(doesFileExist maxUltraMcpBootstrapPath\) then/);
    assert.match(bootstrapSource, /callbacks\.addScript #postSystemStartup/);
    assert.match(bootstrapSource, /deleteFile autostartFilePath/);
    assert.match(bootstrapSource, /if \(doesFileExist autostartFilePath\) do deleteFile autostartFilePath/);
    assert.match(bootstrapSource, /persistAutostartSetting false/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "settings" "showServerConsole"/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "settings" "showServerConsole"/);
    assert.match(bootstrapSource, /fn handleServerConsoleVisibilityChanged isVisible/);
    assert.match(bootstrapSource, /persistServerConsoleVisibleSetting false[\s\S]*return false/);
    assert.match(bootstrapSource, /workerArguments\.Add \(loadServerConsoleVisibleSetting\(\)\)/);
    assert.match(bootstrapSource, /local workerServerConsoleVisible = workerArguments\.Item\[11\]/);
    assert.match(bootstrapSource, /disposeSettingsDialog\(\)/);
    assert.match(bootstrapSource, /settingsDialog: MaxUltraMcpSettingsDialog/);
    assert.match(bootstrapSource, /fn productWindowTitle = \([\s\S]*return "3DGROUND - Max Ultra MCP"/);
    assert.match(bootstrapSource, /UIAccessor\.SetWindowText panelFloater\.hwnd expectedTitle/);
    assert.doesNotMatch(bootstrapSource, /MaxUltraMcpAiStatusDialog ".*First Step/);
    assert.doesNotMatch(bootstrapSource, /3D\sGround/);
    assert.match(bootstrapSource, /on MaxUltraMcpAiStatusDialog moved panelPosition do if \(bridgeClient != undefined\) do bridgeClient\.handlePanelMoved panelPosition/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler panelForm "FormClosing" handlePanelFormClosing/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler panelForm "LocationChanged" handlePanelGeometryChanged/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler panelForm "ResizeEnd" handlePanelGeometryChanged/);
    assert.match(bootstrapSource, /formSender\.WindowState != normalWindowState/);
    assert.match(bootstrapSource, /local restoreBounds = formSender\.RestoreBounds/);
    assert.match(bootstrapSource, /local finalGeometry = capturePanelGeometry formSender/);
    assert.match(bootstrapSource, /persistPanelGeometry finalGeometry\[1\] finalGeometry\[2\]/);
    const stopTimerBody = bootstrapSource.slice(bootstrapSource.indexOf("fn stopPollTimer"), bootstrapSource.indexOf("fn performPanelFormClosing"));
    const formClosingBody = bootstrapSource.slice(bootstrapSource.indexOf("fn performPanelFormClosing"), bootstrapSource.indexOf("fn attachPanelFormClosing"));
    assert.match(stopTimerBody, /pollTimer = undefined[\s\S]*timerToDispose\.Stop\(\)[\s\S]*removeEventHandlers timerToDispose "Tick"[\s\S]*timerToDispose\.Dispose\(\)/);
    assert.ok(formClosingBody.indexOf("stopPollTimer()") < formClosingBody.indexOf("persistPanelGeometry"), "Timer must stop before panel cleanup touches external controls");
    assert.ok(formClosingBody.indexOf("persistPanelGeometry") < formClosingBody.indexOf("CancelAsync"), "Final panel geometry must be saved before transport cleanup");
    assert.match(formClosingBody, /detachPanelFormEvents formSender/);
    assert.match(formClosingBody, /fn handlePanelRolloutClosed/);
    assert.match(formClosingBody, /local wasAlreadyDisposed = isDisposed[\s\S]*if \(suppressPanelShutdown or wasAlreadyDisposed\) do return true/);
    assert.match(formClosingBody, /if \(suppressPanelShutdown or isDisposed or panelCloseInProgress\) do \([\s\S]*panelFloater = undefined[\s\S]*panelForm = undefined[\s\S]*return true/);
    assert.match(formClosingBody, /handlePanelFormClosing closedPanelForm undefined/);
    assert.match(bootstrapSource, /removeEventHandler formSender "LocationChanged" handlePanelGeometryChanged/);
    assert.match(bootstrapSource, /removeEventHandler formSender "ResizeEnd" handlePanelGeometryChanged/);
    assert.match(bootstrapSource, /fn normalizePanelGeometry/);
    assert.match(bootstrapSource, /System\.Windows\.Forms\.Screen/);
    assert.match(bootstrapSource, /Screen"\)\.FromRectangle candidateBounds/);
    assert.match(bootstrapSource, /fn requestedPanelSize panelSize = \([\s\S]*return \[720, 640\]/);
    const requestedPanelSizeBody = sourceSection(bootstrapSource, "fn requestedPanelSize", "fn clampPanelSizeToWorkingArea", "fixed main panel size");
    assert.doesNotMatch(requestedPanelSizeBody, /panelSize\.x|panelSize\.y|requestedWidth|requestedHeight/);
    assert.match(bootstrapSource, /local minimumWidth = 680[\s\S]*local minimumHeight = 600/);
    assert.match(bootstrapSource, /local maximumWidth = amax minimumWidth \(workingArea\.Width as integer\)/);
    assert.match(bootstrapSource, /local maximumHeight = amax minimumHeight \(workingArea\.Height as integer\)/);
    assert.match(bootstrapSource, /local clampedX = amax workingArea\.Left \(amin maximumX panelX\)/);
    assert.match(bootstrapSource, /local clampedY = amax workingArea\.Top \(amin maximumY panelY\)/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "panel" "x"/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "panel" "width"/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "panel" "height"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "panel" "x"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "panel" "width"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "panel" "height"/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "panel" "hidden"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "panel" "hidden" \(if \(isHidden\) then "true" else "false"\)/);
    assert.match(bootstrapSource, /if \(storedHiddenState == "true"\) do return true/);
    assert.match(bootstrapSource, /if \(storedHiddenState != "false"\) do persistPanelHiddenState false/);
    assert.match(bootstrapSource, /if \(not isDisposed and rememberNormalPanelGeometry formSender\)[\s\S]*persistPanelGeometry lastNormalPanelPosition lastNormalPanelSize/);
    assert.match(bootstrapSource, /return normalizePanelGeometry storedPosition storedSize/);
    assert.match(bootstrapSource, /PrimaryScreen\.WorkingArea/);
    assert.match(bootstrapSource, /fn normalizeThemePoint themeValue fallbackPoint/);
    assert.match(bootstrapSource, /if \(convertedPoint\.x <= 1\.001 and convertedPoint\.y <= 1\.001 and convertedPoint\.z <= 1\.001\) do convertedPoint \*= 255\.0/);
    assert.match(bootstrapSource, /amin #\(255\.0, amax #\(0\.0, convertedPoint\.x\)\)/);
    assert.match(bootstrapSource, /colorMan\.getColor colorId/);
    assert.match(bootstrapSource, /backgroundPoint = this\.getThemePoint #window \[68, 68, 68\]/);
    assert.match(bootstrapSource, /rolloutPoint = this\.getThemePoint #rollupTitleFace \[81, 81, 81\]/);
    assert.match(bootstrapSource, /passPoint = \(backgroundPoint \* 0\.20\) \+ \(\[54, 132, 66\] \* 0\.80\)/);
    assert.match(bootstrapSource, /issuePoint = \(backgroundPoint \* 0\.20\) \+ \(\[164, 52, 52\] \* 0\.80\)/);
    assert.match(bootstrapSource, /supportPoint = \(backgroundPoint \* 0\.18\) \+ \(\[184, 88, 52\] \* 0\.82\)/);
    assert.match(bootstrapSource, /linkPoint = \[255, 127, 0\][\s\S]*linkColor = this\.toDotNetColor linkPoint/);
    assert.match(bootstrapSource, /bridgePassTextPoint = \[112, 210, 125\][\s\S]*bridgeIssueTextPoint = \[238, 126, 126\][\s\S]*bridgePassTextColor = this\.toDotNetColor bridgePassTextPoint[\s\S]*bridgeIssueTextColor = this\.toDotNetColor bridgeIssueTextPoint/);
    assert.match(bootstrapSource, /footerPoint = backgroundPoint/);
    assert.match(bootstrapSource, /fn statusColor statusState = \([\s\S]*#support: supportColor[\s\S]*default: neutralColor/);
    assert.match(bootstrapSource, /fn styleButton buttonControl[\s\S]*FlatStyle"\)\.Flat[\s\S]*UseCompatibleTextRendering = false[\s\S]*MouseOverBackColor[\s\S]*MouseDownBackColor/);
    assert.match(bootstrapSource, /fn applyIndependentBoldFont targetControl = \([\s\S]*System\.Drawing\.Font" baseFont\.FontFamily baseFont\.SizeInPoints[\s\S]*FontStyle"\)\.Bold[\s\S]*targetControl\.Font = controlFont[\s\S]*targetControl\.Tag = controlFont/);
    const inheritParentBackColorBody = sourceSection(bootstrapSource, "fn inheritParentBackColor", "fn styleLink", "parent background inheritance");
    assert.match(inheritParentBackColorBody, /maximumThemeChannelDelta = 32[\s\S]*targetControl\.Parent[\s\S]*parentDepth < 8[\s\S]*candidateColor = parentControl\.BackColor[\s\S]*not candidateColor\.IsEmpty[\s\S]*candidateColor\.A > 0[\s\S]*rolloutDelta[\s\S]*backgroundDelta[\s\S]*amin rolloutDelta backgroundDelta[\s\S]*theme\.rolloutColor[\s\S]*targetControl\.BackColor = inheritedColor/);
    assert.match(bootstrapSource, /fn styleLink linkControl = \([\s\S]*inheritParentBackColor linkControl fallbackColor: theme\.rolloutColor[\s\S]*LinkColor = theme\.linkColor[\s\S]*ActiveLinkColor = .*theme\.linkColor[\s\S]*VisitedLinkColor = theme\.linkColor[\s\S]*LinkBehavior"\)\.HoverUnderline[\s\S]*TabStop = true/);
    assert.match(bootstrapSource, /MaxUltraMcpUiKit\.styleButton supportDialog\.btnDonate baseColorValue: MaxUltraMcpTheme\.linkColor/);
    assert.match(bootstrapSource, /supportDialog\.btnDonate\.Text = "  Donate"[\s\S]*supportDialog\.btnDonate\.Image = donateIconImage[\s\S]*ImageAlign = \(dotNetClass "System\.Drawing\.ContentAlignment"\)\.MiddleCenter[\s\S]*TextAlign = \(dotNetClass "System\.Drawing\.ContentAlignment"\)\.MiddleCenter[\s\S]*TextImageRelation"\)\.ImageBeforeText/);
    assert.match(bootstrapSource, /statusDialog\.btnHide\.Text = if \(hideIconImage == undefined\) then "Hide panel" else "  Hide panel"[\s\S]*statusDialog\.btnHide\.Image = hideIconImage[\s\S]*TextImageRelation"\)\.ImageBeforeText/);
    assert.match(bootstrapSource, /activityDialog\.btnReconnect\.Text = if \(reconnectIconImage == undefined\) then "Reconnect" else "  Reconnect"[\s\S]*activityDialog\.btnReconnect\.Image = reconnectIconImage[\s\S]*TextImageRelation"\)\.ImageBeforeText/);
    assert.match(bootstrapSource, /activityDialog\.btnStop\.Text = if \(stopIconImage == undefined\) then "Stop \/ Exit" else "  Stop \/ Exit"[\s\S]*activityDialog\.btnStop\.Image = stopIconImage[\s\S]*TextImageRelation"\)\.ImageBeforeText/);
    assert.match(bootstrapSource, /activityDialog\.btnSettings\.Text = if \(settingsIconImage == undefined\) then "Settings" else "  Settings"[\s\S]*activityDialog\.btnSettings\.Image = settingsIconImage[\s\S]*TextImageRelation"\)\.ImageBeforeText/);
    assert.match(bootstrapSource, /local hideButtonWidth = 120[\s\S]*statusDialog\.btnHide\.width = hideButtonWidth/);
    assert.match(bootstrapSource, /fn lighterThemeSurface/);
    const lighterThemeSurfaceBody = sourceSection(bootstrapSource, "fn lighterThemeSurface", "fn themeIsDark", "lighter themed log surface");
    assert.equal((lighterThemeSurfaceBody.match(/\* 0\.08\) as integer/g) || []).length, 3);
    assert.match(bootstrapSource, /MaxUltraMcpUiKit\.styleLabel serverStatusDialog\.lblConnectionIndicator[\s\S]*MaxUltraMcpUiKit\.styleLabel serverStatusDialog\.lblEndpoint[\s\S]*MaxUltraMcpUiKit\.styleLabel serverStatusDialog\.lblContext/);
    assert.match(bootstrapSource, /applyIndependentBoldFont serverStatusDialog\.lblEndpoint/);
    assert.match(bootstrapSource, /fn styleLabel labelControl[\s\S]*labelControl\.AutoSize = false[\s\S]*labelControl\.UseCompatibleTextRendering = false/);
    assert.match(bootstrapSource, /inheritParentBackColor serverStatusDialog\.lblConnectionIndicator fallbackColor: MaxUltraMcpTheme\.rolloutColor[\s\S]*inheritParentBackColor serverStatusDialog\.lblEndpoint fallbackColor: MaxUltraMcpTheme\.rolloutColor[\s\S]*inheritParentBackColor serverStatusDialog\.lblContext fallbackColor: MaxUltraMcpTheme\.rolloutColor/);
    assert.doesNotMatch(bootstrapSource, /serverStatusDialog\.lbl(?:ConnectionIndicator|Endpoint|Context)\.BackColor = transparentUiColor/);
    assert.match(bootstrapSource, /activityDialog\.rtbActivity\.BackColor = lighterThemeSurface\(\)/);
    assert.match(bootstrapSource, /activityDialog\.rtbActivity\.BorderStyle = \(dotNetClass "System\.Windows\.Forms\.BorderStyle"\)\.None/);
    assert.match(bootstrapSource, /activityDialog\.rtbActivity\.WordWrap = true/);
    assert.match(bootstrapSource, /AccessibleName = "Bridge connection indicator"/);
    assert.match(bootstrapSource, /AccessibleName = "Max Ultra MCP endpoint or connection problem"/);
    assert.match(bootstrapSource, /AccessibleName = "3ds Max scene context"/);
    const sceneUiNameBody = sourceSection(bootstrapSource, "fn currentSceneUiName", "fn safeSingleLineUiText", "filename-only scene UI name");
    assert.match(sceneUiNameBody, /if \(maxFileName == undefined or maxFileName == ""\) do return "Untitled"[\s\S]*return maxFileName/);
    assert.doesNotMatch(sceneUiNameBody, /maxFilePath|currentSceneFilePath|currentSceneDisplayName/);
    const refreshUiBody = sourceSection(bootstrapSource, "fn refreshUserInterface", "fn showPanel", "main panel status refresh");
    assert.match(refreshUiBody, /#connected: endpointText = "Server " \+ hostAddress \+ ":" \+ \(hostPort as string\)/);
    assert.match(refreshUiBody, /#error: endpointText = "Please restart the script"[\s\S]*default: endpointText = "Please restart the script"/);
    assert.match(refreshUiBody, /endpointDetails = if \(connectionState == #error or connectionState == #disconnected or connectionState == #stopped\) then \(safeSingleLineUiText connectionError endpointText\) else endpointText/);
    assert.match(refreshUiBody, /local connectionColor = bridgeStatusTextColor\(\)/);
    assert.match(refreshUiBody, /serverStatusDialog\.lblConnectionIndicator\.AccessibleDescription = connectionStateText\(\)/);
    assert.match(refreshUiBody, /local contextText = "PID " \+ \(processId as string\) \+ " \| Scene " \+ currentSceneUiName\(\) \+ " \| Objects " \+ \(objects\.count as string\) \+ " \| Selection " \+ \(selection\.count as string\)/);
    assert.doesNotMatch(refreshUiBody, /currentSceneFilePath|currentSceneDisplayName/);
    assert.match(refreshUiBody, /serverStatusDialog\.lblEndpoint\.AccessibleDescription = endpointDetails/);
    assert.match(refreshUiBody, /serverStatusDialog\.lblContext\.AccessibleDescription = contextText/);
    assert.match(refreshUiBody, /panelToolTip\.SetToolTip serverStatusDialog\.lblEndpoint endpointDetails[\s\S]*panelToolTip\.SetToolTip serverStatusDialog\.lblContext contextText/);
    assert.match(bootstrapSource, /firstSupportReminderMinutes = 10/);
    assert.match(bootstrapSource, /recurringSupportReminderMinutes = 60/);
    assert.match(bootstrapSource, /maximumSupportReminders = 3/);
    const supportArmBody = sourceSection(bootstrapSource, "fn armSupportReminders", "fn pollSupportReminder", "support reminder arming");
    assert.match(supportArmBody, /if \(supportReminderCount > 0 or supportReminderDueAt != undefined\) do return true/);
    assert.match(supportArmBody, /UtcNow\.AddMinutes \(firstSupportReminderMinutes as double\)/);
    const supportPollBody = sourceSection(bootstrapSource, "fn pollSupportReminder", "fn configureMainPanelControls", "support reminder polling");
    assert.match(supportPollBody, /supportReminderCount >= maximumSupportReminders/);
    assert.match(supportPollBody, /if \(not deadlineReached\) do return true/);
    assert.equal((supportPollBody.match(/addActivity "support" supportReminderMessage/g) || []).length, 1);
    assert.match(supportPollBody, /supportReminderCount \+= 1[\s\S]*UtcNow\.AddMinutes \(recurringSupportReminderMinutes as double\)/);
    assert.match(supportPollBody, /else \([\s\S]*supportReminderDueAt = undefined/);
    assert.doesNotMatch(supportPollBody, /\b(?:while|for)\b/);
    assert.match(bootstrapSource, /"connected": \([\s\S]*armSupportReminders\(\)/);
    assert.match(bootstrapSource, /maximumActivityEntries = 30/);
    assert.match(bootstrapSource, /activityStatusColumnWidth = 7/);
    assert.match(bootstrapSource, /activityStatusLeadingGap = "  "/);
    assert.match(bootstrapSource, /activityStatusSeparator = "  >  "/);
    assert.match(bootstrapSource, /activityBottomPadding = "\\r\\n\\r\\n\\r\\n"/);
    const activityDisplayEntryTextBody = sourceSection(bootstrapSource, "fn activityDisplayEntryText", "fn activityDisplayCoreText", "activity status display alignment");
    assert.match(activityDisplayEntryTextBody, /statusStart = findString normalizedEntry "\["[\s\S]*statusEnd = findString normalizedEntry "\]"/);
    assert.match(activityDisplayEntryTextBody, /while \(statusName\.count < activityStatusColumnWidth\) do statusName \+= " "/);
    assert.match(activityDisplayEntryTextBody, /substring suffixText 1 activityStatusSeparator\.count\) == activityStatusSeparator\) do return normalizedEntry/);
    assert.match(activityDisplayEntryTextBody, /prefixText = if \(statusStart > 1\) then \(\(substring normalizedEntry 1 \(statusStart - 1\)\) \+ activityStatusLeadingGap \+ "\["\) else "\["/);
    assert.match(activityDisplayEntryTextBody, /substring suffixText 1 1\) == " "[\s\S]*return prefixText \+ statusName \+ "\]" \+ activityStatusSeparator \+ suffixText/);
    const activityDisplayCoreTextBody = sourceSection(bootstrapSource, "fn activityDisplayCoreText", "fn activityDisplayText", "activity display-only text");
    assert.match(activityDisplayCoreTextBody, /outputText \+= activityDisplayEntryText activityEntry/);
    const activityDisplayTextBody = sourceSection(bootstrapSource, "fn activityDisplayText", "fn activityTextWithoutBottomPadding", "activity log bottom padding");
    assert.match(activityDisplayTextBody, /local outputText = activityDisplayCoreText\(\)[\s\S]*return outputText \+ activityBottomPadding/);
    const activityStripPaddingBody = sourceSection(bootstrapSource, "fn activityTextWithoutBottomPadding", "fn configureActivityLog", "activity log padding removal");
    assert.match(activityStripPaddingBody, /suffixStart = normalizedText\.count - activityBottomPadding\.count \+ 1[\s\S]*contentLength = normalizedText\.count - activityBottomPadding\.count/);
    const activityLogPaddingBody = sourceSection(bootstrapSource, "fn applyActivityLogPadding", "fn configureActivityLog", "activity log horizontal padding");
    assert.match(activityLogPaddingBody, /richEditMessageSetMargins = 0x00D3[\s\S]*bothHorizontalMargins = 0x0003[\s\S]*horizontalPadding = 6[\s\S]*packedMargins = horizontalPadding \+ \(horizontalPadding \* 65536\)[\s\S]*windows\.sendMessage logWindowHandle richEditMessageSetMargins bothHorizontalMargins packedMargins/);
    const activityBadgeFontBody = sourceSection(bootstrapSource, "fn ensureActivityBadgeFont", "fn configureActivityLog", "activity status monospace font");
    assert.match(activityBadgeFontBody, /FontFamily"\)\.GenericMonospace[\s\S]*dotNetObject "System\.Drawing\.Font" monospaceFamily baseFont\.SizeInPoints/);
    assert.match(bootstrapSource, /activityDialog\.rtbActivity\.Font = MaxUltraMcpUiKit\.messageFont\(\)[\s\S]*ensureActivityBadgeFont\(\)[\s\S]*applyActivityLogPadding\(\)/);
    assert.match(bootstrapSource, /activityLogDirty = true/);
    const appendColoredActivityTextBody = sourceSection(bootstrapSource, "fn appendColoredActivityText", "fn refreshActivityText", "activity log category highlighting");
    assert.match(appendColoredActivityTextBody, /normalizedActivityEntry = activityDisplayEntryText activityEntry/);
    assert.match(appendColoredActivityTextBody, /statusStart = findString normalizedActivityEntry "\["[\s\S]*statusEnd = findString normalizedActivityEntry "\]"[\s\S]*hasStatusToken = statusStart != undefined and statusEnd != undefined and statusEnd >= statusStart/);
    assert.match(appendColoredActivityTextBody, /badgeStart = if \(hasStatusToken and statusStart > 1[\s\S]*substring normalizedActivityEntry \(statusStart - 1\) 1\) == " "/);
    assert.match(appendColoredActivityTextBody, /badgeEnd = if \(hasStatusToken and statusEnd < normalizedActivityEntry\.count[\s\S]*substring normalizedActivityEntry \(statusEnd \+ 1\) 1\) == " "/);
    assert.match(appendColoredActivityTextBody, /prefixText = if \(hasStatusToken and badgeStart > 1\)[\s\S]*statusText = if \(hasStatusToken\) then \(substring normalizedActivityEntry badgeStart \(badgeEnd - badgeStart \+ 1\)\)[\s\S]*suffixText = if \(hasStatusToken and badgeEnd < normalizedActivityEntry\.count\)/);
    assert.match(appendColoredActivityTextBody, /badgeBackgroundColor = activityEntryBadgeBackgroundColor normalizedActivityEntry[\s\S]*badgeTextColor = activityEntryBadgeTextColor normalizedActivityEntry/);
    assert.match(appendColoredActivityTextBody, /SelectionBackColor = activityDialog\.rtbActivity\.BackColor[\s\S]*SelectionColor = entryColor[\s\S]*SelectionFont = activityDialog\.rtbActivity\.Font[\s\S]*AppendText prefixText[\s\S]*SelectionBackColor = badgeBackgroundColor[\s\S]*SelectionColor = badgeTextColor[\s\S]*SelectionFont = badgeFont[\s\S]*AppendText statusText[\s\S]*SelectionBackColor = activityDialog\.rtbActivity\.BackColor[\s\S]*SelectionColor = entryColor[\s\S]*SelectionFont = activityDialog\.rtbActivity\.Font[\s\S]*AppendText suffixText[\s\S]*SelectionColor = activityDialog\.rtbActivity\.ForeColor/);
    assert.match(bootstrapSource, /FromArgb 255 125 125/);
    assert.match(bootstrapSource, /FromArgb 255 195 80/);
    assert.match(bootstrapSource, /FromArgb 120 225 150/);
    assert.match(bootstrapSource, /findString normalizedEntry " \[support"[\s\S]*ControlPaint"\)\.Light MaxUltraMcpTheme\.supportColor[\s\S]*ControlPaint"\)\.Dark MaxUltraMcpTheme\.supportColor/);
    assert.match(bootstrapSource, /FromArgb 110 205 235/);
    assert.match(bootstrapSource, /FromArgb 20 90 145/);
    const badgeBackgroundColorBody = sourceSection(bootstrapSource, "fn activityEntryBadgeBackgroundColor", "fn activityEntryBadgeTextColor", "activity status badge background");
    assert.match(badgeBackgroundColorBody, /entryColor = activityEntryColor activityEntry[\s\S]*if \(themeIsDark\(\)\) do return entryColor[\s\S]*ControlPaint"\)\.Light entryColor 0\.65/);
    const badgeTextColorBody = sourceSection(bootstrapSource, "fn activityEntryBadgeTextColor", "fn activityLogIsNearBottom", "activity status badge text");
    assert.match(badgeTextColorBody, /entryColor = activityEntryColor activityEntry[\s\S]*ControlPaint"\)\.Dark entryColor 0\.55/);
    assert.match(bootstrapSource, /ScrollToCaret\(\)/);
    assert.match(bootstrapSource, /fn activityLogIsNearBottom/);
    assert.match(bootstrapSource, /fn activityLogFirstVisibleLine/);
    assert.match(bootstrapSource, /fn restoreActivityLogFirstVisibleLine/);
    assert.match(bootstrapSource, /fn scrollActivityLogToBottom/);
    assert.match(bootstrapSource, /fn handleActivityLogMouseEnter/);
    assert.match(bootstrapSource, /fn handleActivityLogScrolled/);
    assert.match(bootstrapSource, /SelectionStart = activityDialog\.rtbActivity\.TextLength/);
    assert.match(bootstrapSource, /windows\.sendMessage logWindowHandle windowsMessageVerticalScroll scrollBarBottom 0/);
    assert.match(bootstrapSource, /SelectionLength > 0\) do return false/);
    assert.match(bootstrapSource, /GetPositionFromCharIndex lastCharacterIndex/);
    assert.match(bootstrapSource, /local lastLineBottom = lastCharacterPosition\.Y \+ activityDialog\.rtbActivity\.Font\.Height/);
    assert.match(bootstrapSource, /richEditMessageGetFirstVisibleLine = 0x00CE/);
    assert.match(bootstrapSource, /richEditMessageLineScroll = 0x00B6/);
    assert.match(bootstrapSource, /if \(activityLogUpdating\) do return true/);
    assert.match(bootstrapSource, /if \(activityLogDirty\) do refreshActivityText\(\)/);
    assert.match(bootstrapSource, /if \(not activityLogDirty and currentActivityText == expectedActivityText\) do return true/);
    assert.match(bootstrapSource, /local expectedActivityCoreText = activityDisplayCoreText\(\)/);
    assert.match(bootstrapSource, /changedIncrementally/);
    assert.match(bootstrapSource, /local currentActivityCoreText = activityTextWithoutBottomPadding currentActivityText[\s\S]*Select currentActivityCoreText\.count bottomPaddingLength[\s\S]*appendColoredActivityText appendedActivityText[\s\S]*AppendText activityBottomPadding/);
    assert.match(bootstrapSource, /for activityIndex in 1 to activityEntries\.count do \([\s\S]*appendColoredActivityText activityEntries\[activityIndex\][\s\S]*if \(activityEntries\.count > 0\) do activityDialog\.rtbActivity\.AppendText activityBottomPadding[\s\S]*SelectionBackColor = activityDialog\.rtbActivity\.BackColor/);
    assert.match(bootstrapSource, /responseBody \+= ",\\"content\\":\\"" \+ jsonEscape\(activityText\(\)\)/);
    assert.doesNotMatch(bootstrapSource, /responseBody \+= ",\\"content\\":\\"" \+ jsonEscape\(activityDisplayCoreText\(\)\)/);
    assert.match(bootstrapSource, /singleLineActivityMessage = substituteString/);
    assert.match(bootstrapSource, /on rtbActivity MouseEnter[\s\S]*enableAccelerators = false/);
    assert.match(bootstrapSource, /on rtbActivity MouseLeave[\s\S]*enableAccelerators = true/);
    assert.match(bootstrapSource, /on rtbActivity VScroll[\s\S]*handleActivityLogScrolled/);
    assert.match(bootstrapSource, /local shouldAutoScroll = activityAutoScroll and activityLogIsNearBottom\(\)/);
    assert.doesNotMatch(bootstrapSource, /btnStart\.enabled = isStopped\s+refreshActivityText\(\)/);
    const activityRefreshBody = bootstrapSource.slice(bootstrapSource.indexOf("fn refreshActivityText"), bootstrapSource.indexOf("fn resizePanelControls"));
    assert.doesNotMatch(activityRefreshBody, /rtbActivity\.Update\(\)/);
    assert.match(activityRefreshBody, /restoreActivityLogFirstVisibleLine/);
    assert.match(bootstrapSource, /fn showRestoreBubble/);
    assert.match(bootstrapSource, /FormBorderStyle"\)\.None/);
    assert.match(bootstrapSource, /restoreBubbleForm\.ControlBox = false/);
    assert.match(bootstrapSource, /restoreBubbleForm\.MinimizeBox = false/);
    assert.match(bootstrapSource, /restoreBubbleForm\.MaximizeBox = false/);
    assert.match(bootstrapSource, /restoreBubbleForm\.ShowIcon = false/);
    assert.match(bootstrapSource, /ShowInTaskbar = false/);
    assert.match(bootstrapSource, /restoreBubbleForm\.Size = dotNetObject "System\.Drawing\.Size" 236 64/);
    assert.match(bootstrapSource, /restoreBubbleForm\.BackColor = MaxUltraMcpTheme\.outlineColor/);
    assert.match(bootstrapSource, /restoreBubbleSurface = dotNetObject "System\.Windows\.Forms\.Panel"/);
    assert.match(bootstrapSource, /restoreBubbleSurface\.Location = dotNetObject "System\.Drawing\.Point" 1 1/);
    assert.match(bootstrapSource, /restoreBubbleSurface\.Size = dotNetObject "System\.Drawing\.Size" 234 62/);
    assert.match(bootstrapSource, /restoreBubbleSurface\.BackColor = MaxUltraMcpTheme\.backgroundColor/);
    assert.match(bootstrapSource, /restoreBubbleSurface\.Controls\.Add restoreBubbleLabel[\s\S]*restoreBubbleSurface\.Controls\.Add restoreBubbleButton[\s\S]*restoreBubbleForm\.Controls\.Add restoreBubbleSurface/);
    assert.match(bootstrapSource, /screenClass\.FromHandle maxWindowHandle/);
    assert.match(bootstrapSource, /windows\.getMAXHWND\(\)/);
    assert.match(bootstrapSource, /workingArea\.Bottom - 64 - 12/);
    assert.match(bootstrapSource, /fn normalizeRestoreBubblePosition/);
    assert.match(bootstrapSource, /Screen"\)\.FromRectangle bubbleBounds/);
    assert.match(bootstrapSource, /local minimumVisibleDragHeight = 24[\s\S]*local maximumY = workingArea\.Bottom - minimumVisibleDragHeight/);
    assert.doesNotMatch(bootstrapSource, /local maximumY = workingArea\.Bottom - 64/);
    assert.match(bootstrapSource, /local clampedX = amax workingArea\.Left \(amin maximumX bubbleX\)/);
    assert.match(bootstrapSource, /local clampedY = amax workingArea\.Top \(amin maximumY bubbleY\)/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "restoreBubble" "x"/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "restoreBubble" "y"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "restoreBubble" "x"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "restoreBubble" "y"/);
    assert.match(bootstrapSource, /local bubblePosition = loadRestoreBubblePosition\(\)/);
    assert.match(bootstrapSource, /restoreBubbleForm\.Location = dotNetObject "System\.Drawing\.Point" bubblePosition\.x bubblePosition\.y/);
    assert.match(bootstrapSource, /restoreBubbleLabel\.Text = "Max Ultra MCP"/);
    assert.match(bootstrapSource, /restoreBubbleLabel\.AutoSize = false[\s\S]*restoreBubbleLabel\.UseCompatibleTextRendering = false[\s\S]*applyIndependentBoldFont restoreBubbleLabel/);
    assert.match(bootstrapSource, /restoreBubbleLabel\.Cursor = \(dotNetClass "System\.Windows\.Forms\.Cursors"\)\.SizeAll/);
    assert.match(bootstrapSource, /restoreBubbleButton\.Text = "Expand MCP Server"/);
    assert.match(bootstrapSource, /restoreBubbleButton\.AccessibleName = "Expand MCP Server"/);
    assert.match(bootstrapSource, /styleButton restoreBubbleButton baseColorValue: \(statusTextColor\(\)\)[\s\S]*applyIndependentBoldFont restoreBubbleButton[\s\S]*restoreBubbleButton\.ForeColor = MaxUltraMcpTheme\.textColor/);
    assert.match(bootstrapSource, /fn styleButton buttonControl[\s\S]*buttonControl\.UseCompatibleTextRendering = false/);
    assert.doesNotMatch(bootstrapSource, /restoreBubbleButton\.Dock = .*DockStyle.*Fill/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler restoreBubbleForm "FormClosing" handleRestoreBubbleFormClosing/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler restoreBubbleLabel "MouseDown" handleRestoreBubbleMouseDown/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler restoreBubbleLabel "MouseMove" handleRestoreBubbleMouseMove/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler restoreBubbleLabel "MouseUp" handleRestoreBubbleMouseUp/);
    assert.match(bootstrapSource, /labelOffsetX = labelSender\.Left as integer/);
    assert.match(bootstrapSource, /labelOffsetY = labelSender\.Top as integer/);
    assert.match(bootstrapSource, /labelOffsetX \+= restoreBubbleSurface\.Left as integer/);
    assert.match(bootstrapSource, /labelOffsetY \+= restoreBubbleSurface\.Top as integer/);
    assert.match(bootstrapSource, /restoreBubbleDragOffset = \[labelOffsetX \+ \(eventArgs\.X as integer\), labelOffsetY \+ \(eventArgs\.Y as integer\)\]/);
    assert.match(bootstrapSource, /labelSender\.Capture = true/);
    assert.match(bootstrapSource, /Cursor"\)\.Position/);
    assert.match(bootstrapSource, /persistRestoreBubblePosition \[restoreBubbleForm\.Left as integer, restoreBubbleForm\.Top as integer\]/);
    assert.match(bootstrapSource, /not restoreBubbleCloseAllowed[\s\S]*eventArgs\.Cancel = true/);
    assert.match(bootstrapSource, /removeAllEventHandlers bubbleLabelToDispose/);
    assert.match(bootstrapSource, /removeAllEventHandlers bubbleButtonToDispose/);
    assert.match(bootstrapSource, /removeAllEventHandlers bubbleFormToDispose/);
    assert.match(bootstrapSource, /formOwnsSurface = bubbleFormToDispose != undefined[\s\S]*surfaceOwnsLabel = bubbleSurfaceToDispose != undefined[\s\S]*surfaceOwnsButton = bubbleSurfaceToDispose != undefined/);
    assert.match(bootstrapSource, /if \(not surfaceOwnsLabel and bubbleLabelToDispose != undefined\) do bubbleLabelToDispose\.Dispose\(\)[\s\S]*if \(not surfaceOwnsButton and bubbleButtonToDispose != undefined\) do bubbleButtonToDispose\.Dispose\(\)[\s\S]*if \(not formOwnsSurface and bubbleSurfaceToDispose != undefined\) do bubbleSurfaceToDispose\.Dispose\(\)/);
    const disposeRestoreBubbleBody = sourceSection(bootstrapSource, "fn disposeRestoreBubble", "fn handleRestoreBubbleFormClosing", "restore mini-panel cleanup");
    assert.ok(disposeRestoreBubbleBody.indexOf("restoreBubbleForm = undefined") < disposeRestoreBubbleBody.indexOf("removeAllEventHandlers bubbleFormToDispose"), "Restore mini-panel references must clear before disposing handlers and controls");
    const disposeToolTipBody = sourceSection(bootstrapSource, "fn disposePanelToolTip", "fn performPanelFormClosing", "panel tooltip cleanup");
    assert.match(disposeToolTipBody, /local tooltipToDispose = panelToolTip[\s\S]*panelToolTip = undefined[\s\S]*tooltipToDispose\.Dispose\(\)/);
    assert.doesNotMatch(bootstrapSource, /boldUiFont|ensureBoldUiFont|disposeBoldUiFont/);
    const releasePanelIconImagesBody = sourceSection(bootstrapSource, "fn releasePanelIconImages", "fn ensurePanelIconImages", "safe panel icon release");
    assert.match(releasePanelIconImagesBody, /btnRefreshAgents\.Image = undefined[\s\S]*btnHide\.Image = undefined[\s\S]*btnReconnect\.Image = undefined[\s\S]*btnStop\.Image = undefined[\s\S]*btnSettings\.Image = undefined[\s\S]*supportDialog\.btnDonate\.Image = undefined[\s\S]*settingsDialog\.btnAboutDonate\.Image = undefined[\s\S]*refreshIconImage = undefined[\s\S]*donateIconImage = undefined[\s\S]*hideIconImage = undefined[\s\S]*settingsIconImage = undefined[\s\S]*stopIconImage = undefined[\s\S]*reconnectIconImage = undefined/);
    assert.doesNotMatch(releasePanelIconImagesBody, /\.Dispose\(\)/);
    assert.match(formClosingBody, /disposeRestoreBubble\(\)[\s\S]*releasePanelIconImages\(\)[\s\S]*disposePanelToolTip\(\)/);
    assert.match(panelResizeBody, /if \(isDisposed or not panelIsOpen\(\) or panelLayoutInProgress\) do return false/);
    assert.match(panelResizeBody, /panelFloater\.placementName == #minimized[\s\S]*return true/);
    assert.match(bootstrapSource, /fn refreshRestoreBubbleStatus = \([\s\S]*local bubbleStatusColor = statusTextColor\(\)[\s\S]*restoreBubbleButton\.BackColor = bubbleStatusColor[\s\S]*restoreBubbleButton\.ForeColor = MaxUltraMcpTheme\.textColor[\s\S]*MouseOverBackColor = controlPaintClass\.Light bubbleStatusColor[\s\S]*MouseDownBackColor = controlPaintClass\.Dark bubbleStatusColor[\s\S]*restoreBubbleButton\.Refresh\(\)/);
    assert.match(bootstrapSource, /fn refreshUserInterface = \([\s\S]*local miniPanelRefreshed = refreshRestoreBubbleStatus\(\)[\s\S]*if \(not panelIsOpen\(\)\) do return miniPanelRefreshed/);
    const restorePanelBody = sourceSection(bootstrapSource, "fn restoreHiddenPanel", "fn handleRestoreBubbleClick", "hidden floater restoration");
    const restoreClickBody = sourceSection(bootstrapSource, "fn handleRestoreBubbleClick", "fn showRestoreBubble", "restore mini-panel click");
    const restoreMiniPanelBody = sourceSection(bootstrapSource, "fn showRestoreBubble", "fn refreshRestoreBubbleStatus", "restore mini-panel creation");
    assert.match(restoreMiniPanelBody, /if \(restoreBubbleForm != undefined\)[\s\S]*if \(not restoreBubbleForm\.IsDisposed\)[\s\S]*return true[\s\S]*restoreBubbleForm = dotNetObject "System\.Windows\.Forms\.Form"/);
    assert.match(restorePanelBody, /local wasPersistedHidden = loadPanelHiddenState\(\)/);
    assert.match(restorePanelBody, /restoreGeometry = if \(hiddenPanelPosition == undefined and hiddenPanelSize == undefined\) then loadPanelGeometry\(\) else normalizePanelGeometry hiddenPanelPosition hiddenPanelSize/);
    assert.match(restorePanelBody, /restorePosition = restoreGeometry\[1\]/);
    assert.match(restorePanelBody, /restoreSize = restoreGeometry\[2\]/);
    assert.match(restorePanelBody, /if \(not panelIsOpen\(\)\) do \([\s\S]*this\.createPanelFloater restorePosition restoreSize/);
    assert.match(restorePanelBody, /panelFloater\.visible = true[\s\S]*if \(not panelIsVisible\(\)\) do/);
    assert.match(restorePanelBody, /if \(wasPersistedHidden\) do persistPanelHiddenState true[\s\S]*return false/);
    assert.ok(restorePanelBody.indexOf("panelFloater.visible = true") < restorePanelBody.indexOf("persistPanelHiddenState false"), "Expand must make the existing floater visible before persisting expanded state");
    assert.ok(restorePanelBody.indexOf("persistPanelHiddenState false") < restorePanelBody.indexOf("disposeRestoreBubble()"), "The mini-panel must remain until the floater is visibly restored and state is saved");
    assert.match(restorePanelBody, /panelFloater\.placementName = #normal/);
    assert.doesNotMatch(restorePanelBody, /destroyDialog|closeRolloutFloater|panelForm\.Show/);
    assert.match(restoreClickBody, /restoreHiddenPanel\(\)/);
    assert.doesNotMatch(restoreClickBody, /disposeRestoreBubble\(\)/);
    const showPanelBody = sourceSection(bootstrapSource, "fn showPanel", "fn hidePanel", "show main panel");
    assert.match(showPanelBody, /restoreHiddenPanel\(\)/);
    const hidePanelBody = sourceSection(bootstrapSource, "fn hidePanel", "fn restoreSavedPanelVisibility", "hide main floater");
    assert.match(hidePanelBody, /if \(panelIsOpen\(\)\) do/);
    assert.match(hidePanelBody, /local hideGeometry = capturePanelGeometry panelForm/);
    assert.match(hidePanelBody, /hiddenPanelPosition = hideGeometry\[1\]/);
    assert.match(hidePanelBody, /hiddenPanelSize = hideGeometry\[2\]/);
    assert.match(hidePanelBody, /persistPanelGeometry hiddenPanelPosition hiddenPanelSize/);
    assert.match(hidePanelBody, /if \(not \(persistPanelHiddenState true\)\) do/);
    assert.match(hidePanelBody, /showRestoreBubble\(\)/);
    assert.match(hidePanelBody, /panelFloater\.visible = false[\s\S]*if \(panelIsVisible\(\)\) do throw/);
    assert.ok(hidePanelBody.indexOf("showRestoreBubble()") < hidePanelBody.indexOf("panelFloater.visible = false"), "The restore mini-panel must exist before the floater is hidden");
    assert.ok(hidePanelBody.indexOf("persistPanelHiddenState true") < hidePanelBody.indexOf("panelFloater.visible = false"), "Hide must be persisted before the floater is hidden");
    assert.match(hidePanelBody, /if \(not \(showRestoreBubble\(\)\)\) do \([\s\S]*persistPanelHiddenState false/);
    assert.match(hidePanelBody, /catch \([\s\S]*persistPanelHiddenState false[\s\S]*disposeRestoreBubble\(\)[\s\S]*panelFloater\.visible = true/);
    const savedVisibilityBody = sourceSection(bootstrapSource, "fn restoreSavedPanelVisibility", "fn closeForLifecycle", "saved panel visibility");
    assert.match(savedVisibilityBody, /if \(not \(loadPanelHiddenState\(\)\)\) do return showPanel\(\)/);
    assert.match(savedVisibilityBody, /local savedPanelGeometry = loadPanelGeometry\(\)/);
    assert.match(savedVisibilityBody, /if \(showRestoreBubble\(\)\) do return true/);
    assert.match(savedVisibilityBody, /persistPanelHiddenState false[\s\S]*return showPanel\(\)/);
    assert.match(bootstrapSource, /if \(not \(restoreSavedPanelVisibility\(\)\)\) do addActivity "error" "Could not restore the saved panel visibility"/);
    const startBridgeBody = sourceSection(bootstrapSource, "fn startBridge", "bridgeClient = MaxUltraMcpBridgeClient", "bridge startup");
    assert.doesNotMatch(startBridgeBody, /^\s*showPanel\(\)/m);
    assert.match(formClosingBody, /persistPanelGeometry finalGeometry\[1\] finalGeometry\[2\][\s\S]*persistPanelHiddenState false/);
    assert.doesNotMatch(hidePanelBody, /destroyDialog|closeRolloutFloater|detachPanelFormEvents|stopPollTimer|CancelAsync|shutdown_owned|shutdown_when_idle|startTransport|stopBridge|closeForLifecycle|handleViewportScreenshot|disposeForReload/);
    const closeForLifecycleBody = sourceSection(bootstrapSource, "fn closeForLifecycle", "fn minimizePanel", "explicit panel shutdown");
    assert.match(closeForLifecycleBody, /stopPollTimer\(\)[\s\S]*if \(panelIsOpen\(\)\) then \([\s\S]*closeRolloutFloater panelFloater/);
    assert.doesNotMatch(closeForLifecycleBody, /destroyDialog statusDialog/);
    assert.doesNotMatch(closeForLifecycleBody, /panelForm\.Close\(\)/);
    assert.doesNotMatch(restorePanelBody + restoreClickBody + restoreMiniPanelBody, /CancelAsync|shutdown_owned|shutdown_when_idle|startTransport|stopBridge|closeForLifecycle/);
    const minimizePanelBody = sourceSection(bootstrapSource, "fn minimizePanel", "fn restorePanel", "floater minimization");
    const restorePlacementBody = sourceSection(bootstrapSource, "fn restorePanel", "fn createSynchronizedQueue", "floater placement restoration");
    assert.match(minimizePanelBody, /showPanel\(\)[\s\S]*panelFloater\.placementName = #minimized/);
    assert.match(restorePlacementBody, /showPanel\(\)[\s\S]*panelFloater\.placementName = #normal[\s\S]*refreshUserInterface\(\)/);
    const workerLaunchServerBody = bootstrapSource.slice(bootstrapSource.indexOf("fn workerLaunchServer"), bootstrapSource.indexOf("fn transportDoWork"));
    assert.match(workerLaunchServerBody, /if \(workerServerConsoleVisible\) then \([\s\S]*UseShellExecute = true[\s\S]*CreateNoWindow = false[\s\S]*ProcessWindowStyle"\)\.Normal/);
    assert.match(workerLaunchServerBody, /else \([\s\S]*UseShellExecute = false[\s\S]*CreateNoWindow = true[\s\S]*ProcessWindowStyle"\)\.Hidden/);
    assert.doesNotMatch(workerLaunchServerBody, /ProcessWindowStyle"\)\.Minimized/);
    assert.match(bootstrapSource, /if \(workerServerConsoleVisible\) then "a visible console" else "a hidden console"/);
    const viewportScreenshotBody = bootstrapSource.slice(bootstrapSource.indexOf("fn handleViewportScreenshot"), bootstrapSource.indexOf("fn handleExecuteRequest"));
    assert.match(viewportScreenshotBody, /max tool maximize/);
    assert.match(viewportScreenshotBody, /originalViewportArea/);
    assert.match(viewportScreenshotBody, /if \(toggledViewportArea < originalViewportArea\)[\s\S]*max tool maximize/);
    assert.ok(viewportScreenshotBody.indexOf("max tool maximize") < viewportScreenshotBody.indexOf("viewportBitmap = gw.getViewportDib()"), "The active viewport must be maximized before capture");
    assert.match(viewportScreenshotBody, /viewportBitmap = gw\.getViewportDib\(\)/);
    assert.match(viewportScreenshotBody, /ShowSelectionBracketsEnabled = false/);
    assert.match(viewportScreenshotBody, /SelectionHighlightEnabled = false/);
    assert.match(viewportScreenshotBody, /PreviewOutlineEnabled = false/);
    assert.match(viewportScreenshotBody, /AntialiasingQuality = #8X/);
    assert.match(viewportScreenshotBody, /viewport\.setGridVisibility activeViewportIndex false/);
    assert.match(viewportScreenshotBody, /restoreViewportReviewSettings reviewState/);
    assert.ok(viewportScreenshotBody.indexOf("ShowSelectionBracketsEnabled = false") < viewportScreenshotBody.indexOf("viewportBitmap = gw.getViewportDib()"), "Viewport clutter must be hidden before capture");
    assert.match(viewportScreenshotBody, /viewportBitmap\.filename = screenshotPath[\s\S]*save viewportBitmap/);
    assert.match(viewportScreenshotBody, /if \(not \(doesFileExist screenshotPath\)\) do throw "3ds Max did not write the viewport PNG"/);
    assert.doesNotMatch(viewportScreenshotBody, /save viewportBitmap screenshotPath/);
    const executeRequestBody = bootstrapSource.slice(bootstrapSource.indexOf("fn handleExecuteRequest"), bootstrapSource.indexOf("fn uiHandleText"));
    assert.match(executeRequestBody, /maximumResultCharacters = 500000/);
    assert.match(executeRequestBody, /resultCharacterCount/);
    assert.match(executeRequestBody, /resultTruncated/);
    assert.doesNotMatch(executeRequestBody, /> 16000/);
    assert.match(getMcpTools("core").find((toolDefinition) => toolDefinition.name === "max_run_script").description, /500,000 characters/);
    assert.match(bootstrapSource, /serverShutdownHelperPath/);
    assert.match(bootstrapSource, /stop-owned-server\.bat/);
    assert.match(bootstrapSource, /fn launchDetachedShutdownHelper/);
    assert.match(bootstrapSource, /CreateNoWindow = true/);
    assert.match(bootstrapSource, /-OwnershipFile/);
    assert.match(bootstrapSource, /--owner-file/);
    assert.match(bootstrapSource, /--owner-token/);
    assert.match(bootstrapSource, /--owner-max-pid/);
    assert.match(bootstrapSource, /startTransport allowServerLaunch: true/);
    assert.match(bootstrapSource, /startTransport allowServerLaunch: false/);
    assert.match(bootstrapSource, /workerControlRequest workerHost workerPort "shutdown_owned"[\s\S]*requestPayload: probeReply\.responsePayload[\s\S]*controlToken: workerControlToken/);
    assert.match(bootstrapSource, /workerWaitForEndpointClose/);
    const endpointCloseBody = bootstrapSource.slice(bootstrapSource.indexOf("fn workerWaitForEndpointClose"), bootstrapSource.indexOf("fn workerHostIsLoopback"));
    assert.doesNotMatch(endpointCloseBody, /controlState == #occupied\) do return/);
    assert.match(bootstrapSource, /restartExistingServer: restartServerForReload/);
    assert.match(bootstrapSource, /MAX_ULTRA_MCP_TOKEN_FILE/);
    assert.match(bootstrapSource, /LOCALAPPDATA/);
    assert.match(bootstrapSource, /3DGROUND\\MaxUltraMCP\\runtime\\state\\control-token/);
    assert.match(bootstrapSource, /System\.IO\.File"\)\.Copy legacyTokenFilePath controlTokenFilePath true/);
    assert.doesNotMatch(bootstrapSource, /workerRequestOwnedShutdown|workerWaitForOwnedServerExit|ownedServerProcess\.Kill/);
    assert.match(bootstrapSource, /workerArguments\.Item\[12\]/);
    assert.match(bootstrapSource, /workerArguments\.Item\[13\]/);
    assert.match(bootstrapSource, /if \(workerSender\.CancellationPending\) do throw "Server startup cancelled"[\s\S]*workerLaunchServer/);
    assert.doesNotMatch(bootstrapSource, /mod tickCount 20[^\n]*startTransport/);
    const timerBody = sourceSection(bootstrapSource, "fn handleTimerTick", "fn startBridge", "main UI timer");
    assert.match(timerBody, /isDisposed or pollTimer == undefined or timerSender != pollTimer/);
    assert.match(timerBody, /runPendingAutomaticOnboardingCheck\(\)[\s\S]*pollIntegrationOperation\(\)[\s\S]*pollUpdateOperation\(\)[\s\S]*pollSupportReminder\(\)/);
    assert.match(timerBody, /catch \([\s\S]*stopPollTimer\(\)[\s\S]*CancelAsync\(\)/);
    assert.match(timerBody, /pendingConnectOnly/);
    assert.doesNotMatch(timerBody, /workerLaunchServer/);
    const disposeForReloadBody = sourceSection(bootstrapSource, "fn disposeForReload", "fn registerMaxShutdownCallback", "reload cleanup");
    assert.match(disposeForReloadBody, /if \(disposeInProgress\) do return true[\s\S]*disposeInProgress = true[\s\S]*stopPollTimer\(\)[\s\S]*disposeInProgress = false[\s\S]*return true/);
    assert.match(disposeForReloadBody, /isDisposed = true[\s\S]*isStopped = true[\s\S]*pendingConnectOnly = false[\s\S]*stopPollTimer\(\)/);
    assert.match(disposeForReloadBody, /removeEventHandler transportWorker "DoWork" transportDoWork/);
    assert.match(disposeForReloadBody, /disposeRestoreBubble\(\)[\s\S]*releasePanelIconImages\(\)[\s\S]*detachPanelFormEvents panelForm[\s\S]*closeRolloutFloater panelFloater[\s\S]*detachPanelFormEvents panelForm[\s\S]*disposePanelToolTip\(\)[\s\S]*panelFloater = undefined[\s\S]*panelForm = undefined/);
    assert.doesNotMatch(disposeForReloadBody, /launchDetachedShutdownHelper/);
    assert.ok(startBridgeBody.indexOf("startTransport allowServerLaunch: true") < startBridgeBody.indexOf('dotNet.addEventHandler pollTimer'), "Replacement timer must be created only after startup state and transport are ready");
    assert.match(startBridgeBody, /supportReminderCount = 0[\s\S]*supportReminderDueAt = undefined/);
    assert.match(startBridgeBody, /pollTimer\.Interval = 250/);
    assert.ok(startBridgeBody.indexOf("pollTimer.Start()") < startBridgeBody.indexOf("beginAutomaticOnboardingCheck()"), "The two-second AI check must be scheduled only after the shared UI timer starts");
    assert.match(startBridgeBody, /TIMER START ERROR[\s\S]*disposeForReload\(\)[\s\S]*MaxUltraMcpActiveClient = undefined/);
    assert.equal((bootstrapSource.match(/dotNet\.addEventHandler pollTimer "Tick" handleTimerTick/g) || []).length, 1);
    assert.match(formClosingBody, /launchDetachedShutdownHelper\(\)[\s\S]*CancelAsync\(\)/);
    assert.doesNotMatch(formClosingBody, /workerControlRequest|RunWorkerAsync|shutdown_owned/);
    assert.match(shutdownHelperBatSource, /stop-owned-server\.ps1/);
    assert.match(shutdownHelperSource, /Get-Process -Name 3dsmax/);
    assert.match(shutdownHelperSource, /\$liveMaxCount -ne 1/);
    assert.match(shutdownHelperSource, /Get-CimInstance Win32_Process/);
    assert.match(shutdownHelperSource, /Test-CreationTime/);
    assert.match(shutdownHelperSource, /Test-CommandLineContains/);
    assert.match(shutdownHelperSource, /Stop-Process -Id \$ownedNodePid -Force/);
    assert.match(shutdownHelperSource, /Stop-Process -Id \$ownedLauncherPid -Force/);
    assert.doesNotMatch(shutdownHelperSource, /TcpClient|CONTROL|shutdown_owned|Invoke-WebRequest/);
    assert.doesNotMatch(bootstrapSource, /MaxProcessCountOverride/);
    assert.match(serverSource, /MAX_ULTRA_MCP_OWNER_FILE/);
    assert.match(serverSource, /processStartedAtUtc/);
    assert.match(serverSource, /launcherStartedAtUtc/);
    assert.match(serverSource, /fs\.renameSync\(temporaryFile, ownerFile\)/);
    assert.match(bootstrapSource, /hasConnectedThisSession = true/);
    assert.match(bootstrapSource, /if \(hasConnectedThisSession\) then/);
    assert.match(bootstrapSource, /else if \(connectionError == ""\) do/);
    assert.match(bootstrapSource, /Initial server connection ended before this Max registered/);
    assert.match(bootstrapSource, /Server connection ended\. Run 01_START_MAX_ULTRA_MCP_FIRST\.ms to start it again\./);
    assert.doesNotMatch(bootstrapSource, /Connect-only retry requested/);
    assert.match(bootstrapSource, /Reconnect requested; a stopped server will not be launched/);
    assert.doesNotMatch(bootstrapSource, /restartServerOnNextConnect/);
    assert.match(bridgeControlClientSource, /onDisconnect/);
    assert.match(bridgeControlClientSource, /if \(!this\.closing && this\.onDisconnect\) this\.onDisconnect\(\)/);
    assert.match(stdioHostSource, /new StdioHost\(\{ onBridgeDisconnect: shutdown \}\)/);
    assert.match(stdioHostSource, /input\.on\("close", shutdown\)/);
    assert.match(bootstrapSource, /#preSystemShutdown/);
    assert.match(bootstrapSource, /workerFindFreeFallbackPort/);
    assert.match(bootstrapSource, /#legacyCandidate/);
    assert.match(bootstrapSource, /"port_changed"/);
    assert.equal((bootstrapSource.match(/fn refreshUserInterface = \(/g) || []).length, 1);
    assert.match(bootstrapSource, /UIAccessor\.PressButton/);
    assert.match(bootstrapSource, /uiHandleBelongsToMax/);

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
