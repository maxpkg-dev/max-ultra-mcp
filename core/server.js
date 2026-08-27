/*
 * Exposes already-running 3ds Max processes through a local MCP server.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const readline = require("node:readline");
const { randomUUID } = require("node:crypto");
const { allToolNames } = require("./tool-catalog");
const { activityLabelForTool, invokeV1Tool, NOT_HANDLED } = require("./tool-runtime");
const { version: SERVER_VERSION } = require("./package.json");

const { ensureControlToken, readControlToken, tokenMatches } = require("./local-auth");
const CONTROL_CALLABLE_TOOLS = new Set([
  "max_list_instances",
  "max_health",
  "max_scene_summary",
  "max_get_info",
  "max_create_box",
  "max_execute",
  "max_viewport_screenshot",
  ...allToolNames,
]);

const WIRE_VERSION = "1";
const DEFAULT_HOST = process.env.MAX_ULTRA_MCP_HOST || "127.0.0.1";
const DEFAULT_PORT = Number(process.env.MAX_ULTRA_MCP_PORT || 47635);
const DEFAULT_REQUEST_TIMEOUT_MS = Number(process.env.MAX_ULTRA_MCP_TIMEOUT_MS || 5000);
const MAX_EXECUTION_TIMEOUT_MS = 600000;
const MAX_LINE_BYTES = 4 * 1024 * 1024;
const MAX_LOG_ENTRIES = 200;
let launchOwnershipRecord = null;

function writeLaunchOwnership(bridge) {
  const ownerFileValue = process.env.MAX_ULTRA_MCP_OWNER_FILE || "";
  const ownerToken = process.env.MAX_ULTRA_MCP_OWNER_TOKEN || "";
  if (!ownerFileValue || !ownerToken) return;

  const ownerFile = path.resolve(ownerFileValue);
  const launcherPid = Number(process.env.MAX_ULTRA_MCP_LAUNCHER_PID || 0);
  const ownerMaxPid = Number(process.env.MAX_ULTRA_MCP_OWNER_MAX_PID || 0);
  const launcherPath = path.resolve(process.env.MAX_ULTRA_MCP_LAUNCHER_PATH || "");
  const processStartedAtUtc = new Date(Date.now() - (process.uptime() * 1000)).toISOString();
  const record = {
    schemaVersion: 1,
    server: "max-ultra-mcp",
    ownerToken,
    ownerFile,
    ownerMaxPid,
    pid: process.pid,
    processStartedAtUtc,
    launcherPid,
    launcherStartedAtUtc: process.env.MAX_ULTRA_MCP_LAUNCHER_STARTED_AT_UTC || "",
    launcherPath,
    projectRoot: path.resolve(__dirname, ".."),
    scriptPath: path.resolve(__filename),
    host: bridge.host,
    port: bridge.port,
  };
  fs.mkdirSync(path.dirname(ownerFile), { recursive: true });
  const temporaryFile = ownerFile + "." + process.pid + ".tmp";
  fs.writeFileSync(temporaryFile, JSON.stringify(record, null, 2) + "\n", { encoding: "utf8", mode: 0o600 });
  fs.renameSync(temporaryFile, ownerFile);
  launchOwnershipRecord = record;
}

function removeLaunchOwnership() {
  if (!launchOwnershipRecord) return;
  try {
    const currentRecord = JSON.parse(fs.readFileSync(launchOwnershipRecord.ownerFile, "utf8"));
    if (currentRecord.pid === process.pid && currentRecord.ownerToken === launchOwnershipRecord.ownerToken) {
      fs.unlinkSync(launchOwnershipRecord.ownerFile);
    }
  } catch {
    // Missing, replaced, or unreadable ownership records are left untouched.
  }
  launchOwnershipRecord = null;
}

function encodeField(sourceContent) {
  const normalizedContent = String(sourceContent ?? "");
  if (!normalizedContent) return "-";
  return Buffer.from(normalizedContent, "utf8").toString("base64");
}

function decodeField(sourceContent) {
  if (!sourceContent || sourceContent === "-") return "";
  return Buffer.from(sourceContent, "base64").toString("utf8");
}

function parseBoolean(sourceContent) {
  return String(sourceContent).toLowerCase() === "true";
}

function compactInstance(instanceInfo) {
  return {
    instanceId: instanceInfo.instanceId,
    maxVersion: instanceInfo.maxVersion,
    pid: instanceInfo.pid,
    healthy: instanceInfo.healthy,
    scene: instanceInfo.scene ? {
      filePath: instanceInfo.scene.filePath,
      saveRequired: instanceInfo.scene.saveRequired,
      objectCount: instanceInfo.scene.objectCount,
    } : null,
  };
}

function finiteNumber(value, fallback, fieldName, { positive = false } = {}) {
  const numericValue = Number(value ?? fallback);
  if (!Number.isFinite(numericValue) || (positive && numericValue <= 0)) {
    throw new Error(`${fieldName} must be a ${positive ? "positive " : ""}finite number`);
  }
  return numericValue;
}

function maxScriptString(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n");
}
function textContent(payload) {
  return [{ type: "text", text: JSON.stringify(payload, null, 2) }];
}

class MaxBridge {
  constructor(options = {}) {
    this.host = options.host || DEFAULT_HOST;
    this.port = options.port ?? DEFAULT_PORT;
    this.requestTimeoutMs = options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
    this.instances = new Map();
    this.connections = new Set();
    this.controlToken = options.controlToken || ensureControlToken();
    this.pendingRequests = new Map();
    this.selectedInstanceId = "";
    this.startedAt = new Date().toISOString();
    this.shutdownHandler = options.shutdownHandler || (() => this.stop().finally(() => process.exit(0)));
    this.shutdownWhenIdle = false;
    this.shutdownScheduled = false;
    this.tcpServer = net.createServer((socket) => this.acceptConnection(socket));
    this.tcpServer.on("error", (error) => {
      process.stderr.write(`[3DGROUND | Max Ultra MCP] ERROR | TCP listener: ${error.message}\n`);
    });
  }

  start() {
    return new Promise((resolve, reject) => {
      const rejectStart = (error) => reject(error);
      this.tcpServer.once("error", rejectStart);
      this.tcpServer.listen(this.port, this.host, () => {
        this.tcpServer.off("error", rejectStart);
        const serverAddress = this.tcpServer.address();
        this.port = serverAddress.port;
        process.stderr.write(`[3DGROUND | Max Ultra MCP] RUNNING | ${this.host}:${this.port} | connected=0\n`);
        resolve(serverAddress);
      });
    });
  }

  async stop() {
    for (const instanceInfo of this.instances.values()) instanceInfo.socket.destroy();
    for (const connectionInfo of this.connections) connectionInfo.socket.destroy();
    this.connections.clear();
    this.instances.clear();
    for (const pendingRequest of this.pendingRequests.values()) {
      clearTimeout(pendingRequest.timeoutHandle);
      pendingRequest.reject(new Error("Bridge stopped"));
    }
    this.pendingRequests.clear();
    if (!this.tcpServer.listening) return;
    await new Promise((resolve) => this.tcpServer.close(resolve));
  }

  acceptConnection(socket) {
    const connectionInfo = { socket, buffer: "", instanceId: "", controlClient: false, selectedInstanceId: "", jobs: new Map() };
    this.connections.add(connectionInfo);
    socket.setEncoding("utf8");
    socket.setNoDelay(true);
    socket.on("data", (chunk) => this.readConnectionData(connectionInfo, chunk));
    socket.on("error", (error) => {
      if (connectionInfo.instanceId) this.appendLog(connectionInfo.instanceId, "error", `Socket error: ${error.message}`);
    });
    socket.on("close", () => {
      this.connections.delete(connectionInfo);
      this.removeConnection(connectionInfo);
    });
  }

  readConnectionData(connectionInfo, chunk) {
    connectionInfo.buffer += chunk;
    if (Buffer.byteLength(connectionInfo.buffer, "utf8") > MAX_LINE_BYTES) {
      connectionInfo.socket.destroy(new Error("Protocol line exceeded the 4 MiB limit"));
      return;
    }
    let newlineIndex = connectionInfo.buffer.indexOf("\n");
    while (newlineIndex !== -1) {
      const wireLine = connectionInfo.buffer.slice(0, newlineIndex).replace(/\r$/, "");
      connectionInfo.buffer = connectionInfo.buffer.slice(newlineIndex + 1);
      if (wireLine) this.handleWireLine(connectionInfo, wireLine);
      newlineIndex = connectionInfo.buffer.indexOf("\n");
    }
  }

  removeConnection(connectionInfo) {
    if (!connectionInfo.instanceId) return;
    const currentInstance = this.instances.get(connectionInfo.instanceId);
    if (!currentInstance || currentInstance.socket !== connectionInfo.socket) return;
    this.rejectPendingForInstance(connectionInfo.instanceId, "3ds Max disconnected");
    this.instances.delete(connectionInfo.instanceId);
    if (this.selectedInstanceId === connectionInfo.instanceId) this.selectedInstanceId = "";
    process.stderr.write(`[3DGROUND | Max Ultra MCP] DISCONNECTED | ${connectionInfo.instanceId} | connected=${this.instances.size}\n`);
    this.scheduleIdleShutdownIfNeeded();
  }

  scheduleIdleShutdownIfNeeded() {
    if (!this.shutdownWhenIdle || this.instances.size !== 0 || this.shutdownScheduled) return;
    this.shutdownScheduled = true;
    setTimeout(() => this.shutdownHandler(), 50);
  }

  rejectPendingForInstance(instanceId, errorMessage) {
    for (const [requestId, pendingRequest] of this.pendingRequests.entries()) {
      if (pendingRequest.instanceId !== instanceId) continue;
      clearTimeout(pendingRequest.timeoutHandle);
      this.pendingRequests.delete(requestId);
      pendingRequest.reject(new Error(errorMessage));
    }
  }

  handleWireLine(connectionInfo, wireLine) {
    const fields = wireLine.split("\t");
    const messageType = fields[0];
    try {
      if (messageType === "CONTROL") {
        void this.handleControlMessage(connectionInfo, fields);
        return;
      }
      if (connectionInfo.controlClient) throw new Error("CONTROL clients may only send CONTROL messages");
      if (messageType === "HELLO") {
        this.registerInstance(connectionInfo, fields);
        return;
      }
      if (!connectionInfo.instanceId) throw new Error("HELLO must be the first message");
      const instanceInfo = this.instances.get(connectionInfo.instanceId);
      if (!instanceInfo || instanceInfo.socket !== connectionInfo.socket) return;
      instanceInfo.lastSeen = new Date().toISOString();

      if (messageType === "STATUS") {
        instanceInfo.scene = {
          filePath: decodeField(fields[1]),
          saveRequired: parseBoolean(fields[2]),
          objectCount: Number(fields[3]),
          selectionCount: Number(fields[4]),
          frame: decodeField(fields[5]),
          sampledAt: instanceInfo.lastSeen,
        };
      } else if (messageType === "LOG") {
        this.appendLog(connectionInfo.instanceId, fields[1] || "info", decodeField(fields[3]), fields[2]);
      } else if (messageType === "RESPONSE") {
        this.resolveRequest(fields);
      } else {
        throw new Error(`Unknown message type '${messageType}'`);
      }
    } catch (error) {
      if (connectionInfo.instanceId) this.appendLog(connectionInfo.instanceId, "error", `Protocol error: ${error.message}`);
      else connectionInfo.socket.destroy(error);
    }
  }

  async handleControlMessage(connectionInfo, fields) {
    const requestId = fields[2] || "unknown";
    const sendResponse = (state, payload) => {
      if (!connectionInfo.socket.destroyed) {
        connectionInfo.socket.write(`CONTROL_RESPONSE\t${requestId}\t${state}\t${encodeField(payload)}\n`);
      }
    };
    try {
      if (fields[1] !== WIRE_VERSION) throw new Error(`Unsupported control protocol version '${fields[1]}'`);
      connectionInfo.controlClient = true;
      const operation = fields[3];
      const tokenProtected = operation === "call" || operation.startsWith("shutdown");
      const suppliedToken = decodeField(fields.at(-1));
      if (tokenProtected) {
        const currentControlToken = readControlToken() || this.controlToken;
        if (currentControlToken !== this.controlToken) this.controlToken = currentControlToken;
        if (!tokenMatches(this.controlToken, suppliedToken)) throw new Error("Control authentication failed");
      }

      let responsePayload;
      let shutdownAfterResponse = false;
      if (operation === "probe") {
        responsePayload = { server: "max-ultra-mcp", wireVersion: WIRE_VERSION, healthy: this.tcpServer.listening, authRequired: true, pid: process.pid, startedAt: this.startedAt };
      } else if (operation === "shutdown") {
        responsePayload = { server: "max-ultra-mcp", pid: process.pid, startedAt: this.startedAt, shuttingDown: true };
        shutdownAfterResponse = true;
      } else if (operation === "shutdown_owned") {
        const expectedIdentity = decodeField(fields[4]);
        const currentIdentity = JSON.stringify({ server: "max-ultra-mcp", wireVersion: WIRE_VERSION, healthy: this.tcpServer.listening, authRequired: true, pid: process.pid, startedAt: this.startedAt });
        if (!expectedIdentity || expectedIdentity !== currentIdentity) throw new Error("Server ownership identity does not match the current Max Ultra MCP process");
        responsePayload = { server: "max-ultra-mcp", pid: process.pid, startedAt: this.startedAt, shuttingDown: true, ownerMatched: true };
        shutdownAfterResponse = true;
      } else if (operation === "shutdown_when_idle") {
        this.shutdownWhenIdle = true;
        responsePayload = { server: "max-ultra-mcp", pid: process.pid, startedAt: this.startedAt, armed: true, connected: this.instances.size };
      } else if (operation === "shutdown_owned_when_idle") {
        const expectedIdentity = decodeField(fields[4]);
        const currentIdentity = JSON.stringify({ server: "max-ultra-mcp", wireVersion: WIRE_VERSION, healthy: this.tcpServer.listening, authRequired: true, pid: process.pid, startedAt: this.startedAt });
        if (!expectedIdentity || expectedIdentity !== currentIdentity) throw new Error("Server ownership identity does not match the current Max Ultra MCP process");
        this.shutdownWhenIdle = true;
        responsePayload = { server: "max-ultra-mcp", pid: process.pid, startedAt: this.startedAt, armed: true, ownerMatched: true, connected: this.instances.size };
      } else if (operation === "list") {
        responsePayload = await this.callTool("max_list_instances", {}, connectionInfo);
      } else if (operation === "call") {
        const toolName = decodeField(fields[4]);
        if (CONTROL_CALLABLE_TOOLS.has(toolName) === false) {
          throw new Error(`Control client cannot call '${toolName}'`);
        }
        const argumentText = decodeField(fields[5]);
        const toolArguments = argumentText ? JSON.parse(argumentText) : {};
        responsePayload = await this.callTool(toolName, toolArguments, connectionInfo);
      } else {
        throw new Error(`Unknown control operation '${operation}'`);
      }
      sendResponse("ok", JSON.stringify(responsePayload));
      if (shutdownAfterResponse) setTimeout(() => this.shutdownHandler(), 50);
      else if (operation === "shutdown_when_idle" || operation === "shutdown_owned_when_idle") setTimeout(() => this.scheduleIdleShutdownIfNeeded(), 50);
    } catch (error) {
      sendResponse("error", error.message);
    }
  }

  registerInstance(connectionInfo, fields) {
    if (fields[1] !== WIRE_VERSION) throw new Error(`Unsupported wire version '${fields[1]}'`);
    const instanceId = decodeField(fields[2]);
    if (!instanceId) throw new Error("HELLO omitted the instance id");
    const previousInstance = this.instances.get(instanceId);
    if (previousInstance && previousInstance.socket !== connectionInfo.socket) {
      this.rejectPendingForInstance(instanceId, "3ds Max reconnected while a request was pending");
      previousInstance.socket.end("STOP\treplaced\n");
    }
    const currentTimestamp = new Date().toISOString();
    const instanceInfo = {
      instanceId,
      pid: Number(fields[3]),
      maxVersion: decodeField(fields[4]),
      productVersion: decodeField(fields[5]),
      processStartedAt: decodeField(fields[6]),
      connectedAt: currentTimestamp,
      lastSeen: currentTimestamp,
      scene: null,
      logs: [],
      socket: connectionInfo.socket,
    };
    connectionInfo.instanceId = instanceId;
    this.instances.set(instanceId, instanceInfo);
    this.appendLog(instanceId, "info", `Registered 3ds Max ${instanceInfo.maxVersion}, pid ${instanceInfo.pid}`);
    process.stderr.write(`[3DGROUND | Max Ultra MCP] CONNECTED | Max ${instanceInfo.maxVersion} | pid=${instanceInfo.pid} | connected=${this.instances.size}\n`);
  }

  resolveRequest(fields) {
    const requestId = fields[1];
    const pendingRequest = this.pendingRequests.get(requestId);
    if (!pendingRequest) return;
    this.pendingRequests.delete(requestId);
    clearTimeout(pendingRequest.timeoutHandle);
    const responseContent = decodeField(fields[3]);
    if (fields[2] === "ok") {
      try {
        pendingRequest.resolve(JSON.parse(responseContent));
      } catch {
        pendingRequest.resolve({ message: responseContent });
      }
    } else {
      pendingRequest.reject(new Error(responseContent || "3ds Max request failed"));
    }
  }

  appendLog(instanceId, logLevel, messageContent, timestamp) {
    const instanceInfo = this.instances.get(instanceId);
    if (!instanceInfo) return;
    instanceInfo.logs.push({
      timestamp: timestamp || new Date().toISOString(),
      level: String(logLevel || "info"),
      message: String(messageContent || ""),
    });
    if (instanceInfo.logs.length > MAX_LOG_ENTRIES) instanceInfo.logs.splice(0, instanceInfo.logs.length - MAX_LOG_ENTRIES);
  }

  publicInstance(instanceInfo) {
    const heartbeatAgeMs = Date.now() - Date.parse(instanceInfo.lastSeen);
    return {
      instanceId: instanceInfo.instanceId,
      pid: instanceInfo.pid,
      maxVersion: instanceInfo.maxVersion,
      productVersion: instanceInfo.productVersion,
      processStartedAt: instanceInfo.processStartedAt,
      connectedAt: instanceInfo.connectedAt,
      lastSeen: instanceInfo.lastSeen,
      healthy: heartbeatAgeMs < 10000,
      scene: instanceInfo.scene,
    };
  }

  listInstances() {
    return [...this.instances.values()]
      .map((instanceInfo) => this.publicInstance(instanceInfo))
      .sort((firstInstance, secondInstance) => {
        return firstInstance.maxVersion.localeCompare(secondInstance.maxVersion) || firstInstance.pid - secondInstance.pid;
      });
  }

  selectInstance(instanceId, session = this) {
    if (typeof session.selectedInstanceId !== "string") session.selectedInstanceId = "";
    const requestedInstanceId = instanceId || session.selectedInstanceId;
    if (requestedInstanceId) {
      const selectedInstance = this.instances.get(requestedInstanceId);
      if (!selectedInstance) {
        if (!instanceId) session.selectedInstanceId = "";
        throw new Error(`No connected 3ds Max instance named '${requestedInstanceId}'. Inventory: ${JSON.stringify(this.listInstances())}`);
      }
      return selectedInstance;
    }
    const connectedInstances = [...this.instances.values()];
    if (connectedInstances.length === 0) throw new Error("No 3ds Max instances are connected.");
    if (connectedInstances.length > 1) {
      throw new Error(`Multiple 3ds Max instances are connected. Call max_select_instance or pass instance_id from this inventory: ${JSON.stringify(this.listInstances())}`);
    }
    return connectedInstances[0];
  }
  request(instanceId, actionName, actionPayload = "", timeoutMs = this.requestTimeoutMs, activityLabel = "") {
    const instanceInfo = this.selectInstance(instanceId);
    const requestId = randomUUID();
    return new Promise((resolve, reject) => {
      const timeoutHandle = setTimeout(() => {
        this.pendingRequests.delete(requestId);
        if (!instanceInfo.socket.destroyed) instanceInfo.socket.write(`CANCEL\t${requestId}\n`);
        reject(new Error(`3ds Max ${instanceInfo.instanceId} did not answer '${actionName}' within ${timeoutMs} ms; queued work was cancelled if it had not started`));
      }, timeoutMs);
      this.pendingRequests.set(requestId, { resolve, reject, timeoutHandle, instanceId: instanceInfo.instanceId });
      const wirePayload = encodeField(actionPayload);
      const wireActivityLabel = encodeField(String(activityLabel || "").slice(0, 120));
      instanceInfo.socket.write(`REQUEST\t${requestId}\t${actionName}\t${wirePayload}\t${wireActivityLabel}\n`, (error) => {
        if (!error) return;
        const pendingRequest = this.pendingRequests.get(requestId);
        if (!pendingRequest) return;
        this.pendingRequests.delete(requestId);
        clearTimeout(timeoutHandle);
        reject(error);
      });
    });
  }

  async callTool(toolName, toolArguments = {}, session = this) {
    if (typeof session.selectedInstanceId !== "string") session.selectedInstanceId = "";
    if (toolName === "max_list_instances") {
      const connectedInstances = this.listInstances();
      return {
        count: connectedInstances.length,
        selectionRequired: connectedInstances.length > 1 && !session.selectedInstanceId,
        selectedInstanceId: session.selectedInstanceId || null,
        instances: toolArguments.details ? connectedInstances : connectedInstances.map(compactInstance),
      };
    }
    if (toolName === "max_select_instance") {
      const selectedInstance = this.selectInstance(toolArguments.instance_id, session);
      session.selectedInstanceId = selectedInstance.instanceId;
      return { selected: compactInstance(this.publicInstance(selectedInstance)) };
    }

    const v1Payload = await invokeV1Tool(this, toolName, toolArguments, session);
    if (v1Payload !== NOT_HANDLED) return v1Payload;

    const instanceInfo = this.selectInstance(toolArguments.instance_id, session);
    const publicInstanceInfo = this.publicInstance(instanceInfo);
    if (toolName === "max_scene_summary") {
      const sceneSummary = await this.request(instanceInfo.instanceId, "scene_summary");
      const response = { instanceId: instanceInfo.instanceId, maxVersion: instanceInfo.maxVersion, scene: sceneSummary.scene };
      if (toolArguments.details) response.details = sceneSummary;
      return response;
    }
    if (toolName === "max_create_box") {
      const boxName = String(toolArguments.name || "MaxUltraBox").trim();
      if (!boxName || boxName.length > 128) throw new Error("name must contain 1 to 128 characters");
      const positionInput = toolArguments.position || {};
      const dimensionsInput = toolArguments.dimensions || {};
      const position = { x: finiteNumber(positionInput.x, 0, "position.x"), y: finiteNumber(positionInput.y, 0, "position.y"), z: finiteNumber(positionInput.z, 0, "position.z") };
      const dimensions = {
        length: finiteNumber(dimensionsInput.length, 20, "dimensions.length", { positive: true }),
        width: finiteNumber(dimensionsInput.width, 20, "dimensions.width", { positive: true }),
        height: finiteNumber(dimensionsInput.height, 20, "dimensions.height", { positive: true }),
      };
      const selectCreated = toolArguments.select !== false;
      const escapedName = maxScriptString(boxName);
      const script = `(
  if getNodeByName "${escapedName}" exact:true != undefined do throw "${escapedName} already exists"
  local createdBox = box name:"${escapedName}" length:${dimensions.length} width:${dimensions.width} height:${dimensions.height} pos:[${position.x},${position.y},${position.z}]
  if ${selectCreated} do select createdBox
  createdBox.name
)`;
      const execution = await this.request(instanceInfo.instanceId, "execute", script, 30000);
      const response = { instanceId: instanceInfo.instanceId, maxVersion: instanceInfo.maxVersion, box: { name: boxName, position, dimensions, selected: selectCreated } };
      if (toolArguments.details) response.details = { execution, script };
      return response;
    }
    if (toolName === "max_health") return { instance: publicInstanceInfo, health: await this.request(instanceInfo.instanceId, "health") };
    if (toolName === "max_get_info") return { instance: publicInstanceInfo, info: await this.request(instanceInfo.instanceId, "get_info", "", 30000) };
    if (toolName === "max_logs") {
      const requestedTail = Number(toolArguments.tail ?? 20);
      const logTail = Number.isFinite(requestedTail) ? Math.min(MAX_LOG_ENTRIES, Math.max(1, requestedTail)) : 20;
      return { instance: publicInstanceInfo, bridgeLogs: instanceInfo.logs.slice(-logTail), panelLog: await this.request(instanceInfo.instanceId, "logs") };
    }
    if (toolName === "max_smoke") return { instance: publicInstanceInfo, smoke: await this.request(instanceInfo.instanceId, "smoke") };
    if (toolName === "max_execute") {
      if (typeof toolArguments.script !== "string" || !toolArguments.script.trim()) throw new Error("max_execute requires a non-empty script string");
      const requestedTimeout = Number(toolArguments.timeout_ms ?? 60000);
      if (!Number.isFinite(requestedTimeout)) throw new Error("timeout_ms must be a finite number");
      const timeoutMs = Math.min(MAX_EXECUTION_TIMEOUT_MS, Math.max(1000, requestedTimeout));
      return { instance: publicInstanceInfo, execution: await this.request(instanceInfo.instanceId, "execute", toolArguments.script, timeoutMs, activityLabelForTool(toolName, toolArguments)) };
    }
    if (toolName === "max_panel") {
      const allowedActions = new Set(["show", "hide", "minimize", "restore"]);
      if (!allowedActions.has(toolArguments.action)) throw new Error("max_panel action must be show, hide, minimize, or restore");
      return { instance: publicInstanceInfo, panel: await this.request(instanceInfo.instanceId, "panel", toolArguments.action) };
    }
    if (toolName === "max_ui_list") {
      const requestedDepth = Number(toolArguments.max_depth ?? 3);
      const requestedLimit = Number(toolArguments.limit ?? 25);
      if (!Number.isFinite(requestedDepth) || !Number.isFinite(requestedLimit)) throw new Error("max_depth and limit must be finite numbers");
      const maximumDepth = Math.min(6, Math.max(0, Math.trunc(requestedDepth)));
      const maximumControls = Math.min(200, Math.max(1, Math.trunc(requestedLimit)));
      const uiScope = toolArguments.scope || "max_window";
      if (!new Set(["max_window", "popups"]).has(uiScope)) throw new Error("scope must be max_window or popups");
      const payload = [uiScope, maximumDepth, maximumControls, encodeField(toolArguments.title_contains || ""), encodeField(toolArguments.class_contains || "")].join("\t");
      const ui = await this.request(instanceInfo.instanceId, "ui_list", payload, 10000);
      if (toolArguments.details) return { instance: publicInstanceInfo, ui };
      return { instanceId: instanceInfo.instanceId, count: ui.count, truncated: ui.truncated, controls: ui.controls.map((control) => ({ hwnd: control.hwnd, text: control.text, className: control.className, depth: control.depth })) };
    }
    if (toolName === "max_ui_invoke") {
      const allowedActions = new Set(["press_button", "set_window_text", "send_message"]);
      if (!allowedActions.has(toolArguments.action)) throw new Error("action must be press_button, set_window_text, or send_message");
      if (typeof toolArguments.target_hwnd !== "string" || !/^\d+[lp]?$/i.test(toolArguments.target_hwnd)) throw new Error("target_hwnd must be the decimal handle returned by max_ui_list");
      if (toolArguments.action === "set_window_text" && typeof toolArguments.value !== "string") throw new Error("set_window_text requires value");
      if (toolArguments.action === "send_message" && !Number.isInteger(toolArguments.message)) throw new Error("send_message requires integer message");
      const payload = [toolArguments.action, encodeField(toolArguments.target_hwnd), encodeField(toolArguments.expected_text || ""), encodeField(toolArguments.expected_class || ""), String(toolArguments.message ?? 0), String(toolArguments.wparam ?? 0), String(toolArguments.lparam ?? 0), encodeField(toolArguments.value || "")].join("\t");
      const ui = await this.request(instanceInfo.instanceId, "ui_invoke", payload, 10000);
      if (toolArguments.details) return { instance: publicInstanceInfo, ui };
      return { instanceId: instanceInfo.instanceId, action: ui.uiAction, targetHwnd: ui.targetHwnd, result: ui.result };
    }
    if (toolName === "max_viewport_screenshot") {
      const screenshotPath = path.join(os.tmpdir(), `max-ultra-mcp-${randomUUID()}.png`);
      return { instanceId: instanceInfo.instanceId, maxVersion: instanceInfo.maxVersion, screenshot: await this.request(instanceInfo.instanceId, "screenshot", screenshotPath, 30000) };
    }
    throw new Error(`Unknown tool '${toolName}'`);
  }
}

const targetProperties = {
  instance_id: { type: "string", description: "Optional after max_select_instance or when only one Max is connected." },
};
const detailsProperty = { details: { type: "boolean", default: false, description: "Include verbose diagnostics only when needed." } };
const targetSchema = { type: "object", properties: targetProperties, additionalProperties: false };
const readOnlyAnnotations = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const controlAnnotations = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };

const mcpTools = [
  { name: "max_list_instances", description: "List connected 3ds Max instances. Compact unless details=true.", inputSchema: { type: "object", properties: detailsProperty, additionalProperties: false }, annotations: readOnlyAnnotations },
  { name: "max_select_instance", description: "Select the default Max for later short calls.", inputSchema: { type: "object", properties: targetProperties, required: ["instance_id"], additionalProperties: false }, annotations: controlAnnotations },
  { name: "max_scene_summary", description: "Return a concise live scene summary; no MaxScript needed.", inputSchema: { type: "object", properties: { ...targetProperties, ...detailsProperty }, additionalProperties: false }, annotations: readOnlyAnnotations },
  {
    name: "max_create_box",
    description: "Create one standard Box from semantic arguments. Refuses an existing exact name and never saves.",
    inputSchema: {
      type: "object",
      properties: {
        ...targetProperties,
        name: { type: "string", minLength: 1, maxLength: 128, default: "MaxUltraBox" },
        position: { type: "object", properties: { x: { type: "number", default: 0 }, y: { type: "number", default: 0 }, z: { type: "number", default: 0 } }, additionalProperties: false },
        dimensions: { type: "object", properties: { length: { type: "number", exclusiveMinimum: 0, default: 20 }, width: { type: "number", exclusiveMinimum: 0, default: 20 }, height: { type: "number", exclusiveMinimum: 0, default: 20 } }, additionalProperties: false },
        select: { type: "boolean", default: true },
        ...detailsProperty,
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
  },
  { name: "max_health", description: "Ping the selected Max main thread.", inputSchema: targetSchema, annotations: readOnlyAnnotations },
  { name: "max_get_info", description: "Return detailed read-only Max, scene, object-category, topology, selection, material, layer, animation, and render information.", inputSchema: targetSchema, annotations: readOnlyAnnotations },
  { name: "max_logs", description: "Return detailed server and panel diagnostics.", inputSchema: { type: "object", properties: { ...targetProperties, tail: { type: "integer", minimum: 1, maximum: MAX_LOG_ENTRIES, default: 20 } }, additionalProperties: false }, annotations: readOnlyAnnotations },
  { name: "max_smoke", description: "Run a fixed non-mutating main-thread check.", inputSchema: targetSchema, annotations: readOnlyAnnotations },
  { name: "max_execute", description: "Advanced escape hatch: execute arbitrary MaxScript. Prefer semantic tools. A specific activity name is required and is shown in the 3ds Max log.", inputSchema: { type: "object", properties: { ...targetProperties, script: { type: "string" }, activity: { type: "string", minLength: 3, maxLength: 80, description: "Required exact imperative English operation name shown in the 3ds Max activity log. Generic labels, code, filenames, and paths are rejected." }, timeout_ms: { type: "integer", minimum: 1000, maximum: MAX_EXECUTION_TIMEOUT_MS, default: 60000 } }, required: ["script", "activity"], additionalProperties: false }, annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true } },
  { name: "max_panel", description: "Show, hide, minimize, or restore the Max Ultra MCP panel.", inputSchema: { type: "object", properties: { ...targetProperties, action: { type: "string", enum: ["show", "hide", "minimize", "restore"] } }, required: ["action"], additionalProperties: false }, annotations: controlAnnotations },
  {
    name: "max_ui_list",
    description: "Inspect Max-owned UI. Compact by default; details=true adds resource/DLL/rectangle fields.",
    inputSchema: { type: "object", properties: { ...targetProperties, scope: { type: "string", enum: ["max_window", "popups"], default: "max_window" }, max_depth: { type: "integer", minimum: 0, maximum: 6, default: 3 }, limit: { type: "integer", minimum: 1, maximum: 200, default: 25 }, title_contains: { type: "string" }, class_contains: { type: "string" }, ...detailsProperty }, additionalProperties: false },
    annotations: readOnlyAnnotations,
  },
  {
    name: "max_ui_invoke",
    description: "Invoke one discovered Max-owned control with optional stale-handle guards.",
    inputSchema: { type: "object", properties: { ...targetProperties, target_hwnd: { type: "string", pattern: "^[0-9]+[LP]?$" }, action: { type: "string", enum: ["press_button", "set_window_text", "send_message"] }, expected_text: { type: "string" }, expected_class: { type: "string" }, value: { type: "string" }, message: { type: "integer", minimum: 0, maximum: 4294967295 }, wparam: { type: "integer", default: 0 }, lparam: { type: "integer", default: 0 }, ...detailsProperty }, required: ["target_hwnd", "action"], additionalProperties: false },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true },
  },
  { name: "max_viewport_screenshot", description: "Maximize the selected Max active viewport and capture it as an MCP image. The viewport remains maximized.", inputSchema: targetSchema, annotations: readOnlyAnnotations },
];
function writeRpcMessage(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

async function buildToolContent(toolName, toolPayload) {
  const content = textContent(toolPayload);
  if (toolName !== "max_viewport_screenshot") return content;
  const screenshotPath = toolPayload?.screenshot?.filePath;
  if (!screenshotPath) throw new Error("3ds Max did not return a screenshot path");
  const imageData = await fs.promises.readFile(screenshotPath);
  let temporaryFileRemoved = false;
  try {
    await fs.promises.unlink(screenshotPath);
    temporaryFileRemoved = true;
  } catch {
    temporaryFileRemoved = false;
  }
  toolPayload.screenshot.temporaryFileRemoved = temporaryFileRemoved;
  content[0] = { type: "text", text: JSON.stringify(toolPayload, null, 2) };
  content.push({ type: "image", data: imageData.toString("base64"), mimeType: toolPayload.screenshot.mimeType || "image/png" });
  return content;
}

async function handleRpcMessage(bridge, message, sendResponse = writeRpcMessage) {
  if (!message || message.jsonrpc !== "2.0" || typeof message.method !== "string") return;
  if (message.method.startsWith("notifications/")) return;
  const rpcResponse = { jsonrpc: "2.0", id: message.id };
  try {
    if (message.method === "initialize") {
      rpcResponse.result = {
        protocolVersion: message.params?.protocolVersion || "2024-11-05",
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "max-ultra-mcp", version: SERVER_VERSION },
        instructions: "Use concise semantic tools first: max_list_instances, max_select_instance, max_scene_summary, max_get_info, max_create_box, max_ui_list/invoke, and max_viewport_screenshot. Results are compact by default; use max_get_info for detailed scene statistics. max_execute is the advanced full-control escape hatch and requires the exact operation name in activity. All Max work is queued on the main thread.",
      };
    } else if (message.method === "ping") {
      rpcResponse.result = {};
    } else if (message.method === "tools/list") {
      rpcResponse.result = { tools: mcpTools };
    } else if (message.method === "tools/call") {
      try {
        const toolName = message.params?.name;
        const toolPayload = await bridge.callTool(toolName, message.params?.arguments || {});
        rpcResponse.result = { content: await buildToolContent(toolName, toolPayload), structuredContent: toolPayload, isError: false };
      } catch (error) {
        rpcResponse.result = { content: [{ type: "text", text: error.message }], isError: true };
      }
    } else {
      rpcResponse.error = { code: -32601, message: `Method not found: ${message.method}` };
    }
  } catch (error) {
    rpcResponse.error = { code: -32603, message: error.message };
  }
  sendResponse(rpcResponse);
}

async function main() {
  if (process.argv.includes("--stdio")) {
    await require("./stdio-host").main();
    return;
  }
  const daemonOnly = process.argv.includes("--daemon");
  const bridge = new MaxBridge();
  await bridge.start();
  try {
    writeLaunchOwnership(bridge);
    process.once("exit", removeLaunchOwnership);
  } catch (error) {
    process.stderr.write("[3DGROUND | Max Ultra MCP] WARNING | Ownership record was not written: " + error.message + "\n");
  }
  if (!daemonOnly) {
    const inputReader = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
    inputReader.on("line", (inputLine) => {
      if (!inputLine.trim()) return;
      let rpcMessage;
      try {
        rpcMessage = JSON.parse(inputLine);
      } catch (error) {
        writeRpcMessage({ jsonrpc: "2.0", id: null, error: { code: -32700, message: `Parse error: ${error.message}` } });
        return;
      }
      void handleRpcMessage(bridge, rpcMessage);
    });
    inputReader.on("close", () => void bridge.stop());
  }
  const shutdown = () => void bridge.stop().finally(() => process.exit(0));
  process.once("SIGINT", shutdown);
  process.once("SIGTERM", shutdown);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`[3DGROUND | Max Ultra MCP] FATAL | ${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = { MaxBridge, decodeField, encodeField, handleRpcMessage, mcpTools };
