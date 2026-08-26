/* Local installation-stable per-user control token management. */

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { randomBytes, timingSafeEqual } = require("node:crypto");

function tokenFilePath() {
  if (process.env.MAX_ULTRA_MCP_TOKEN_FILE) return path.resolve(process.env.MAX_ULTRA_MCP_TOKEN_FILE);
  if (process.env.LOCALAPPDATA) {
    return path.resolve(process.env.LOCALAPPDATA, "3DGROUND", "MaxUltraMCP", "runtime", "state", "control-token");
  }
  return path.resolve(__dirname, "..", "runtime", "state", "control-token");
}

function validToken(value) {
  return typeof value === "string" && /^[a-f0-9]{64}$/i.test(value.trim());
}

function readControlToken() {
  if (validToken(process.env.MAX_ULTRA_MCP_CONTROL_TOKEN)) return process.env.MAX_ULTRA_MCP_CONTROL_TOKEN.trim().toLowerCase();
  try {
    const value = fs.readFileSync(tokenFilePath(), "utf8").trim();
    return validToken(value) ? value.toLowerCase() : "";
  } catch {
    return "";
  }
}

function ensureControlToken() {
  const existing = readControlToken();
  if (existing) return existing;
  const filePath = tokenFilePath();
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const token = randomBytes(32).toString("hex");
  try {
    fs.writeFileSync(filePath, `${token}\n`, { encoding: "utf8", mode: 0o600, flag: "wx" });
    return token;
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    const raced = readControlToken();
    if (!raced) throw new Error(`Control token file is invalid: ${filePath}`);
    return raced;
  }
}

function tokenMatches(expected, supplied) {
  if (!validToken(expected) || !validToken(supplied)) return false;
  const expectedBytes = Buffer.from(expected.toLowerCase(), "hex");
  const suppliedBytes = Buffer.from(supplied.toLowerCase(), "hex");
  return expectedBytes.length === suppliedBytes.length && timingSafeEqual(expectedBytes, suppliedBytes);
}

module.exports = { ensureControlToken, readControlToken, tokenFilePath, tokenMatches };
