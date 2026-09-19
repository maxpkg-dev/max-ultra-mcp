/* Verifies lossless Antigravity entry updates, backups, concurrency and recovery in isolated files.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { installConfiguration, intendedEntry } = require("../core/antigravity-config");
const root = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-antigravity-write-"));
const configPath = path.join(root, "Example User", "mcp_config.json");
const nodePath = path.join(root, "Package With Spaces", "node.exe");
const serverPath = path.join(root, "Package With Spaces", "core", "server.js");
fs.mkdirSync(path.dirname(configPath), { recursive: true });
fs.mkdirSync(path.dirname(serverPath), { recursive: true });
fs.writeFileSync(nodePath, ""); fs.writeFileSync(serverPath, "");
const options = { configPath, nodePath, serverPath, profile: "archviz", port: 47635 };
try {
  let outcome = installConfiguration(options);
  assert.equal(outcome.ok, true); assert.equal(outcome.changed, true); assert.equal(outcome.backupPath, "");
  assert.deepEqual(JSON.parse(fs.readFileSync(configPath, "utf8")).mcpServers["max-ultra-mcp"], intendedEntry(options));
  const originalStat = fs.statSync(configPath);
  assert.deepEqual(installConfiguration(options), { ok: true, changed: false, backupPath: "", connection: "unverified" });
  assert.equal(fs.statSync(configPath).mtimeMs, originalStat.mtimeMs);
  for (const initial of ["", " \r\n", '{"theme":"dark","mcpServers":{}}',
    '{\r\n  "large": 900719925474099312345, "date":"2026-01-01T00:00:00Z", "mcpServers": { "first": {"command":"other","env":{"KEY":"synthetic"}}, "second": {"serverUrl":"https://example.invalid/mcp"} }, "nested": [1,{"x":true}]\r\n}']) {
    fs.writeFileSync(configPath, initial);
    outcome = installConfiguration(options);
    assert.equal(outcome.ok, true);
    assert.equal(fs.readFileSync(outcome.backupPath, "utf8"), initial);
    const written = fs.readFileSync(configPath, "utf8");
    if (initial.includes('"large"')) {
      assert(written.includes('"large": 900719925474099312345'));
      const decoded = JSON.parse(written);
      assert.deepEqual(decoded.mcpServers.first, {command:"other",env:{KEY:"synthetic"}});
      assert.deepEqual(decoded.mcpServers.second, {serverUrl:"https://example.invalid/mcp"});
      assert.deepEqual(decoded.nested, [1,{x:true}]);
    }
  }
  const initialEntry = intendedEntry(options);
  const existing = JSON.stringify({ keep: { value: "unchanged" }, mcpServers: { "max-ultra-mcp": initialEntry, other: { command: "keep" } } });
  fs.writeFileSync(configPath, existing);
  const alternate = { ...options, profile: "full", port: 47636 };
  outcome = installConfiguration(alternate);
  assert.equal(outcome.ok, true); assert.equal(fs.readFileSync(outcome.backupPath, "utf8"), existing);
  assert.deepEqual(JSON.parse(fs.readFileSync(configPath, "utf8")).mcpServers["max-ultra-mcp"], intendedEntry(alternate));
  for (const corrupt of ['{bad', '[]', '{"mcpServers":[]}', '{"x":1,"x":2}', '{"mcpServers":{"max-ultra-mcp":{"serverUrl":"https://example.invalid/"}}}']) {
    fs.writeFileSync(configPath, corrupt);
    outcome = installConfiguration(options);
    assert.equal(outcome.ok, false); assert.equal(fs.readFileSync(configPath, "utf8"), corrupt);
    assert.equal(outcome.backupPath, "");
  }
  fs.writeFileSync(configPath, "{}");
  outcome = installConfiguration(options, { beforeCommit() { fs.writeFileSync(configPath, '{"newer":"edit"}'); } });
  assert.equal(outcome.error.code, "CONFIG_CHANGED");
  assert.equal(fs.readFileSync(configPath, "utf8"), '{"newer":"edit"}');
  assert.equal(fs.readFileSync(outcome.backupPath, "utf8"), "{}");
  fs.writeFileSync(configPath, "{}");
  outcome = installConfiguration(options, { afterCommit() { throw new Error("Injected verification failure"); } });
  assert.equal(outcome.ok, false); assert.equal(outcome.restored, true);
  assert.equal(fs.readFileSync(configPath, "utf8"), "{}");
  fs.unlinkSync(configPath);
  outcome = installConfiguration(options, { afterCommit() { throw new Error("Injected missing-file recovery"); } });
  assert.equal(outcome.restored, true); assert.equal(fs.existsSync(configPath), false);
  fs.writeFileSync(configPath, "{}");
  outcome = installConfiguration(options, { afterCommit() { fs.writeFileSync(configPath, '{"newer":"post-write"}'); } });
  assert.equal(outcome.ok, false); assert.equal(outcome.restored, false);
  assert.equal(fs.readFileSync(configPath, "utf8"), '{"newer":"post-write"}');
  assert.equal(fs.readFileSync(outcome.backupPath, "utf8"), "{}");
  fs.writeFileSync(configPath, Buffer.from("\uFEFF{}"));
  outcome = installConfiguration(options);
  assert.equal(outcome.ok, true); assert(fs.readFileSync(configPath).subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])));
  fs.writeFileSync(configPath, "{}");
  fs.writeFileSync(configPath + ".max-ultra.lock", "busy");
  outcome = installConfiguration(options);
  assert.equal(outcome.ok, false); assert.equal(fs.readFileSync(configPath, "utf8"), "{}");
  assert.equal(fs.readFileSync(configPath + ".max-ultra.lock", "utf8"), "busy");
  fs.unlinkSync(configPath + ".max-ultra.lock");
  assert.equal(fs.readdirSync(path.dirname(configPath)).filter(name => name.endsWith(".tmp") || name.endsWith(".lock")).length, 0);
  console.log("Antigravity atomic setup passed: preservation, backups, idempotency, conflicts, concurrency, recovery and BOM.");
} finally {
  assert(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
  fs.rmSync(root, { recursive: true, force: true });
}
