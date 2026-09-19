/* Bounded ZIP staging for instruction-only skill imports. No archive content is executed.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { inflateRawSync } = require("node:zlib");
const { TextDecoder } = require("node:util");
const { LIMITS, noLinks } = require("./skill-store");
function invalid(message) { const error = new Error(`SKILL_ZIP_INVALID: ${message}`); error.code = "SKILL_ZIP_INVALID"; throw error; }
function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) { crc ^= byte; for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
  return (crc ^ 0xffffffff) >>> 0;
}
function entries(buffer) {
  let end = buffer.length - 22;
  for (; end >= Math.max(0, buffer.length - 65557); end--) {
    if (buffer.readUInt32LE(end) === 0x06054b50 && end + 22 + buffer.readUInt16LE(end + 20) === buffer.length) break;
  }
  if (end < 0 || buffer.length < 22 || buffer.readUInt32LE(end) !== 0x06054b50) invalid("Corrupt ZIP directory. Create a standard unencrypted ZIP and retry.");
  const count = buffer.readUInt16LE(end + 10), size = buffer.readUInt32LE(end + 12), offset = buffer.readUInt32LE(end + 16);
  if (buffer.readUInt16LE(end + 4) || buffer.readUInt16LE(end + 6) || count !== buffer.readUInt16LE(end + 8) || count === 65535 || size === 0xffffffff || offset === 0xffffffff) invalid("Split and ZIP64 archives are not supported. Use a standard ZIP.");
  if (!count || count > LIMITS.files * 9 || offset + size !== end) invalid("Invalid directory or too many archive entries.");
  const result = [], seen = new Map();
  let cursor = offset, total = 0, files = 0;
  for (let i = 0; i < count; i++) {
    if (cursor + 46 > end || buffer.readUInt32LE(cursor) !== 0x02014b50) invalid("Corrupt ZIP entry.");
    const flags = buffer.readUInt16LE(cursor + 8), method = buffer.readUInt16LE(cursor + 10);
    const compressed = buffer.readUInt32LE(cursor + 20), expanded = buffer.readUInt32LE(cursor + 24);
    const nameLength = buffer.readUInt16LE(cursor + 28), extraLength = buffer.readUInt16LE(cursor + 30), commentLength = buffer.readUInt16LE(cursor + 32);
    const attributes = buffer.readUInt32LE(cursor + 38), local = buffer.readUInt32LE(cursor + 42);
    const next = cursor + 46 + nameLength + extraLength + commentLength;
    if (next > end || buffer.readUInt16LE(cursor + 34) || compressed === 0xffffffff || expanded === 0xffffffff || local === 0xffffffff) invalid("Unsupported ZIP entry layout.");
    if ((flags & ~0x80e) || ![0, 8].includes(method)) invalid("Encrypted or unsupported compression. Use unencrypted Store or Deflate ZIP.");
    const rawName = buffer.subarray(cursor + 46, cursor + 46 + nameLength);
    let name;
    try {
      if (!(flags & 0x800) && rawName.some((byte) => byte >= 128)) invalid("Non-ASCII ZIP names must use UTF-8 encoding.");
      name = new TextDecoder("utf-8", { fatal: true }).decode(rawName);
    } catch { invalid("Invalid ZIP filename encoding. Use UTF-8 filenames."); }
    const directory = name.endsWith("/");
    if (directory) name = name.slice(0, -1);
    const parts = name.split("/");
    if (!name || name.length > 240 || parts.length > 10 || /[\\:\x00-\x1f\x7f<>"|?*]/.test(name) || parts.some((part) => !part || part === "." || part === ".." || /[. ]$/.test(part) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part))) invalid("Unsafe archive path. Use relative files inside one skill folder.");
    const type = (attributes >>> 16) & 0xf000;
    if ((type && type !== (directory ? 0x4000 : 0x8000)) || (attributes & 0x400)) invalid("Links, reparse points and special files are not supported.");
    if (directory && (expanded || compressed)) invalid("Directory entries must be empty.");
    const folded = name.toLowerCase();
    if (seen.has(folded)) invalid("Case-insensitive duplicate archive path.");
    seen.set(folded, { name, directory });
    if (!directory) { total += expanded; files++; }
    if (total > LIMITS.bytes || expanded > LIMITS.image || files > LIMITS.files) invalid("Expanded archive exceeds 50 MiB, 200 files, or the per-file limit.");
    if (local + 30 > offset || buffer.readUInt32LE(local) !== 0x04034b50 || buffer.readUInt16LE(local + 6) !== flags || buffer.readUInt16LE(local + 8) !== method) invalid("Corrupt local ZIP entry.");
    const localNameLength = buffer.readUInt16LE(local + 26), localExtraLength = buffer.readUInt16LE(local + 28);
    const data = local + 30 + localNameLength + localExtraLength;
    if (data + compressed > offset || !rawName.equals(buffer.subarray(local + 30, local + 30 + localNameLength))) invalid("Inconsistent ZIP filenames or data bounds.");
    result.push({ name, directory, expanded, compressed, method, data, crc: buffer.readUInt32LE(cursor + 16) });
    cursor = next;
  }
  if (cursor !== end) invalid("Corrupt ZIP directory length.");
  // Detect both explicit and implicit directory casing/file collisions before writing anything.
  const paths = new Map(seen);
  for (const entry of result) {
    const parts = entry.name.split("/");
    for (let i = 1; i < parts.length; i++) {
      const name = parts.slice(0, i).join("/"), key = name.toLowerCase(), existing = paths.get(key);
      if (existing && (!existing.directory || existing.name !== name)) invalid("Conflicting file/directory names or directory casing.");
      paths.set(key, { name, directory: true });
    }
  }
  const roots = result.filter((entry) => !entry.directory && entry.name.split("/").at(-1) === "SKILL.md");
  if (roots.length !== 1) invalid(roots.length ? "Multiple SKILL.md roots found. Put exactly one skill in each ZIP." : "Missing correctly named SKILL.md. Place SKILL.md at ZIP root or inside one enclosing folder.");
  const root = roots[0].name.slice(0, -"SKILL.md".length);
  if (root && root.split("/").length !== 2) invalid("SKILL.md must be at ZIP root or inside one enclosing folder.");
  if (result.some((entry) => root && entry.name !== root.slice(0, -1) && !entry.name.startsWith(root))) invalid("Archive contains files outside the single skill folder. Repackage only that folder.");
  return { entries: result, root };
}
function withZipSkill(source, operation, { tempRoot = os.tmpdir(), signal } = {}) {
  function cancelled() { if (signal?.aborted) { const error = new Error("Skill ZIP operation cancelled."); error.code = "ABORT_ERR"; throw error; } }
  cancelled();
  const archive = noLinks(source);
  if (path.extname(archive).toLowerCase() !== ".zip" || !fs.statSync(archive).isFile()) invalid("Select a ZIP file.");
  if (fs.statSync(archive).size > LIMITS.bytes + 4 * 1024 * 1024) invalid("ZIP file exceeds the 54 MiB archive limit.");
  const buffer = fs.readFileSync(archive), parsed = entries(buffer);
  const staging = fs.mkdtempSync(path.join(noLinks(tempRoot), "max-ultra-skill-zip-"));
  try {
    for (const entry of parsed.entries) {
      cancelled();
      const destination = noLinks(path.join(staging, ...entry.name.split("/")));
      if (!destination.startsWith(staging + path.sep)) invalid("Archive path escaped staging.");
      if (entry.directory) { fs.mkdirSync(destination, { recursive: true }); continue; }
      const compressed = buffer.subarray(entry.data, entry.data + entry.compressed);
      let bytes;
      try { bytes = entry.method === 0 ? compressed : inflateRawSync(compressed, { maxOutputLength: Math.max(1, entry.expanded) }); }
      catch { invalid("Corrupt compressed data or expanded size limit exceeded."); }
      if (bytes.length !== entry.expanded || crc32(bytes) !== entry.crc) invalid("ZIP size or checksum mismatch.");
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.writeFileSync(destination, bytes, { flag: "wx" });
    }
    cancelled();
    return operation(path.join(staging, parsed.root), archive);
  } finally {
    // Remove only this freshly-created owned staging directory; links are never followed.
    noLinks(staging);
    fs.rmSync(staging, { recursive: true, force: true });
  }
}
module.exports = { withZipSkill, crc32 };
