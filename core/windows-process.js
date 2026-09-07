/*
 * Resolves Windows PowerShell without searching PATH or the current directory.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");

function resolveWindowsPowerShell({ env = process.env, arch = process.arch, isFile = (candidate) => {
  try { return fs.statSync(candidate).isFile(); } catch { return false; }
} } = {}) {
  const systemRoots = [env.SystemRoot, env.windir].filter((root) =>
    typeof root === "string" && /^[a-z]:[\\/]/i.test(root));
  for (const root of systemRoots) {
    const systemFolders = arch === "ia32" ? ["Sysnative", "System32"] : ["System32"];
    for (const folder of systemFolders) {
      const candidate = path.win32.join(root, folder, "WindowsPowerShell", "v1.0", "powershell.exe");
      if (isFile(candidate)) return candidate;
    }
  }
  const error = new Error("POWERSHELL_NOT_FOUND: Windows PowerShell was not found in the Windows system directories. Check the Windows installation and SystemRoot/windir environment; PATH is not used.");
  error.code = "POWERSHELL_NOT_FOUND";
  throw error;
}

module.exports = { resolveWindowsPowerShell };