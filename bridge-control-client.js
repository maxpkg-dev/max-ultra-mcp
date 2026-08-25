/*
 * Small loopback client for Max Ultra MCP's local control protocol.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Developed by https://3dground.net (3DGROUND)
 */

"use strict";

const net = require("node:net");
const { randomUUID } = require("node:crypto");
const { decodeField, encodeField } = require("./server");

class BridgeControlClient {
  constructor(options = {}) {
    this.host = options.host || process.env.MAX_ULTRA_MCP_HOST || "127.0.0.1";
    this.port = Number(options.port ?? process.env.MAX_ULTRA_MCP_PORT ?? 47635);
    this.timeoutMs = Number(options.timeoutMs ?? process.env.MAX_ULTRA_MCP_TIMEOUT_MS ?? 5000);
    this.socket = null;
    this.buffer = "";
    this.pendingRequests = new Map();
  }

  connect() {
    if (this.socket) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const socket = net.createConnection({ host: this.host, port: this.port });
      socket.setEncoding("utf8");
      socket.setNoDelay(true);
      socket.once("error", reject);
      socket.once("connect", () => {
        socket.off("error", reject);
        this.socket = socket;
        socket.on("data", (chunk) => this.readData(chunk));
        socket.on("error", (error) => this.rejectAll(error));
        socket.on("close", () => {
          this.rejectAll(new Error("Max Ultra MCP control connection closed"));
          this.socket = null;
        });
        resolve();
      });
    });
  }

  close() {
    if (this.socket) this.socket.end();
  }

  listInstances() {
    return this.request("list");
  }

  callTool(toolName, toolArguments = {}) {
    return this.request("call", toolName, toolArguments);
  }

  request(operation, toolName = "", toolArguments = {}) {
    if (!this.socket || this.socket.destroyed) throw new Error("Max Ultra MCP control client is not connected");
    const requestId = randomUUID();
    return new Promise((resolve, reject) => {
      const timeoutHandle = setTimeout(() => {
        this.pendingRequests.delete(requestId);
        reject(new Error(`Max Ultra MCP control request timed out after ${this.timeoutMs} ms`));
      }, this.timeoutMs);
      this.pendingRequests.set(requestId, { resolve, reject, timeoutHandle });
      const fields = ["CONTROL", "1", requestId, operation];
      if (operation === "call") fields.push(encodeField(toolName), encodeField(JSON.stringify(toolArguments)));
      this.socket.write(`${fields.join("\t")}\n`);
    });
  }

  readData(chunk) {
    this.buffer += chunk;
    let newlineIndex = this.buffer.indexOf("\n");
    while (newlineIndex !== -1) {
      const wireLine = this.buffer.slice(0, newlineIndex).replace(/\r$/, "");
      this.buffer = this.buffer.slice(newlineIndex + 1);
      this.handleLine(wireLine);
      newlineIndex = this.buffer.indexOf("\n");
    }
  }

  handleLine(wireLine) {
    const fields = wireLine.split("\t");
    if (fields[0] !== "CONTROL_RESPONSE") return;
    const pendingRequest = this.pendingRequests.get(fields[1]);
    if (!pendingRequest) return;
    this.pendingRequests.delete(fields[1]);
    clearTimeout(pendingRequest.timeoutHandle);
    const responseText = decodeField(fields[3]);
    if (fields[2] === "ok") {
      try {
        pendingRequest.resolve(JSON.parse(responseText));
      } catch {
        pendingRequest.resolve(responseText);
      }
    } else {
      pendingRequest.reject(new Error(responseText || "Max Ultra MCP control request failed"));
    }
  }

  rejectAll(error) {
    for (const pendingRequest of this.pendingRequests.values()) {
      clearTimeout(pendingRequest.timeoutHandle);
      pendingRequest.reject(error);
    }
    this.pendingRequests.clear();
  }
}

module.exports = { BridgeControlClient };