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
const { MockMaxClient } = require("./helpers/mock-max-client");
const { BridgeControlClient } = require("../core/bridge-control-client");
const { getMcpTools } = require("../core/tool-catalog");
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

    const boxResponse = await createTestBox({ client: controlClient, output: quietOutput });
    assert.equal(boxResponse.instanceId, "test-max-2027");
    const exampleScript = max2027.executeRequests.at(-1);
    assert.match(exampleScript, new RegExp(`box name:"${TEST_BOX_NAME}"`));
    assert.match(exampleScript, /pos:\[0,0,0\]/);
    assert.doesNotMatch(exampleScript, /save(MaxFile|Nodes|AsVersion)/i);

    const titleResponse = await createSplineTextExample({ client: controlClient, output: quietOutput });
    assert.equal(titleResponse.instance.instanceId, "test-max-2027");
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
    const serverSource = fs.readFileSync(path.join(PROJECT_ROOT, "core", "server.js"), "utf8");
    const shutdownHelperSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "stop-owned-server.ps1"), "utf8");
    const shutdownHelperBatSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "stop-owned-server.bat"), "utf8");
    const agentIntegrationSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "agent-integration.ps1"), "utf8");
    const localAuthSource = fs.readFileSync(path.join(PROJECT_ROOT, "core", "local-auth.js"), "utf8");
    const maxPkgFilesSource = fs.readFileSync(path.join(PROJECT_ROOT, "maxpkg-files.txt"), "utf8");
    const maxPkgPrepareSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "prepare-maxpkg.ps1"), "utf8");
    const maxPkgSyncSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "sync-maxpkg-tooling.ps1"), "utf8");
    const maxPkgUninstallSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "maxpkg-uninstall.ps1"), "utf8");
    const maxPkgUninstallHookSource = fs.readFileSync(path.join(PROJECT_ROOT, "scripts", "maxpkg-uninstall.ms"), "utf8");
    const maxPkgIconSource = fs.readFileSync(path.join(PROJECT_ROOT, "assets", "max-ultra-mcp.svg"), "utf8");
    const skillRoot = path.join(PROJECT_ROOT, "skills", "max-ultra-mcp");
    const skillSource = fs.readFileSync(path.join(skillRoot, "SKILL.md"), "utf8");
    const skillReferenceRoot = path.join(skillRoot, "references");
    const skillReferenceNames = fs.readdirSync(skillReferenceRoot).filter((entryName) => entryName.endsWith(".md")).sort();
    const linkedSkillReferences = [...skillSource.matchAll(/\]\(references\/([a-z0-9-]+\.md)\)/g)].map((entry) => entry[1]).sort();
    assert.deepEqual(linkedSkillReferences, skillReferenceNames, "Every skill reference must be linked exactly once from SKILL.md");
    assert.match(skillSource, /^---\r?\nname: max-ultra-mcp\r?\ndescription: .+\r?\n---\r?\n/);
    const skillDocumentation = [skillSource, ...skillReferenceNames.map((entryName) => fs.readFileSync(path.join(skillReferenceRoot, entryName), "utf8"))].join("\n");
    const implementedToolNames = new Set(getMcpTools("full").map((tool) => tool.name));
    const documentedToolNames = new Set([...skillDocumentation.matchAll(/\bmax_[a-z0-9_]+\b/g)].map((entry) => entry[0]));
    for (const documentedToolName of documentedToolNames) {
      assert.equal(implementedToolNames.has(documentedToolName), true, `Skill references unavailable tool ${documentedToolName}`);
    }
    assertBalancedMaxScript(bootstrapSource);
    assertBalancedMaxScript(maxPkgUninstallHookSource);
    const uiRolloutSource = fs.readFileSync(path.join(PROJECT_ROOT, "tests", "fixtures", "ui-automation-rollout", "test-ui-rollout.ms"), "utf8");
    assertBalancedMaxScript(uiRolloutSource);
    assert.match(uiRolloutSource, /Max Ultra MCP UI Automation Test/);
    assert.match(uiRolloutSource, /button applyButton "Apply with MCP"/);
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
    assert.match(bootstrapSource, /lblStatus .* pos: \[12,10\] width: 480/);
    assert.match(bootstrapSource, /lblContext .* pos: \[12,34\]/);
    assert.match(bootstrapSource, /button btnAgents "AI setup" pos: \[516,8\] width: 72 height: 22/);
    assert.match(bootstrapSource, /on btnAgents pressed do if \(bridgeClient != undefined\) do bridgeClient\.showOnboardingDialog\(\)/);
    assert.match(bootstrapSource, /button btnHide "Hide panel" pos: \[596,8\] width: 72 height: 22/);
    assert.match(bootstrapSource, /button btnSettings "Settings" pos: \[548,456\] width: 120 height: 30/);
    assert.match(bootstrapSource, /on btnSettings pressed do if \(bridgeClient != undefined\) do bridgeClient\.showSettingsDialog\(\)/);
    assert.match(bootstrapSource, /rtbActivity .* pos: \[4,62\] width: 672 height: 386/);
    assert.doesNotMatch(bootstrapSource, /pnlLogOutline/);
    assert.match(bootstrapSource, /#style_resizing/);
    assert.match(bootstrapSource, /on MaxUltraMcpStatusDialog resized panelSize/);
    assert.match(bootstrapSource, /on MaxUltraMcpStatusDialog close do \([\s\S]*enableAccelerators = true[\s\S]*handlePanelRolloutClosed/);
    assert.match(bootstrapSource, /rtbActivity\.width = panelWidth - 8/);
    assert.match(bootstrapSource, /rtbActivity\.height = logHeight/);
    assert.match(bootstrapSource, /btnSettings\.pos = \[panelWidth - 132, buttonY\]/);
    assert.match(bootstrapSource, /btnAgents\.pos = \[panelWidth - 164, 8\]/);
    assert.match(bootstrapSource, /btnHide\.pos = \[panelWidth - 84, 8\]/);
    assert.match(bootstrapSource, /lblStatus\.width = panelWidth - 188/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpSettingsDialog "Max Ultra MCP Settings"/);
    assert.match(bootstrapSource, /groupBox grpAutostart "Autostart" pos: \[12,10\] width: 356 height: 58/);
    assert.match(bootstrapSource, /groupBox grpAbout "About" pos: \[12,216\] width: 356 height: 72/);
    assert.match(bootstrapSource, /label lblAboutVersion "Version: 1\.0\.0"/);
    assert.match(bootstrapSource, /label lblAboutAuthor "Author: Lukianenko Vasyl"/);
    assert.match(bootstrapSource, /hyperLink lnkAboutWebsite "https:\/\/3dground\.net"[\s\S]*address: "https:\/\/3dground\.net"/);
    assert.match(bootstrapSource, /checkbox chkAutostart "Autostart with 3ds Max"/);
    assert.match(bootstrapSource, /on chkAutostart changed isChecked do if \(bridgeClient != undefined\) do bridgeClient\.handleAutostartSettingChanged isChecked/);
    assert.match(bootstrapSource, /groupBox grpServerConsole "Server console" pos: \[12,78\] width: 356 height: 58/);
    assert.match(bootstrapSource, /checkbox chkShowServerConsole "Show server console when starting"/);
    assert.match(bootstrapSource, /on chkShowServerConsole changed isChecked do if \(bridgeClient != undefined\) do bridgeClient\.handleServerConsoleVisibilityChanged isChecked/);
    assert.doesNotMatch(bootstrapSource, /btnSave|on btnSave pressed|btnClose|on btnClose pressed/);
    assert.match(bootstrapSource, /createDialog settingsDialog width: 380 height: 300/);
    assert.match(bootstrapSource, /button btnAgentSetup "Open AI client setup\.\.\."/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpOnboardingTabsDialog ""/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpOnboardingSetupDialog ""/);
    assert.match(bootstrapSource, /rollout MaxUltraMcpOnboardingTestDialog ""/);
    assert.match(bootstrapSource, /dotNetControl dncPages "System\.Windows\.Forms\.TabControl"/);
    assert.match(bootstrapSource, /checkbox chkOpenAI "ChatGPT Desktop \/ Codex"/);
    assert.match(bootstrapSource, /checkbox chkClaudeCode "Claude Code"/);
    assert.match(bootstrapSource, /button btnCopyTestPrompt "Copy test prompt"/);
    assert.match(bootstrapSource, /dotNetControl txtTestPrompt "System\.Windows\.Forms\.TextBox"/);
    assert.match(bootstrapSource, /txtTestPrompt\.Text = onboardingTestPromptText\(\)/);
    assert.match(bootstrapSource, /newRolloutFloater "Max Ultra MCP - AI Client Setup"/);
    assert.match(bootstrapSource, /addRollout onboardingTabsDialog onboardingFloater rolledUp: false border: false/);
    assert.match(bootstrapSource, /addRollout onboardingTestDialog onboardingFloater rolledUp: false border: false/);
    assert.match(bootstrapSource, /addRollout onboardingSetupDialog onboardingFloater rolledUp: false border: false/);
    assert.match(bootstrapSource, /removeRollout onboardingSetupDialog onboardingFloater/);
    assert.doesNotMatch(bootstrapSource, /btnSetupPage|btnTestPage|txtTestPrompt\.Visible|txtTestPrompt\.BringToFront/);
    assert.match(bootstrapSource, /themeDrawingColor #rollupTitleFace 81 81 81/);
    assert.match(bootstrapSource, /lblOpenAIStatus\.BackColor = rolloutBackground/);
    assert.match(bootstrapSource, /clipboardFeedbackButton\.text = "Copied"/);
    assert.match(bootstrapSource, /clipboardFeedbackTimer\.Interval = 1600/);
    assert.match(bootstrapSource, /fn onboardingTestPromptText/);
    assert.match(bootstrapSource, /Call max_health and max_scene_summary/);
    assert.match(bootstrapSource, /Do not run arbitrary MaxScript, change the scene, start a render, or save any file/);
    assert.match(bootstrapSource, /restart or reconnect this AI client so it reloads the MCP host/);
    assert.match(bootstrapSource, /button btnInstallAgents "Install selected"/);
    assert.match(bootstrapSource, /button btnCopyManual "Copy manual setup"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "onboarding" "dismissed"/);
    assert.match(bootstrapSource, /fn beginAutomaticOnboardingCheck/);
    assert.match(bootstrapSource, /beginAutomaticOnboardingCheck\(\)/);
    assert.match(bootstrapSource, /pollIntegrationOperation\(\)/);
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
    assert.match(localAuthSource, /path\.resolve\(__dirname, "\.\.", "runtime", "state", "control-token"\)/);
    assert.match(maxPkgFilesSource, /runtime\/win-x64\/node\.exe/);
    assert.match(maxPkgFilesSource, /skills\/max-ultra-mcp\/SKILL\.md/);
    for (const skillReferenceName of skillReferenceNames) assert.ok(maxPkgFilesSource.includes(`skills/max-ultra-mcp/references/${skillReferenceName}`));
    assert.doesNotMatch(maxPkgFilesSource, /smoke-test|mock-max-client|runtime\/state/);
    assert.match(maxPkgPrepareSource, /packageGuid = 'c6977570-25a6-41b0-b9bb-b3be8101123c'/);
    assert.match(maxPkgPrepareSource, /entry=01_START_MAX_ULTRA_MCP_FIRST\.ms/);
    assert.match(maxPkgPrepareSource, /compileEntry=false/);
    assert.match(maxPkgPrepareSource, /customUninstallScript=/);
    assert.match(maxPkgSyncSource, /93ceb0e018b44ca53546cf2c274b196160495699/);
    assert.match(maxPkgSyncSource, /Get-FileHash -LiteralPath \$temporaryPath -Algorithm SHA256/);
    assert.match(maxPkgUninstallSource, /function Get-PackageOwnedNodeProcesses/);
    assert.match(maxPkgUninstallSource, /function Stop-PackageOwnedNodeProcess/);
    assert.match(maxPkgUninstallSource, /Close ChatGPT Desktop, Codex, and Claude Code/);
    assert.match(maxPkgUninstallSource, /\[Console\]::Error\.WriteLine\(\$_\.Exception\.Message\)/);
    assert.match(maxPkgUninstallSource, /\[Regex\]::IsMatch\(\[string\]\$currentProcess\.CommandLine, \$escapedServerPath/);
    assert.match(maxPkgUninstallHookSource, /WaitForExit 30000/);
    assert.match(maxPkgUninstallHookSource, /RedirectStandardError = true/);
    assert.match(maxPkgUninstallHookSource, /cleanup failed: /);
    assert.match(maxPkgUninstallHookSource, /maxpkg-uninstall\.ps1/);
    assert.doesNotMatch(maxPkgIconSource, /<rect\b/);
    assert.match(maxPkgIconSource, /<circle cx="8" cy="8"/);
    assert.match(maxPkgIconSource, /<circle cx="56" cy="8"/);
    assert.ok(maxPkgIconSource.lastIndexOf('fill="#55d88a"') > maxPkgIconSource.lastIndexOf('stroke="#f5b942"'), "The M mark must render above the connection graphics");
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
    assert.match(bootstrapSource, /3DGROUND - Max Ultra MCP \| First Step/);
    assert.doesNotMatch(bootstrapSource, /3D\sGround/);
    assert.doesNotMatch(bootstrapSource, /on MaxUltraMcpStatusDialog moved panelPosition/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler panelForm "FormClosing" handlePanelFormClosing/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler panelForm "LocationChanged" handlePanelGeometryChanged/);
    assert.match(bootstrapSource, /dotNet\.addEventHandler panelForm "ResizeEnd" handlePanelGeometryChanged/);
    assert.match(bootstrapSource, /formSender\.WindowState != normalWindowState/);
    assert.match(bootstrapSource, /local restoreBounds = formSender\.RestoreBounds/);
    assert.match(bootstrapSource, /local finalGeometry = capturePanelGeometry formSender/);
    assert.match(bootstrapSource, /persistPanelGeometry finalGeometry\[1\] finalGeometry\[2\]/);
    const stopTimerBody = bootstrapSource.slice(bootstrapSource.indexOf("fn stopPollTimer"), bootstrapSource.indexOf("fn performPanelFormClosing"));
    const formClosingBody = bootstrapSource.slice(bootstrapSource.indexOf("fn performPanelFormClosing"), bootstrapSource.indexOf("fn attachPanelFormClosing"));
    assert.match(stopTimerBody, /pollTimer = undefined[\s\S]*timerToDispose\.Stop\(\)[\s\S]*removeEventHandler timerToDispose "Tick" handleTimerTick[\s\S]*timerToDispose\.Dispose\(\)/);
    assert.ok(formClosingBody.indexOf("stopPollTimer()") < formClosingBody.indexOf("persistPanelGeometry"), "Timer must stop before panel cleanup touches external controls");
    assert.ok(formClosingBody.indexOf("persistPanelGeometry") < formClosingBody.indexOf("CancelAsync"), "Final panel geometry must be saved before transport cleanup");
    assert.match(formClosingBody, /detachPanelFormEvents formSender/);
    assert.match(formClosingBody, /fn handlePanelRolloutClosed/);
    assert.match(formClosingBody, /if \(suppressPanelShutdown or isDisposed or panelCloseInProgress\) do return true/);
    assert.match(formClosingBody, /handlePanelFormClosing closedPanelForm undefined/);
    assert.match(bootstrapSource, /removeEventHandler formSender "LocationChanged" handlePanelGeometryChanged/);
    assert.match(bootstrapSource, /removeEventHandler formSender "ResizeEnd" handlePanelGeometryChanged/);
    assert.match(bootstrapSource, /fn normalizePanelGeometry/);
    assert.match(bootstrapSource, /System\.Windows\.Forms\.Screen/);
    assert.match(bootstrapSource, /Screen"\)\.FromRectangle candidateBounds/);
    assert.match(bootstrapSource, /local minimumWidth = amin 540 maximumWidth/);
    assert.match(bootstrapSource, /local minimumHeight = amin 420 maximumHeight/);
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
    assert.match(bootstrapSource, /colorMan\.getColor themeColorKey/);
    assert.match(bootstrapSource, /fn lighterThemeSurface/);
    const lighterThemeSurfaceBody = bootstrapSource.slice(bootstrapSource.indexOf("fn lighterThemeSurface"), bootstrapSource.indexOf("fn themeIsDark"));
    assert.equal((lighterThemeSurfaceBody.match(/\* 0\.08\) as integer/g) || []).length, 3);
    assert.match(bootstrapSource, /local panelThemeBackground = themeDrawingColor #background 68 68 68/);
    assert.match(bootstrapSource, /lblStatus\.BackColor = panelThemeBackground/);
    assert.match(bootstrapSource, /lblContext\.BackColor = panelThemeBackground/);
    assert.doesNotMatch(bootstrapSource, /lbl(?:Status|Context)\.BackColor = statusDialog\.rtbActivity\.BackColor/);
    assert.match(bootstrapSource, /rtbActivity\.BackColor = lighterThemeSurface\(\)/);
    assert.match(bootstrapSource, /rtbActivity\.BorderStyle = \(dotNetClass "System\.Windows\.Forms\.BorderStyle"\)\.FixedSingle/);
    assert.match(bootstrapSource, /rtbActivity\.WordWrap = false/);
    assert.match(bootstrapSource, /FontStyle"\)\.Bold/);
    assert.match(bootstrapSource, /AccessibleName = "Max Ultra MCP connection status"/);
    assert.match(bootstrapSource, /maximumActivityEntries = 30/);
    assert.match(bootstrapSource, /activityLogDirty = true/);
    assert.match(bootstrapSource, /SelectionColor = activityEntryColor/);
    assert.match(bootstrapSource, /FromArgb 255 125 125/);
    assert.match(bootstrapSource, /FromArgb 255 195 80/);
    assert.match(bootstrapSource, /FromArgb 120 225 150/);
    assert.match(bootstrapSource, /FromArgb 110 205 235/);
    assert.match(bootstrapSource, /FromArgb 20 90 145/);
    assert.match(bootstrapSource, /AppendText activityEntry/);
    assert.match(bootstrapSource, /ScrollToCaret\(\)/);
    assert.match(bootstrapSource, /fn activityLogIsNearBottom/);
    assert.match(bootstrapSource, /fn activityLogFirstVisibleLine/);
    assert.match(bootstrapSource, /fn restoreActivityLogFirstVisibleLine/);
    assert.match(bootstrapSource, /fn scrollActivityLogToBottom/);
    assert.match(bootstrapSource, /fn handleActivityLogMouseEnter/);
    assert.match(bootstrapSource, /fn handleActivityLogScrolled/);
    assert.match(bootstrapSource, /SelectionStart = statusDialog\.rtbActivity\.TextLength/);
    assert.match(bootstrapSource, /windows\.sendMessage logWindowHandle windowsMessageVerticalScroll scrollBarBottom 0/);
    assert.match(bootstrapSource, /SelectionLength > 0\) do return false/);
    assert.match(bootstrapSource, /GetPositionFromCharIndex lastCharacterIndex/);
    assert.match(bootstrapSource, /local lastLineBottom = lastCharacterPosition\.Y \+ statusDialog\.rtbActivity\.Font\.Height/);
    assert.match(bootstrapSource, /richEditMessageGetFirstVisibleLine = 0x00CE/);
    assert.match(bootstrapSource, /richEditMessageLineScroll = 0x00B6/);
    assert.match(bootstrapSource, /if \(activityLogUpdating\) do return true/);
    assert.match(bootstrapSource, /if \(activityLogDirty\) do refreshActivityText\(\)/);
    assert.match(bootstrapSource, /if \(not activityLogDirty and currentActivityText == expectedActivityText\) do return true/);
    assert.match(bootstrapSource, /changedIncrementally/);
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
    assert.match(bootstrapSource, /restoreBubbleForm\.BackColor = \(dotNetClass "System\.Drawing\.Color"\)\.Black/);
    assert.match(bootstrapSource, /restoreBubbleSurface = dotNetObject "System\.Windows\.Forms\.Panel"/);
    assert.match(bootstrapSource, /restoreBubbleSurface\.Location = dotNetObject "System\.Drawing\.Point" 1 1/);
    assert.match(bootstrapSource, /restoreBubbleSurface\.Size = dotNetObject "System\.Drawing\.Size" 234 62/);
    assert.match(bootstrapSource, /restoreBubbleSurface\.BackColor = themeDrawingColor #background 68 68 68/);
    assert.match(bootstrapSource, /restoreBubbleSurface\.Controls\.Add restoreBubbleLabel[\s\S]*restoreBubbleSurface\.Controls\.Add restoreBubbleButton[\s\S]*restoreBubbleForm\.Controls\.Add restoreBubbleSurface/);
    assert.match(bootstrapSource, /screenClass\.FromHandle maxWindowHandle/);
    assert.match(bootstrapSource, /windows\.getMAXHWND\(\)/);
    assert.match(bootstrapSource, /workingArea\.Bottom - 64 - 12/);
    assert.match(bootstrapSource, /fn normalizeRestoreBubblePosition/);
    assert.match(bootstrapSource, /Screen"\)\.FromRectangle bubbleBounds/);
    assert.match(bootstrapSource, /local clampedX = amax workingArea\.Left \(amin maximumX bubbleX\)/);
    assert.match(bootstrapSource, /local clampedY = amax workingArea\.Top \(amin maximumY bubbleY\)/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "restoreBubble" "x"/);
    assert.match(bootstrapSource, /getINISetting uiStateFilePath "restoreBubble" "y"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "restoreBubble" "x"/);
    assert.match(bootstrapSource, /setINISetting uiStateFilePath "restoreBubble" "y"/);
    assert.match(bootstrapSource, /local bubblePosition = loadRestoreBubblePosition\(\)/);
    assert.match(bootstrapSource, /restoreBubbleForm\.Location = dotNetObject "System\.Drawing\.Point" bubblePosition\.x bubblePosition\.y/);
    assert.match(bootstrapSource, /restoreBubbleLabel\.Text = "Max Ultra MCP"/);
    assert.match(bootstrapSource, /restoreBubbleLabel\.Cursor = \(dotNetClass "System\.Windows\.Forms\.Cursors"\)\.SizeAll/);
    assert.match(bootstrapSource, /restoreBubbleButton\.Text = "Expand MCP Server"/);
    assert.match(bootstrapSource, /restoreBubbleButton\.AccessibleName = "Expand MCP Server"/);
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
    assert.match(bootstrapSource, /removeEventHandler bubbleLabelToDispose "MouseDown" handleRestoreBubbleMouseDown/);
    assert.match(bootstrapSource, /removeEventHandler bubbleLabelToDispose "MouseMove" handleRestoreBubbleMouseMove/);
    assert.match(bootstrapSource, /removeEventHandler bubbleLabelToDispose "MouseUp" handleRestoreBubbleMouseUp/);
    assert.match(bootstrapSource, /removeEventHandler bubbleButtonToDispose "Click" handleRestoreBubbleClick/);
    assert.match(bootstrapSource, /removeEventHandler bubbleFormToDispose "FormClosing" handleRestoreBubbleFormClosing/);
    assert.match(bootstrapSource, /if \(bubbleSurfaceToDispose != undefined\) do bubbleSurfaceToDispose\.Dispose\(\)/);
    assert.match(bootstrapSource, /fn resizePanelControls panelSize = \([\s\S]*if \(isDisposed or not panelIsOpen\(\)\) do return false/);
    assert.match(bootstrapSource, /fn refreshRestoreBubbleStatus = \([\s\S]*restoreBubbleButton\.ForeColor = statusTextColor\(\)[\s\S]*restoreBubbleButton\.Refresh\(\)/);
    assert.match(bootstrapSource, /fn refreshUserInterface = \([\s\S]*local miniPanelRefreshed = refreshRestoreBubbleStatus\(\)[\s\S]*if \(not panelIsOpen\(\)\) do return miniPanelRefreshed/);
    const restorePanelBody = bootstrapSource.slice(bootstrapSource.indexOf("fn restoreHiddenPanel"), bootstrapSource.indexOf("fn handleRestoreBubbleClick"));
    const restoreClickBody = bootstrapSource.slice(bootstrapSource.indexOf("fn handleRestoreBubbleClick"), bootstrapSource.indexOf("fn showRestoreBubble"));
    const restoreMiniPanelBody = bootstrapSource.slice(bootstrapSource.indexOf("fn showRestoreBubble"), bootstrapSource.indexOf("fn stopPollTimer"));
    assert.match(restoreMiniPanelBody, /if \(restoreBubbleForm != undefined\)[\s\S]*if \(not restoreBubbleForm\.IsDisposed\)[\s\S]*return true[\s\S]*restoreBubbleForm = dotNetObject "System\.Windows\.Forms\.Form"/);
    assert.match(restorePanelBody, /restoreGeometry = if \(hiddenPanelPosition == undefined and hiddenPanelSize == undefined\) then loadPanelGeometry\(\) else normalizePanelGeometry hiddenPanelPosition hiddenPanelSize/);
    assert.match(restorePanelBody, /restorePosition = restoreGeometry\[1\]/);
    assert.match(restorePanelBody, /restoreSize = restoreGeometry\[2\]/);
    assert.match(restorePanelBody, /createDialog statusDialog width: restoreSize\.x height: restoreSize\.y pos: restorePosition/);
    assert.match(restorePanelBody, /local wasPersistedHidden = loadPanelHiddenState\(\)/);
    assert.ok(restorePanelBody.indexOf("persistPanelHiddenState false") < restorePanelBody.indexOf("createDialog statusDialog"), "Expand must persist the expanded state before replacing the mini-panel");
    assert.match(restorePanelBody, /if \(wasPersistedHidden\) do persistPanelHiddenState true/);
    assert.ok(restorePanelBody.indexOf("if (not panelIsOpen()) do return false") < restorePanelBody.indexOf("disposeRestoreBubble()"), "The mini-panel must remain available when the native rollout cannot be recreated");
    assert.doesNotMatch(restorePanelBody, /panelForm == undefined|panelForm\.Bounds|panelForm\.Show/);
    assert.doesNotMatch(restorePanelBody, /refreshUserInterface\(\)/);
    assert.match(restoreClickBody, /restoreHiddenPanel\(\)/);
    assert.doesNotMatch(restoreClickBody, /disposeRestoreBubble\(\)/);
    const showPanelBody = bootstrapSource.slice(bootstrapSource.indexOf("fn showPanel"), bootstrapSource.indexOf("fn hidePanel"));
    assert.match(showPanelBody, /restoreHiddenPanel\(\)/);
    const hidePanelBody = bootstrapSource.slice(bootstrapSource.indexOf("fn hidePanel"), bootstrapSource.indexOf("fn closeForLifecycle"));
    assert.match(hidePanelBody, /if \(panelIsOpen\(\)\) do/);
    assert.match(hidePanelBody, /local hideGeometry = capturePanelGeometry panelForm/);
    assert.match(hidePanelBody, /hiddenPanelPosition = hideGeometry\[1\]/);
    assert.match(hidePanelBody, /hiddenPanelSize = hideGeometry\[2\]/);
    assert.match(hidePanelBody, /persistPanelGeometry hiddenPanelPosition hiddenPanelSize/);
    assert.match(hidePanelBody, /if \(not \(persistPanelHiddenState true\)\) do/);
    assert.match(hidePanelBody, /showRestoreBubble\(\)/);
    assert.match(hidePanelBody, /detachPanelFormEvents panelForm/);
    assert.match(hidePanelBody, /suppressPanelShutdown = true[\s\S]*destroyDialog statusDialog[\s\S]*suppressPanelShutdown = false/);
    assert.match(hidePanelBody, /destroyDialog statusDialog/);
    assert.ok(hidePanelBody.indexOf("showRestoreBubble()") < hidePanelBody.indexOf("destroyDialog statusDialog"), "The restore mini-panel must exist before the native rollout is destroyed");
    assert.ok(hidePanelBody.indexOf("persistPanelHiddenState true") < hidePanelBody.indexOf("destroyDialog statusDialog"), "Hide must be persisted before the native rollout is destroyed");
    assert.match(hidePanelBody, /if \(not \(showRestoreBubble\(\)\)\) do \([\s\S]*persistPanelHiddenState false/);
    const savedVisibilityBody = bootstrapSource.slice(bootstrapSource.indexOf("fn restoreSavedPanelVisibility"), bootstrapSource.indexOf("fn closeForLifecycle"));
    assert.match(savedVisibilityBody, /if \(not \(loadPanelHiddenState\(\)\)\) do return showPanel\(\)/);
    assert.match(savedVisibilityBody, /local savedPanelGeometry = loadPanelGeometry\(\)/);
    assert.match(savedVisibilityBody, /if \(showRestoreBubble\(\)\) do return true/);
    assert.match(savedVisibilityBody, /persistPanelHiddenState false[\s\S]*return showPanel\(\)/);
    assert.match(bootstrapSource, /if \(not \(restoreSavedPanelVisibility\(\)\)\) do addActivity "error" "Could not restore the saved panel visibility"/);
    assert.doesNotMatch(bootstrapSource.slice(bootstrapSource.indexOf("fn startBridge"), bootstrapSource.indexOf("bridgeClient =")), /^\s*showPanel\(\)/m);
    assert.match(formClosingBody, /persistPanelGeometry finalGeometry\[1\] finalGeometry\[2\][\s\S]*persistPanelHiddenState false/);
    assert.doesNotMatch(hidePanelBody, /panelForm\.Hide\(\)|CancelAsync|shutdown_owned|shutdown_when_idle|startTransport|stopBridge|closeForLifecycle|handleViewportScreenshot|disposeForReload/);
    const closeForLifecycleBody = bootstrapSource.slice(bootstrapSource.indexOf("fn closeForLifecycle"), bootstrapSource.indexOf("fn minimizePanel"));
    assert.match(closeForLifecycleBody, /if \(panelIsOpen\(\)\) then \([\s\S]*destroyDialog statusDialog/);
    assert.doesNotMatch(closeForLifecycleBody, /panelForm\.Close\(\)/);
    assert.doesNotMatch(restorePanelBody + restoreClickBody + restoreMiniPanelBody, /CancelAsync|shutdown_owned|shutdown_when_idle|startTransport|stopBridge|closeForLifecycle/);
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
    assert.match(viewportScreenshotBody, /viewportBitmap\.filename = screenshotPath[\s\S]*save viewportBitmap/);
    assert.match(viewportScreenshotBody, /if \(not \(doesFileExist screenshotPath\)\) do throw "3ds Max did not write the viewport PNG"/);
    assert.doesNotMatch(viewportScreenshotBody, /save viewportBitmap screenshotPath/);
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
    assert.doesNotMatch(bootstrapSource, /workerControlRequest workerHost workerPort "shutdown/);
    assert.doesNotMatch(bootstrapSource, /workerRequestOwnedShutdown|workerWaitForOwnedServerExit|ownedServerProcess\.Kill/);
    assert.doesNotMatch(bootstrapSource, /workerArguments\.Item\[12\]/);
    assert.match(bootstrapSource, /if \(workerSender\.CancellationPending\) do throw "Server startup cancelled"[\s\S]*workerLaunchServer/);
    assert.doesNotMatch(bootstrapSource, /mod tickCount 20[^\n]*startTransport/);
    const timerBody = bootstrapSource.slice(bootstrapSource.indexOf("fn handleTimerTick"), bootstrapSource.indexOf("fn startBridge"));
    assert.match(timerBody, /isDisposed or pollTimer == undefined or timerSender != pollTimer/);
    assert.match(timerBody, /catch \([\s\S]*stopPollTimer\(\)[\s\S]*CancelAsync\(\)/);
    assert.match(timerBody, /pendingConnectOnly/);
    assert.doesNotMatch(timerBody, /workerLaunchServer/);
    const disposeForReloadBody = bootstrapSource.slice(bootstrapSource.indexOf("fn disposeForReload"), bootstrapSource.indexOf("fn registerMaxShutdownCallback"));
    assert.match(disposeForReloadBody, /isDisposed = true[\s\S]*isStopped = true[\s\S]*pendingConnectOnly = false[\s\S]*stopPollTimer\(\)/);
    assert.match(disposeForReloadBody, /removeEventHandler transportWorker "DoWork" transportDoWork/);
    assert.match(disposeForReloadBody, /detachPanelFormEvents panelForm/);
    assert.doesNotMatch(disposeForReloadBody, /launchDetachedShutdownHelper/);
    const startBridgeBody = bootstrapSource.slice(bootstrapSource.indexOf("fn startBridge"), bootstrapSource.indexOf("bridgeClient = MaxUltraMcpBridgeClient"));
    assert.ok(startBridgeBody.indexOf("startTransport allowServerLaunch: true") < startBridgeBody.indexOf('dotNet.addEventHandler pollTimer'), "Replacement timer must be created only after startup state and transport are ready");
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
    assert.match(bootstrapSource, /Connect-only retry requested; a stopped server will not be launched/);
    assert.doesNotMatch(bootstrapSource, /restartServerForReload|restartServerOnNextConnect/);
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
