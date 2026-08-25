/*
 * Maximizes and captures the active 3ds Max viewport, opens the PNG, and removes it after the BAT exits.
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

const CLEANUP_MODE = "--cleanup-after-process";
const PRODUCT_TEMP_DIRECTORY = path.resolve(os.tmpdir(), "3DGROUND-Max-Ultra-MCP-Examples");
const MAXIMIZE_VIEWPORT_MAXSCRIPT = `(
  local originalViewportSize = getViewSize()
  max tool maximize
  local toggledViewportSize = getViewSize()
  if ((toggledViewportSize.x * toggledViewportSize.y) < (originalViewportSize.x * originalViewportSize.y)) do max tool maximize
  completeRedraw()
  "Active viewport maximized"
)`;

function pathIsInsideDirectory(filePath, directoryPath) {
  const relativePath = path.relative(path.resolve(directoryPath), path.resolve(filePath));
  return relativePath !== "" && !relativePath.startsWith(`..${path.sep}`) && relativePath !== ".." && !path.isAbsolute(relativePath);
}

function processIsRunning(processId) {
  try {
    process.kill(processId, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

async function removeScreenshotAfterProcessExit(screenshotFilePath, watchedProcessId, options = {}) {
  const normalizedFilePath = path.resolve(screenshotFilePath);
  const normalizedProcessId = Number(watchedProcessId);
  if (!pathIsInsideDirectory(normalizedFilePath, PRODUCT_TEMP_DIRECTORY) || path.extname(normalizedFilePath).toLowerCase() !== ".png") {
    throw new Error("Screenshot cleanup refused a file outside the product temporary directory");
  }
  if (!Number.isInteger(normalizedProcessId) || normalizedProcessId <= 0) throw new Error("Screenshot cleanup requires a valid BAT process ID");

  const pollIntervalMs = options.pollIntervalMs || 500;
  while (processIsRunning(normalizedProcessId)) await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
  const maximumDeleteAttempts = options.maximumDeleteAttempts || 60;
  for (let deleteAttempt = 1; deleteAttempt <= maximumDeleteAttempts; deleteAttempt += 1) {
    try {
      fs.unlinkSync(normalizedFilePath);
      return true;
    } catch (error) {
      if (error.code === "ENOENT") return true;
      if (deleteAttempt === maximumDeleteAttempts) throw error;
      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }
  }
  return false;
}

function startCleanupWatcher(screenshotFilePath, watchedProcessId) {
  const normalizedProcessId = Number(watchedProcessId);
  if (!Number.isInteger(normalizedProcessId) || normalizedProcessId <= 0) return false;
  const cleanupProcess = spawn(process.execPath, [__filename, CLEANUP_MODE, String(normalizedProcessId), screenshotFilePath], {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  });
  cleanupProcess.unref();
  return true;
}

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
    await client.callTool("max_execute", { script: MAXIMIZE_VIEWPORT_MAXSCRIPT, timeout_ms: 10000 });
    const toolResponse = await client.callTool("max_viewport_screenshot", {});
    const sourceFilePath = path.resolve(String(toolResponse.screenshot?.filePath || ""));
    if (!sourceFilePath || !fs.statSync(sourceFilePath).isFile()) throw new Error("3ds Max did not create the viewport PNG");

    const outputDirectory = path.resolve(options.outputDirectory || PRODUCT_TEMP_DIRECTORY);
    fs.mkdirSync(outputDirectory, { recursive: true });
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const environmentOutputPath = process.env.MAX_ULTRA_MCP_EXAMPLE_SCREENSHOT_FILE;
    const savedFilePath = path.resolve(options.outputFilePath || environmentOutputPath || path.join(outputDirectory, `viewport-${timestamp}.png`));
    if (environmentOutputPath && !pathIsInsideDirectory(savedFilePath, PRODUCT_TEMP_DIRECTORY)) throw new Error("BAT requested a screenshot path outside the product temporary directory");
    if (path.extname(savedFilePath).toLowerCase() !== ".png") throw new Error("Viewport screenshot output must use the .png extension");
    fs.copyFileSync(sourceFilePath, savedFilePath, fs.constants.COPYFILE_EXCL);
    if (sourceFilePath !== savedFilePath) fs.unlinkSync(sourceFilePath);

    const opened = options.openImage === false ? false : openImageFile(savedFilePath);
    const cleanupScheduled = options.cleanupAfterProcessId
      ? startCleanupWatcher(savedFilePath, options.cleanupAfterProcessId)
      : false;
    (options.output || process.stdout).write(`Viewport PNG: ${savedFilePath}\n${opened ? "Opened in the default image viewer.\n" : ""}${cleanupScheduled ? "The PNG will be deleted after the BAT closes.\n" : ""}`);
    return { ...toolResponse, savedFilePath, opened, cleanupScheduled };
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) {
  const cleanupModeRequested = process.argv[2] === CLEANUP_MODE;
  const mainOperation = cleanupModeRequested
    ? removeScreenshotAfterProcessExit(process.argv[4], process.argv[3])
    : captureViewportScreenshotExample({ cleanupAfterProcessId: process.env.MAX_ULTRA_MCP_EXAMPLE_BAT_PID });
  void mainOperation.catch((error) => {
    if (!cleanupModeRequested) process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  MAXIMIZE_VIEWPORT_MAXSCRIPT,
  PRODUCT_TEMP_DIRECTORY,
  captureViewportScreenshotExample,
  removeScreenshotAfterProcessExit,
};
