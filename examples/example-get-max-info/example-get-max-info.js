/*
 * Prints detailed non-mutating information from the sole connected 3ds Max.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { BridgeControlClient } = require("../../core/bridge-control-client");

async function getMaxInfoExample(options = {}) {
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 35000 });
  const ownsClient = options.client === undefined;
  try {
    await client.connect();
    const toolResponse = await client.callTool("max_get_info", {});
    (options.output || process.stdout).write(`SUCCESS:\n${JSON.stringify(toolResponse, null, 2)}\n`);
    return toolResponse;
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) void getMaxInfoExample().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});

module.exports = { getMaxInfoExample };
