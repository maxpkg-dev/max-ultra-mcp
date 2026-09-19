/* ZIP fixtures never touch user skills or real scenes.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { deflateRawSync } = require("node:zlib");
const { crc32, withZipSkill } = require("../core/skill-zip");
const { SkillStore, LIMITS } = require("../core/skill-store");
const { run } = require("../core/skills-cli");
const root = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-zip-test-"));
const stageRoot = path.join(root, "staging"); fs.mkdirSync(stageRoot);
const store = new SkillStore({ root: path.join(root, "store"), builtinRoot: path.join(root, "builtin"), clientRoots: Object.fromEntries(["codex", "claude", "antigravity"].map((client) => [client, path.join(root, "clients", client)])) });
const skill = "---\nname: zip-example\ndescription: Test ZIP import.\n---\nRead [rules](references/rules.md). View [image](assets/example.png).\n";
const valid = [{ name: "SKILL.md", text: skill }, { name: "references/rules.md", text: "Check results." }, { name: "assets/example.png", text: "fixture" }];
function zip(records, file = path.join(root, "skill.zip")) {
  const locals = [], central = []; let offset = 0;
  for (const record of records) {
    const bytes = Buffer.from(record.text || ""), name = Buffer.from(record.name), method = record.method ?? 8;
    const data = method === 0 ? bytes : deflateRawSync(bytes), flags = record.flags ?? 0x800;
    const checksum = record.crc ?? crc32(bytes), expanded = record.expanded ?? bytes.length;
    const local = Buffer.alloc(30); local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4); local.writeUInt16LE(flags, 6); local.writeUInt16LE(method, 8);
    local.writeUInt32LE(checksum, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(expanded, 22); local.writeUInt16LE(name.length, 26);
    const directory = Buffer.alloc(46); directory.writeUInt32LE(0x02014b50); directory.writeUInt16LE(0x314, 4); directory.writeUInt16LE(20, 6);
    directory.writeUInt16LE(flags, 8); directory.writeUInt16LE(method, 10); directory.writeUInt32LE(checksum, 16); directory.writeUInt32LE(data.length, 20); directory.writeUInt32LE(expanded, 24); directory.writeUInt16LE(name.length, 28); directory.writeUInt32LE(record.attributes ?? 0, 38); directory.writeUInt32LE(offset, 42);
    locals.push(local, name, data); central.push(directory, name); offset += 30 + name.length + data.length;
  }
  const directory = Buffer.concat(central), end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50); end.writeUInt16LE(records.length, 8); end.writeUInt16LE(records.length, 10); end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  fs.writeFileSync(file, Buffer.concat([...locals, directory, end])); return file;
}
function reject(records, pattern) {
  assert.throws(() => withZipSkill(zip(records), (folder) => store.preview(folder), { tempRoot: stageRoot }), pattern);
  assert.deepEqual(fs.readdirSync(stageRoot), [], "failed ZIP staging must be removed");
}
try {
  const archive = zip(valid), original = fs.readFileSync(archive);
  const preview = run(["preview-zip", archive], store);
  assert.equal(preview.preview.files.length, 3); assert.equal(preview.preview.source, archive);
  assert.match(preview.html, /zip-example/);
  assert.equal(fs.existsSync(store.root), false, "preview/cancel must not create installed state");
  const imported = run(["import-zip", archive, preview.revision, "none"], store);
  assert.equal(imported.skills[0].state, "ready");
  assert.equal(store.registry().skills[0].source, archive);
  assert.equal(store.read({ id: imported.skills[0].id, relativePath: "assets/example.png" }).imageBase64, Buffer.from("fixture").toString("base64"));
  store.remove(imported.skills[0].id); assert.deepEqual(fs.readFileSync(archive), original);
  const enclosed = zip([{ name: "example/", method: 0 }, ...valid.map((entry) => ({ ...entry, name: "example/" + entry.name }))]);
  assert.equal(run(["preview-zip", enclosed], store).revision, preview.revision);
  const allClients = run(["import-zip", enclosed, preview.revision], store).skills[0];
  assert.deepEqual(allClients.clients.map((client) => client.client), ["codex", "claude", "antigravity"]);
  store.remove(allClients.id);
  withZipSkill(enclosed, (folder) => assert.ok(fs.existsSync(path.join(folder, "SKILL.md"))), { tempRoot: stageRoot });
  assert.deepEqual(fs.readdirSync(stageRoot), []);
  assert.throws(() => withZipSkill(enclosed, () => { throw new Error("operation failed"); }, { tempRoot: stageRoot }), /operation failed/);
  assert.deepEqual(fs.readdirSync(stageRoot), []);
  const signal = new AbortController(); signal.abort();
  assert.throws(() => withZipSkill(enclosed, () => assert.fail(), { tempRoot: stageRoot, signal: signal.signal }), /cancelled/);
  const lateSignal = { reads: 0, get aborted() { return ++this.reads > 2; } };
  assert.throws(() => withZipSkill(enclosed, () => assert.fail(), { tempRoot: stageRoot, signal: lateSignal }), /cancelled/);
  assert.deepEqual(fs.readdirSync(stageRoot), []);
  reject([{ name: "skill.md", text: skill }], /Missing correctly named SKILL.md/);
  reject([{ name: "README.md", text: "No skill" }], /Missing correctly named SKILL.md/);
  reject([{ name: "a/SKILL.md", text: skill }, { name: "b/SKILL.md", text: skill }], /Multiple SKILL.md/);
  reject([{ name: "outer/inner/SKILL.md", text: skill }], /one enclosing folder/);
  for (const name of ["../outside", "/absolute", "C:/absolute", "a\\b", "assets/CON.png", "assets/name.png:stream"]) reject([...valid, { name }], /Unsafe archive path/);
  reject([...valid, { name: "skill.md", text: skill }], /duplicate/);
  reject([...valid, { name: "References/extra.md", text: "bad casing" }], /directory casing/);
  reject([...valid, { name: "references", text: "file collision" }], /Conflicting/);
  reject([...valid, { name: "assets/link.png", attributes: 0xa1ff0000 }], /Links/);
  reject([{ name: "SKILL.md", text: skill, flags: 0x801 }], /Encrypted/);
  reject([{ name: "SKILL.md", text: skill, method: 99 }], /unsupported compression/);
  reject([{ name: "SKILL.md", text: skill, crc: 123 }], /checksum/);
  reject([{ name: "SKILL.md", text: skill, expanded: 1 }], /expanded size/);
  reject([{ name: "SKILL.md", text: skill, expanded: LIMITS.image + 1 }], /Expanded archive/);
  reject([...valid, ...Array.from({ length: 11 }, (_, i) => ({ name: `assets/${i}.png`, expanded: LIMITS.image }))], /Expanded archive/);
  reject([...valid, ...Array.from({ length: 200 }, (_, i) => ({ name: `references/${i}.md` }))], /Expanded archive/);
  reject([{ name: "SKILL.md", text: "x".repeat(LIMITS.entry + 1) }], /size or file-count/);
  reject([{ name: "SKILL.md", text: skill }], /Missing relative reference/);
  const stale = zip(valid); const revision = run(["preview-zip", stale], store).revision;
  zip(valid.map((entry) => entry.name === "references/rules.md" ? { ...entry, text: "Changed" } : entry));
  assert.throws(() => run(["import-zip", stale, revision, "none"], store), /SKILL_STALE/);
  fs.writeFileSync(stale, "not a zip"); assert.throws(() => run(["preview-zip", stale], store), /SKILL_ZIP_INVALID/);
  assert.deepEqual(fs.readdirSync(stageRoot), []); assert.equal(store.list().skills.length, 0);
  console.log("ZIP root/wrapper, assets, revision, unsafe/corrupt/encrypted archives, expanded bounds, cancellation and staging cleanup passed.");
} finally { fs.rmSync(root, { recursive: true, force: true }); }
