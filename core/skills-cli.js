/* Local Skills window helper; mutations require explicit UI actions, never MCP calls.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { SkillStore, noLinks } = require("./skill-store");
const { renderMarkdown } = require("./skill-markdown");
const { withZipSkill } = require("./skill-zip");

function run(args, store = new SkillStore(), appearance = {}) {
  const [command, ...values] = args;
  if (command === "preview-zip") return withZipSkill(values[0], (folder, archive) => {
    const result = run(["preview", folder], store, appearance);
    result.preview.source = archive;
    return result;
  });
  if (command === "import-zip") return withZipSkill(values[0], (folder, archive) => run(["import", folder, values[1], values[2], archive], store, appearance));
  if (command === "list") {
    const text = "# Welcome to Skills\n\nSkills give your AI reusable instructions for working in 3ds Max.\n\n**Built-in** contains bundled workflows; **Custom** contains your own skills.\n\nAfter completing and checking a task, use **How to create and import skills** to save it as a repeatable workflow.\n\nUse **Submit Your Skill** to send a tested, useful skill to the author for review and possible inclusion in Max Ultra MCP.\n";
    // Only these fixed application-authored links can invoke the host's existing local-help actions.
    const html = renderMarkdown(text, appearance)
      .replace("<strong>How to create and import skills</strong>", '<a href="skill-help:create">How to create and import skills</a>')
      .replace("<strong>Submit Your Skill</strong>", '<a href="skill-help:submit">Submit Your Skill</a>');
    return { ...store.list({ management: true }), text, html, message: "Select a skill to read it, or choose Custom to add your own." };
  }
  if (command === "preview") {
    const preview = store.preview(values[0]);
    const text = fs.readFileSync(path.join(preview.source, "SKILL.md"), "utf8");
    const notice = `${preview.files.length} files, ${preview.bytes} bytes\n${preview.files.map((file) => file.path).join("\n")}\n\n${preview.warning}`;
    return { preview, revision: preview.revision, text, html: renderMarkdown(text, { ...appearance, notice }), message: "Preview checked. Click Add Skill to make it available to Codex, Claude Code and Antigravity." };
  }
  if (command === "import") {
    const clients = values[2] === undefined ? Object.keys(store.clientRoots) : values[2] && values[2] !== "none" ? values[2].split(",") : [];
    const imported = store.import(values[0], values[1], clients, values[3]);
    return { ...store.list({ management: true }), message: imported.state === "ready" ? "Skill added. Refresh your AI client or start a new conversation if it is not found." : `Saved, but activation failed: ${imported.error}. Delete the incomplete import before retrying.` };
  }
  if (command === "read") {
    const relativePath = values[1] || "SKILL.md";
    const result = store.read({ id: values[0], relativePath }, { management: true });
    const text = result.text === undefined ? `Image asset: ${relativePath}\n\nThis image is available to the agent through max_skill_read.` : result.text + (result.nextOffset ? "\n[Preview truncated]" : "");
    const entry = store.list({ management: true }).skills.find((skill) => skill.id === values[0]);
    const notice = [entry?.source, entry?.state, ...(entry?.clients || []).map((client) => `${client.client}: ${client.state}`)].filter(Boolean).join(" | ");
    return { text, html: renderMarkdown(text, { ...appearance, relativePath, notice, navigation: true }), message: "Read-only Markdown preview. Imported HTML and scripts are not executed." };
  }
  if (command === "delete") {
    const result = store.remove(values[0]);
    return { ...store.list({ management: true }), text: result.message, html: renderMarkdown(result.message, appearance), message: `${result.message}${result.error ? " " + result.error : ""}` };
  }
  if (command === "enable" || command === "disable") {
    store.setEnabled(values[0], command === "enable");
    return { ...store.list({ management: true }), message: "Read access updated. Native metadata and already loaded instructions can remain in existing conversations." };
  }
  throw new Error("Unknown Skills command.");
}
function ini(result) {
  const encode = (value) => Buffer.from(String(value ?? ""), "utf8").toString("base64");
  const lines = ["[result]", `ok=${result.ok === false ? "false" : "true"}`, `message=${encode(result.message)}`, `text=${encode(result.text)}`, `revision=${result.revision || ""}`, `hasList=${Array.isArray(result.skills) ? "true" : "false"}`, `count=${result.skills?.length || 0}`];
  for (const [index, skill] of (result.skills || []).entries()) {
    lines.push(`[skill${index}]`, `id=${encode(skill.id)}`, `name=${encode(skill.name)}`, `description=${encode(skill.description)}`, `source=${encode(skill.source)}`, `state=${encode(skill.state)}`, `clients=${encode((skill.clients || []).map((client) => `${client.client}: ${client.state}`).join("; "))}`, `error=${encode(skill.error)}`);
  }
  return lines.join("\n") + "\n";
}
if (require.main === module) {
  const args = process.argv.slice(2);
  const resultIndex = args.indexOf("--result");
  const destination = resultIndex >= 0 ? args[resultIndex + 1] : null;
  if (resultIndex >= 0) args.splice(resultIndex, 2);
  const appearance = {};
  for (const key of ["background", "foreground", "buttonBackground", "buttonHover"]) {
    const index = args.indexOf("--" + key);
    if (index >= 0) { appearance[key] = args[index + 1]; args.splice(index, 2); }
  }
  let result;
  try { result = run(args, new SkillStore(), appearance); } catch (error) { result = { ok: false, message: error.message }; process.exitCode = 1; }
  if (destination) {
    const resolved = noLinks(destination);
    const temporary = `${resolved}.${randomUUID()}.tmp`;
    fs.writeFileSync(noLinks(resolved + ".txt"), String(result.text || ""), { flag: "wx" });
    fs.writeFileSync(noLinks(resolved + ".html"), result.html || renderMarkdown(result.message || "Select a skill to read its instructions.", appearance), { flag: "wx" });
    fs.writeFileSync(temporary, ini(result), { flag: "wx" });
    fs.renameSync(temporary, resolved);
  } else process.stdout.write(JSON.stringify(result, null, 2) + "\n");
}
module.exports = { run, ini };
