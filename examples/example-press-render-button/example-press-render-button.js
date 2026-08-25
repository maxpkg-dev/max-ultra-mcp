/*
 * Starts the current production render through the MaxScript equivalent of F9.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { BridgeControlClient } = require("../../core/bridge-control-client");

const QUICK_RENDER_MAXSCRIPT = "max quick render";

async function pressRenderButtonExample(options = {}) {
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 610000 });
  const ownsClient = options.client === undefined;
  try {
    await client.connect();
    const toolResponse = await client.callTool("max_execute", {
      script: QUICK_RENDER_MAXSCRIPT,
      timeout_ms: 600000,
    });
    (options.output || process.stdout).write("Production render completed through the MaxScript F9 equivalent.\n");
    return toolResponse;
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) void pressRenderButtonExample().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});

module.exports = { QUICK_RENDER_MAXSCRIPT, pressRenderButtonExample };
