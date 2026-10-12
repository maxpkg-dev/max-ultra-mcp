/* Verified, bounded community downloads through the existing skill importer.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const https = require("node:https");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { TextDecoder } = require("node:util");
const { withZipSkill } = require("./skill-zip");
const SITE = "https://maxpkg-dev.github.io/max-ultra-mcp-community-skills/";
const FEED = SITE + "catalog.json";
const RELEASE_DATES = "https://api.github.com/repos/maxpkg-dev/max-ultra-mcp-community-skills/releases?per_page=100";
const RELEASE = "https://github.com/maxpkg-dev/max-ultra-mcp-community-skills/releases/download/";
const MAX_ZIP = 50 * 1024 * 1024;
function fail(message) { throw new Error(message); }
function releaseUrl(value) {
  if (typeof value !== "string" || !value.startsWith(RELEASE) || !/^[A-Za-z0-9._/-]+$/.test(value.slice(RELEASE.length)) || value.includes("..") || !value.endsWith(".zip")) fail("Unsupported catalog download address.");
  return value;
}
function validateFeed(value) {
  if (!value || value.schemaVersion !== 1 || !Array.isArray(value.skills) || value.skills.length > 1000) fail("Unsupported community catalog format.");
  const seen = new Set();
  return value.skills.map(entry => {
    const limits = { id: 100, name: 64, title: 160, description: 1024, author: 256, version: 64 };
    for (const [key, limit] of Object.entries(limits)) if (typeof entry?.[key] !== "string" || !entry[key].trim() || entry[key].length > limit || /[\x00-\x1f\x7f]/.test(entry[key])) fail("Invalid catalog metadata.");
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(entry.id) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(entry.name) || seen.has(entry.id) || seen.has("name:" + entry.name)) fail("Duplicate or invalid catalog identity.");
    seen.add(entry.id); seen.add("name:" + entry.name);
    if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(entry.version) || !/^[a-f0-9]{64}$/.test(entry.sha256) || !Number.isSafeInteger(entry.sizeBytes) || entry.sizeBytes < 22 || entry.sizeBytes > MAX_ZIP) fail("Invalid catalog version, checksum or archive size.");
    releaseUrl(entry.downloadUrl);
    return Object.fromEntries([...Object.keys(limits), "downloadUrl", "sha256", "sizeBytes"].map(key => [key, entry[key]]));
  });
}
function download(address, limit, request = https.get, progress = () => {}, expectedTotal = null) {
  const deadline = Date.now() + 90000;
  function fetch(url, redirects) {
    const parsed = new URL(url);
    const permitted = url === FEED || url === RELEASE_DATES || url.startsWith(RELEASE) || parsed.hostname === "release-assets.githubusercontent.com" || parsed.hostname === "objects.githubusercontent.com";
    if (!permitted || parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.port) return Promise.reject(new Error("Unsafe catalog redirect."));
    return new Promise((resolve, reject) => {
      const remaining = deadline - Date.now();
      if (remaining <= 0) return reject(new Error("Community download timed out. Retry or open the web catalog."));
      const req = request(url, { headers: { "User-Agent": "Max-Ultra-MCP", "Accept-Encoding": "identity" } }, response => {
        if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
          response.resume();
          if (redirects >= 5 || !response.headers.location) return reject(new Error("Too many catalog redirects."));
          try { fetch(new URL(response.headers.location, url).href, redirects + 1).then(resolve, reject); } catch (error) { reject(error); }
          return;
        }
        if (response.statusCode !== 200) { response.resume(); reject(new Error("Community catalog download failed. Retry or open the web catalog.")); return; }
        if (Number(response.headers["content-length"]) > limit) { response.destroy(); reject(new Error("Community download exceeds the size limit.")); return; }
        const chunks = []; let size = 0;
        const headerTotal = Number(response.headers["content-length"]);
        const total = expectedTotal || (Number.isSafeInteger(headerTotal) && headerTotal > 0 ? headerTotal : null);
        progress({ bytes: 0, total });
        response.on("data", chunk => { size += chunk.length; if (size > limit) { response.destroy(); reject(new Error("Community download exceeds the size limit.")); } else { chunks.push(chunk); progress({ bytes: size, total }); } });
        response.on("end", () => resolve(Buffer.concat(chunks)));
        response.on("error", () => reject(new Error("Community download was interrupted. Retry.")));
        response.on("aborted", () => reject(new Error("Community download was interrupted. Retry.")));
      });
      const timer = setTimeout(() => req.destroy(new Error("Community download timed out. Retry.")), remaining);
      req.on("close", () => clearTimeout(timer));
      req.setTimeout(30000, () => req.destroy(new Error("Community download timed out. Retry.")));
      req.on("error", () => reject(new Error("Cannot reach the community catalog. Check your connection, Retry or Open Online Catalog.")));
    });
  }
  return fetch(address, 0);
}
async function catalog(fetch = download) {
  const bytes = await fetch(FEED, 2 * 1024 * 1024);
  if (bytes.length > 2 * 1024 * 1024) fail("Community catalog exceeds the size limit.");
  let parsed;
  try { parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); } catch { fail("Community catalog is not valid UTF-8 JSON."); }
  return validateFeed(parsed);
}
function installedState(entry, installed) {
  const record = installed.find(item => item.name === entry.name);
  if (!record) return "available";
  if (record.version === entry.version) return record.state === "ready" ? "installed" : "needs-attention";
  return "different-version";
}
function ownedImport(entry, installed) {
  return installed.find(item => item.source === "Custom" && /^user\/[a-f0-9-]{36}$/.test(item.id) && item.name === entry.name && item.displaySource === "Community Skills" && item.title === entry.title && item.author === entry.author);
}
async function run(command, values, store, fetch = download, progress = () => {}) {
  progress({ phase: "catalog", bytes: 0, total: null });
  const entries = await catalog(fetch);
  // Optional display metadata must never prevent browsing or installing.
  try {
    const releases = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(await fetch(RELEASE_DATES, 2 * 1024 * 1024)));
    if (Array.isArray(releases)) for (const entry of entries) {
      const tag = entry.downloadUrl.slice(RELEASE.length).split('/')[0];
      const release = releases.find(item => item.tag_name === tag && !item.draft && !item.prerelease);
      if (/^\d{4}-\d{2}-\d{2}T/.test(release?.published_at || '') && Number.isFinite(Date.parse(release.published_at))) entry.publishedAt = release.published_at.slice(0, 10);
    }
  } catch { /* GitHub rate limits or offline date metadata leave dates unknown. */ }
  let message = entries.length ? "Choose a skill to install. Imported instructions are available in new AI conversations." : "No community skills are published yet.";
  if (command === "community-delete") {
    const entry = entries.find(item => item.id === values[1]);
    const record = entry && ownedImport(entry, store.list({ management: true }).skills);
    if (!record || record.id !== values[0] || record.revision !== values[2]) fail("The installed skill changed or does not belong to this card. Refresh before deleting.");
    const result = store.remove(record.id);
    message = result.message + (result.error ? " " + result.error : "");
  }
  if (command === "community-install") {
    const entry = entries.find(item => item.id === values[0]);
    if (!entry || entry.version !== values[1] || entry.sha256 !== values[2]) fail("The catalog changed. Refresh the list before installing.");
    if (installedState(entry, store.list({ management: true }).skills) !== "available") fail("A skill with this name is already installed. Your copy was not changed. Use Custom to inspect/export and explicitly delete it before installing another version.");
    progress({ phase: "download", bytes: 0, total: entry.sizeBytes });
    const bytes = await fetch(entry.downloadUrl, entry.sizeBytes, undefined, state => progress({ phase: "download", ...state }), entry.sizeBytes);
    progress({ phase: "verify", bytes: bytes.length, total: entry.sizeBytes });
    if (bytes.length !== entry.sizeBytes || createHash("sha256").update(bytes).digest("hex") !== entry.sha256) fail("Archive checksum or size does not match the catalog. Refresh and retry; nothing was installed.");
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), "max-ultra-community-"));
    try {
      const archive = path.join(directory, "skill.zip");
      fs.writeFileSync(archive, bytes, { flag: "wx" });
      const imported = withZipSkill(archive, folder => {
        const preview = store.preview(folder);
        if (preview.name !== entry.name || preview.version !== entry.version || preview.author !== entry.author || preview.title !== entry.title) fail("Package metadata does not match the catalog. Nothing was installed.");
        progress({ phase: "install", bytes: bytes.length, total: entry.sizeBytes });
        return store.import(folder, preview.revision, Object.keys(store.clientRoots), archive, entry.publishedAt || "");
      });
      if (imported.state !== "ready") fail("Package saved, but client registration failed. Inspect the Custom list before retrying.");
      message = "Skill installed. Start a new conversation in your AI client.";
    } finally { fs.rmSync(directory, { recursive: true, force: true }); }
  }
  const listing = store.list({ management: true });
  return { ...listing, community: entries.map(entry => {
    const owned = ownedImport(entry, listing.skills);
    return { ...entry, installState: installedState(entry, listing.skills), installedId: owned?.id || "", installedRevision: owned?.revision || "" };
  }), message };
}
module.exports = { run, validateFeed, download, installedState, ownedImport, SITE, FEED };
