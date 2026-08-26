/*
 * MCP STDIO host for the singleton Max Ultra MCP daemon.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const readline = require("node:readline");
const { BridgeControlClient } = require("./bridge-control-client");
const { getMcpTools, normalizeProfile } = require("./tool-catalog");
const { version: SERVER_VERSION } = require("./package.json");

const INSTRUCTIONS = "Control already-open Autodesk 3ds Max through semantic tools. If several Max instances are connected, list and select one explicitly. Run mutations serially. Use max_job_* for the common lifecycle of long operations; render-specific job tools remain compatible. Use max_material_find_unassigned before changing material assignments. For polygon modeling, inspect scene units, validate object-local vertices and zero-based faces, create with the unchanged validation token, then capture and inspect the viewport. For floor-plan images, interpret the image in the model, validate the structured plan, and build it with the unchanged token. The floor-plan builder preserves a source wall spline, extrudes a separate working copy, and creates door/window topology through meshOp before viewport verification. Raw image bytes are not sent to Max Ultra MCP. Use max_execute only when no semantic tool fits.";

function writeRpc(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function errorCode(error) {
  const message = String(error?.message || error || "Unknown error");
  if (/ECONNREFUSED|control client is not connected|connection closed/i.test(message)) return "BRIDGE_DOWN";
  if (/No 3ds Max instances/i.test(message)) return "MAX_NOT_CONNECTED";
  if (/Multiple 3ds Max|max_select_instance/i.test(message)) return "INSTANCE_REQUIRED";
  if (/STALE_NODE_REF/i.test(message)) return "STALE_NODE_REF";
  if (/STALE_PLAN/i.test(message)) return "STALE_PLAN";
  if (/JOB_NOT_FOUND/i.test(message)) return "JOB_NOT_FOUND";
  if (/JOB_NOT_COMPLETE/i.test(message)) return "JOB_NOT_COMPLETE";
  if (/JOB_LIMIT_REACHED/i.test(message)) return "JOB_LIMIT_REACHED";
  if (/JOB_TYPE_MISMATCH/i.test(message)) return "JOB_TYPE_MISMATCH";
  if (/MATERIAL_DIAGNOSTICS_INVALID/i.test(message)) return "MATERIAL_DIAGNOSTICS_INVALID";
  if (/VALIDATION_FAILED|must |requires |unknown wall|overlap|extends past/i.test(message)) return "VALIDATION_FAILED";
  if (/RENDERER_UNSUPPORTED/i.test(message)) return "RENDERER_UNSUPPORTED";
  if (/UI element was not found/i.test(message)) return "UI_ELEMENT_NOT_FOUND";
  if (/timed out|TIMEOUT/i.test(message)) return "TIMEOUT";
  if (/cancel/i.test(message)) return "JOB_CANCELLED";
  return "INTERNAL_ERROR";
}

function validateSchema(value, schema, field = "arguments") {
  if (!schema) return;
  const allowedTypes = Array.isArray(schema.type) ? schema.type : schema.type ? [schema.type] : [];
  if (allowedTypes.length) {
    const actual = Array.isArray(value) ? "array" : value === null ? "null" : Number.isInteger(value) ? "integer" : typeof value;
    const compatible = allowedTypes.includes(actual) || (actual === "integer" && allowedTypes.includes("number"));
    if (!compatible) throw new Error(`${field} must be ${allowedTypes.join(" or ")}`);
  }
  if (schema.enum && !schema.enum.includes(value)) throw new Error(`${field} must be one of ${schema.enum.join(", ")}`);
  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) throw new Error(`${field} is too short`);
    if (schema.maxLength !== undefined && value.length > schema.maxLength) throw new Error(`${field} is too long`);
    if (schema.pattern && !(new RegExp(schema.pattern).test(value))) throw new Error(`${field} has an invalid format`);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error(`${field} must be finite`);
    if (schema.minimum !== undefined && value < schema.minimum) throw new Error(`${field} must be >= ${schema.minimum}`);
    if (schema.maximum !== undefined && value > schema.maximum) throw new Error(`${field} must be <= ${schema.maximum}`);
    if (schema.exclusiveMinimum !== undefined && value <= schema.exclusiveMinimum) throw new Error(`${field} must be > ${schema.exclusiveMinimum}`);
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) throw new Error(`${field} needs at least ${schema.minItems} items`);
    if (schema.maxItems !== undefined && value.length > schema.maxItems) throw new Error(`${field} needs at most ${schema.maxItems} items`);
    if (schema.items) value.forEach((item, index) => validateSchema(item, schema.items, `${field}[${index}]`));
  } else if (value && typeof value === "object") {
    const properties = schema.properties || {};
    for (const required of schema.required || []) {
      if (!(required in value)) throw new Error(`${field}.${required} is required`);
    }
    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) if (!(key in properties)) throw new Error(`${field}.${key} is not supported`);
    }
    for (const [key, propertyValue] of Object.entries(value)) {
      if (properties[key]) validateSchema(propertyValue, properties[key], `${field}.${key}`);
      else if (schema.additionalProperties && typeof schema.additionalProperties === "object") validateSchema(propertyValue, schema.additionalProperties, `${field}.${key}`);
    }
  }
}

function successEnvelope(data, startedAt) {
  return {
    ok: true,
    data,
    warnings: [],
    error: null,
    hints: [],
    sceneRevision: data?.sceneRevision ?? data?.validation?.sceneRevision ?? null,
    durationMs: Date.now() - startedAt,
  };
}

function errorEnvelope(error, startedAt) {
  return {
    ok: false,
    data: null,
    warnings: [],
    error: { code: errorCode(error), message: String(error?.message || error) },
    hints: [],
    sceneRevision: null,
    durationMs: Date.now() - startedAt,
  };
}

function imageDescriptor(toolName, data) {
  if (toolName === "max_capture_viewport") return { image: data?.screenshot, remove: true };
  if (toolName === "max_ui_capture_window") return { image: data?.ui, remove: true };
  if (toolName === "max_render_get_result") return { image: data?.image, remove: false };
  if (toolName === "max_job_result") return { image: data?.image, remove: false };
  return null;
}

async function buildContent(toolName, envelope) {
  const content = [{ type: "text", text: JSON.stringify(envelope, null, 2) }];
  if (!envelope.ok) return content;
  const descriptor = imageDescriptor(toolName, envelope.data);
  const filePath = descriptor?.image?.filePath;
  if (!filePath) return content;
  const imageData = await fs.promises.readFile(filePath);
  content.push({ type: "image", data: imageData.toString("base64"), mimeType: descriptor.image.mimeType || "image/png" });
  if (descriptor.remove) {
    const temporaryRoot = path.resolve(os.tmpdir()) + path.sep;
    const resolved = path.resolve(filePath);
    if (resolved.startsWith(temporaryRoot)) await fs.promises.unlink(resolved).catch(() => {});
  }
  return content;
}

class StdioHost {
  constructor(options = {}) {
    this.profile = normalizeProfile(options.profile || process.env.MAX_ULTRA_MCP_TOOL_PROFILE || "archviz");
    this.tools = getMcpTools(this.profile);
    this.toolByName = new Map(this.tools.map((entry) => [entry.name, entry]));
    this.client = options.client || new BridgeControlClient({ timeoutMs: Number(process.env.MAX_ULTRA_MCP_TIMEOUT_MS || 600000) });
  }

  async ensureConnected() {
    if (!this.client.socket || this.client.socket.destroyed) await this.client.connect();
  }

  async handle(message, send = writeRpc) {
    if (!message || message.jsonrpc !== "2.0" || typeof message.method !== "string") return;
    if (message.method.startsWith("notifications/")) return;
    const response = { jsonrpc: "2.0", id: message.id };
    try {
      if (message.method === "initialize") {
        response.result = {
          protocolVersion: message.params?.protocolVersion || "2025-06-18",
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: "max-ultra-mcp", version: SERVER_VERSION },
          instructions: INSTRUCTIONS,
        };
      } else if (message.method === "ping") {
        response.result = {};
      } else if (message.method === "tools/list") {
        response.result = { tools: this.tools };
      } else if (message.method === "tools/call") {
        const startedAt = Date.now();
        const toolName = message.params?.name;
        const definition = this.toolByName.get(toolName);
        if (!definition) throw new Error(`Tool '${toolName}' is not enabled in profile '${this.profile}'`);
        const args = message.params?.arguments || {};
        validateSchema(args, definition.inputSchema);
        try {
          await this.ensureConnected();
          const data = await this.client.callTool(toolName, args);
          const envelope = successEnvelope(data, startedAt);
          response.result = { content: await buildContent(toolName, envelope), structuredContent: envelope, isError: false };
        } catch (error) {
          const envelope = errorEnvelope(error, startedAt);
          response.result = { content: await buildContent(toolName, envelope), structuredContent: envelope, isError: true };
        }
      } else {
        response.error = { code: -32601, message: `Method not found: ${message.method}` };
      }
    } catch (error) {
      response.error = { code: -32602, message: error.message };
    }
    send(response);
  }

  close() {
    this.client.close();
  }
}

async function main() {
  const host = new StdioHost();
  const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  input.on("line", (line) => {
    if (!line.trim()) return;
    try {
      void host.handle(JSON.parse(line));
    } catch (error) {
      writeRpc({ jsonrpc: "2.0", id: null, error: { code: -32700, message: `Parse error: ${error.message}` } });
    }
  });
  input.on("close", () => host.close());
  const shutdown = () => { host.close(); process.exit(0); };
  process.once("SIGINT", shutdown);
  process.once("SIGTERM", shutdown);
}

if (require.main === module) main().catch((error) => {
  process.stderr.write(`[3DGROUND | Max Ultra MCP] STDIO FATAL | ${error.stack || error.message}\n`);
  process.exitCode = 1;
});

module.exports = { INSTRUCTIONS, StdioHost, errorCode, main, validateSchema };
