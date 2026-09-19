/* Passive local Markdown previews: escaped content, no scripts, remote images, or active HTML.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const path = require("node:path");
const { metadata } = require("./skill-store");
const escape = (value) => String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
function linkTarget(target, relativePath) {
  if (/^https?:\/\//i.test(target)) {
    try { const url = new URL(target); if (url.username || url.password) return null; return url.href; } catch { return null; }
  }
  if (/^#[a-z0-9_-]+$/i.test(target)) return target;
  if (/^[a-z][a-z0-9+.-]*:|^[\/\\]|[\\\x00-\x1f]/i.test(target)) return null;
  let decoded;
  try { decoded = decodeURIComponent(target.split("#")[0]); } catch { return null; }
  const normalized = path.posix.normalize(path.posix.join(path.posix.dirname(relativePath), decoded));
  if (!normalized || normalized === ".." || normalized.startsWith("../") || /[:\\]/.test(normalized)) return null;
  return `skill-ref:${encodeURIComponent(normalized)}`;
}
function inline(input, relativePath, depth = 0) {
  if (depth > 8) return escape(input);
  const pattern = /(`+)([^`\n]+)\1|!?\[([^\]\n]+)\]\(([^)\s]+)\)|\*\*([^*\n]+)\*\*|__([^_\n]+)__|\*([^*\n]+)\*|_([^_\n]+)_/g;
  let html = "", cursor = 0, match;
  while ((match = pattern.exec(input))) {
    html += escape(input.slice(cursor, match.index));
    if (match[1]) html += `<code>${escape(match[2])}</code>`;
    else if (match[3]) {
      const target = linkTarget(match[4], relativePath);
      const label = inline(match[3], relativePath, depth + 1);
      html += target ? `<a href="${escape(target)}">${match[0][0] === "!" ? "Image: " : ""}${label}</a>` : label;
    } else if (match[5] || match[6]) html += `<strong>${inline(match[5] || match[6], relativePath, depth + 1)}</strong>`;
    else html += `<em>${inline(match[7] || match[8], relativePath, depth + 1)}</em>`;
    cursor = pattern.lastIndex;
  }
  return html + escape(input.slice(cursor));
}
function markdownBody(markdown, relativePath = "SKILL.md", depth = 0) {
  if (depth > 12) return `<pre>${escape(markdown)}</pre>`;
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  const output = [];
  const list = (line) => /^( *)([-+*]|\d+[.)])\s+(.*)$/.exec(line);
  const tableSeparator = (line) => /^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line || "");
  const cells = (line) => line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|");
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    if (!line.trim()) { index++; continue; }
    const fence = /^\s*(`{3,}|~{3,})([^`]*)$/.exec(line);
    if (fence) {
      const code = [];
      index++;
      while (index < lines.length && !new RegExp(`^\\s*${fence[1][0]}{${fence[1].length},}\\s*$`).test(lines[index])) code.push(lines[index++]);
      if (index < lines.length) index++;
      output.push(`<pre><code>${escape(code.join("\n"))}</code></pre>`); continue;
    }
    const heading = /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line);
    if (heading) {
      const id = heading[2].toLowerCase().replace(/[^a-z0-9 _-]/g, "").trim().replace(/\s+/g, "-");
      output.push(`<h${heading[1].length} id="${escape(id)}">${inline(heading[2], relativePath)}</h${heading[1].length}>`); index++; continue;
    }
    if (/^\s*(?:---+|\*\*\*+|___+)\s*$/.test(line)) { output.push("<hr>"); index++; continue; }
    if (/^>\s?/.test(line)) {
      const quote = [];
      while (index < lines.length && /^>\s?/.test(lines[index])) quote.push(lines[index++].replace(/^>\s?/, ""));
      output.push(`<blockquote>${markdownBody(quote.join("\n"), relativePath, depth + 1)}</blockquote>`); continue;
    }
    const firstItem = list(line);
    if (firstItem) {
      const indent = firstItem[1].length;
      const ordered = /^\d/.test(firstItem[2]);
      const tag = ordered ? "ol" : "ul";
      const items = [];
      while (index < lines.length) {
        const entry = list(lines[index]);
        if (!entry || entry[1].length !== indent || /^\d/.test(entry[2]) !== ordered) break;
        const content = [entry[3]];
        const contentIndent = entry[0].length - entry[3].length;
        index++;
        while (index < lines.length) {
          const next = list(lines[index]);
          if (next && next[1].length <= indent) break;
          if (lines[index].trim() && lines[index].search(/\S/) <= indent) break;
          if (!lines[index].trim() && index + 1 < lines.length && lines[index + 1].trim() && lines[index + 1].search(/\S/) <= indent && !list(lines[index + 1])) break;
          content.push(lines[index].slice(Math.min(contentIndent, lines[index].search(/\S/) < 0 ? contentIndent : lines[index].search(/\S/)))); index++;
        }
        items.push(`<li>${markdownBody(content.join("\n"), relativePath, depth + 1)}</li>`);
      }
      output.push(`<${tag}>${items.join("")}</${tag}>`); continue;
    }
    if (line.includes("|") && tableSeparator(lines[index + 1])) {
      const head = cells(line); index += 2;
      const rows = [];
      while (index < lines.length && lines[index].includes("|") && lines[index].trim()) rows.push(cells(lines[index++]));
      output.push(`<table><thead><tr>${head.map((cell) => `<th>${inline(cell.trim(), relativePath)}</th>`).join("")}</tr></thead><tbody>${rows.map((row) => `<tr>${row.map((cell) => `<td>${inline(cell.trim(), relativePath)}</td>`).join("")}</tr>`).join("")}</tbody></table>`); continue;
    }
    const paragraph = [line]; index++;
    while (index < lines.length && lines[index].trim() && !/^(#{1,6}\s|\s*```|\s*~~~|>\s?|\s*---+\s*$)/.test(lines[index]) && !list(lines[index]) && !tableSeparator(lines[index + 1])) paragraph.push(lines[index++]);
    output.push(`<p>${paragraph.map((part) => inline(part.replace(/ {2}$/, ""), relativePath)).join("<br>\n")}</p>`);
  }
  return output.join("\n");
}
function renderMarkdown(markdown, { relativePath = "SKILL.md", title = "Skill preview", notice = "", status, navigation = false, theme = "dark", background, foreground, buttonBackground, buttonHover } = {}) {
  let details = "";
  let body = markdown;
  if (/^\uFEFF?---\r?\n/.test(markdown) || markdown.startsWith("---\n") || markdown.startsWith("---\r\n")) {
    try {
      const fields = metadata(markdown);
      body = markdown.replace(/^\uFEFF?---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
      if (body === markdown) body = markdown.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
      details = `<div class="metadata"><div class="eyebrow">SKILL</div><h1>${escape(fields.name)}</h1><p>${escape(fields.description)}</p></div>`;
    } catch { /* Non-skill references may start with a horizontal rule. */ }
  }
  const color = (value) => typeof value === "string" && /^\d{1,3},\d{1,3},\d{1,3}$/.test(value) && value.split(",").every((part) => Number(part) <= 255) ? value.split(",").map(Number) : null;
  const backgroundRgb = color(background);
  const foregroundRgb = color(foreground);
  const light = backgroundRgb ? backgroundRgb[0] * .299 + backgroundRgb[1] * .587 + backgroundRgb[2] * .114 > 150 : theme === "light";
  const backgroundCss = backgroundRgb ? `rgb(${backgroundRgb.join(",")})` : light ? "#f5f5f5" : "#444444";
  const foregroundCss = foregroundRgb ? `rgb(${foregroundRgb.join(",")})` : light ? "#242424" : "#eeeeee";
  const buttonCss = color(buttonBackground) ? `rgb(${color(buttonBackground).join(",")})` : "#747474";
  const hoverCss = color(buttonHover) ? `rgb(${color(buttonHover).join(",")})` : "#969696";
  // Official Lucide arrow-left geometry, ISC/MIT notices in assets/icons/LUCIDE-LICENSE.txt.
  const backIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="m12 19-7-7 7-7"/><path d="M19 12H5"/></svg>';
  const statusHtml = status ? `<span class="skill-kind">${escape(status.kind || "Custom")}</span> <span class="skill-badge" title="${escape(status.detail || (status.label === "Ready" ? "Local import and registration completed. Running client discovery is not verified." : status.label))}">${escape(status.label)}</span>` : escape(notice);
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="X-UA-Compatible" content="IE=edge"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; script-src 'none'; base-uri 'none'; form-action 'none'"><title>${escape(title)}</title><style>
html{background:${backgroundCss};color:${foregroundCss};font:14px/1.6 'Segoe UI',Arial,sans-serif}body{margin:0;padding:18px;overflow-wrap:break-word;word-wrap:break-word}.document{max-width:1000px;margin:0 auto}h1,h2,h3,h4,h5,h6{line-height:1.3;margin:1.3em 0 .6em;font-weight:600}h1{font-size:25px}h2{font-size:21px}h3{font-size:18px}h4{font-size:16px}h5{font-size:15px}h6{font-size:14px}p{margin:.65em 0 1em}ul,ol{margin:.6em 0 1em;padding-left:28px}li{margin:.35em 0}li p{margin:.3em 0}pre,code{font-family:Consolas,'Courier New',monospace}code{background:${light ? "#e5e5e5" : "#353535"};padding:2px 4px;border-radius:3px}pre{background:${light ? "#e5e5e5" : "#292929"};padding:14px;overflow:auto;white-space:pre;border:0}pre code{padding:0;background:transparent}a,a:link,a:visited,a:active{color:#ff7f00;text-decoration:underline}a:hover{color:#ff7f00;text-decoration:none}a:focus{outline:1px solid #aaa;outline-offset:2px}strong{font-weight:700}em{font-style:italic}blockquote{margin:1em 0;padding:1px 16px;border:0;border-left:3px solid #ff7f00;background:rgba(255,127,0,.1);border-radius:0}table{border-collapse:collapse;width:100%;margin:1em 0}th,td{border:0;padding:8px;text-align:left;vertical-align:top}th{background:${light ? "#e5e5e5" : "#353535"}}hr{border:0;border-top:1px solid #777;margin:22px 0}.metadata,.notice{padding:0;border:0;margin-bottom:18px}.metadata{padding:12px 14px;border:1px solid #aaa;border-radius:0}.metadata h1{margin:.25em 0}.eyebrow{font-size:11px;letter-spacing:2px}.notice{border:0}
${navigation ? `.skill-header{position:fixed;top:0;left:0;right:0;height:42px;padding:0 18px;background:${backgroundCss};border-bottom:1px solid #aaa;z-index:10;white-space:nowrap}.skill-back{display:inline-block;margin-top:5px;padding:0 14px 0 10px;height:30px;line-height:28px;border:1px solid transparent;border-radius:0;color:#fff;background:${buttonCss};text-decoration:none;cursor:pointer}.skill-back svg{display:inline-block;vertical-align:-3px;margin-right:7px;pointer-events:none}.skill-back:link,.skill-back:visited,.skill-back:hover,.skill-back:active{color:#fff;text-decoration:none}.skill-back:hover{background:${hoverCss};text-decoration:none}.skill-back:focus{outline:2px solid ${foregroundCss};outline-offset:1px}.skill-back[aria-disabled=true]{opacity:.45;cursor:default;background:transparent}.skill-badge{display:inline-block;border:1px solid #aaa;border-radius:0;padding:3px 7px;font-size:12px;line-height:14px;vertical-align:middle;margin-left:5px}.skill-status{position:absolute;right:18px;left:118px;top:0;height:42px;line-height:17px;display:flex;align-items:center;justify-content:flex-end;text-align:right;overflow:hidden;text-overflow:ellipsis}body{padding-top:60px}` : ""}
</style></head><body>${navigation ? `<div class="skill-header" id="skill-header" role="navigation" aria-label="Skill document navigation"><a class="skill-back" id="skill-back" href="skill-nav:back" style="display:none" aria-disabled="true" tabindex="-1" title="Return to the previous skill document">${backIcon}Back</a><span class="skill-back" id="skill-back-disabled" aria-disabled="true">${backIcon}Back</span><span class="skill-status"${status ? "" : ` title="${escape(notice)}"`}>${statusHtml}</span></div>` : ""}<div class="document">${notice && !navigation ? `<div class="notice">${escape(notice).replace(/\n/g, "<br>")}</div>` : ""}${status?.detail ? `<div class="notice">${escape(status.detail)}</div>` : ""}${details}${markdownBody(body, relativePath)}</div></body></html>`;
}
function renderImportReport(succeeded, failed, appearance = {}) {
  const color = (value) => typeof value === "string" && /^\d{1,3},\d{1,3},\d{1,3}$/.test(value) && value.split(",").every((part) => Number(part) <= 255) ? `rgb(${value})` : "inherit";
  const successColor = color(appearance.successColor);
  const errorColor = typeof appearance.errorColor === "string" && /^\d{1,3},\d{1,3},\d{1,3}$/.test(appearance.errorColor) && appearance.errorColor.split(",").every((part) => Number(part) <= 255) ? `rgb(${appearance.errorColor})` : "inherit";
  const content = `<h1>Import results</h1><p><span style="color:${successColor}">${succeeded.length} imported</span>, <span style="color:${errorColor}">${failed.length} failed</span>.</p>`
    + (succeeded.length ? `<div class="import-success" style="color:${successColor}"><h2>Imported</h2><ul>${succeeded.map((item) => `<li>${escape(item.name)}</li>`).join("")}</ul></div>` : "")
    + (failed.length ? `<div class="import-errors" style="color:${errorColor}"><h2>Failed</h2><ul>${failed.map((item) => `<li><strong>${escape(item.name)}</strong><p>${escape(item.reason).replace(/\r?\n/g, "<br>")}</p></li>`).join("")}</ul></div>` : "")
    + (succeeded.length ? '<blockquote class="import-tip"><p>Restart your AI client or start a new chat to make the skills available.</p></blockquote>' : "");
  return renderMarkdown("", { ...appearance, title: "Import results", navigation: false }).replace('<div class="document">', `<div class="document">${content}`);
}
module.exports = { renderMarkdown, renderImportReport, markdownBody, linkTarget };
