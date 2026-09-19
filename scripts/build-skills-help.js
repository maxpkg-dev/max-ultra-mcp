/* Generates self-contained local HTML help from the reviewed English Markdown sources.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { renderMarkdown } = require("../core/skill-markdown");
// Trusted packaged help only. Imported previews never receive this script or CSP permission.
const copyTemplateScript = `(function () {
  var button = document.getElementById('copy-template');
  var template = document.getElementById('mail-template');
  var status = document.getElementById('copy-status');
  function selectTemplate() {
    var range = document.createRange(); range.selectNodeContents(template);
    var selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
  }
  function fallback() {
    var field = document.createElement('textarea');
    field.value = template.textContent; field.setAttribute('readonly', '');
    field.style.cssText = 'position:fixed;left:0;top:0;opacity:0';
    document.body.appendChild(field); field.focus(); field.select();
    var copied = false;
    try { copied = document.execCommand('copy') === true; } catch (error) {}
    document.body.removeChild(field); button.focus();
    if (copied) status.textContent = 'Copied';
    else { selectTemplate(); status.textContent = 'Template selected. Press Ctrl+C (Command+C on Mac) to copy.'; }
  }
  button.addEventListener('click', function () {
    status.textContent = '';
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(template.textContent).then(function () { status.textContent = 'Copied'; }, fallback);
      } else fallback();
    } catch (error) { fallback(); }
  });
}());`;
for (const [name, title] of [["CUSTOM_SKILLS", "Max Ultra MCP - Create and import skills"], ["SUBMIT_SKILL", "Max Ultra MCP - Submit Your Skill"]]) {
  const source = path.join(__dirname, "..", "docs", name + ".md");
  let html = renderMarkdown(fs.readFileSync(source, "utf8"), { title, theme: "light" });
  // This fixed project-owned email link is allowed in the standalone help, never imported previews.
  if (name === "SUBMIT_SKILL") {
    html = html.replace("Open your email application", '<a href="mailto:info@3dground.net?subject=Max%20Ultra%20MCP%20skill%20submission">Open your email application</a>');
    html = html.replace(/<h2[^>]*>Mail template<\/h2>/, '<div class="template-heading"><h2>Mail template</h2><button id="copy-template" type="button">Copy Text</button><span id="copy-status" role="status" aria-live="polite"></span></div>');
    html = html.replace('<pre><code>', '<pre><code id="mail-template">');
    html = html.replace('</style>', '.template-heading h2{display:inline-block;margin-right:16px}.template-heading button{font:inherit;padding:6px 12px;cursor:pointer}.template-heading button:focus{outline:2px solid #175eb4;outline-offset:2px}#copy-status{display:block;font-size:13px;margin-bottom:8px}</style>');
    const hash = createHash("sha256").update(copyTemplateScript).digest("base64");
    html = html.replace("script-src 'none'", `script-src 'sha256-${hash}'`);
    html = html.replace('</body>', `<script>${copyTemplateScript}</script></body>`);
  }
  fs.writeFileSync(path.join(__dirname, "..", "docs", name + ".html"), html + "\n");
}
module.exports = { copyTemplateScript };
