# URL-Fragment File Relay

Read this reference only when the first two file-attach methods are unavailable or fail: the user's own browser through an extension that attaches files, such as Claude in Chrome `file_upload`, or another tool that sets files directly, such as Playwright `setInputFiles`; and computer use that clicks "Choose MZP" or "Choose screenshots" and fills the Windows Open dialog or drags files from Explorer. When an extension could work but is not installed or connected, ask the user whether to set it up first. A typical case is the Claude desktop built-in browser without usable computer use. This relay is the last resort. The relay was verified on maxpkg.dev on 2026-11-06.

## How it works

The maxpkg.dev Content Security Policy blocks the page from fetching localhost, but it does not restrict top-level navigation, and a URL fragment is never sent to any server. The relay uses that:

1. A local static server on 127.0.0.1 serves a staging folder.
2. `relay.html`, served by that server, fetches the requested files, base64-encodes them, and calls `location.replace(target + '#mrfiles=' + parts)`. Each part is `encodeURIComponent(name)|type|base64`, and the parts are joined with `;`.
3. On the maxpkg.dev page, a JavaScript snippet reads `location.hash`, clears it with `history.replaceState`, decodes it into `File` objects, and compares each SHA-256 from `crypto.subtle.digest` with the local `Get-FileHash` or `sha256sum` value. Only then does it assign the files to the site's input through `new DataTransfer()` and dispatch a bubbling `change` event. The site uploads them with its normal code, exactly as after drag and drop.

## Limits

- Keep each navigation under about 2 MB of URL; `relay.html` refuses longer URLs. Base64 adds a third, so one navigation carries about 1.4 MB of files. An MZP of about 320 KB fits. Send screenshots about three at a time.
- When one image is too large, export it again in a smaller encoding, such as optimized PNG or WEBP, without changing what it shows.
- A larger file, such as an MZP that bundles a runtime, goes through [chunk mode](#chunk-mode-for-large-files): about 1.45 MB per navigation, kept in a temporary IndexedDB database on the maxpkg.dev page, then assembled and verified. This was verified on 2026-11-06 with a 37 MB MZP in 26 chunks. The MZP input accepts up to 100 MB.
- `relay.html` sends files only to `https://maxpkg.dev` pages.

## Steps

1. **Stage the files.** Create a new, empty temporary folder and copy only the files for this upload into it. Never serve a project root, a `dist` folder with other releases, or a profile folder. Record the hashes:

   ```powershell
   Get-FileHash -Algorithm SHA256 -LiteralPath <STAGING_DIR>\<FILE> | Select-Object -ExpandProperty Hash
   ```

2. **Start the server** with [`scripts/serve-relay.ps1`](../scripts/serve-relay.ps1) `-Root <STAGING_DIR> -Port 8765`. It binds 127.0.0.1 only, serves `/relay.html` from the skill's `scripts` folder and `/files/<name>` from the top level of the staging folder (`.mzp`, `.png`, `.jpg`, `.jpeg`, and `.webp` only), rejects other `Host` headers, and stops after 30 idle minutes.
   - **Claude desktop:** add a temporary entry to `.claude/launch.json` in the session's working folder and call `preview_start` with its name. If the file already exists, add only this entry and later remove only this entry.

     ```json
     {
       "version": "0.0.1",
       "configurations": [
         {
           "name": "maxpkg-file-relay",
           "runtimeExecutable": "powershell.exe",
           "runtimeArgs": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<SKILL_DIR>/scripts/serve-relay.ps1", "-Root", "<STAGING_DIR>", "-Port", "8765"],
           "port": 8765
         }
       ]
     }
     ```

   - **Other agents:** run the script as a background process. Any static server bound to 127.0.0.1 also works when it serves `relay.html` at its root and the staged files below `files/`, for example `python -m http.server 8765 --bind 127.0.0.1` started in a staging folder that holds a copy of `relay.html` and a `files` subfolder.

3. **Open the target page.** In the signed-in tab, open the maxpkg.dev page whose input will receive the files, and identify the input as described in the [site map](site-map.md). Note the page URL.
4. **Run the relay.** In the same tab, navigate to:

   ```text
   http://127.0.0.1:8765/relay.html?target=<encoded page URL>&files=<encoded comma-separated file names>
   ```

   `localhost:8765` works the same way. The relay page replaces itself with the target page plus the fragment. If it shows "Relay failed", fix the reported cause and retry.
5. **Inject the files.** When the maxpkg.dev page has loaded, fill `selector` and `expectedSha256` in the injector below and run it with the browser's JavaScript tool. It clears the fragment first. It assigns nothing when the fragment is missing, a hash differs, a file is missing, or the input is not found. If it returns `NO_RELAY_FRAGMENT`, run the relay again. The returned `assigned` count can be 0 even on success, because the site takes the file and clears its input; watch the page instead.
6. **Confirm the upload.** Wait for "Upload complete" or the new image previews, then verify as the skill describes. Repeat steps 4 to 6 for the next batch.
7. **Clean up.** Stop the server (`preview_stop`, or end the process), remove the temporary launch entry, any `relay.html` copy, and the staging folder, and confirm that nothing listens on the port anymore.

## Page-side injector

Most browser JavaScript tools await a returned promise. If yours does not, prefix the expression with `await`.

```javascript
(async () => {
  // Fill these two values before running. Use lowercase or uppercase hex from Get-FileHash or sha256sum.
  const selector = 'input.file-dropzone__input[accept=".mzp"]';
  const expectedSha256 = {
    "<FILE NAME>": "<SHA-256>",
  };
  const prefix = "#mrfiles=";
  if (!location.hash.startsWith(prefix)) return { ok: false, code: "NO_RELAY_FRAGMENT" };
  const fragment = location.hash.slice(prefix.length);
  history.replaceState(history.state, "", location.pathname + location.search);
  const files = [];
  for (const part of fragment.split(";")) {
    const [encodedName, type, base64] = part.split("|");
    const name = decodeURIComponent(encodedName);
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const sha256 = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
    files.push({ file: new File([bytes], name, { type }), name, size: bytes.length, sha256 });
  }
  const report = files.map(({ name, size, sha256 }) => ({ name, size, sha256 }));
  const expectedNames = Object.keys(expectedSha256);
  const mismatched = files.filter((entry) => String(expectedSha256[entry.name] || "").toLowerCase() !== entry.sha256);
  if (mismatched.length || files.length !== expectedNames.length) return { ok: false, code: "HASH_MISMATCH", files: report };
  const matches = document.querySelectorAll(selector);
  if (matches.length !== 1 || matches[0].type !== "file") return { ok: false, code: "INPUT_NOT_FOUND", count: matches.length, files: report };
  const input = matches[0];
  if (files.length > 1 && !input.multiple) return { ok: false, code: "INPUT_SINGLE_FILE", files: report };
  const transfer = new DataTransfer();
  for (const entry of files) transfer.items.add(entry.file);
  input.files = transfer.files;
  input.dispatchEvent(new Event("change", { bubbles: true }));
  return { ok: true, assigned: input.files.length, files: report };
})();
```

## Chunk mode for large files

Use chunk mode for one file whose base64 does not fit in one URL. Staging, the server, the target page, and cleanup stay as in the steps above.

1. Compute the chunk count: `ceil(size / 1450000)`.
2. For every index from 0 to count - 1, in the signed-in tab, navigate to:

   ```text
   http://127.0.0.1:8765/relay.html?target=<encoded page URL>&files=<encoded file name>&chunk=<index>&chunkSize=1450000
   ```

   Wait about 3 seconds, then run the chunk receiver below. It stores the chunk and returns how many are stored. If it returns `NO_RELAY_CHUNK`, the page has not finished loading or lost the fragment: wait and run it again, or repeat that index. When the browser tools can batch steps, send several chunks per call as navigate, wait, run.
3. When `stored` equals the count, fill `expected` and `selector` in the chunk assembler and run it. It joins the chunks in order, checks size and SHA-256 against the local file, deletes the temporary database in every case, and only on a match hands the file to the input.
4. Wait for "Upload complete", then verify as the skill describes. Confirm that `indexedDB.databases()` no longer lists `max-ultra-relay`.

Chunk receiver:

```javascript
(async () => {
  const prefix = "#mrchunk=";
  if (location.hostname !== "maxpkg.dev" || !location.hash.startsWith(prefix)) return { ok: false, code: "NO_RELAY_CHUNK" };
  const fragment = location.hash.slice(prefix.length);
  history.replaceState(history.state, "", location.pathname + location.search);
  const [encodedName, type, index, total, size, base64] = fragment.split("|");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let offset = 0; offset < binary.length; offset += 1) bytes[offset] = binary.charCodeAt(offset);
  const name = decodeURIComponent(encodedName);
  const db = await new Promise((resolve, reject) => {
    const request = indexedDB.open("max-ultra-relay", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("chunks");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  await new Promise((resolve, reject) => {
    const transaction = db.transaction("chunks", "readwrite");
    transaction.objectStore("chunks").put({ name, type, index: Number(index), total: Number(total), size: Number(size), blob: new Blob([bytes]) }, name + ":" + index);
    transaction.oncomplete = resolve;
    transaction.onerror = () => reject(transaction.error);
  });
  const stored = await new Promise((resolve, reject) => {
    const request = db.transaction("chunks").objectStore("chunks").count();
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  db.close();
  return { ok: true, index: Number(index), total: Number(total), bytes: bytes.length, stored };
})();
```

Chunk assembler:

```javascript
(async () => {
  // Fill these values before running: the file name, its SHA-256, and its size in bytes.
  const expected = { name: "<FILE NAME>", sha256: "<SHA-256>", size: 0 };
  const selector = 'input.file-dropzone__input[accept=".mzp"]';
  if (location.hostname !== "maxpkg.dev") return { ok: false, code: "WRONG_PAGE" };
  const db = await new Promise((resolve, reject) => {
    const request = indexedDB.open("max-ultra-relay", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("chunks");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  const records = await new Promise((resolve, reject) => {
    const request = db.transaction("chunks").objectStore("chunks").getAll();
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  db.close();
  const removeDatabase = () => new Promise((resolve) => {
    const request = indexedDB.deleteDatabase("max-ultra-relay");
    request.onsuccess = request.onerror = request.onblocked = () => resolve();
  });
  const parts = records.filter((record) => record.name === expected.name).sort((left, right) => left.index - right.index);
  const total = parts.length ? parts[0].total : 0;
  const complete = parts.length > 0 && parts.length === total && parts.every((record, index) => record.index === index && record.total === total && record.size === expected.size);
  if (!complete) { await removeDatabase(); return { ok: false, code: "CHUNKS_INCOMPLETE", count: parts.length, total }; }
  const file = new File(parts.map((record) => record.blob), expected.name, { type: parts[0].type || "application/octet-stream" });
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", await file.arrayBuffer()));
  const sha256 = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
  await removeDatabase();
  if (file.size !== expected.size || sha256 !== String(expected.sha256).toLowerCase()) return { ok: false, code: "HASH_MISMATCH", size: file.size, sha256 };
  const matches = document.querySelectorAll(selector);
  if (matches.length !== 1 || matches[0].type !== "file") return { ok: false, code: "INPUT_NOT_FOUND", count: matches.length, sha256 };
  const transfer = new DataTransfer();
  transfer.items.add(file);
  matches[0].files = transfer.files;
  matches[0].dispatchEvent(new Event("change", { bubbles: true }));
  return { ok: true, name: file.name, size: file.size, sha256 };
})();
```

## relay.html listing

The canonical file is [`scripts/relay.html`](../scripts/relay.html). A skill loaded through `max_skill_read` exposes only its Markdown and text files, so recreate the page byte for byte from this listing when the `scripts` folder is not readable, and delete the copy afterwards.

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>Max Ultra MCP file relay</title>
<style>
  body { margin: 0; padding: 24px; background: #1f1f1f; color: #e8e8e8; font: 14px/1.5 system-ui, sans-serif; }
  pre { margin: 0; white-space: pre-wrap; }
</style>
</head>
<body>
<pre id="status">Preparing files...</pre>
<script>
"use strict";
// Carries local release files into a maxpkg.dev tab through the URL fragment.
// Usage: relay.html?target=<encoded https://maxpkg.dev page URL>&files=<encoded comma-separated file names>
// Each fragment part is encodeURIComponent(name)|type|base64; parts are joined with ";".
// Chunk mode for one large file: add &chunk=<zero-based index>&chunkSize=<bytes>.
// The fragment is then #mrchunk=encodeURIComponent(name)|type|index|total|size|base64.
(async () => {
  const MAX_URL_LENGTH = 2000000;
  const status = document.getElementById("status");
  const show = (text) => { status.textContent = text; };
  const toBase64 = (bytes) => {
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(offset, offset + 0x8000));
    return btoa(binary);
  };
  try {
    const query = new URLSearchParams(location.search);
    const target = new URL(query.get("target") || "about:blank");
    if (target.protocol !== "https:" || target.hostname !== "maxpkg.dev") throw new Error("The target must be an https://maxpkg.dev page.");
    const names = (query.get("files") || "").split(",").map((name) => name.trim()).filter(Boolean);
    if (!names.length) throw new Error("No files were requested.");
    const chunked = query.has("chunk");
    if (chunked && names.length !== 1) throw new Error("Chunk mode sends exactly one file.");
    const parts = [];
    for (const name of names) {
      if (/[\\/:]/.test(name) || name.startsWith(".")) throw new Error("Invalid file name: " + name);
      const response = await fetch("files/" + encodeURIComponent(name), { cache: "no-store" });
      if (!response.ok) throw new Error("Cannot read " + name + " (HTTP " + response.status + ").");
      const bytes = new Uint8Array(await response.arrayBuffer());
      const type = (response.headers.get("content-type") || "application/octet-stream").split(";")[0].trim();
      if (chunked) {
        const chunkSize = Number(query.get("chunkSize"));
        const index = Number(query.get("chunk"));
        if (!Number.isInteger(chunkSize) || chunkSize < 1) throw new Error("chunkSize must be a positive whole number of bytes.");
        const total = Math.max(1, Math.ceil(bytes.length / chunkSize));
        if (!Number.isInteger(index) || index < 0 || index >= total) throw new Error("chunk must be between 0 and " + (total - 1) + ".");
        const slice = bytes.subarray(index * chunkSize, Math.min(bytes.length, (index + 1) * chunkSize));
        parts.push(encodeURIComponent(name) + "|" + type + "|" + index + "|" + total + "|" + bytes.length + "|" + toBase64(slice));
        show("Prepared chunk " + (index + 1) + " of " + total + "...");
      } else {
        parts.push(encodeURIComponent(name) + "|" + type + "|" + toBase64(bytes));
        show("Prepared " + parts.length + " of " + names.length + " files...");
      }
    }
    target.hash = "";
    const url = target.href + (chunked ? "#mrchunk=" : "#mrfiles=") + parts.join(";");
    if (url.length > MAX_URL_LENGTH) throw new Error("The relay URL has " + url.length + " characters; the limit is " + MAX_URL_LENGTH + ". Send fewer or smaller files, or use a smaller chunkSize.");
    show("Opening " + target.origin + target.pathname + "...");
    location.replace(url);
  } catch (error) {
    show("Relay failed: " + error.message);
  }
})();
</script>
</body>
</html>
```
