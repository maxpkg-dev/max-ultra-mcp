/*
 * Windows UI Automation and native HWND adapter scoped to one 3dsmax.exe process.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { execFile } = require("node:child_process");
const path = require("node:path");

const helperPath = path.resolve(__dirname, "..", "scripts", "max-ui-automation.ps1");

function runUiAutomation(processId, operation, payload = {}, timeoutMs = 15000) {
  const encodedPayload = Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
  const args = [
    "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
    "-File", helperPath,
    "-TargetProcessId", String(processId),
    "-Operation", operation,
    "-PayloadBase64", encodedPayload,
  ];
  return new Promise((resolve, reject) => {
    execFile("powershell.exe", args, {
      windowsHide: true,
      encoding: "utf8",
      timeout: Math.max(1000, timeoutMs),
      maxBuffer: 8 * 1024 * 1024,
    }, (error, stdout, stderr) => {
      if (error) {
        const details = String(stderr || stdout || error.message).trim();
        reject(new Error(`Windows UI Automation failed: ${details}`));
        return;
      }
      try {
        const lines = String(stdout).trim().split(/\r?\n/).filter(Boolean);
        const parsed = JSON.parse(lines.at(-1) || "{}");
        if (!parsed.ok) throw new Error(parsed.error || "UI Automation returned no result");
        resolve(parsed.data);
      } catch (parseError) {
        reject(new Error(`Windows UI Automation returned invalid JSON: ${parseError.message}`));
      }
    });
  });
}

module.exports = { runUiAutomation };
