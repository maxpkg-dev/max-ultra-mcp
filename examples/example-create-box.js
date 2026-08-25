/*
 * Defines one readable real Box action for the reusable safe action runner.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

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