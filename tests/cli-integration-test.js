/* End-to-end daemon/STDIO process-boundary verification. */

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const CORE_ROOT = path.join(PROJECT_ROOT, "core");

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
      const text = getText();
      if (pattern.test(text)) return resolve(text);
      if (Date.now() - started > timeoutMs) return reject(new Error(`Timed out waiting for ${pattern}: ${text}`));
      setTimeout(check, 20);
    };
    check();
  });
}

function waitForLines(lines, count, timeoutMs = 10000) {
  return waitForText(() => lines.join("\n"), new RegExp(`(?:^|\\n)(?:[^\\n]+\\n){${Math.max(0, count - 1)}}[^\\n]+$`), timeoutMs);
}

async function run() {
  const port = await freePort();
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-mcp-cli-"));
  const tokenFile = path.join(temporaryRoot, "control-token");
  const environment = {
    ...process.env,
    MAX_ULTRA_MCP_HOST: "127.0.0.1",
    MAX_ULTRA_MCP_PORT: String(port),
    MAX_ULTRA_MCP_TOKEN_FILE: tokenFile,
    MAX_ULTRA_MCP_TOOL_PROFILE: "archviz",
  };
  let daemon;
  let mock;
  let host;
  let daemonError = "";
  let daemonOutput = "";
  let mockError = "";
  let hostError = "";
  const hostLines = [];
  try {
    daemon = spawn(process.execPath, [path.join(CORE_ROOT, "server.js"), "--daemon"], { env: environment, stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
    daemon.stdout.setEncoding("utf8");
    daemon.stderr.setEncoding("utf8");
    daemon.stdout.on("data", (chunk) => { daemonOutput += chunk; });
    daemon.stderr.on("data", (chunk) => { daemonError += chunk; });
    await waitForText(() => daemonError, /RUNNING/);

    mock = spawn(process.execPath, [path.join(__dirname, "helpers", "mock-max-client.js"), "2027"], { env: environment, stdio: ["ignore", "ignore", "pipe"], windowsHide: true });
    mock.stderr.setEncoding("utf8");
    mock.stderr.on("data", (chunk) => { mockError += chunk; });
    await waitForText(() => daemonError, /CONNECTED/);

    host = spawn(process.execPath, [path.join(CORE_ROOT, "server.js"), "--stdio"], { env: environment, stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
    host.stdout.setEncoding("utf8");
    host.stderr.setEncoding("utf8");
    let hostBuffer = "";
    host.stdout.on("data", (chunk) => {
      hostBuffer += chunk;
      let newline = hostBuffer.indexOf("\n");
      while (newline !== -1) {
        const line = hostBuffer.slice(0, newline).replace(/\r$/, "");
        hostBuffer = hostBuffer.slice(newline + 1);
        if (line) hostLines.push(line);
        newline = hostBuffer.indexOf("\n");
      }
    });
    host.stderr.on("data", (chunk) => { hostError += chunk; });

    host.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } })}\n`);
    host.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list" })}\n`);
    host.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "max_list_instances", arguments: {} } })}\n`);
    await waitForLines(hostLines, 3);

    const responses = hostLines.map((line) => JSON.parse(line));
    assert.equal(responses[0].result.serverInfo.version, "1.1.0");
    assert.ok(responses[1].result.tools.length >= 56);
    assert.equal(responses[2].result.structuredContent.ok, true, JSON.stringify(responses[2].result.structuredContent));
    assert.equal(responses[2].result.structuredContent.data.count, 1);
    assert.equal(daemonOutput, "", "Daemon must not emit non-MCP content to stdout");
    assert.equal(hostError, "", `STDIO host emitted unexpected stderr: ${hostError}`);
    for (const line of hostLines) assert.doesNotThrow(() => JSON.parse(line));

    process.env.MAX_ULTRA_MCP_TOKEN_FILE = tokenFile;
    const { BridgeControlClient } = require("../core/bridge-control-client");
    const unauthenticated = new BridgeControlClient({ port, timeoutMs: 5000, controlToken: "0".repeat(64) });
    await unauthenticated.connect();
    await assert.rejects(unauthenticated.callTool("max_list_instances"), /authentication failed/i);
    unauthenticated.close();
    const control = new BridgeControlClient({ port, timeoutMs: 5000 });
    await control.connect();
    const daemonExit = daemon.exitCode === null ? new Promise((resolve) => daemon.once("exit", resolve)) : Promise.resolve();
    const hostExit = host.exitCode === null ? new Promise((resolve) => host.once("exit", resolve)) : Promise.resolve(host.exitCode);
    await control.shutdownServer();
    control.close();
    await daemonExit;
    daemon = null;
    const hostExitCode = await Promise.race([
      hostExit,
      new Promise((resolve) => setTimeout(() => resolve("timeout"), 5000)),
    ]);
    assert.notEqual(hostExitCode, "timeout", "STDIO host remained alive after its verified daemon connection closed");
    assert.equal(hostExitCode, 0, `STDIO host exited with code ${hostExitCode}: ${hostError}`);
    host = null;
  } finally {
    if (host && host.exitCode === null) host.kill();
    if (mock && mock.exitCode === null) mock.kill();
    if (daemon && daemon.exitCode === null) daemon.kill();
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
  process.stdout.write("Max Ultra MCP CLI integration passed: daemon + authenticated STDIO, JSON-only stdout\n");
}

run().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
