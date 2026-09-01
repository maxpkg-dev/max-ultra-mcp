/* Verifies the read-only diagnostics CLI against a disposable daemon and mock 3ds Max client. */

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { BridgeControlClient } = require("../core/bridge-control-client");
const { MockMaxClient } = require("./helpers/mock-max-client");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const CLI_PATH = path.join(PROJECT_ROOT, "core", "cli.js");
const SERVER_PATH = path.join(PROJECT_ROOT, "core", "server.js");
const LAUNCHER_PATH = path.join(PROJECT_ROOT, "diagnostics", "Max Ultra MCP Diagnostics.bat");

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      server.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

function waitForText(getText, pattern, timeoutMs = 10000) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const check = () => {
      const currentText = getText();
      if (pattern.test(currentText)) return resolve(currentText);
      if (Date.now() - started > timeoutMs) return reject(new Error(`Timed out waiting for ${pattern}: ${currentText}`));
      setTimeout(check, 20);
    };
    check();
  });
}

function runCli(argumentsToPass, environment) {
  return new Promise((resolve, reject) => {
    const cliRun = spawn(process.execPath, [CLI_PATH, ...argumentsToPass], {
      cwd: PROJECT_ROOT,
      env: environment,
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });
    let standardOutput = "";
    let standardError = "";
    cliRun.stdout.setEncoding("utf8");
    cliRun.stderr.setEncoding("utf8");
    cliRun.stdout.on("data", (chunk) => { standardOutput += chunk; });
    cliRun.stderr.on("data", (chunk) => { standardError += chunk; });
    const timeoutHandle = setTimeout(() => {
      cliRun.kill();
      reject(new Error(`CLI timed out: ${standardError || standardOutput}`));
    }, 30000);
    cliRun.once("error", (error) => {
      clearTimeout(timeoutHandle);
      reject(error);
    });
    cliRun.once("exit", (exitCode) => {
      clearTimeout(timeoutHandle);
      try {
        assert.equal(exitCode, 0, `CLI failed: ${standardError || standardOutput}`);
        resolve(standardOutput);
      } catch (error) {
        reject(error);
      }
    });
  });
}

async function parseCliJson(argumentsToPass, environment) {
  return JSON.parse(await runCli([...argumentsToPass, "--json"], environment));
}

async function run() {
  const port = await freePort();
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-mcp-diagnostics-"));
  const tokenFile = path.join(temporaryRoot, "control-token");
  const environment = {
    ...process.env,
    MAX_ULTRA_MCP_HOST: "127.0.0.1",
    MAX_ULTRA_MCP_PORT: String(port),
    MAX_ULTRA_MCP_TOKEN_FILE: tokenFile,
    MAX_ULTRA_MCP_TOOL_PROFILE: "archviz",
    MAX_ULTRA_MCP_CLI_SKIP_CLIENT_PROBES: "1",
  };
  let daemon = null;
  let mock = null;
  let daemonError = "";
  try {
    const help = await runCli(["help"], environment);
    assert.match(help, /status[\s\S]*setup[\s\S]*skills[\s\S]*health[\s\S]*capabilities/);
    assert.match(help, /never installs skills/i);

    const setup = await parseCliJson(["setup"], environment);
    assert.equal(setup.readOnly, true);
    assert.deepEqual(setup.codex.verify, ["codex", "mcp", "get", "max-ultra-mcp"]);
    assert.deepEqual(setup.claudeCode.verify, ["claude", "mcp", "get", "max-ultra-mcp"]);
    assert.ok(setup.codex.command.includes("--env"));
    assert.ok(setup.claudeCode.command.includes("--scope"));
    assert.ok(setup.claudeCode.command.includes("user"));

    const skillsWithoutMax = await parseCliJson(["skills"], environment);
    assert.ok(skillsWithoutMax.count >= 7);
    const skillNames = new Set(skillsWithoutMax.skills.map((skill) => skill.name));
    for (const requiredSkill of [
      "max-ultra-mcp",
      "max-ultra-floor-plan",
      "max-ultra-camera-composition",
      "max-ultra-character-object-modeling",
      "max-ultra-renderer-settings",
      "max-ultra-spline-modeling",
      "max-ultra-maxpkg-packaging",
    ]) assert.ok(skillNames.has(requiredSkill), `Missing discovered skill ${requiredSkill}`);
    const generalSkill = skillsWithoutMax.skills.find((skill) => skill.name === "max-ultra-mcp");
    const floorPlanSkill = skillsWithoutMax.skills.find((skill) => skill.name === "max-ultra-floor-plan");
    assert.ok(generalSkill.toolReferences.includes("max_run_script"));
    assert.ok(generalSkill.toolReferences.includes("max_capture_viewport"));
    assert.ok(floorPlanSkill.toolReferences.includes("max_validate_floor_plan"));
    assert.ok(floorPlanSkill.toolReferences.includes("max_build_floor_plan"));
    for (const skill of skillsWithoutMax.skills) {
      assert.ok(path.isAbsolute(skill.path));
      assert.ok(fs.existsSync(skill.path));
      assert.ok(skill.description.length > 20);
    }

    const packageAllowlist = fs.readFileSync(path.join(PROJECT_ROOT, "maxpkg-files.txt"), "utf8");
    assert.match(packageAllowlist, /^core\/cli\.js$/m);
    assert.doesNotMatch(packageAllowlist, /^diagnostics\//m, "Developer-only diagnostics launcher must not ship in MaxPkg");

    if (process.platform === "win32") {
      const launcherRun = spawnSync("cmd.exe", ["/d", "/s", "/c", "call", LAUNCHER_PATH, "version"], {
        cwd: PROJECT_ROOT,
        env: environment,
        encoding: "utf8",
        windowsHide: true,
        timeout: 30000,
      });
      assert.equal(launcherRun.status, 0, `Diagnostics launcher failed: ${launcherRun.stderr || launcherRun.stdout}`);
      assert.match(launcherRun.stdout, /^\d+\.\d+\.\d+/m);
    }

    daemon = spawn(process.execPath, [SERVER_PATH, "--daemon"], {
      cwd: PROJECT_ROOT,
      env: environment,
      stdio: ["ignore", "ignore", "pipe"],
      windowsHide: true,
    });
    daemon.stderr.setEncoding("utf8");
    daemon.stderr.on("data", (chunk) => { daemonError += chunk; });
    await waitForText(() => daemonError, /RUNNING/);

    mock = new MockMaxClient({ host: "127.0.0.1", port, maxVersion: "2027", pid: 22027, instanceId: "mock-max-2027-cli" });
    await mock.connect();
    await waitForText(() => daemonError, /CONNECTED/);

    const status = await parseCliJson(["status"], environment);
    assert.equal(status.ok, true);
    assert.equal(status.readOnly, true);
    assert.equal(status.connection.connected, true);
    assert.equal(status.connection.instances.count, 1);
    assert.deepEqual(status.mcp.clients.map((client) => [client.client, client.state]), [["codex", "skipped"], ["claude", "skipped"]]);

    const health = await parseCliJson(["health"], environment);
    assert.equal(health.ok, true);
    assert.equal(health.readOnly, true);
    assert.equal(health.data.instance.instanceId, "mock-max-2027-cli");
    assert.equal(health.data.health.mainThread, true);

    const capabilities = await parseCliJson(["capabilities"], environment);
    assert.equal(capabilities.ok, true);
    assert.equal(capabilities.data.activeRenderer, "MockRenderer");
    assert.ok(capabilities.data.tools.includes("max_health"));
    assert.ok(capabilities.data.tools.includes("max_capabilities"));

    const checkedSkills = await parseCliJson(["skills", "--check"], environment);
    assert.equal(checkedSkills.capabilityCheck.connected, true);
    assert.equal(checkedSkills.capabilityCheck.instanceId, "mock-max-2027-cli");
    const checkedFloorPlan = checkedSkills.skills.find((skill) => skill.name === "max-ultra-floor-plan");
    assert.equal(checkedFloorPlan.capabilities.unavailable.length, 0);

    assert.equal(mock.executeRequests.length, 0, "Diagnostics CLI must never execute MaxScript");
    assert.equal(mock.screenshotRequests.length, 0, "Diagnostics CLI must not change viewport state");

    const controlToken = fs.readFileSync(tokenFile, "utf8").trim();
    const control = new BridgeControlClient({ host: "127.0.0.1", port, timeoutMs: 5000, controlToken });
    await control.connect();
    const daemonExit = new Promise((resolve) => daemon.once("exit", resolve));
    await control.shutdownServer();
    control.close();
    await daemonExit;
    daemon = null;
  } finally {
    if (mock) mock.disconnect();
    if (daemon && daemon.exitCode === null) daemon.kill();
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
  process.stdout.write("Max Ultra MCP diagnostics CLI passed: skills + Codex/Claude setup + read-only live checks\n");
}

run().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
