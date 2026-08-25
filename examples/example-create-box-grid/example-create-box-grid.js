/*
 * Creates a small named Box grid without saving or touching existing objects.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { BridgeControlClient } = require("../../core/bridge-control-client");

const GRID_BOX_NAMES = [
  "MaxUltraMCP_GridBox_01",
  "MaxUltraMCP_GridBox_02",
  "MaxUltraMCP_GridBox_03",
];

async function createBoxGridExample(options = {}) {
  const maxscript = `(
    local boxNames = #("${GRID_BOX_NAMES.join('", "')}")
    local boxPositions = #([-30,0,0], [0,0,0], [30,0,0])
    for boxIndex in 1 to boxNames.count do (
        if (getNodeByName boxNames[boxIndex] exact:true != undefined) do throw (boxNames[boxIndex] + " already exists")
    )
    local createdBoxes = #()
    for boxIndex in 1 to boxNames.count do (
        append createdBoxes (box name:boxNames[boxIndex] length:20 width:20 height:20 pos:boxPositions[boxIndex])
    )
    select createdBoxes
    "Created three Max Ultra MCP grid boxes"
  )`;
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 35000 });
  const ownsClient = !options.client;
  try {
    await client.connect();
    const toolResult = await client.callTool("max_execute", { script: maxscript, timeout_ms: 30000 });
    (options.output || process.stdout).write(`SUCCESS:\n${JSON.stringify(toolResult, null, 2)}\n`);
    return toolResult;
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) void createBoxGridExample().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});

module.exports = { GRID_BOX_NAMES, createBoxGridExample };
