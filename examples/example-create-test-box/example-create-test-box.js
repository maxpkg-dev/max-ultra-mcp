/*
 * Creates one named Box through the semantic core client without saving the scene.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { BridgeControlClient } = require("../../core/bridge-control-client");

const TEST_BOX_NAME = "MaxUltraMCP_TestBox";

async function createTestBox(options = {}) {
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 35000 });
  const ownsClient = !options.client;
  try {
    await client.connect();
    const toolResult = await client.callTool("max_create_box", {
      name: TEST_BOX_NAME,
      position: { x: 0, y: 0, z: 0 },
      dimensions: { length: 20, width: 20, height: 20 },
      select: true,
    });
    (options.output || process.stdout).write(`SUCCESS:\n${JSON.stringify(toolResult, null, 2)}\n`);
    return toolResult;
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) void createTestBox().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});

module.exports = { TEST_BOX_NAME, createTestBox };
