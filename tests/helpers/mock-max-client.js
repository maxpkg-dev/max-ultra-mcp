/*
 * Simulates Max 2022 or 2027 for local bridge and protocol verification.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const fs = require("node:fs");
const net = require("node:net");
const { decodeField, encodeField } = require("../../core/server");

const ONE_PIXEL_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64",
);

class MockMaxClient {
  constructor(options = {}) {
    this.host = options.host || process.env.MAX_ULTRA_MCP_HOST || "127.0.0.1";
    this.port = Number(options.port ?? process.env.MAX_ULTRA_MCP_PORT ?? 47635);
    this.maxVersion = String(options.maxVersion || "2027");
    this.pid = options.pid ?? process.pid;
    this.instanceId = options.instanceId || `mock-max-${this.maxVersion}-${this.pid}`;
    this.socket = null;
    this.readBuffer = "";
    this.cancelledRequests = new Set();
    this.executeRequests = [];
    this.activityLabels = [];
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
    const activityLabel = fields.length >= 5 ? decodeField(fields[4]) : "";
    let responsePayload;
    if (actionName === "never") {
      return;
    } else if (actionName === "logs") {
      responsePayload = {
        action: actionName, available: true, source: "Max Ultra MCP panel",
        content: "[mock] Max Ultra MCP panel activity", entryCount: 2, maximumEntries: 30, mock: true,
      };
    } else if (actionName === "get_info") {
      responsePayload = {
        action: actionName, ok: true, instanceId: this.instanceId, pid: this.pid,
        maxVersion: this.maxVersion, productVersion: `mock-${this.maxVersion}`, mainThread: true,
        sampledAt: new Date().toISOString(),
        units: { systemType: "Millimeters", systemScale: 1, displayType: "Metric" },
        scene: {
          filePath: "", displayName: "Untitled", saveRequired: false, objectCount: 3, selectionCount: 0, frame: "0f",
          animation: { current: "0f", start: "0f", end: "100f" },
          statistics: {
            objects: { total: 3, geometry: 2, shapes: 1, lights: 0, cameras: 0, helpers: 0, spaceWarps: 0, systems: 0, selected: 0, hidden: 0, hiddenInViewport: 0, frozen: 0, renderable: 3, groupHeads: 0, groupMembers: 0 },
            geometry: { nodes: 2, evaluatedNodes: 2, failedNodes: 0, vertices: 16, polygons: 24, meshFaces: 24, triangles: 24, countingMode: "evaluatedMesh/getPolygonCount" },
            selection: { total: 0, geometryNodes: 0, evaluatedNodes: 0, failedNodes: 0, vertices: 0, polygons: 0, triangles: 0 },
            materials: 1, layers: 1,
          },
          render: { renderer: "MockRenderer", width: 1920, height: 1080 },
        },
        mock: true,
      };
    } else if (actionName === "execute") {
      this.executeRequests.push(actionPayload);
      this.activityLabels.push(activityLabel);
      let executionResult = `mock-result:${actionPayload}`;
      if (actionPayload.includes("Max Ultra MCP: Create polygon mesh")) {
        const nodeNameMatch = /local nodeName = ("(?:\\.|[^"\\])*")/.exec(actionPayload);
        const nodeName = nodeNameMatch ? JSON.parse(nodeNameMatch[1]) : "MockPolygonMesh";
        executionResult = `42001|${nodeName}|8|12|6|0|Editable_Poly`;
      } else if (actionPayload.includes("Max Ultra MCP: Build floor plan")) {
        const sourceNameMatch = /local sourceSplineName = ("(?:\\.|[^"\\])*")/.exec(actionPayload);
        const wallNameMatch = /local wallMeshName = ("(?:\\.|[^"\\])*")/.exec(actionPayload);
        const sourceName = sourceNameMatch ? JSON.parse(sourceNameMatch[1]) : "MCP_WallPlan_SOURCE";
        const wallName = wallNameMatch ? JSON.parse(wallNameMatch[1]) : "MCP_Walls";
        executionResult = `sourceHandle=52001;sourceSpline=${sourceName};wallHandle=52002;wallMesh=${wallName};walls=4;segments=8;openings=2;helpers=0;floor=1`;
      } else if (actionPayload.includes("Max Ultra MCP: Find material diagnostics")) {
        executionResult = JSON.stringify({
          scanned: 3,
          matched: 2,
          returned: 2,
          truncated: false,
          categories: {
            noMaterial: [
              { node: { handle: 51001, name: "Fixture_NoMaterial" }, className: "Box", layer: "Fixture", materialClass: "", emptySlots: 0, missingPaths: [] },
            ],
            invalidMaterial: [],
            emptyMultiSubSlot: [
              { node: { handle: 51002, name: "Fixture_EmptySlot" }, className: "Editable_Poly", layer: "Fixture", materialClass: "Multimaterial", emptySlots: 1, missingPaths: [] },
            ],
            unsupportedMaterial: [],
            materialMissingMaps: [],
          },
          coverage: { missingMaps: "Bitmaptexture file inputs; renderer-specific assets require max_assets_scan" },
        });
      } else if (actionPayload.includes("local b=render()")) {
        const outputPathMatch = /b\.filename=("(?:\\.|[^"\\])*")/.exec(actionPayload);
        if (outputPathMatch) {
          const outputPath = JSON.parse(outputPathMatch[1]);
          fs.writeFileSync(outputPath, ONE_PIXEL_PNG);
          executionResult = outputPath;
        }
      }
      responsePayload = {
        action: actionName, ok: true, instanceId: this.instanceId, mainThread: true,
        sourceLength: actionPayload.length, result: executionResult, resultType: "String", mock: true,
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
