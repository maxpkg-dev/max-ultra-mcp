/* Checks passive Markdown rendering, package link routing, and shipped local manuals.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { renderMarkdown, linkTarget } = require("../core/skill-markdown");
const sample = "---\nname: preview-example\ndescription: Check readable passive Markdown.\n---\n# Workflow\n\n## Inputs\n\nA **bold** and *italic* paragraph.\nSecond line.\n\n- First\n  - Nested\n    1. Ordered child\n- Second\n\n```maxscript\nif (ready) do (\n    format \"<safe>\"\n)\n```\n\n| Name | Result |\n| --- | --- |\n| Example | Pass |\n\n[Reference](references/rules.md)\n\n<script id=attack>alert('bad')</script>\n\n[Unsafe](javascript:alert)\n![Remote](https://example.invalid/image.png)\n";
const html = renderMarkdown(sample, { background: "81,81,81", foreground: "225,225,225" });
assert.match(html, /<div class="metadata">/);
assert.match(html, /<h1 id="workflow">Workflow<\/h1>/);
assert.match(html, /<h2 id="inputs">Inputs<\/h2>/);
assert.match(html, /<strong>bold<\/strong> and <em>italic<\/em>/);
assert.match(html, /<ul>[\s\S]*<ul>[\s\S]*<ol>/);
assert.match(html, /\n    format &quot;&lt;safe&gt;&quot;\n/);
assert.match(html, /<table><thead>/);
assert.match(html, /href="skill-ref:references%2Frules.md"/);
assert.match(html, /background:rgb\(81,81,81\);color:rgb\(225,225,225\)/);
assert.doesNotMatch(html, /<script|<img|href="javascript:|onerror=/i);
assert.match(html, /&lt;script id=attack&gt;/);
assert.match(renderMarkdown("Text", { background: "bad<style>", foreground: "-1,900,0" }), /background:#444444/);
assert.equal(linkTarget("../assets/example.png", "references/rules.md"), "skill-ref:assets%2Fexample.png");
assert.equal(linkTarget("nested.md", "references/rules.md"), "skill-ref:references%2Fnested.md");
assert.equal(linkTarget("../../outside.txt", "references/rules.md"), null);
assert.equal(linkTarget("file:///private.txt", "SKILL.md"), null);
const navigation = renderMarkdown("# Instructions", { notice: "Built-in | Read only", navigation: true });
assert.match(navigation, /position:fixed/);
assert.match(navigation, /href="skill-nav:back"/);
assert.match(navigation, /id="skill-back"[^>]*aria-disabled="true"[^>]*tabindex="-1"/);
assert.match(navigation, /<svg[^>]*stroke="currentColor"/);
assert.match(navigation, /m12 19-7-7 7-7/);
assert.match(navigation, /text-align:right/);
assert.match(navigation, /cursor:pointer/);
assert.doesNotMatch(navigation, /<script\b|onclick=/i);
assert.doesNotMatch(navigation, /#(?:9bc8ff|175eb4|769bd0|7187a5|67707d|596372)/i);
assert.match(navigation, /#ff7f00/);
assert.match(navigation, /a,a:link,a:visited,a:active\{color:#ff7f00;text-decoration:underline\}/);
assert.match(navigation, /a:hover\{color:#ff7f00;text-decoration:none\}/);
assert.match(navigation, /\.skill-back:link,\.skill-back:visited,\.skill-back:hover,\.skill-back:active\{color:#fff;text-decoration:none\}/);
assert.match(navigation, /border-radius:0/);
assert.match(navigation, /\.metadata\{padding:12px 14px;border:1px solid #aaa;border-radius:0\}/);
assert.match(navigation, /border-bottom:1px solid #aaa/);
assert.doesNotMatch(navigation, /\.eyebrow\{[^}]*border/);
assert.match(navigation, /padding:0 14px 0 10px/);
assert.match(renderMarkdown("Text", { navigation: true, buttonBackground: "116,116,116", buttonHover: "150,150,150" }), /background:rgb\(116,116,116\)/);
assert.equal(linkTarget("https://user:secret@example.invalid", "SKILL.md"), null);
for (const skill of ["max-ultra-renderer-settings", "max-ultra-small-house-detailing"]) {
  const rendered = renderMarkdown(fs.readFileSync(path.join(__dirname, "..", "skills", skill, "SKILL.md"), "utf8"));
  assert.match(rendered, /<h2/);
  assert.match(rendered, /skill-ref:/);
  assert.doesNotMatch(rendered, /<script\b/i);
}
for (const manual of ["CUSTOM_SKILLS", "SUBMIT_SKILL"]) {
  const file = path.join(__dirname, "..", "docs", manual + ".html");
  const content = fs.readFileSync(file, "utf8");
  assert.match(content, /<!doctype html>/);
  assert.match(content, /<h1/);
  assert.doesNotMatch(content, /<link\b|<iframe\b/i);
  if (manual === "CUSTOM_SKILLS") assert.doesNotMatch(content, /<script\b/i);
  else { assert.match(content, /script-src 'sha256-/); assert.match(content, /id="copy-template"/); }
  assert.ok(fs.readFileSync(path.join(__dirname, "..", "maxpkg-files.txt"), "utf8").includes(`docs/${manual}.html`));
}
assert.match(fs.readFileSync(path.join(__dirname, "../docs/SUBMIT_SKILL.html"), "utf8"), /href="mailto:info@3dground.net/);
assert.match(fs.readFileSync(path.join(__dirname, "../docs/SKILL_CREATION_PROMPT.md"), "utf8"), /If an installed Skill Creator/);
console.log("Passive Markdown, nested content, theme colors, links, and packaged HTML manual checks passed.");
