/* Guard Python package boundaries and immutable public integration contracts.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
function verify(root) {
  const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
  const files = fs.readdirSync(path.join(root, "python/max_ultra")).filter(name => name.endsWith(".py"));
  const allowlist = new Set(read("maxpkg-files.txt").split(/\r?\n/));
  for (const file of files) {
    assert.ok(allowlist.has("python/max_ultra/" + file), "Python runtime file missing from MZP: " + file);
    assert.doesNotMatch(read("python/max_ultra/" + file), /import clr|pythonnet|System\.Windows\.Forms/);
  }
  for (const name of ["bootstrap.py"]) assert.ok(allowlist.has("python/" + name));
  for (const name of ["close", "copy", "download", "expand", "heart", "panel-top-close", "plug-zap", "power", "refresh-cw", "search", "settings", "skills", "arrow-left", "folder-open", "file-archive", "trash-2", "send", "book-open", "globe"]) {
    assert.ok(allowlist.has("assets/icons/" + name + ".svg"));
    assert.match(read("assets/icons/" + name + ".svg"), /viewBox="0 0 24 24"/);
  }
  for (const name of ["codex", "claude", "antigravity"]) {
    const asset = "assets/client-logos/" + name + ".svg";
    assert.ok(allowlist.has(asset), "Vector client logo missing from MZP: " + asset);
    assert.doesNotMatch(read(asset), /<(?:mask|filter|image)\b/, "Client logos must render as vectors in Qt 5");
  }
  assert.doesNotMatch(read("python/max_ultra/dialogs.py"), /(?:codex|claude|antigravity)\.png/);
  assert.doesNotMatch(read("python/max_ultra/transport.py"), /import pymxs|from pymxs|import Qt|from PySide/);
  assert.doesNotMatch(read("core/max-operations.ms") + read("core/layers.ms") + read("scripts/maxpkg-uninstall.ms"), /dotNetObject|dotNetClass|dotNetControl/);
  assert.match(read("python/max_ultra/client.py"), /self\.api\.request/);
  assert.match(read("python/max_ultra/client.py"), /self\.transport\.inbound\.empty\(\)/);
  assert.match(read("python/max_ultra/qt.py"), /PySide6[\s\S]*PySide2/);
  assert.doesNotMatch(read("python/max_ultra/widgets.py"), /WindowStaysOnTopHint/);
}
module.exports = { verify };
