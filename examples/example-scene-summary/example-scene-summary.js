/*
 * Prints a semantic read-only summary for the sole connected 3ds Max scene.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { BridgeControlClient } = require("../../core/bridge-control-client");

async function sceneSummaryExample(options = {}) {
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 35000 });
  const ownsClient = !options.client;
  try {
    await client.connect();
    const toolResult = await client.callTool("max_scene_summary", { details: true });
    (options.output || process.stdout).write(`SUCCESS:\n${JSON.stringify(toolResult, null, 2)}\n`);
    return toolResult;
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) void sceneSummaryExample().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});

module.exports = { sceneSummaryExample };
