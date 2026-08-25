/*
 * Simulates Max 2022 or 2027 for local bridge and protocol verification.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const fs = require("node:fs");
const net = require("node:net");
const { decodeField, encodeField } = require("./server");

const ONE_PIXEL_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64",
);

class MockMaxClient {
  constructor(options = {}) {
    this.host = options.host || "127.0.0.1";
    this.port = options.port ?? 47635;
    this.maxVersion = String(options.maxVersion || "2027");
    this.pid = options.pid ?? process.pid;
    this.instanceId = options.instanceId || `mock-max-${this.maxVersion}-${this.pid}`;
    this.socket = null;
    this.readBuffer = "";
    this.cancelledRequests = new Set();
    this.executeRequests = [];
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.socket = net.createConnection({ host: this.host, port: this.port });
      this.socket.setEncoding("utf8");
      this.socket.once("error", reject);
      this.socket.once("connect", () => {
        this.socket.off("error", reject);
        this.socket.on("data", (chunk) => this.readData(chunk));
        this.sendFields([
          "HELLO", "1", encodeField(this.instanceId), String(this.pid), encodeField(this.maxVersion),
          encodeField(`mock-${this.maxVersion}`), encodeField(new Date().toISOString()),
        ]);
        this.sendFields(["STATUS", encodeField(""), "false", "3", "0", encodeField("0f")]);
        resolve();
      });
    });
  }

  disconnect() {
    if (this.socket) this.socket.destroy();
  }

  sendFields(fields) {
    this.socket.write(`${fields.join("\t")}\n`);
  }

  readData(chunk) {
    this.readBuffer += chunk;
    let newlineIndex = this.readBuffer.indexOf("\n");
    while (newlineIndex !== -1) {
      const wireLine = this.readBuffer.slice(0, newlineIndex).replace(/\r$/, "");
      this.readBuffer = this.readBuffer.slice(newlineIndex + 1);
      this.handleWireLine(wireLine);
      newlineIndex = this.readBuffer.indexOf("\n");
    }
  }

  handleWireLine(wireLine) {
    const fields = wireLine.split("\t");
    if (fields[0] === "CANCEL") {
      this.cancelledRequests.add(fields[1]);
      return;
    }
    if (fields[0] !== "REQUEST") return;
    const requestId = fields[1];
    const actionName = fields[2];
    const actionPayload = decodeField(fields[3]);
    let responsePayload;
    if (actionName === "never") {
      return;
    } else if (actionName === "logs") {
      responsePayload = {
        action: actionName, available: true, source: "Max Ultra MCP panel",
        content: "[mock] Max Ultra MCP panel activity", entryCount: 2, maximumEntries: 30, mock: true,
      };
    } else if (actionName === "execute") {
      this.executeRequests.push(actionPayload);
      responsePayload = {
        action: actionName, ok: true, instanceId: this.instanceId, mainThread: true,
        sourceLength: actionPayload.length, result: `mock-result:${actionPayload}`, resultType: "String", mock: true,
      };
    } else if (actionName === "panel") {
      responsePayload = { action: actionName, ok: true, requestedAction: actionPayload, state: actionPayload, mainThread: true, mock: true };
    } else if (actionName === "ui_list") {
      const uiFields = actionPayload.split("\t");
      responsePayload = {
        action: actionName, ok: true, scope: uiFields[0], mainThread: true, count: 2, truncated: false,
        controls: [
          { hwnd: "1000", parentHwnd: "0", depth: 0, text: `Autodesk 3ds Max ${this.maxVersion}`, className: "3DSMAX", resourceId: "", dllFileName: "3dsmax.exe", rect: "[0,0,1600,900]" },
          { hwnd: "1001", parentHwnd: "1000", depth: 1, text: "Mock Button", className: "Button", resourceId: "42", dllFileName: "mock.dll", rect: "[10,10,120,30]" },
        ],
        mock: true,
      };
    } else if (actionName === "ui_invoke") {
      const uiFields = actionPayload.split("\t");
      responsePayload = {
        action: actionName, ok: true, uiAction: uiFields[0], targetHwnd: decodeField(uiFields[1]),
        targetText: decodeField(uiFields[2]) || "Mock Button", targetClass: decodeField(uiFields[3]) || "Button",
        result: "mock-invoked", mainThread: true, mock: true,
      };    } else if (actionName === "screenshot") {
      fs.writeFileSync(actionPayload, ONE_PIXEL_PNG);
      responsePayload = {
        action: actionName, ok: true, filePath: actionPayload, mimeType: "image/png",
        width: 1, height: 1, mainThread: true, mock: true,
      };
    } else {
      responsePayload = {
        action: actionName, ok: true, instanceId: this.instanceId, pid: this.pid,
        maxVersion: this.maxVersion, mainThread: true,
        scene: { filePath: "", saveRequired: false, objectCount: 3, selectionCount: 0, frame: "0f" },
        mock: true,
      };
    }
    this.sendFields(["RESPONSE", requestId, "ok", encodeField(JSON.stringify(responsePayload))]);
  }
}

async function main() {
  const maxVersion = process.argv[2] || "2027";
  const mockClient = new MockMaxClient({ maxVersion });
  await mockClient.connect();
  process.stderr.write(`[mock-max] Connected ${mockClient.instanceId}; press Ctrl+C to stop.\n`);
  process.once("SIGINT", () => { mockClient.disconnect(); process.exit(0); });
  process.once("SIGTERM", () => { mockClient.disconnect(); process.exit(0); });
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`[mock-max] ${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = { MockMaxClient };
