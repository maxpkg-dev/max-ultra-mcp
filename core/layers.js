/*
 * Validates layer operations and generates one bounded main-thread layer transaction.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { createPlanToken, canonicalString } = require("./plan-token");
const layerSource = fs.readFileSync(path.join(__dirname, "layers.ms"), "utf8");
const READ_OPERATIONS = new Set(["list", "get", "get_nodes"]);
const PLAN_OPERATIONS = new Set(["delete", "merge", "remove_empty"]);
const BOOLEAN_PROPERTIES = ["isHidden", "isFrozen", "renderable", "inheritVisibility", "primaryVisibility", "secondaryVisibility", "receiveShadows", "castShadows", "applyAtmospherics", "renderOccluded", "boxMode", "backfaceCull", "allEdges", "vertexTicks", "showTrajectory", "xray", "ignoreExtents", "showFrozenInGray", "isGIExcluded"];
const BY_LAYER_PROPERTIES = ["displayByLayer", "renderByLayer", "colorByLayer", "motionByLayer", "globalIlluminationByLayer"];
const layerSelector = {
  type: ["object", "null"], description: "Use a returned LayerRef (handle, instanceId, sceneId). {name} performs an explicit current-name lookup; never a stale-reference fallback. null means top-level only for parent fields.",
  properties: { handle: { type: "integer", minimum: 1 }, instanceId: { type: "string", minLength: 1 }, sceneId: { type: "string", minLength: 1 }, name: { type: "string", minLength: 1, maxLength: 128 } }, additionalProperties: false,
};
const layerProperties = { type: "object", properties: Object.fromEntries(BOOLEAN_PROPERTIES.map(key => [key, { type: "boolean" }])), additionalProperties: false };
layerProperties.properties.wireColor = { type: "array", items: { type: "integer", minimum: 0, maximum: 255 }, minItems: 3, maxItems: 3 };
layerProperties.properties.visibility = { type: "number", minimum: 0, maximum: 1 };
const byLayer = { type: "object", properties: Object.fromEntries(BY_LAYER_PROPERTIES.map(key => [key, { type: "boolean" }])), additionalProperties: false };

function layerTools({ tool, schema, readOnly, write, objectRef }) {
  const page = { offset: { type: "integer", minimum: 0, default: 0 }, limit: { type: "integer", minimum: 1, maximum: 200, default: 100 } };
  const dry = { dryRun: { type: "boolean", default: false } };
  const plan = { ...dry, preview: { type: "boolean", default: true }, planToken: { type: "string", minLength: 64, maxLength: 64, description: "Token returned by preview in this MCP session; repeat identical arguments with preview:false." } };
  const children = { type: "string", enum: ["reject", "reparent", "deleteBranch"], default: "reject" };
  return [
    tool("max_layer_list", "List paginated layers with parent references, direct node/child counts and own properties. parent:null lists roots; a parent reference lists its immediate children. Contains filter is case-insensitive.", schema({ ...page, parent: layerSelector, filter: { type: "string", maxLength: 128 }, includeDescendants: { type: "boolean", default: false } }), readOnly),
    tool("max_layer_get", "Inspect a layer, scene-bound identity and own properties. Layer settings do not imply effective object visibility or By Layer mode.", schema({ layer: layerSelector }, ["layer"]), readOnly),
    tool("max_layer_create", "Create or get a layer by name, optionally parented. An existing layer must already have the requested parent.", schema({ name: { type: "string", minLength: 1, maxLength: 128 }, parent: layerSelector, ...dry }, ["name"]), write),
    tool("max_layer_rename", "Rename a scene-bound layer, preserving its identity; reject conflicts and layer 0.", schema({ layer: layerSelector, name: { type: "string", minLength: 1, maxLength: 128 }, ...dry }, ["layer", "name"]), write),
    tool("max_layer_set_parent", "Reparent a layer; parent:null moves to the top level. Reject cycles and layer 0.", schema({ layer: layerSelector, parent: layerSelector, ...dry }, ["layer", "parent"]), write),
    tool("max_layer_set_current", "Make a verified layer current without changing object selection.", schema({ layer: layerSelector, ...dry }, ["layer"]), write),
    tool("max_layer_set_properties", "Set own layer properties. includeDescendants explicitly expands scope; byLayer changes node inheritance only when supplied. Unsupported properties abort before changes.", schema({ layer: layerSelector, properties: layerProperties, byLayer, includeDescendants: { type: "boolean", default: false }, ...dry }, ["layer"]), write),
    tool("max_layer_get_nodes", "Return paginated NodeRefs and actual node visibility/frozen/By Layer flags for a layer or explicit descendant scope.", schema({ layer: layerSelector, includeDescendants: { type: "boolean", default: false }, ...page }, ["layer"]), readOnly),
    tool("max_layer_assign", "Assign a node batch to a layer after validating every NodeRef. Legacy name creates a missing layer; layer requires an existing target. Never changes By Layer flags implicitly.", schema({ name: { type: "string", minLength: 1, maxLength: 128 }, layer: layerSelector, nodes: { type: "array", items: objectRef, minItems: 1, maxItems: 2000 }, ...dry }, ["nodes"]), write),
    tool("max_layer_select_nodes", "Replace, add or remove layer nodes in the selection; descendant scope is explicit.", schema({ layer: layerSelector, includeDescendants: { type: "boolean", default: false }, mode: { type: "string", enum: ["replace", "add", "remove"], default: "replace" }, ...dry }, ["layer"]), write),
    tool("max_layer_delete", "Preview deletion (default). Empty leaf only unless explicit node/child policies supplied. Apply requires a fresh preview token; replacementCurrent is mandatory when deleting the current layer. Never use forceDelete to delete geometry.", schema({ layer: layerSelector, nodePolicy: { type: "string", enum: ["reject", "move", "delete"], default: "reject" }, destination: layerSelector, childPolicy: children, childParent: layerSelector, replacementCurrent: layerSelector, ...plan }, ["layer"]), write),
    tool("max_layer_merge", "Preview moving source contents to destination and removing source layers after verified moves. Child policy must reject, reparent, or flatten explicitly. Apply needs a preview token.", schema({ sources: { type: "array", items: layerSelector, minItems: 1, maxItems: 100 }, destination: layerSelector, childPolicy: { type: "string", enum: ["reject", "reparent", "flatten"], default: "reject" }, replacementCurrent: layerSelector, ...plan }, ["sources", "destination"]), write),
    tool("max_layer_remove_empty", "Preview removal of empty leaves/wholly empty branches in an explicit root scope (null means scene). Protect layer 0 and branches containing nodes. Apply requires a preview token.", schema({ root: layerSelector, replacementCurrent: layerSelector, ...plan }, ["root"]), write),
  ];
}

function invalid(message) { throw new Error(`VALIDATION_FAILED: ${message}`); }
function maxLiteral(value) {
  if (value === null || value === undefined) return "undefined";
  if (typeof value === "boolean") return String(value);
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  if (typeof value === "string") return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n").replace(/\t/g, "\\t")}"`;
  if (Array.isArray(value)) return `#(${value.map(maxLiteral).join(",")})`;
  if (value && typeof value === "object") return maxLiteral(Object.entries(value));
  invalid("Unsupported layer argument value");
}
function normalizeLayerRequest(toolName, args, instanceId, sceneRevision) {
  const operation = toolName.replace(/^max_layer_/, "");
  const fields = {
    list: ["parent", "filter", "includeDescendants", "offset", "limit"], get: ["layer"],
    create: ["name", "parent"], rename: ["layer", "name"], set_parent: ["layer", "parent"], set_current: ["layer"],
    set_properties: ["layer", "properties", "byLayer", "includeDescendants"],
    get_nodes: ["layer", "includeDescendants", "offset", "limit"], assign: ["layer", "name", "nodes"],
    select_nodes: ["layer", "includeDescendants", "mode"],
    delete: ["layer", "nodePolicy", "destination", "childPolicy", "childParent", "replacementCurrent"],
    merge: ["sources", "destination", "childPolicy", "replacementCurrent"], remove_empty: ["root", "replacementCurrent"],
  };
  if (!fields[operation]) invalid("Unknown layer operation");
  for (const key of Object.keys(args)) if (![...fields[operation], "instance_id", "dryRun", ...(PLAN_OPERATIONS.has(operation) ? ["preview", "planToken"] : [])].includes(key)) invalid(`Unsupported layer argument ${key}`);
  for (const key of ["dryRun", "preview", "includeDescendants"]) if (args[key] !== undefined && typeof args[key] !== "boolean") invalid(`${key} must be boolean`);
  for (const [key, max] of [["limit", 200], ["offset", 100000000]]) if (args[key] !== undefined && (!Number.isInteger(args[key]) || args[key] < (key === "limit" ? 1 : 0) || args[key] > max)) invalid(`Invalid ${key}`);
  const enums = { mode: ["replace", "add", "remove"], nodePolicy: ["reject", "move", "delete"], childPolicy: operation === "merge" ? ["reject", "reparent", "flatten"] : ["reject", "reparent", "deleteBranch"] };
  for (const [key, values] of Object.entries(enums)) if (args[key] !== undefined && !values.includes(args[key])) invalid(`Invalid ${key}`);
  for (const [key, allowed] of [["properties", [...BOOLEAN_PROPERTIES, "visibility", "wireColor"]], ["byLayer", BY_LAYER_PROPERTIES]]) if (args[key] !== undefined) {
    if (!args[key] || typeof args[key] !== "object" || Array.isArray(args[key])) invalid(`${key} must be an object`);
    for (const [property, value] of Object.entries(args[key])) {
      if (!allowed.includes(property)) invalid(`Unsupported ${key}.${property}`);
      if (property === "wireColor") {
        if (!Array.isArray(value) || value.length !== 3 || value.some(channel => !Number.isInteger(channel) || channel < 0 || channel > 255)) invalid("wireColor must contain three byte values");
      } else if (property === "visibility") {
        if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) invalid("visibility must be between 0 and 1");
      } else if (typeof value !== "boolean") invalid(`${property} must be boolean`);
    }
  }
  const request = { ...args, operation };
  delete request.instance_id; delete request.planToken; delete request.preview; delete request.dryRun;
  for (const key of ["name", "filter"]) if (request[key] !== undefined) {
    if (typeof request[key] !== "string" || /[\u0000-\u001f\u007f]/.test(request[key]) || request[key].length > 128 || (key === "name" && !request[key].trim())) invalid(`Invalid ${key}`);
    if (key === "name") request[key] = request[key].trim();
  }
  const ref = (value, nullable = false) => {
    if (value === null && nullable) return;
    if (!value || typeof value !== "object" || Array.isArray(value)) invalid("Layer selector requires a LayerRef or {name}");
    if (Object.keys(value).some(key => !["handle", "instanceId", "sceneId", "name"].includes(key))) invalid("Unknown LayerRef field");
    if (value.handle !== undefined) {
      if (!Number.isSafeInteger(value.handle) || value.handle < 1 || !value.sceneId || !value.instanceId) invalid("LayerRef requires positive handle, sceneId and instanceId");
      if (value.instanceId !== instanceId) throw new Error("STALE_LAYER_REF: layer belongs to another instance");
    } else if (typeof value.name !== "string" || !value.name.trim() || value.name.length > 128 || /[\u0000-\u001f\u007f]/.test(value.name)) invalid("Layer lookup requires a valid name");
  };
  for (const key of ["layer", "parent", "root", "destination", "childParent", "replacementCurrent"]) if (key in request) ref(request[key], ["parent", "root", "childParent"].includes(key));
  if (request.sources) {
    if (!Array.isArray(request.sources) || request.sources.length < 1 || request.sources.length > 100) invalid("sources needs 1 to 100 layers");
    request.sources.forEach(value => ref(value));
  }
  if (!["list", "create", "assign", "merge", "remove_empty"].includes(operation) && !request.layer) invalid("layer is required");
  if (["create", "rename"].includes(operation) && !request.name) invalid("name is required");
  if (operation === "assign" && Boolean(request.name) === Boolean(request.layer)) invalid("Specify exactly one of name or layer");
  if (operation === "set_parent" && !("parent" in request)) invalid("parent is required; use null for top level");
  if (operation === "remove_empty" && !("root" in request)) invalid("root scope is required; use null for scene");
  if (operation === "merge" && (!request.sources?.length || !request.destination)) invalid("sources and destination are required");
  if (operation === "assign" && (!Array.isArray(request.nodes) || !request.nodes.length || request.nodes.length > 2000)) invalid("nodes needs 1 to 2000 NodeRefs");
  if (request.nodes) for (const node of request.nodes) {
    if (!node || typeof node !== "object" || Array.isArray(node)) invalid("Invalid NodeRef");
    if (Object.keys(node).some(key => !["handle", "name", "sceneRevision"].includes(key))) invalid("Unknown NodeRef field");
    if (node.sceneRevision !== undefined && node.sceneRevision !== sceneRevision) throw new Error("STALE_NODE_REF: query fresh nodes before assigning layers");
    if (node.handle !== undefined ? (!Number.isSafeInteger(node.handle) || node.handle < 1) : !(typeof node.name === "string" && node.name.trim())) invalid("NodeRef requires handle or name");
  }
  if (operation === "set_properties" && !Object.keys(request.properties || {}).length && !Object.keys(request.byLayer || {}).length) invalid("properties or byLayer must not be empty");
  return request;
}

function generateLayerScript(request, instanceId, { preview = false, expectedFingerprint = "" } = {}) {
  return `(\nlocal layerRequest = ${maxLiteral(request)}\nlocal layerInstanceId = ${maxLiteral(instanceId)}\nlocal layerPreview = ${preview}\nlocal layerExpectedFingerprint = ${maxLiteral(expectedFingerprint)}\nlocal layerSceneEpoch = if (MaxUltraMcpActiveClient != undefined and isProperty MaxUltraMcpActiveClient #layerSceneEpoch) then MaxUltraMcpActiveClient.layerSceneEpoch else \"\"\n${layerSource}\n)`;
}

async function invokeLayerTool({ toolName, args, bridge, session, instance, revision, increment }) {
  const request = normalizeLayerRequest(toolName, args, instance.instanceId, revision);
  const planned = PLAN_OPERATIONS.has(request.operation);
  const preview = Boolean(args.dryRun || (planned && args.preview !== false));
  let storedPlan;
  if (planned && !preview) {
    storedPlan = session.layerPlans?.get(args.planToken);
    if (!storedPlan || storedPlan.instanceId !== instance.instanceId || storedPlan.revision !== revision || storedPlan.request !== canonicalString(request) || storedPlan.expiresAt < Date.now()) throw new Error("STALE_PLAN: preview the identical layer operation again in this session");
    session.layerPlans.delete(args.planToken);
  }
  const script = generateLayerScript(request, instance.instanceId, { preview, expectedFingerprint: storedPlan?.fingerprint });
  const execution = await bridge.request(instance.instanceId, "execute", script, 60000);
  if (execution?.ok === false || execution?.truncated) throw new Error("LAYER_OPERATION_FAILED: invalid or truncated Max layer response");
  let result;
  try { result = JSON.parse(execution.result); } catch { throw new Error("LAYER_OPERATION_FAILED: Max returned invalid layer JSON"); }
  if (!result.ok) throw new Error(`${result.code || "LAYER_OPERATION_FAILED"}: ${result.message || "Layer operation failed"}`);
  const nextRevision = result.changed ? increment() : revision;
  const decorate = value => {
    if (!value || typeof value !== "object") return;
    if (value.kind === "node") { delete value.kind; value.sceneRevision = nextRevision; }
    for (const child of Object.values(value)) decorate(child);
  };
  decorate(result);
  if (planned && preview) {
    const token = createPlanToken({ operation: toolName, instanceId: instance.instanceId, sceneRevision: revision, request, externalState: { fingerprint: result.fingerprint } });
    if (!session.layerPlans) session.layerPlans = new Map();
    if (session.layerPlans.size >= 32) session.layerPlans.delete(session.layerPlans.keys().next().value);
    session.layerPlans.set(token, { instanceId: instance.instanceId, revision, request: canonicalString(request), fingerprint: result.fingerprint, expiresAt: Date.now() + 300000 });
    result.planToken = token;
  }
  delete result.fingerprint;
  delete result.ok;
  return { instanceId: instance.instanceId, sceneRevision: nextRevision, ...result };
}

module.exports = { layerTools, layerSelector, BOOLEAN_PROPERTIES, BY_LAYER_PROPERTIES, READ_OPERATIONS, PLAN_OPERATIONS, normalizeLayerRequest, generateLayerScript, invokeLayerTool };
