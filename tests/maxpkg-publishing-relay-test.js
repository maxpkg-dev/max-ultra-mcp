/* MaxPkg publishing skill helpers: loopback relay server, URL-fragment relay, page-side injector and MZP inspection.
 * Fixtures are synthetic temporary files; no browser, site, account, or real package is used.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const { spawn, spawnSync } = require("node:child_process");
const { crc32 } = require("../core/skill-zip");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const SKILL_ROOT = path.join(PROJECT_ROOT, "skills", "max-ultra-maxpkg-publishing");
const SCRIPTS_ROOT = path.join(SKILL_ROOT, "scripts");
const POWERSHELL = path.join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
const GUID = "00000000-0000-4000-8000-000000000000";
const MZP_NAME = `demo-tool@1.2.3@${GUID}.mzp`;

const sha256 = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const normalize = (text) => text.replace(/\r\n/g, "\n");

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

function request(port, requestPath, { method = "GET", host = `127.0.0.1:${port}` } = {}) {
  return new Promise((resolve, reject) => {
    const outgoing = http.request({ host: "127.0.0.1", port, path: requestPath, method, headers: { Host: host } }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => resolve({ status: response.statusCode, headers: response.headers, body: Buffer.concat(chunks) }));
    });
    outgoing.on("error", reject);
    outgoing.end();
  });
}

function startRelayServer(stagingRoot, port) {
  const child = spawn(POWERSHELL, ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path.join(SCRIPTS_ROOT, "serve-relay.ps1"), "-Root", stagingRoot, "-Port", String(port), "-IdleMinutes", "2"], { windowsHide: true });
  let output = "";
  const ready = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Relay server did not start: ${output}`)), 30000);
    child.stdout.on("data", (chunk) => {
      output += chunk;
      if (/listening on http:\/\/127\.0\.0\.1:/.test(output)) { clearTimeout(timer); resolve(); }
    });
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.once("exit", (code) => { clearTimeout(timer); reject(new Error(`Relay server exited with ${code}: ${output}`)); });
  });
  return { child, ready, output: () => output };
}

function stopProcess(child) {
  return new Promise((resolve) => {
    if (child.exitCode !== null || child.signalCode !== null) { resolve(); return; }
    child.once("exit", () => resolve());
    child.kill();
  });
}

function scriptFromRelayPage(source) {
  const match = source.match(/<script>\r?\n([\s\S]*?)<\/script>/);
  assert.ok(match, "relay.html must contain one inline script");
  return match[1];
}

async function runRelay(relaySource, port, target, names) {
  let settle;
  const finished = new Promise((resolve) => { settle = resolve; });
  const status = { textContent: "" };
  const query = new URLSearchParams({ target, files: names.join(",") });
  const context = {
    URL, URLSearchParams, Uint8Array, String, Error, btoa,
    fetch: (url, options) => fetch(new URL(url, `http://127.0.0.1:${port}/relay.html`), options),
    document: { getElementById: () => status },
    location: { search: `?${query}`, replace: (url) => settle({ replaced: url, status: status.textContent }) },
  };
  vm.runInNewContext(relaySource, context);
  const watchdog = setInterval(() => { if (/^Relay failed/.test(status.textContent)) settle({ replaced: "", status: status.textContent }); }, 20);
  try { return await finished; } finally { clearInterval(watchdog); }
}

function prepareInjector(injectorSource, selector, expected) {
  const entries = Object.entries(expected).map(([name, hash]) => `    ${JSON.stringify(name)}: ${JSON.stringify(hash)},`).join("\n");
  const prepared = injectorSource
    .replace(/const selector = '[^']*';/, () => `const selector = ${JSON.stringify(selector)};`)
    .replace(/const expectedSha256 = \{\n[\s\S]*?\n  \};/, () => `const expectedSha256 = {\n${entries}\n  };`);
  assert.notEqual(prepared, injectorSource, "injector placeholders must be replaceable");
  return prepared;
}

async function runInjector(injectorSource, relayedUrl, { multiple = true, inputs = 1 } = {}) {
  const parsed = new URL(relayedUrl);
  const replaced = [];
  const events = [];
  const fakeInput = { type: "file", multiple, files: null, dispatchEvent: (event) => { events.push({ type: event.type, bubbles: event.bubbles }); return true; } };
  class FakeDataTransfer {
    constructor() {
      const list = [];
      this.items = { add: (file) => { list.push(file); } };
      this.files = list;
    }
  }
  const context = {
    URL, Uint8Array, String, Array, Object, atob, File, Event, crypto: globalThis.crypto,
    DataTransfer: FakeDataTransfer,
    history: { state: { router: true }, replaceState: (state, unused, url) => replaced.push({ state, url }) },
    location: { hash: parsed.hash, pathname: parsed.pathname, search: parsed.search },
    document: { querySelectorAll: () => Array.from({ length: inputs }, () => fakeInput) },
  };
  const result = await vm.runInNewContext(injectorSource, context);
  return { result: JSON.parse(JSON.stringify(result)), replaced, events, input: fakeInput };
}

function storedZip(file, records) {
  const locals = [];
  const central = [];
  let offset = 0;
  for (const record of records) {
    const bytes = Buffer.from(record.text, "utf8");
    const name = Buffer.from(record.name, "utf8");
    const checksum = crc32(bytes);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4); local.writeUInt16LE(0x800, 6); local.writeUInt16LE(0, 8);
    local.writeUInt32LE(checksum, 14); local.writeUInt32LE(bytes.length, 18); local.writeUInt32LE(bytes.length, 22); local.writeUInt16LE(name.length, 26);
    const directory = Buffer.alloc(46);
    directory.writeUInt32LE(0x02014b50); directory.writeUInt16LE(0x314, 4); directory.writeUInt16LE(20, 6); directory.writeUInt16LE(0x800, 8);
    directory.writeUInt32LE(checksum, 16); directory.writeUInt32LE(bytes.length, 20); directory.writeUInt32LE(bytes.length, 24); directory.writeUInt16LE(name.length, 28); directory.writeUInt32LE(offset, 42);
    locals.push(local, name, bytes);
    central.push(directory, name);
    offset += 30 + name.length + bytes.length;
  }
  const directory = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(records.length, 8); end.writeUInt16LE(records.length, 10); end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  fs.writeFileSync(file, Buffer.concat([...locals, directory, end]));
  return file;
}

function inspectMzp(file) {
  const run = spawnSync(POWERSHELL, ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path.join(SCRIPTS_ROOT, "inspect-mzp.ps1"), "-Path", file], { encoding: "utf8", windowsHide: true, timeout: 60000 });
  assert.equal(run.status, 0, `inspect-mzp.ps1 failed: ${run.stderr}`);
  return JSON.parse(run.stdout);
}

function manifest(overrides) {
  return JSON.stringify({ manifestVersion: "1", packageGuid: GUID, name: "Demo Tool", description: "Demo short description.", version: "1.2.3", releaseChannel: "stable", releaseDate: "2026-11-06", min3dsMax: 2022, max3dsMax: 2028, license: "MIT", ...overrides }, null, 2);
}

async function main() {
  const relayPageSource = fs.readFileSync(path.join(SCRIPTS_ROOT, "relay.html"), "utf8");
  const relayDocumentation = fs.readFileSync(path.join(SKILL_ROOT, "references", "file-relay.md"), "utf8");
  const listing = normalize(relayDocumentation).match(/## relay\.html listing\n[\s\S]*?```html\n([\s\S]*?)```/);
  assert.ok(listing, "file-relay.md must list relay.html");
  assert.equal(listing[1], normalize(relayPageSource), "The relay.html listing in file-relay.md must match scripts/relay.html byte for byte");
  const injectorBlock = normalize(relayDocumentation).match(/## Page-side injector\n[\s\S]*?```javascript\n([\s\S]*?)```/);
  assert.ok(injectorBlock, "file-relay.md must contain the page-side injector");
  const injectorSource = injectorBlock[1];
  const serverSource = fs.readFileSync(path.join(SCRIPTS_ROOT, "serve-relay.ps1"), "utf8");
  assert.match(serverSource, /\[Net\.IPAddress\]::Loopback/);
  assert.doesNotMatch(serverSource, /IPAddress\]::Any|HttpListener/);
  assert.doesNotMatch(serverSource, /Access-Control-Allow-Origin/);

  if (process.platform !== "win32") {
    console.log("MaxPkg publishing relay listing checks passed; PowerShell helper tests require Windows.");
    return;
  }

  const root = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-relay-test-"));
  let server;
  try {
    const stagingRoot = path.join(root, "staging");
    fs.mkdirSync(stagingRoot);
    const mzpBytes = crypto.randomBytes(320 * 1024);
    const screenshotBytes = crypto.randomBytes(48 * 1024);
    fs.writeFileSync(path.join(stagingRoot, MZP_NAME), mzpBytes);
    fs.writeFileSync(path.join(stagingRoot, "screenshot-01.png"), screenshotBytes);
    fs.writeFileSync(path.join(stagingRoot, "large.webp"), crypto.randomBytes(1600 * 1024));
    fs.writeFileSync(path.join(stagingRoot, "private-notes.txt"), "not servable");
    fs.writeFileSync(path.join(root, "outside.png"), "outside the staging folder");

    const port = await freePort();
    server = startRelayServer(stagingRoot, port);
    await server.ready;

    const index = await request(port, "/");
    assert.equal(index.status, 200);
    assert.match(index.body.toString("utf8"), /file relay is running/);
    const page = await request(port, "/relay.html?target=x");
    assert.equal(page.status, 200);
    assert.match(page.headers["content-type"], /^text\/html/);
    assert.equal(page.headers["cache-control"], "no-store");
    assert.equal(page.headers["access-control-allow-origin"], undefined);
    assert.equal(normalize(page.body.toString("utf8")), normalize(relayPageSource));
    const served = await request(port, `/files/${encodeURIComponent(MZP_NAME)}`, { host: `localhost:${port}` });
    assert.equal(served.status, 200);
    assert.equal(served.headers["content-type"], "application/octet-stream");
    assert.equal(sha256(served.body), sha256(mzpBytes));
    const head = await request(port, "/files/screenshot-01.png", { method: "HEAD" });
    assert.equal(head.status, 200);
    assert.equal(head.headers["content-type"], "image/png");
    assert.equal(head.body.length, 0);
    for (const blocked of ["/files/private-notes.txt", "/files/..%5Coutside.png", "/files/..%2Foutside.png", "/files/%2E%2E%5Coutside.png", "/files/", "/staging/screenshot-01.png", "/serve-relay.ps1"]) {
      assert.equal((await request(port, blocked)).status, 404, `Relay server must not serve ${blocked}`);
    }
    assert.equal((await request(port, "/relay.html", { host: "rebind.example" })).status, 403);
    assert.equal((await request(port, "/relay.html", { method: "POST" })).status, 405);

    const relaySource = scriptFromRelayPage(relayPageSource);
    const target = "https://maxpkg.dev/dashboard/packages/example/assets?tab=images#old";
    const relayed = await runRelay(relaySource, port, target, [MZP_NAME, "screenshot-01.png"]);
    assert.equal(relayed.replaced.startsWith("https://maxpkg.dev/dashboard/packages/example/assets?tab=images#mrfiles="), true, relayed.status);
    assert.ok(relayed.replaced.length < 2000000);
    const expected = { [MZP_NAME]: sha256(mzpBytes).toUpperCase(), "screenshot-01.png": sha256(screenshotBytes) };
    const injected = await runInjector(prepareInjector(injectorSource, 'input[type="file"][multiple]', expected), relayed.replaced);
    assert.equal(injected.result.ok, true, JSON.stringify(injected.result));
    assert.equal(injected.result.assigned, 2);
    assert.deepEqual(injected.result.files.map((file) => file.name), [MZP_NAME, "screenshot-01.png"]);
    assert.deepEqual(injected.replaced, [{ state: { router: true }, url: "/dashboard/packages/example/assets?tab=images" }]);
    assert.deepEqual(injected.events, [{ type: "change", bubbles: true }]);
    const assignedMzp = injected.input.files[0];
    assert.equal(assignedMzp.name, MZP_NAME);
    assert.equal(assignedMzp.type, "application/octet-stream");
    assert.equal(sha256(Buffer.from(await assignedMzp.arrayBuffer())), sha256(mzpBytes));
    assert.equal(injected.input.files[1].type, "image/png");

    const mismatch = await runInjector(prepareInjector(injectorSource, "input", { ...expected, "screenshot-01.png": "0".repeat(64) }), relayed.replaced);
    assert.equal(mismatch.result.code, "HASH_MISMATCH");
    assert.equal(mismatch.input.files, null, "A hash mismatch must not assign files");
    assert.equal(mismatch.replaced.length, 1, "The fragment is cleared even when verification fails");
    const singleInput = await runInjector(prepareInjector(injectorSource, "input", expected), relayed.replaced, { multiple: false });
    assert.equal(singleInput.result.code, "INPUT_SINGLE_FILE");
    const ambiguousInput = await runInjector(prepareInjector(injectorSource, "input", expected), relayed.replaced, { inputs: 2 });
    assert.equal(ambiguousInput.result.code, "INPUT_NOT_FOUND");
    const withoutFragment = await runInjector(prepareInjector(injectorSource, "input", expected), "https://maxpkg.dev/dashboard/packages");
    assert.equal(withoutFragment.result.code, "NO_RELAY_FRAGMENT");

    assert.match((await runRelay(relaySource, port, "https://maxpkg.dev.example/dashboard", [MZP_NAME])).status, /must be an https:\/\/maxpkg\.dev page/);
    assert.match((await runRelay(relaySource, port, "http://maxpkg.dev/dashboard", [MZP_NAME])).status, /must be an https:\/\/maxpkg\.dev page/);
    assert.match((await runRelay(relaySource, port, "https://maxpkg.dev/dashboard", ["large.webp"])).status, /limit is 2000000/);
    assert.match((await runRelay(relaySource, port, "https://maxpkg.dev/dashboard", ["../outside.png"])).status, /Invalid file name/);
    assert.match((await runRelay(relaySource, port, "https://maxpkg.dev/dashboard", ["missing.png"])).status, /HTTP 404/);

    await stopProcess(server.child);
    server = null;
    await assert.rejects(request(port, "/"), "The relay server must stop listening");

    const readyMzp = inspectMzp(storedZip(path.join(root, MZP_NAME), [{ name: "manifest.json", text: manifest({}) }, { name: "mzp.run", text: "run" }]));
    assert.equal(readyMzp.ready, true, JSON.stringify(readyMzp.problems));
    assert.equal(readyMzp.file, MZP_NAME);
    assert.equal(readyMzp.sha256, sha256(fs.readFileSync(path.join(root, MZP_NAME))));
    assert.equal(readyMzp.version, "1.2.3");
    assert.equal(readyMzp.min3dsMax, 2022);
    assert.equal(readyMzp.entries, 2);
    assert.deepEqual(readyMzp.problems, []);
    assert.deepEqual(readyMzp.warnings, []);
    assert.equal(Object.hasOwn(readyMzp, "packageGuid"), false);
    const betaName = `demo-tool@1.2.4@${GUID}.mzp`;
    const betaMzp = inspectMzp(storedZip(path.join(root, betaName), [{ name: "manifest.json", text: manifest({ releaseChannel: "beta", min3dsMax: 2012, description: "" }) }]));
    assert.equal(betaMzp.ready, false);
    assert.ok(betaMzp.problems.some((problem) => /releaseChannel is 'beta'/.test(problem)));
    assert.ok(betaMzp.problems.some((problem) => /file name version 1\.2\.4 differs/.test(problem)));
    assert.ok(betaMzp.problems.some((problem) => /description is empty/.test(problem)));
    assert.ok(betaMzp.warnings.some((warning) => /min3dsMax is 2012/.test(warning)));
    const renamed = inspectMzp(storedZip(path.join(root, "demo-tool-1.2.3.mzp"), [{ name: "manifest.json", text: manifest({}) }]));
    assert.ok(renamed.problems.some((problem) => /original packager name/.test(problem)));

    console.log("MaxPkg publishing relay passed: loopback-only static server, host/path guards, fragment relay, SHA-256 verified injection, URL limit, and MZP inspection.");
  } finally {
    if (server) await stopProcess(server.child);
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
