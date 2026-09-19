/* Updates only Max Ultra MCP's Antigravity entry with backup and verified atomic replacement.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { isDeepStrictEqual } = require("node:util");

function failure(code, message) { return Object.assign(new Error(message), { code }); }

// Standard JSON parsing preserves numeric tokens through the runtime's rawJSON API.
// A validation-only scan rejects duplicate keys that JSON.parse would otherwise hide.
function parseDocument(source) {
  let parsed;
  try {
    parsed = JSON.parse(source, (key, value, context) => {
      if (typeof value !== "number") return value;
      if (typeof JSON.rawJSON === "function" && context?.source) return JSON.rawJSON(context.source);
      if (!Number.isFinite(value) || (Number.isInteger(value) && !Number.isSafeInteger(value))) throw new Error("Unsupported number precision");
      return value;
    });
  } catch { throw failure("INVALID_CONFIG", "Settings are not valid supported JSON. Repair the file and retry; nothing was changed."); }
  if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") throw failure("INVALID_CONFIG", "Settings must be a JSON object.");
  let cursor = 0;
  const whitespace = () => { while (/\s/.test(source[cursor] || "") && cursor < source.length) cursor++; };
  function stringEnd() {
    const start = cursor++;
    while (cursor < source.length) {
      if (source[cursor++] === '"') return { start, end: cursor };
      if (source[cursor - 1] === "\\") cursor++;
    }
    throw failure("INVALID_CONFIG", "Settings contain an incomplete string.");
  }
  function value(depth = 0) {
    if (depth > 100) throw failure("INVALID_CONFIG", "Settings nesting is too deep.");
    whitespace();
    const start = cursor;
    if (source[cursor] === '"') return { ...stringEnd(), kind: "string" };
    if (source[cursor] === "{" || source[cursor] === "[") {
      const object = source[cursor++] === "{";
      const closing = object ? "}" : "]";
      const properties = new Map();
      whitespace();
      while (source[cursor] !== closing) {
        let key;
        if (object) {
          const keyRange = stringEnd();
          key = JSON.parse(source.slice(keyRange.start, keyRange.end));
          if (properties.has(key)) throw failure("AMBIGUOUS_CONFIG", "Settings contain duplicate keys. Resolve them before installing.");
          whitespace(); cursor++; // Colon: JSON.parse already checked the grammar.
        }
        const child = value(depth + 1);
        if (object) properties.set(key, child);
        whitespace();
        if (source[cursor] === ",") { cursor++; whitespace(); } else break;
      }
      cursor++;
      return { start, end: cursor, kind: object ? "object" : "array", properties };
    }
    while (cursor < source.length && !/[\s,}\]]/.test(source[cursor])) cursor++;
    return { start, end: cursor, kind: "scalar" };
  }
  return { parsed, root: value() };
}

function intendedEntry({ nodePath, serverPath, profile = "archviz", port = 47635 }) {
  if (!path.isAbsolute(nodePath || "") || !path.isAbsolute(serverPath || "") ||
      !["core", "archviz", "full"].includes(profile) || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw failure("INVALID_OPTIONS", "The runtime paths, profile, or port are invalid.");
  }
  if (!fs.statSync(nodePath).isFile() || !fs.statSync(serverPath).isFile()) throw failure("RUNTIME_MISSING", "The runtime is unavailable.");
  const env = { MAX_ULTRA_MCP_TOOL_PROFILE: profile };
  if (port !== 47635) env.MAX_ULTRA_MCP_PORT = String(port);
  return { command: path.resolve(nodePath), args: [path.resolve(serverPath), "--stdio"], env };
}

function updateText(source, expected) {
  const { parsed } = parseDocument(source);
  const original = parseDocument(source).parsed;
  const hasServers = Object.hasOwn(parsed, "mcpServers");
  if (hasServers && (!parsed.mcpServers || typeof parsed.mcpServers !== "object" || Array.isArray(parsed.mcpServers) || JSON.isRawJSON?.(parsed.mcpServers))) {
    throw failure("INVALID_CONFIG", "mcpServers must be an object. Existing settings were preserved.");
  }
  if (!hasServers) parsed.mcpServers = {};
  if (Object.hasOwn(parsed.mcpServers, "max-ultra-mcp")) {
    const existing = parsed.mcpServers["max-ultra-mcp"];
    if (isDeepStrictEqual(existing, expected)) return source;
    const oldScript = existing?.args?.[0];
    const oldCommand = existing?.command;
    if (!existing || existing.serverUrl || typeof oldScript !== "string" || typeof oldCommand !== "string" ||
        !/(?:^|[\\/])core[\\/]server\.js$/i.test(oldScript) || existing.args?.[1] !== "--stdio" ||
        !/(?:^|[\\/])node(?:\.exe)?$/i.test(oldCommand)) {
      throw failure("ENTRY_CONFLICT", "The max-ultra-mcp name belongs to an unrecognized server. Review that entry before installing.");
    }
  }
  parsed.mcpServers["max-ultra-mcp"] = expected;
  const serialized = JSON.stringify(parsed, null, 2) + "\n";
  const verified = parseDocument(serialized).parsed;
  const withoutOwnedEntry = document => ({ ...document, mcpServers: Object.fromEntries(Object.entries(document.mcpServers || {}).filter(([key]) => key !== "max-ultra-mcp")) });
  if (!isDeepStrictEqual(withoutOwnedEntry(original), withoutOwnedEntry(verified))) throw failure("VERIFY_FAILED", "Other settings did not survive serialization. Nothing was changed.");
  return serialized;
}

function readSnapshot(configPath) {
  try {
    const stat = fs.lstatSync(configPath);
    if (!stat.isFile() || stat.isSymbolicLink()) throw failure("UNSAFE_CONFIG", "Settings must be a regular file.");
    if (stat.size > 1048576) throw failure("INVALID_CONFIG", "Settings exceed the supported size. Nothing was changed.");
    return fs.readFileSync(configPath);
  } catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

function sameBytes(first, second) { return first === null ? second === null : second !== null && first.equals(second); }

function writeNew(filePath, contents) {
  const descriptor = fs.openSync(filePath, "wx", 0o600);
  try { fs.writeFileSync(descriptor, contents); fs.fsyncSync(descriptor); } finally { fs.closeSync(descriptor); }
}

function installConfiguration(options, hooks = {}) {
  let backupPath = "";
  let temporaryPath = "";
  let lockPath = "";
  let lockDescriptor;
  let committed = false;
  let original;
  let intended;
  let configPath;
  try {
    if (!path.isAbsolute(options.configPath || "")) throw failure("INVALID_OPTIONS", "An absolute settings path is required.");
    configPath = path.resolve(options.configPath);
    const expected = intendedEntry(options);
    original = readSnapshot(configPath);
    // UTF-8 (optionally BOM) is the supported client format. Never transcode unknown encodings.
    const bom = original?.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf]));
    const content = original ? new TextDecoder("utf-8", { fatal: true }).decode(original) : "";
    const source = content.trim() ? content : "{}";
    const updated = updateText(source, expected);
    if (content.trim() && updated === source) return { ok: true, changed: false, backupPath: "", connection: "unverified" };
    intended = Buffer.from((bom ? "\uFEFF" : "") + updated, "utf8");
    const roundTrip = parseDocument(updated).parsed;
    if (!isDeepStrictEqual(roundTrip.mcpServers["max-ultra-mcp"], expected)) throw failure("VERIFY_FAILED", "Prepared settings could not be verified.");
    fs.mkdirSync(path.dirname(configPath), { recursive: true });
    lockPath = configPath + ".max-ultra.lock";
    lockDescriptor = fs.openSync(lockPath, "wx", 0o600);
    if (!sameBytes(original, readSnapshot(configPath))) throw failure("CONFIG_CHANGED", "Settings changed during setup. Refresh status and retry.");
    if (original !== null) {
      backupPath = configPath + ".max-ultra-" + new Date().toISOString().replace(/[:.]/g, "-") + "-" + randomUUID() + ".bak";
      writeNew(backupPath, original);
      if (!fs.readFileSync(backupPath).equals(original)) throw failure("BACKUP_FAILED", "Could not verify the settings backup.");
    }
    temporaryPath = configPath + ".max-ultra-" + randomUUID() + ".tmp";
    writeNew(temporaryPath, intended);
    hooks.beforeCommit?.();
    if (!sameBytes(original, readSnapshot(configPath))) throw failure("CONFIG_CHANGED", "Settings changed during setup. Your latest file was preserved; refresh and retry.");
    // Same-directory rename atomically replaces the file on Windows; readers never see partial JSON.
    fs.renameSync(temporaryPath, configPath);
    temporaryPath = "";
    committed = true;
    hooks.afterCommit?.();
    const written = readSnapshot(configPath);
    if (!sameBytes(intended, written) || !isDeepStrictEqual(parseDocument(new TextDecoder().decode(written)).parsed.mcpServers["max-ultra-mcp"], expected)) {
      throw failure("VERIFY_FAILED", "Settings changed before verification. The backup remains available.");
    }
    return { ok: true, changed: true, backupPath, connection: "unverified" };
  } catch (error) {
    let restored = false;
    let current = null;
    try { if (committed) current = readSnapshot(configPath); } catch { /* Keep the backup when the file cannot be reread. */ }
    if (committed && sameBytes(intended, current)) {
      try {
        if (original === null) fs.unlinkSync(configPath);
        else {
          temporaryPath = configPath + ".max-ultra-restore-" + randomUUID() + ".tmp";
          writeNew(temporaryPath, original);
          if (!sameBytes(intended, readSnapshot(configPath))) throw failure("CONFIG_CHANGED", "Settings changed during recovery.");
          fs.renameSync(temporaryPath, configPath);
          temporaryPath = "";
        }
        restored = sameBytes(original, readSnapshot(configPath));
      } catch { /* Preserve newer edits and the original backup if recovery cannot safely finish. */ }
    }
    return { ok: false, changed: committed && !restored, restored, backupPath,
      error: { code: error.code || "INSTALL_FAILED", message: ["INVALID_CONFIG", "AMBIGUOUS_CONFIG", "INVALID_OPTIONS", "RUNTIME_MISSING", "ENTRY_CONFLICT", "UNSAFE_CONFIG", "VERIFY_FAILED", "BACKUP_FAILED", "CONFIG_CHANGED"].includes(error.code)
        ? error.message : "Could not update Antigravity settings. Check file access, close other setup operations, and retry." } };
  } finally {
    if (temporaryPath) { try { fs.unlinkSync(temporaryPath); } catch { } }
    if (lockDescriptor !== undefined) { fs.closeSync(lockDescriptor); try { fs.unlinkSync(lockPath); } catch { } }
  }
}

module.exports = { installConfiguration, updateText, intendedEntry };
if (require.main === module) {
  const flags = {};
  for (let index = 2; index < process.argv.length; index += 2) flags[process.argv[index]] = process.argv[index + 1];
  const outcome = installConfiguration({ configPath: flags["--config"], nodePath: flags["--node"], serverPath: flags["--server"], profile: flags["--profile"], port: Number(flags["--port"]) });
  process.stdout.write(JSON.stringify(outcome) + "\n");
  process.exitCode = outcome.ok ? 0 : 1;
}
