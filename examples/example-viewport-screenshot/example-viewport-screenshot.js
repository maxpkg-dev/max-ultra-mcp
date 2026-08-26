/*
 * Maximizes and captures the active 3ds Max viewport, overwrites one PNG, and opens it on Windows.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { BridgeControlClient } = require("../../core/bridge-control-client");

const PRODUCT_TEMP_DIRECTORY = path.resolve(os.tmpdir(), "3DGROUND-Max-Ultra-MCP-Examples");
function openImageFile(imageFilePath) {
  if (process.platform !== "win32") return false;
  const imageViewer = spawn("rundll32.exe", ["url.dll,FileProtocolHandler", imageFilePath], {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  });
  imageViewer.unref();
  return true;
}

async function captureViewportScreenshotExample(options = {}) {
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 35000 });
  const ownsClient = options.client === undefined;
  try {
    await client.connect();
    const toolResponse = await client.callTool("max_viewport_screenshot", {});
    const sourceFilePath = path.resolve(String(toolResponse.screenshot?.filePath || ""));
    if (!sourceFilePath || !fs.statSync(sourceFilePath).isFile()) throw new Error("3ds Max did not create the viewport PNG");

    const outputDirectory = path.resolve(options.outputDirectory || PRODUCT_TEMP_DIRECTORY);
    fs.mkdirSync(outputDirectory, { recursive: true });
    const savedFilePath = path.resolve(options.outputFilePath || path.join(outputDirectory, "viewport-current.png"));
    if (path.extname(savedFilePath).toLowerCase() !== ".png") throw new Error("Viewport screenshot output must use the .png extension");
    fs.copyFileSync(sourceFilePath, savedFilePath);
    if (sourceFilePath !== savedFilePath) fs.unlinkSync(sourceFilePath);

    const opened = options.openImage === false ? false : openImageFile(savedFilePath);
    (options.output || process.stdout).write(`Viewport PNG: ${savedFilePath}\n${opened ? "Opened in the default image viewer.\n" : ""}`);
    return { ...toolResponse, savedFilePath, opened };
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) void captureViewportScreenshotExample().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});

module.exports = {
  PRODUCT_TEMP_DIRECTORY,
  captureViewportScreenshotExample,
};
