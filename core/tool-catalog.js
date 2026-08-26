/*
 * Public Max Ultra MCP v1 tool catalog.
 * Copyright (c) 2026 Lukianenko Vasyl
 */

"use strict";

const MAX_EXECUTION_TIMEOUT_MS = 600000;

const target = {
  instance_id: { type: "string", description: "Connected 3ds Max instance id. Optional when exactly one instance is connected or after max_select_instance." },
};
const details = { details: { type: "boolean", default: false } };
const objectRef = {
  type: "object",
  description: "Stable scene node reference. Prefer handle; name is a guarded fallback.",
  properties: {
    handle: { type: "integer", minimum: 1 },
    name: { type: "string", minLength: 1 },
    sceneRevision: { type: "integer", minimum: 0 },
  },
  additionalProperties: false,
};
const polygonFace = {
  type: ["array", "object"],
  description: "A zero-based vertex index array, or an object with vertices, materialId, and smoothingGroup.",
  items: { type: "integer", minimum: 0 },
  minItems: 3,
  maxItems: 256,
  properties: {
    vertices: { type: "array", items: { type: "integer", minimum: 0 }, minItems: 3, maxItems: 256 },
    materialId: { type: "integer", minimum: 1, maximum: 65535, default: 1 },
    smoothingGroup: { type: "integer", minimum: 0, maximum: 2147483647, default: 0 },
  },
  required: ["vertices"],
  additionalProperties: false,
};
const polygonMesh = {
  type: "object",
  description: "Object-local polygon topology. Face indices are zero-based. Physical units are converted without changing scene units.",
  properties: {
    name: { type: "string", minLength: 1, maxLength: 128, pattern: "^[^|\\r\\n\\t]+$" },
    units: { type: "string", enum: ["scene", "mm", "cm", "m", "in", "ft"], default: "scene" },
    vertices: { type: "array", items: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3 }, minItems: 3, maxItems: 10000 },
    faces: { type: "array", items: polygonFace, minItems: 1, maxItems: 20000 },
    position: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3, default: [0, 0, 0] },
    layer: { type: "string", maxLength: 128, default: "" },
    select: { type: "boolean", default: true },
    allowNonManifold: { type: "boolean", default: false },
  },
  required: ["name", "vertices", "faces"],
  additionalProperties: false,
};
const selector = {
  type: "object",
  properties: {
    hwnd: { type: "integer", minimum: 1 },
    automationId: { type: "string" },
    name: { type: "string" },
    nameContains: { type: "string" },
    className: { type: "string" },
    controlType: { type: "string" },
    index: { type: "integer", minimum: 0, default: 0 },
  },
  additionalProperties: false,
};

const readOnly = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const control = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };
const write = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false };
const openWrite = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true };

function schema(properties = {}, required = []) {
  const result = { type: "object", properties: { ...target, ...properties }, additionalProperties: false };
  if (required.length) result.required = required;
  return result;
}

function tool(name, description, inputSchema, annotations, profile = "core") {
  return { name, description, inputSchema, annotations, profile };
}

const tools = [
  tool("max_list_instances", "List live 3ds Max instances. Select explicitly when more than one is connected.", schema({ ...details }), readOnly),
  tool("max_select_instance", "Select the default 3ds Max instance for this MCP client session.", schema({}, ["instance_id"]), control),
  tool("max_capabilities", "Return Max version, active renderer, plugin hints, profiles, and supported tool capabilities.", schema(), readOnly),
  tool("max_health", "Verify daemon transport and execution on the selected Max main thread.", schema(), readOnly),
  tool("max_scene_summary", "Return concise scene state and scene revision.", schema({ ...details }), readOnly),
  tool("max_query_scene", "Return a scene snapshot only when sceneRevision differs from sinceRevision.", schema({ sinceRevision: { type: "integer", minimum: 0, default: 0 }, details: { type: "boolean", default: false } }), readOnly),
  tool("max_get_info", "Return detailed units, scene, topology, material, animation, viewport, and render information.", schema(), readOnly),
  tool("max_get_logs", "Return daemon and in-Max diagnostics.", schema({ tail: { type: "integer", minimum: 1, maximum: 200, default: 20 } }), readOnly),

  tool("max_scene_new", "Create a new empty scene without showing a confirmation dialog.", schema({ dryRun: { type: "boolean", default: false } }), write),
  tool("max_scene_open", "Open a MAX scene file.", schema({ filePath: { type: "string", minLength: 1 }, useFileUnits: { type: "boolean", default: true }, dryRun: { type: "boolean", default: false } }, ["filePath"]), write),
  tool("max_scene_save", "Save the current scene, optionally to a new MAX file.", schema({ filePath: { type: "string" }, dryRun: { type: "boolean", default: false } }), write),
  tool("max_scene_merge", "Merge a MAX scene file into the current scene.", schema({ filePath: { type: "string", minLength: 1 }, dryRun: { type: "boolean", default: false } }, ["filePath"]), write),
  tool("max_scene_reset", "Reset the current scene without a confirmation dialog.", schema({ dryRun: { type: "boolean", default: false } }), write),
  tool("max_undo", "Undo the last 3ds Max transaction.", schema(), write),
  tool("max_redo", "Redo the last undone 3ds Max transaction.", schema(), write),

  tool("max_create_box", "Create a Box and return a NodeRef.", schema({ name: { type: "string", minLength: 1, maxLength: 128, default: "MaxUltraBox" }, position: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3, default: [0, 0, 0] }, size: { type: "array", items: { type: "number", exclusiveMinimum: 0 }, minItems: 3, maxItems: 3, default: [20, 20, 20] }, select: { type: "boolean", default: true }, dryRun: { type: "boolean", default: false } }), write),
  tool("max_create_primitive", "Create a box, sphere, cylinder, plane, teapot, camera, omni, spot, or directional light.", schema({ type: { type: "string", enum: ["box", "sphere", "cylinder", "plane", "teapot", "camera", "omni", "spot", "directional"] }, name: { type: "string", minLength: 1 }, position: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3 }, parameters: { type: "object", additionalProperties: { type: ["number", "string", "boolean"] } }, dryRun: { type: "boolean", default: false } }, ["type", "name"]), write),
  tool("max_validate_polygon_mesh", "Validate object-local vertices and zero-based polygon faces without changing the scene.", schema({ mesh: polygonMesh }, ["mesh"]), readOnly),
  tool("max_create_polygon_mesh", "Create a validated Editable Poly through bounded meshOp operations and return measured topology.", schema({ mesh: polygonMesh, validationToken: { type: "string", minLength: 64, maxLength: 64 }, dryRun: { type: "boolean", default: false } }, ["mesh", "validationToken"]), write),
  tool("max_clone_object", "Clone a scene node as copy, instance, or reference.", schema({ node: objectRef, cloneType: { type: "string", enum: ["copy", "instance", "reference"], default: "copy" }, name: { type: "string" }, dryRun: { type: "boolean", default: false } }, ["node"]), write),
  tool("max_delete_objects", "Delete guarded scene nodes in one undo transaction.", schema({ nodes: { type: "array", items: objectRef, minItems: 1 }, dryRun: { type: "boolean", default: false } }, ["nodes"]), write),
  tool("max_rename_object", "Rename one guarded scene node.", schema({ node: objectRef, name: { type: "string", minLength: 1, maxLength: 128 }, dryRun: { type: "boolean", default: false } }, ["node", "name"]), write),
  tool("max_transform_object", "Set or offset node position, Euler rotation, and scale.", schema({ node: objectRef, mode: { type: "string", enum: ["set", "offset"], default: "set" }, position: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3 }, rotation: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3 }, scale: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3 }, dryRun: { type: "boolean", default: false } }, ["node"]), write),
  tool("max_select_objects", "Replace, add to, remove from, or clear the current selection.", schema({ nodes: { type: "array", items: objectRef, default: [] }, mode: { type: "string", enum: ["replace", "add", "remove", "clear"], default: "replace" } }), write),
  tool("max_layer_create", "Create or get a layer by name.", schema({ name: { type: "string", minLength: 1 }, dryRun: { type: "boolean", default: false } }, ["name"]), write, "full"),
  tool("max_layer_assign", "Assign guarded nodes to a layer.", schema({ name: { type: "string", minLength: 1 }, nodes: { type: "array", items: objectRef, minItems: 1 }, dryRun: { type: "boolean", default: false } }, ["name", "nodes"]), write, "full"),
  tool("max_add_modifier", "Add a named modifier to one guarded scene node.", schema({ node: objectRef, modifier: { type: "string", minLength: 1 }, parameters: { type: "object", additionalProperties: { type: ["number", "string", "boolean"] } }, dryRun: { type: "boolean", default: false } }, ["node", "modifier"]), openWrite, "full"),
  tool("max_material_create", "Create a standard material with optional diffuse color.", schema({ name: { type: "string", minLength: 1 }, diffuse: { type: "array", items: { type: "integer", minimum: 0, maximum: 255 }, minItems: 3, maxItems: 3 }, dryRun: { type: "boolean", default: false } }, ["name"]), write, "archviz"),
  tool("max_material_assign", "Assign a named scene material to guarded nodes.", schema({ materialName: { type: "string", minLength: 1 }, nodes: { type: "array", items: objectRef, minItems: 1 }, dryRun: { type: "boolean", default: false } }, ["materialName", "nodes"]), write, "archviz"),
  tool("max_import_file", "Import a supported file through 3ds Max with prompts disabled.", schema({ filePath: { type: "string", minLength: 1 }, dryRun: { type: "boolean", default: false } }, ["filePath"]), openWrite, "full"),
  tool("max_export_file", "Export the scene or selection through 3ds Max with prompts disabled.", schema({ filePath: { type: "string", minLength: 1 }, selectedOnly: { type: "boolean", default: false }, dryRun: { type: "boolean", default: false } }, ["filePath"]), openWrite, "full"),
  tool("max_animation_set_time", "Set the current animation frame.", schema({ frame: { type: "number" } }, ["frame"]), write, "full"),
  tool("max_animation_key_transform", "Create transform keys for a guarded node at a frame.", schema({ node: objectRef, frame: { type: "number" }, position: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3 }, rotation: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3 }, scale: { type: "array", items: { type: "number" }, minItems: 3, maxItems: 3 } }, ["node", "frame"]), write, "full"),

  tool("max_capture_viewport", "Maximize the active viewport and capture it as an MCP image. The viewport remains maximized.", schema({ width: { type: "integer", minimum: 1, maximum: 8192 }, height: { type: "integer", minimum: 1, maximum: 8192 } }), readOnly),
  tool("max_set_view", "Set active viewport to top, bottom, front, back, left, right, perspective, or user.", schema({ view: { type: "string", enum: ["top", "bottom", "front", "back", "left", "right", "perspective", "user"] } }, ["view"]), control),
  tool("max_activate_camera", "Activate a camera node in the current viewport.", schema({ camera: objectRef }, ["camera"]), control),
  tool("max_frame_selection", "Frame the current selection in the active viewport.", schema(), control),
  tool("max_zoom_extents", "Zoom the active viewport to all objects.", schema(), control),
  tool("max_set_viewport_mode", "Set wireframe, smooth-highlights, or realistic viewport mode.", schema({ mode: { type: "string", enum: ["wireframe", "smooth", "realistic"] } }, ["mode"]), control),
  tool("max_redraw_viewports", "Force a viewport redraw.", schema(), control),

  tool("max_render_settings_get", "Read active renderer and production render settings.", schema(), readOnly),
  tool("max_render_settings_set", "Set production resolution, frame range, and output path.", schema({ width: { type: "integer", minimum: 1, maximum: 32768 }, height: { type: "integer", minimum: 1, maximum: 32768 }, outputPath: { type: "string" }, frame: { type: "number" }, dryRun: { type: "boolean", default: false } }), write),
  tool("max_render_start", "Start production, region, or renderer-supported interactive render and return a job id immediately.", schema({ mode: { type: "string", enum: ["production", "region", "interactive"], default: "production" }, region: { type: "object", properties: { x: { type: "integer", minimum: 0 }, y: { type: "integer", minimum: 0 }, width: { type: "integer", minimum: 1 }, height: { type: "integer", minimum: 1 } }, required: ["x", "y", "width", "height"], additionalProperties: false }, outputPath: { type: "string" }, timeout_ms: { type: "integer", minimum: 1000, maximum: 3600000, default: 600000 } }), write),
  tool("max_render_status", "Read render job state and renderer metadata.", schema({ jobId: { type: "string", minLength: 1 } }, ["jobId"]), readOnly),
  tool("max_render_wait", "Wait for a render job to finish up to a bounded timeout.", schema({ jobId: { type: "string", minLength: 1 }, timeout_ms: { type: "integer", minimum: 0, maximum: 600000, default: 30000 } }, ["jobId"]), readOnly),
  tool("max_render_cancel", "Request cancellation of a render job and send Escape to the selected Max process.", schema({ jobId: { type: "string", minLength: 1 } }, ["jobId"]), write),
  tool("max_render_get_result", "Return a completed production render as an MCP image.", schema({ jobId: { type: "string", minLength: 1 } }, ["jobId"]), readOnly),

  tool("max_execute", "Execute unrestricted MaxScript. Prefer semantic tools when available.", schema({ script: { type: "string", minLength: 1 }, timeout_ms: { type: "integer", minimum: 1000, maximum: MAX_EXECUTION_TIMEOUT_MS, default: 60000 } }, ["script"]), openWrite),
  tool("max_run_script", "Execute MaxScript text and return its value and type.", schema({ script: { type: "string", minLength: 1 }, timeout_ms: { type: "integer", minimum: 1000, maximum: MAX_EXECUTION_TIMEOUT_MS, default: 60000 } }, ["script"]), openWrite),
  tool("max_run_script_file", "Execute a local .ms or .mse file inside 3ds Max.", schema({ filePath: { type: "string", minLength: 1 }, timeout_ms: { type: "integer", minimum: 1000, maximum: MAX_EXECUTION_TIMEOUT_MS, default: 60000 } }, ["filePath"]), openWrite),
  tool("max_run_macro", "Run a registered MacroScript by category and name.", schema({ category: { type: "string", minLength: 1 }, name: { type: "string", minLength: 1 } }, ["category", "name"]), openWrite),
  tool("max_run_action", "Run a 3ds Max Action Table command.", schema({ tableId: { type: "integer" }, actionId: { type: ["integer", "string"] } }, ["tableId", "actionId"]), openWrite),
  tool("max_get_listener_output", "Return Max Ultra MCP listener/activity output available to the bridge.", schema({ tail: { type: "integer", minimum: 1, maximum: 200, default: 20 } }), readOnly),

  tool("max_ui_list_windows", "List top-level windows owned by the selected 3dsmax.exe process.", schema({ titleContains: { type: "string" }, limit: { type: "integer", minimum: 1, maximum: 200, default: 50 } }), readOnly),
  tool("max_ui_inspect", "Inspect the bounded UI Automation tree of a Max-owned window.", schema({ window: selector, maxDepth: { type: "integer", minimum: 0, maximum: 10, default: 5 }, limit: { type: "integer", minimum: 1, maximum: 1000, default: 200 } }, ["window"]), readOnly),
  tool("max_ui_find", "Find a control inside the selected 3ds Max process using stable selector fields.", schema({ window: selector, control: selector }, ["control"]), readOnly),
  tool("max_ui_invoke", "Invoke a button, menu, checkbox, or other invokable Max-owned control.", schema({ window: selector, control: selector }, ["control"]), openWrite),
  tool("max_ui_set_value", "Set text or numeric value on a Max-owned control.", schema({ window: selector, control: selector, value: { type: ["string", "number"] } }, ["control", "value"]), openWrite),
  tool("max_ui_select", "Select a tab, list, combo, radio, or selection item in a Max-owned window.", schema({ window: selector, control: selector, item: { type: ["string", "integer"] } }, ["control", "item"]), openWrite),
  tool("max_ui_send_keys", "Focus a Max-owned control and send Windows Forms key syntax.", schema({ window: selector, control: selector, keys: { type: "string", minLength: 1 } }, ["keys"]), openWrite),
  tool("max_ui_wait", "Wait until a Max-owned window or control exists, disappears, enables, or becomes visible.", schema({ window: selector, control: selector, state: { type: "string", enum: ["exists", "missing", "enabled", "visible", "closed"], default: "exists" }, timeout_ms: { type: "integer", minimum: 0, maximum: 120000, default: 10000 } }), readOnly),
  tool("max_ui_close_window", "Close one verified Max-owned top-level window.", schema({ window: selector }, ["window"]), openWrite),
  tool("max_ui_capture_window", "Capture one verified Max-owned window as an MCP image.", schema({ window: selector }), readOnly),

  tool("max_validate_floor_plan", "Normalize and validate a structured wall/opening plan without changing the scene.", schema({ plan: { type: "object", additionalProperties: true } }, ["plan"]), readOnly, "archviz"),
  tool("max_build_floor_plan", "Build a validated floor plan from a preserved source spline, an extruded working copy, and meshOp opening topology in one undo transaction.", schema({ plan: { type: "object", additionalProperties: true }, validationToken: { type: "string", minLength: 64, maxLength: 64 }, layer: { type: "string", default: "MCP_ARCHVIZ" }, prefix: { type: "string", default: "MCP" }, dryRun: { type: "boolean", default: false } }, ["plan", "validationToken"]), write, "archviz"),
];

const profileRank = { core: 0, archviz: 1, full: 2 };

function normalizeProfile(value) {
  return Object.hasOwn(profileRank, value) ? value : "archviz";
}

function getMcpTools(profile = "archviz") {
  const normalized = normalizeProfile(profile);
  return tools
    .filter((entry) => profileRank[entry.profile] <= profileRank[normalized])
    .map(({ profile: _profile, ...entry }) => entry);
}

module.exports = {
  MAX_EXECUTION_TIMEOUT_MS,
  allToolNames: new Set(tools.map((entry) => entry.name)),
  getMcpTools,
  normalizeProfile,
  tools,
};
