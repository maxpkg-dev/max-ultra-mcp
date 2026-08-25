"use strict";

const { execFile } = require("node:child_process");
const path = require("node:path");

const resizeScript = path.resolve(__dirname, "..", "scripts", "resize-image.ps1");

function resizePng(filePath, width, height) {
  return new Promise((resolve, reject) => {
    execFile("powershell.exe", [
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
