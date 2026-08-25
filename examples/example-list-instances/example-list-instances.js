/*
 * Lists connected 3ds Max instances without modifying any scene or UI state.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { BridgeControlClient } = require("../../core/bridge-control-client");

async function listInstancesExample(options = {}) {
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 10000 });
  const ownsClient = !options.client;
  try {
    await client.connect();
    const inventory = await client.listInstances();
    (options.output || process.stdout).write(`Connected 3ds Max instances: ${inventory.count}\n${JSON.stringify(inventory.instances, null, 2)}\n`);
    return inventory;
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) void listInstancesExample().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});

module.exports = { listInstancesExample };
