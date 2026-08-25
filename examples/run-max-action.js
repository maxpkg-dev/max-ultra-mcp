/*
 * Provides reusable connection, discovery, routing, and error handling for local examples.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { BridgeControlClient } = require("../core/bridge-control-client");

class AmbiguousMaxInventoryError extends Error {
  constructor(inventory) {
    super(`Refusing to modify a scene while ${inventory.count} 3ds Max instances are connected.`);
    this.name = "AmbiguousMaxInventoryError";
    this.inventory = inventory;
  }
}

async function executeOnSoleMax(maxscript, options = {}) {
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 35000 });
  const ownsClient = !options.client;
  const output = options.output || process.stdout;
  try {
    await client.connect();
    const inventory = await client.listInstances();
    if (inventory.count === 0) throw new Error("No 3ds Max instances are connected to Max Ultra MCP.");
    if (inventory.count !== 1) throw new AmbiguousMaxInventoryError(inventory);

    const target = inventory.instances[0];
    output.write(`Target: Max ${target.maxVersion} | pid=${target.pid} | ${target.instanceId}\n`);
    const result = await client.callTool("max_execute", { script: maxscript, timeout_ms: options.executionTimeoutMs || 30000 });
    output.write(`SUCCESS: ${result.execution.result}\n`);
    return result;
  } finally {
    if (ownsClient) client.close();
  }
}

function reportActionError(error, errorOutput = process.stderr) {
  if (error instanceof AmbiguousMaxInventoryError) {
    errorOutput.write(`${error.message}\nLive instance inventory:\n${JSON.stringify(error.inventory.instances, null, 2)}\n`);
  } else {
    errorOutput.write(`ERROR: ${error.message}\n`);
  }
}

function runMaxAction(maxscript, options = {}) {
  const actionPromise = executeOnSoleMax(maxscript, options);
  if (options.throwOnError) return actionPromise;
  return actionPromise.catch((error) => {
    reportActionError(error, options.errorOutput);
    process.exitCode = 1;
    return null;
  });
}

module.exports = { AmbiguousMaxInventoryError, executeOnSoleMax, reportActionError, runMaxAction };