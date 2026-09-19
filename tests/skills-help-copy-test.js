/* Trusted standalone-help clipboard behavior; no real clipboard or user files.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { createHash } = require("node:crypto");
const html = fs.readFileSync(path.join(__dirname, "../docs/SUBMIT_SKILL.html"), "utf8");
const script = /<script>([\s\S]*?)<\/script>/.exec(html)[1];
const template = "To: info@example.invalid\n\nSubject: Fixture\nSecond line\n";
async function scenario(mode) {
  let click, copied, selected = false, calls = 0, removed = 0, focused = false;
  const status = { textContent: "" }, field = { setAttribute() {}, style: {}, focus() {}, select() {} };
  const button = { addEventListener(event, handler) { assert.equal(event, "click"); click = handler; }, focus() { focused = true; } };
  const document = {
    getElementById(id) { return { "copy-template": button, "mail-template": { textContent: template }, "copy-status": status }[id]; },
    createElement() { return field; }, body: { appendChild() {}, removeChild() { removed++; } },
    createRange() { return { selectNodeContents() { selected = true; } }; },
    execCommand(command) { assert.equal(command, "copy"); calls++; if (mode === "throw") throw new Error("denied"); if (mode === "manual") return false; copied = field.value; return true; },
  };
  const navigator = mode === "native" || mode === "reject" ? { clipboard: { writeText(text) { calls++; if (mode === "reject") return Promise.reject(new Error("denied")); copied = text; return Promise.resolve(); } } } : {};
  vm.runInNewContext(script, { document, navigator, window: { getSelection() { return { removeAllRanges() {}, addRange() {} }; } } });
  assert.equal(calls, 0, "no copying on load"); assert.equal(status.textContent, "");
  click(); await new Promise((resolve) => setImmediate(resolve));
  if (["manual", "throw"].includes(mode)) { assert.equal(selected, true); assert.match(status.textContent, /Press Ctrl\+C/); assert.notEqual(status.textContent, "Copied"); }
  else { assert.equal(copied, template); assert.equal(status.textContent, "Copied"); }
  if (mode !== "native") { assert.equal(removed, 1); assert.equal(focused, true); }
}
(async () => {
  assert.ok(html.includes(`script-src 'sha256-${createHash("sha256").update(script).digest("base64")}'`));
  assert.match(html, /<button id="copy-template" type="button">Copy Text<\/button>/);
  for (const mode of ["native", "fallback", "reject", "manual", "throw"]) await scenario(mode);
  console.log("Trusted help clipboard: explicit click, exact newlines, native/rejection/fallback/manual selection and CSP hash passed.");
})().catch((error) => { console.error(error); process.exitCode = 1; });
