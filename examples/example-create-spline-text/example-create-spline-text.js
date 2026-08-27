/*
 * Creates and frames an extruded 3DGROUND - Max Ultra MCP spline Text shape without saving the scene.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { BridgeControlClient } = require("../../core/bridge-control-client");

const MCP_TITLE_OBJECT_NAME = "MaxUltraMCP_Title";
const MCP_TITLE_TEXT = "3DGROUND - Max Ultra MCP";

async function createSplineTextExample(options = {}) {
  const maxscript = `(
    if (getNodeByName "${MCP_TITLE_OBJECT_NAME}" exact: true != undefined) do throw "${MCP_TITLE_OBJECT_NAME} already exists"
    local titleShape = text name: "${MCP_TITLE_OBJECT_NAME}" text: "${MCP_TITLE_TEXT}" size: 20.0 pos: [0,0,0] wirecolor: (color 80 220 140)
    titleShape.alignment = 2
    addModifier titleShape (Extrude amount: 2.0)
    select titleShape
    max tool zoomextents
    "Created and framed ${MCP_TITLE_TEXT}"
  )`;
  const client = options.client || new BridgeControlClient({ timeoutMs: options.timeoutMs || 35000 });
  const ownsClient = options.client === undefined;
  try {
    await client.connect();
    const toolResponse = await client.callTool("max_execute", { script: maxscript, activity: "Create spline title", timeout_ms: 30000 });
    (options.output || process.stdout).write(`SUCCESS:\n${JSON.stringify(toolResponse, null, 2)}\n`);
    return toolResponse;
  } finally {
    if (ownsClient) client.close();
  }
}

if (require.main === module) void createSplineTextExample().catch((error) => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});

module.exports = { MCP_TITLE_OBJECT_NAME, MCP_TITLE_TEXT, createSplineTextExample };
