/* Resizes viewport images through the Windows PowerShell helper.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";

const { execFile } = require("node:child_process");
const path = require("node:path");
const { resolveWindowsPowerShell } = require("./windows-process");

const resizeScript = path.resolve(__dirname, "..", "scripts", "resize-image.ps1");

function resizePng(filePath, width, height) {
  return new Promise((resolve, reject) => {
    execFile(resolveWindowsPowerShell(), [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
      "-File", resizeScript, "-InputPath", filePath,
      "-Width", String(width || 0), "-Height", String(height || 0),
    ], { windowsHide: true, encoding: "utf8", timeout: 30000 }, (error, stdout, stderr) => {
      if (error) return reject(new Error(`Viewport resize failed: ${String(stderr || error.message).trim()}`));
      try { resolve(JSON.parse(String(stdout).trim().split(/\r?\n/).at(-1))); }
      catch (parseError) { reject(new Error(`Viewport resize returned invalid JSON: ${parseError.message}`)); }
    });
  });
}

module.exports = { resizePng };
