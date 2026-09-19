/* Exercises persistent skills and native adapters only in disposable filesystem fixtures.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { once } = require("node:events");
const { SkillStore, metadata, LIMITS } = require("../core/skill-store");
const { StdioHost } = require("../core/stdio-host");
const { getMcpTools } = require("../core/tool-catalog");
const { run, ini } = require("../core/skills-cli");

const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-skills-test-"));
const options = { root: path.join(fixtureRoot, "persistent"), builtinRoot: path.join(fixtureRoot, "release-v1", "skills"), clientRoots: { codex: path.join(fixtureRoot, "clients", "codex"), claude: path.join(fixtureRoot, "clients", "claude"), antigravity: path.join(fixtureRoot, "clients", "antigravity") } };
function fixture(name, directory = path.join(fixtureRoot, "sources", name)) {
  fs.mkdirSync(path.join(directory, "references"), { recursive: true });
  fs.mkdirSync(path.join(directory, "assets"), { recursive: true });
  fs.writeFileSync(path.join(directory, "SKILL.md"), `---\nname: ${name}\ndescription: Prepare a synthetic fixture using verified rules.\n---\nRead [rules](references/rules.md). Inspect [sample](assets/sample.png).\n`);
  fs.writeFileSync(path.join(directory, "references", "rules.md"), "Check names and report the result.\n");
  fs.writeFileSync(path.join(directory, "assets", "sample.png"), Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7X8AAAAASUVORK5CYII=", "base64"));
  return directory;
}
const builtinFolder = fixture("builtin-example", path.join(options.builtinRoot, "builtin-example"));
const store = new SkillStore(options);
function importFixture(name, clients = []) { const source = fixture(name); return { source, imported: store.import(source, store.preview(source).revision, clients) }; }

async function main() {
  assert.equal(store.list().skills.length, 1);
  const welcome = run(["list"], store);
  assert.match(welcome.html, /Welcome to Skills/);
  assert.match(welcome.html, /href="skill-help:create"/);
  assert.match(welcome.html, /href="skill-help:submit"/);
  assert.doesNotMatch(welcome.html, /installation folder|model weights|<script\b/);
  assert.equal(fs.existsSync(options.root), false, "read-only discovery must not create user state");
  const source = fixture("furniture-export");
  const preview = store.preview(source);
  assert.equal(preview.files.length, 3);
  assert.equal(fs.existsSync(options.root), false);
  const imported = store.import(source, preview.revision, ["codex", "claude", "antigravity"]);
  assert.equal(imported.state, "ready");
  const internalId = imported.id.slice(5);
  const nativeFile = path.join(options.clientRoots.codex, `max-ultra-user-${internalId}`, "SKILL.md");
  assert.match(fs.readFileSync(nativeFile, "utf8"), /max_skill_read/);
  assert.match(fs.readFileSync(nativeFile, "utf8"), new RegExp(internalId));
  assert.equal(store.list().skills.length, 2);
  assert.throws(() => store.import(source, preview.revision), /SKILL_DUPLICATE/);
  assert.throws(() => store.import(source, preview.revision, ["unknown"]), /SKILL_INVALID/);
  const read = store.read({ id: imported.id });
  assert.equal(read.revision, preview.revision);
  assert.match(store.read({ id: imported.id, relativePath: "references/rules.md", revision: read.revision }).text, /Check names/);
  assert.equal(store.read({ id: imported.id, relativePath: "assets/sample.png", revision: read.revision }).mimeType, "image/png");
  const paged = store.read({ id: imported.id, limit: 20 });
  assert.equal(paged.nextOffset, 20);
  for (const unsafe of ["../registry.json", "C:/private.txt", "references\\rules.md", "references/rules.md:secret", "/SKILL.md", "assets/CON.png"]) assert.throws(() => store.read({ id: imported.id, relativePath: unsafe }), /SKILL_PATH_UNSAFE/);
  assert.throws(() => store.read({ id: imported.id, relativePath: "missing.md" }), /SKILL_NOT_FOUND/);
  store.setEnabled(imported.id, false);
  assert.equal(store.list().skills.length, 1);
  assert.throws(() => store.read({ id: imported.id }), /SKILL_NOT_FOUND/);
  store.setEnabled(imported.id, true);
  fs.appendFileSync(path.join(store.packagePath(internalId), "references", "rules.md"), "Verified new rule.\n");
  assert.throws(() => store.read({ id: imported.id, relativePath: "references/rules.md", revision: read.revision }), /SKILL_STALE/);
  assert.notEqual(store.read({ id: imported.id }).revision, read.revision);

  // A new official installation location must not replace the user's registry or bytes.
  const nextBuiltinRoot = path.join(fixtureRoot, "release-v2", "skills");
  fixture("new-builtin", path.join(nextBuiltinRoot, "new-builtin"));
  const afterUpdate = new SkillStore({ ...options, builtinRoot: nextBuiltinRoot });
  assert.match(afterUpdate.read({ id: imported.id, relativePath: "references/rules.md" }).text, /Verified new rule/);
  assert.equal(afterUpdate.list().skills.find((entry) => entry.id === imported.id).enabled, true);
  assert.throws(() => store.remove("bundled/builtin-example"), /SKILL_NOT_FOUND/);
  assert.ok(fs.existsSync(builtinFolder));

  const originalAdapter = fs.readFileSync(nativeFile, "utf8");
  fs.appendFileSync(nativeFile, "\nUser edit\n");
  const conflict = store.remove(imported.id);
  assert.equal(conflict.removed, null);
  assert.match(conflict.error, /SKILL_ADAPTER_CONFLICT/);
  assert.match(fs.readFileSync(nativeFile, "utf8"), /User edit/);
  assert.throws(() => store.read({ id: imported.id }), /SKILL_NOT_FOUND/);
  fs.writeFileSync(nativeFile, originalAdapter);
  const sibling = importFixture("sibling");
  fs.writeFileSync(path.join(store.packagePath(internalId), "unlisted-user-note.txt"), "Owned extra file");
  assert.equal(new SkillStore(options).remove(imported.id).removed, imported.id);
  assert.equal(fs.existsSync(store.packagePath(internalId)), false);
  assert.ok(fs.existsSync(source));
  assert.ok(fs.existsSync(store.packagePath(sibling.imported.id.slice(5))));
  for (const root of Object.values(options.clientRoots)) assert.equal(fs.existsSync(path.join(root, `max-ultra-user-${internalId}`)), false);

  const bad = fixture("bad-package");
  const entry = path.join(bad, "SKILL.md");
  const original = fs.readFileSync(entry, "utf8");
  const invalid = [original.replace("description:", "name: duplicate\ndescription:"), original.replace("description:", "hooks: []\ndescription:"), original + "[missing](references/missing.md)", original + "[escape](../../private.md)", original + "\n!`run-untrusted`", original.replace("name: bad-package", "name: ../escape")];
  for (const content of invalid) { fs.writeFileSync(entry, content); assert.throws(() => store.preview(bad), /SKILL_/); }
  fs.writeFileSync(entry, original);
  fs.writeFileSync(path.join(bad, "helper.ps1"), "throw 'Must never execute'");
  assert.throws(() => store.preview(bad), /Unsupported file/);
  fs.unlinkSync(path.join(bad, "helper.ps1"));
  const oldPreview = store.preview(bad);
  fs.appendFileSync(entry, "Changed.");
  assert.throws(() => store.import(bad, oldPreview.revision), /SKILL_STALE/);
  fs.writeFileSync(entry, "x".repeat(LIMITS.entry + 1));
  assert.throws(() => store.preview(bad), /limits/);
  fs.writeFileSync(entry, original);
  assert.equal(metadata('---\nname: example\ndescription: "Read: a fixture"\n---\nBody').description, "Read: a fixture");

  const linked = path.join(bad, "references", "linked");
  fs.symlinkSync(path.join(sibling.source, "references"), linked, process.platform === "win32" ? "junction" : "dir");
  assert.throws(() => store.preview(bad), /SKILL_PATH_UNSAFE/);
  fs.unlinkSync(linked);
  const pending = importFixture("pending-delete");
  const pendingFolder = store.packagePath(pending.imported.id.slice(5));
  const injected = new SkillStore({ ...options, removeFile: () => { const error = new Error("Fixture file is locked"); error.code = "EBUSY"; throw error; } });
  assert.equal(injected.remove(pending.imported.id).removed, null);
  assert.equal(new SkillStore(options).registry().skills.find((record) => `user/${record.id}` === pending.imported.id).state, "removing");
  assert.equal(new SkillStore(options).remove(pending.imported.id).removed, pending.imported.id);
  assert.equal(fs.existsSync(pendingFolder), false);

  // Replaced package links cannot turn Delete into an operation on external data.
  const linkedImport = importFixture("linked-import");
  const insideLink = path.join(store.packagePath(linkedImport.imported.id.slice(5)), "references", "outside");
  fs.symlinkSync(sibling.source, insideLink, process.platform === "win32" ? "junction" : "dir");
  assert.equal(store.remove(linkedImport.imported.id).removed, null);
  assert.ok(fs.existsSync(path.join(sibling.source, "SKILL.md")));
  fs.unlinkSync(insideLink);
  assert.equal(store.remove(linkedImport.imported.id).removed, linkedImport.imported.id);

  // Simulate a crashed importer after ownership was journaled: Delete remains available.
  store.mutate((registry) => { const record = registry.skills.find((entry) => `user/${entry.id}` === sibling.imported.id); record.state = "installing"; record.enabled = false; store.save(registry); });
  assert.equal(store.list({ management: true }).skills.find((entry) => entry.id === sibling.imported.id).state, "installing");
  assert.equal(store.remove(sibling.imported.id).removed, sibling.imported.id);

  let connected = false;
  const host = new StdioHost({ skillStore: store, client: { connect: () => { connected = true; throw new Error("No daemon expected"); }, close() {} } });
  let response;
  await host.handle({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "max_skills_list", arguments: {} } }, (value) => { response = value; });
  assert.equal(response.result.isError, false);
  await host.handle({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "max_skill_read", arguments: { id: "bundled/builtin-example" } } }, (value) => { response = value; });
  assert.equal(response.result.isError, false);
  assert.equal(connected, false);
  for (const profile of ["core", "archviz", "full"]) assert.ok(getMcpTools(profile).some((tool) => tool.name === "max_skill_read"));
  assert.match(ini(run(["list"], store)), /hasList=true/);
  host.close();

  if (process.platform === "win32") {
    const locked = importFixture("windows-lock");
    const lockFile = path.join(store.packagePath(locked.imported.id.slice(5)), "SKILL.md");
    const lockProcess = spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "$stream = [IO.File]::Open($env:SKILL_FIXTURE_FILE, 'Open', 'Read', 'Read'); [Console]::WriteLine('locked'); [Console]::ReadLine() | Out-Null; $stream.Dispose()"], { env: { ...process.env, SKILL_FIXTURE_FILE: lockFile }, windowsHide: true, stdio: ["pipe", "pipe", "pipe"] });
    try {
      const output = await Promise.race([once(lockProcess.stdout, "data"), once(lockProcess, "exit").then(() => { throw new Error("Fixture lock process exited early"); })]);
      assert.match(String(output[0]), /locked/);
      assert.equal(store.remove(locked.imported.id).removed, null);
    } finally { lockProcess.stdin.end("\n"); await once(lockProcess, "exit"); }
    assert.equal(store.remove(locked.imported.id).removed, locked.imported.id);
    const resultPath = path.join(fixtureRoot, "helper-result.ini");
    const helper = spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.resolve(__dirname, "../scripts/skills-manager.ps1"), "-Action", "list", "-ResultPath", resultPath], { env: { ...process.env, MAX_ULTRA_MCP_SKILLS_ROOT: options.root }, windowsHide: true, encoding: "utf8", timeout: 30000 });
    assert.equal(helper.status, 0, helper.stderr);
    assert.match(fs.readFileSync(resultPath, "utf8"), /ok=true/);
  }
  console.log("Skill store, import, revision, adapters, deletion recovery, and offline MCP tests passed.");
}
main().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => {
  assert.equal(path.dirname(fixtureRoot), path.resolve(os.tmpdir()));
  assert.ok(path.basename(fixtureRoot).startsWith("max-ultra-skills-test-"));
  fs.rmSync(fixtureRoot, { recursive: true, force: true });
});
