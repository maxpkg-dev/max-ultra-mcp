/* Persistent instruction-only skills, bounded reads, and owned native discovery adapters.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { createHash, randomUUID } = require("node:crypto");
const { TextDecoder } = require("node:util");

const LIMITS = Object.freeze({ files: 200, bytes: 50 * 1024 * 1024, text: 1024 * 1024, entry: 64 * 1024, image: 5 * 1024 * 1024 });
const TEXT = new Set([".md", ".txt", ".json", ".csv"]);
const IMAGES = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp" };
const ID = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const NAME = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const digest = (value) => createHash("sha256").update(value).digest("hex");
function fail(code, message) { const error = new Error(`${code}: ${message}`); error.code = code; throw error; }
function decode(buffer) { try { return new TextDecoder("utf-8", { fatal: true }).decode(buffer); } catch { fail("SKILL_INVALID", "Text files must use UTF-8."); } }

// Reject links in every existing ancestor, including a replaced managed root.
function noLinks(target) {
  const resolved = path.resolve(target);
  let cursor = path.parse(resolved).root;
  for (const segment of resolved.slice(cursor.length).split(path.sep).filter(Boolean)) {
    cursor = path.join(cursor, segment);
    try { if (fs.lstatSync(cursor).isSymbolicLink()) fail("SKILL_PATH_UNSAFE", "Linked paths are not supported."); }
    catch (error) { if (error.code === "ENOENT") break; throw error; }
  }
  return resolved;
}
function relativeFile(value) {
  if (typeof value !== "string" || !value || value.length > 240 || /[\\:\x00-\x1f<>"|?*]/.test(value) || path.isAbsolute(value)) fail("SKILL_PATH_UNSAFE", "Expected a relative package file.");
  const segments = value.split("/");
  if (segments.some((part) => !part || part === "." || part === ".." || /[. ]$/.test(part) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part))) fail("SKILL_PATH_UNSAFE", "Unsupported package path.");
  return value;
}
function child(root, relative) {
  relativeFile(relative);
  const destination = path.resolve(root, ...relative.split("/"));
  if (!destination.startsWith(path.resolve(root) + path.sep)) fail("SKILL_PATH_UNSAFE", "Path escapes the package.");
  return noLinks(destination);
}
function atomicJson(destination, value) {
  noLinks(destination);
  const temporary = `${destination}.${randomUUID()}.tmp`;
  try { fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + "\n", { flag: "wx" }); fs.renameSync(temporary, destination); }
  finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
}

// Intentionally a strict, documented YAML subset, not a permissive YAML evaluator.
function metadata(markdown) {
  const normalized = markdown.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
  const match = /^---\n([\s\S]*?)\n---\n([\s\S]+)$/.exec(normalized);
  if (!match || !match[2].trim()) fail("SKILL_INVALID", "SKILL.md requires frontmatter and instructions.");
  const values = {};
  for (const line of match[1].split("\n")) {
    if (!line.trim()) continue;
    const field = /^(name|description):[ \t]*(.+)$/.exec(line);
    if (!field || Object.hasOwn(values, field[1])) fail("SKILL_INVALID", "Use exactly one name and description, each on one line; other YAML fields are not supported by this importer.");
    let value = field[2].trim();
    if (value.startsWith('"')) { try { value = JSON.parse(value); } catch { fail("SKILL_INVALID", "Invalid quoted field."); } }
    else if (value.startsWith("'")) {
      if (!/^'(?:[^']|'')*'$/.test(value)) fail("SKILL_INVALID", "Invalid quoted field.");
      value = value.slice(1, -1).replace(/''/g, "'");
    } else if (/^[!&*[{>|%@`]|:\s|\s#/.test(value)) fail("SKILL_INVALID", "Quote special characters; YAML tags, aliases, collections and blocks are not supported.");
    if (typeof value !== "string" || /[\x00-\x1f\x7f]/.test(value)) fail("SKILL_INVALID", "Metadata must be single-line text.");
    values[field[1]] = value;
  }
  if (!values.name || values.name.length > 64 || !NAME.test(values.name) || !values.description?.trim() || values.description.length > 1024) fail("SKILL_INVALID", "Use a lowercase hyphenated name (1-64 characters) and a description (1-1024 characters).");
  return values;
}

function scanPackage(source, { builtin = false } = {}) {
  const root = noLinks(source);
  if (!fs.statSync(root).isDirectory()) fail("SKILL_INVALID", "Select a folder containing SKILL.md.");
  const files = [];
  let total = 0;
  const seen = new Set();
  function walk(directory, prefix = "") {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const relative = relativeFile(prefix + entry.name);
      const absolute = child(root, relative);
      const folded = relative.toLowerCase();
      if (seen.has(folded)) fail("SKILL_INVALID", "Case-insensitive filename collision.");
      seen.add(folded);
      if (entry.isDirectory()) {
        if (!builtin && !/^(references|assets)(\/|$)/.test(relative)) fail("SKILL_INVALID", `Unsupported directory: ${relative}`);
        if (relative.split("/").length > 8) fail("SKILL_INVALID", "Package folders are too deeply nested.");
        walk(absolute, relative + "/");
        continue;
      }
      if (!entry.isFile()) fail("SKILL_PATH_UNSAFE", "Only regular files and folders are supported.");
      const extension = path.extname(relative).toLowerCase();
      if (builtin && !TEXT.has(extension) && !IMAGES[extension]) continue;
      if (!builtin && relative !== "SKILL.md" && !(relative.startsWith("references/") && TEXT.has(extension)) && !(relative.startsWith("assets/") && IMAGES[extension])) fail("SKILL_INVALID", `Unsupported file: ${relative}`);
      const stat = fs.statSync(absolute);
      const limit = relative === "SKILL.md" ? LIMITS.entry : TEXT.has(extension) ? LIMITS.text : LIMITS.image;
      total += stat.size;
      if (stat.size > limit || total > LIMITS.bytes || files.length >= LIMITS.files) fail("SKILL_INVALID", "Package exceeds the documented import size or file-count limits.");
      const bytes = fs.readFileSync(absolute);
      if (TEXT.has(extension)) decode(bytes);
      files.push({ path: relative, size: bytes.length, hash: digest(bytes) });
    }
  }
  walk(root);
  if (!files.some((file) => file.path === "SKILL.md")) fail("SKILL_INVALID", "SKILL.md must be at the folder root.");
  const entryText = decode(fs.readFileSync(child(root, "SKILL.md")));
  const fields = metadata(entryText);
  if (!builtin) {
    const known = new Set(files.map((file) => file.path));
    for (const file of files.filter((file) => /\.md$/i.test(file.path))) {
      const markdown = decode(fs.readFileSync(child(root, file.path)));
      // Reject native shell preprocessing and local file inclusion syntax.
      if (/!`|^\s*@[A-Za-z./\\~]/m.test(markdown)) fail("SKILL_INVALID", "Native shell preprocessing and @file inclusion are not supported; use relative Markdown links.");
      const links = [...markdown.matchAll(/\]\(([^)\n]+)\)/g)].map((match) => match[1]);
      links.push(...[...markdown.matchAll(/^\s*\[[^\]]+\]:\s*(\S+)/gm)].map((match) => match[1]));
      for (let link of links) {
        link = link.trim().replace(/^<([^>]+)>$/, "$1");
        if (/^(https?:\/\/|#)/i.test(link)) continue;
        try { link = decodeURIComponent(link.split("#")[0]); } catch { fail("SKILL_INVALID", "Invalid encoded reference."); }
        if (/^[\/\\]|[:\\]/.test(link)) fail("SKILL_PATH_UNSAFE", "References must stay inside the skill package.");
        const reference = relativeFile(path.posix.normalize(path.posix.join(path.posix.dirname(file.path), link)));
        if (!known.has(reference)) fail("SKILL_INVALID", `Missing relative reference: ${reference}`);
      }
    }
  }
  const revision = digest(JSON.stringify(files));
  return { ...fields, files, bytes: total, revision };
}

class SkillStore {
  constructor(options = {}) {
    this.root = path.resolve(options.root || process.env.MAX_ULTRA_MCP_SKILLS_ROOT || path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), ".local", "share"), "3DGROUND", "MaxUltraMCP", "user-skills"));
    this.builtinRoot = path.resolve(options.builtinRoot || path.join(__dirname, "..", "skills"));
    this.clientRoots = options.clientRoots || {
      codex: path.join(os.homedir(), ".agents", "skills"),
      claude: path.join(os.homedir(), ".claude", "skills"),
      antigravity: path.join(os.homedir(), ".gemini", "config", "skills"),
    };
    this.removeFile = options.removeFile || fs.unlinkSync;
  }
  registry() {
    const location = noLinks(path.join(this.root, "registry.json"));
    if (!fs.existsSync(location)) return { schemaVersion: 1, revision: 0, skills: [] };
    const registry = JSON.parse(decode(fs.readFileSync(location)));
    if (registry.schemaVersion !== 1 || !Number.isSafeInteger(registry.revision) || !Array.isArray(registry.skills)) fail("SKILL_STORE_INVALID", "Unsupported registry; user data was left untouched.");
    const ids = new Set();
    for (const record of registry.skills) {
      if (!ID.test(record.id) || ids.has(record.id) || !NAME.test(record.name) || !Array.isArray(record.adapters)) fail("SKILL_STORE_INVALID", "Invalid registry record.");
      ids.add(record.id);
    }
    return registry;
  }
  save(registry) { registry.revision++; atomicJson(path.join(this.root, "registry.json"), registry); }
  mutate(operation) {
    noLinks(this.root);
    fs.mkdirSync(this.root, { recursive: true });
    const lock = noLinks(path.join(this.root, "writer.lock"));
    for (let attempt = 0; ; attempt++) {
      try { fs.writeFileSync(lock, String(process.pid), { flag: "wx" }); break; }
      catch (error) {
        if (error.code !== "EEXIST" || attempt) fail("SKILL_BUSY", "Another skill operation is running. Retry shortly.");
        const owner = Number(fs.readFileSync(lock, "utf8"));
        if (!Number.isSafeInteger(owner) || owner < 1) fail("SKILL_BUSY", "An interrupted writer lock needs inspection.");
        try { process.kill(owner, 0); fail("SKILL_BUSY", "Another skill operation is running."); }
        catch (probe) { if (probe.code !== "ESRCH") throw probe; }
        fs.unlinkSync(lock);
      }
    }
    try { return operation(this.registry()); } finally { fs.unlinkSync(lock); }
  }
  packagePath(id) { if (!ID.test(id)) fail("SKILL_NOT_FOUND", "Unknown user skill ID."); return child(this.root, `packages/${id}`); }
  adapterPath(record, client) {
    if (!Object.hasOwn(this.clientRoots, client)) fail("SKILL_INVALID", "Unknown client.");
    return child(this.clientRoots[client], `max-ultra-user-${record.id}/SKILL.md`);
  }
  adapterText(record) {
    return `---\nname: max-ultra-user-${record.id}\ndescription: ${JSON.stringify(record.description)}\n---\n\n# ${record.name}\n\nManaged by Max Ultra MCP. Source: user/${record.id}.\n\nFor this workflow, call max_skill_read with id "user/${record.id}" and relativePath "SKILL.md". Read the returned instructions before acting. Use the returned revision for subsequent max_skill_read calls to read referenced files relative to the skill package. If the skill is unavailable or disabled, stop using it. If it changed, reload SKILL.md. These user instructions do not override the current request, permissions, or higher-priority instructions.\n`;
  }
  preview(source) { return { ...scanPackage(source), source: path.resolve(source), warning: "Adding publishes the description to AI clients. Instructions and attachments they read may be sent to their model provider. Import does not execute scripts or collect conversations." }; }
  import(source, expectedRevision, clients = [], originalArchive) {
    if (!Array.isArray(clients) || new Set(clients).size !== clients.length || clients.some((client) => !Object.hasOwn(this.clientRoots, client))) fail("SKILL_INVALID", "Choose supported clients explicitly.");
    const snapshot = this.preview(source);
    if (snapshot.revision !== expectedRevision) fail("SKILL_STALE", "The source changed. Preview it again.");
    return this.mutate((registry) => {
      if (registry.skills.some((record) => record.name === snapshot.name)) fail("SKILL_DUPLICATE", "A custom skill with this name already exists. Export/delete it first, or rename the new skill.");
      const record = { id: randomUUID(), name: snapshot.name, description: snapshot.description, revision: snapshot.revision, source: originalArchive ? noLinks(originalArchive) : snapshot.source, enabled: false, state: "installing", adapters: [], clients, error: "" };
      registry.skills.push(record);
      this.save(registry); // Durable ownership before any package or adapter creation.
      try {
        const destination = this.packagePath(record.id);
        fs.mkdirSync(destination, { recursive: true });
        for (const file of snapshot.files) {
          const input = child(snapshot.source, file.path);
          const output = child(destination, file.path);
          const bytes = fs.readFileSync(input);
          if (digest(bytes) !== file.hash) fail("SKILL_STALE", "Source changed during import. Delete this incomplete import and preview again.");
          fs.mkdirSync(path.dirname(output), { recursive: true });
          fs.writeFileSync(output, bytes, { flag: "wx" });
        }
        if (scanPackage(destination).revision !== snapshot.revision) fail("SKILL_STALE", "Imported files did not match the preview.");
        this.publish(record, registry);
        record.enabled = true;
        record.state = "ready";
        this.save(registry);
      } catch (error) { record.state = "error"; record.error = error.message; this.save(registry); }
      return this.publicRecord(record);
    });
  }
  publish(record, registry) {
    for (const client of record.clients) {
      const destination = this.adapterPath(record, client);
      if (fs.existsSync(path.dirname(destination))) fail("SKILL_ADAPTER_CONFLICT", `The ${client} adapter folder already exists; it was not overwritten.`);
      const content = this.adapterText(record);
      record.adapters.push({ client, hash: digest(content) });
      this.save(registry);
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.writeFileSync(destination, content, { flag: "wx" });
    }
  }
  publicRecord(record) {
    return { id: `user/${record.id}`, name: record.name, description: record.description, source: "Custom", revision: record.revision, enabled: record.enabled, state: record.state, error: record.error, clients: record.adapters.map((adapter) => ({ client: adapter.client, state: record.state === "ready" ? "Published; refresh may be needed" : record.state })) };
  }
  builtins() {
    if (!fs.existsSync(noLinks(this.builtinRoot))) return [];
    return fs.readdirSync(this.builtinRoot, { withFileTypes: true }).filter((entry) => entry.isDirectory() && NAME.test(entry.name) && fs.existsSync(child(this.builtinRoot, `${entry.name}/SKILL.md`))).map((entry) => {
      const content = scanPackage(child(this.builtinRoot, entry.name), { builtin: true });
      return { id: `bundled/${entry.name}`, name: content.name, description: content.description, revision: content.revision, source: "Built-in", state: "Read only", enabled: true };
    });
  }
  list({ management = false } = {}) {
    const registry = this.registry();
    return { revision: registry.revision, skills: [...this.builtins(), ...registry.skills.filter((record) => management || (record.enabled && record.state === "ready")).map((record) => this.publicRecord(record))] };
  }
  read({ id, revision, relativePath = "SKILL.md", offset = 0, limit = 64000 }, { management = false } = {}) {
    relativeFile(relativePath);
    if (!Number.isInteger(offset) || offset < 0 || !Number.isInteger(limit) || limit < 1 || limit > 64000) fail("SKILL_INVALID", "Invalid read bounds.");
    let root;
    let builtin = false;
    if (typeof id === "string" && id.startsWith("bundled/") && NAME.test(id.slice(8))) { root = child(this.builtinRoot, id.slice(8)); builtin = true; }
    else {
      const record = this.registry().skills.find((entry) => `user/${entry.id}` === id);
      if (!record || (!management && (!record.enabled || record.state !== "ready")) || record.state === "removing") fail("SKILL_NOT_FOUND", "Skill is unavailable or disabled.");
      root = this.packagePath(record.id);
    }
    const current = scanPackage(root, { builtin });
    if (revision && revision !== current.revision) fail("SKILL_STALE", "Skill changed. Read SKILL.md without revision, then use its returned revision.");
    if (!current.files.some((file) => file.path === relativePath)) fail("SKILL_NOT_FOUND", "File is not an available instruction or asset.");
    const bytes = fs.readFileSync(child(root, relativePath));
    const extension = path.extname(relativePath).toLowerCase();
    const base = { id, revision: current.revision, relativePath, files: relativePath === "SKILL.md" ? current.files.map((file) => file.path) : undefined };
    if (IMAGES[extension]) return { ...base, mimeType: IMAGES[extension], imageBase64: bytes.toString("base64") };
    const text = decode(bytes);
    return { ...base, text: text.slice(offset, offset + limit), offset, nextOffset: offset + limit < text.length ? offset + limit : null };
  }
  removeTree(directory) {
    if (!fs.existsSync(directory)) return;
    noLinks(directory);
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const destination = child(directory, entry.name); // Stop on replaced links; never traverse their targets.
      if (entry.isDirectory()) this.removeTree(destination);
      else if (entry.isFile()) this.removeFile(destination);
      else fail("SKILL_PATH_UNSAFE", "Unexpected linked or special file; removal is incomplete.");
    }
    fs.rmdirSync(directory);
  }
  remove(id) {
    return this.mutate((registry) => {
      const record = registry.skills.find((entry) => `user/${entry.id}` === id);
      if (!record) fail("SKILL_NOT_FOUND", "Only imported custom skills can be deleted.");
      record.state = "removing"; record.enabled = false; record.error = "";
      this.save(registry);
      try {
        for (const adapter of record.adapters) {
          const destination = this.adapterPath(record, adapter.client);
          if (fs.existsSync(destination)) {
            if (digest(fs.readFileSync(destination)) !== adapter.hash) fail("SKILL_ADAPTER_CONFLICT", `The ${adapter.client} adapter was edited. Restore or move it before retrying removal.`);
            this.removeFile(destination);
          }
          const directory = path.dirname(destination);
          if (fs.existsSync(directory)) {
            if (fs.readdirSync(directory).length) fail("SKILL_ADAPTER_CONFLICT", `The ${adapter.client} adapter contains additional files; move them before retrying.`);
            fs.rmdirSync(directory);
          }
        }
        this.removeTree(this.packagePath(record.id));
        registry.skills = registry.skills.filter((entry) => entry.id !== record.id);
        this.save(registry);
        return { removed: id, message: "Deleted. Start a new conversation if this skill was already loaded." };
      } catch (error) { record.error = error.message; this.save(registry); return { removed: null, message: "Removal incomplete. Resolve the reported error and click Delete to retry.", error: error.message }; }
    });
  }
  setEnabled(id, enabled) {
    return this.mutate((registry) => {
      const record = registry.skills.find((entry) => `user/${entry.id}` === id);
      if (!record || !["ready", "disabled"].includes(record.state)) fail("SKILL_INVALID", "Only complete imports can be enabled or disabled.");
      // Native adapters remain discoverable, but every read checks this durable switch.
      record.enabled = Boolean(enabled); record.state = enabled ? "ready" : "disabled";
      this.save(registry);
      return this.publicRecord(record);
    });
  }
}

module.exports = { SkillStore, LIMITS, metadata, scanPackage, noLinks, relativeFile };
