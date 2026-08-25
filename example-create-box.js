/* Real Max Ultra MCP example: one standard Box, one safe reusable action helper. */

"use strict";

const { runMaxAction } = require("./run-max-action");

const TEST_BOX_NAME = "MaxUltraMCP_TestBox";

function createTestBox(options = {}) {
  const maxscript = `(
    if getNodeByName "${TEST_BOX_NAME}" exact:true != undefined do throw "${TEST_BOX_NAME} already exists"
    box name:"${TEST_BOX_NAME}" length:20 width:20 height:20 pos:[0,0,0]
    "Created ${TEST_BOX_NAME} at [0,0,0]"
  )`;
  return runMaxAction(maxscript, options);
}

if (require.main === module) void createTestBox();

module.exports = { TEST_BOX_NAME, createTestBox };