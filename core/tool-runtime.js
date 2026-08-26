/* Max Ultra MCP v1 tool execution runtime. */

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { allToolNames, MAX_EXECUTION_TIMEOUT_MS } = require("./tool-catalog");
const { generateFloorPlanScript, validateFloorPlan } = require("./floor-plan");
const { JobRegistry, snapshotJob } = require("./job-registry");
const { generateMaterialDiagnosticsScript, parseMaterialDiagnostics } = require("./material-diagnostics");
const { generatePolygonMeshScript, validatePolygonMesh } = require("./polygon-mesh");
const { runUiAutomation } = require("./windows-ui");

const NOT_HANDLED = Symbol("NOT_HANDLED");

function activityLabelForTool(toolName, args = {}) {
  const labels = {
    max_execute: "Run MaxScript",
    max_run_script: "Run MaxScript",
    max_run_script_file: "Run MaxScript file",
    max_create_polygon_mesh: "Create polygon mesh",
    max_build_floor_plan: "Build floor plan",
    max_material_find_unassigned: "Find material issues",
    max_add_normal_modifier: "Add Normal modifier",
    max_capture_viewport: "Capture viewport",
    max_render_start: `Start ${args.mode || "production"} render`,
    max_render_settings_set: "Update render settings",
  };
  if (labels[toolName]) return labels[toolName];
  return String(toolName || "Max operation")
    .replace(/^max_/, "")
    .split("_")
    .filter(Boolean)
    .map((word) => word[0].toUpperCase() + word.slice(1))
    .join(" ");
}

function withActivityLabel(bridge, activityLabel) {
  return new Proxy(bridge, {
    get(target, property) {
      if (property === "request") {
        return (instanceId, actionName, actionPayload, timeoutMs, explicitLabel) => (
          target.request(instanceId, actionName, actionPayload, timeoutMs, explicitLabel || activityLabel)
        );
      }
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
    set(target, property, value) {
      return Reflect.set(target, property, value, target);
    },
  });
}

function maxString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n")}"`;
}

function finite(value, fallback, field, { positive = false } = {}) {
  const number = Number(value ?? fallback);
  if (!Number.isFinite(number) || (positive && number <= 0)) throw new Error(`${field} must be a ${positive ? "positive " : ""}finite number`);
  return number;
}

function vector3(value, fallback, field, { positive = false } = {}) {
  const input = value ?? fallback;
  if (!Array.isArray(input) || input.length !== 3) throw new Error(`${field} must contain exactly three numbers`);
  return input.map((entry, index) => finite(entry, undefined, `${field}[${index}]`, { positive }));
}

function vectorScript(value) {
  return `[${value.map((entry) => Number(entry)).join(",")}]`;
}

function ensureRuntime(bridge, session) {
  if (!bridge.sceneRevisions) bridge.sceneRevisions = new Map();
  if (!session.jobRegistry) {
    session.jobRegistry = new JobRegistry();
    session.jobs = session.jobRegistry.jobs;
  }
  return session;
}

function revisionFor(bridge, instanceId) {
  return bridge.sceneRevisions?.get(instanceId) || 0;
}

function incrementRevision(bridge, instanceId) {
  const revision = revisionFor(bridge, instanceId) + 1;
  bridge.sceneRevisions.set(instanceId, revision);
  return revision;
}

function nodeExpression(node, bridge, instanceId) {
  if (!node || typeof node !== "object") throw new Error("node must be a NodeRef object");
  if (node.sceneRevision !== undefined && Number(node.sceneRevision) !== revisionFor(bridge, instanceId)) {
    throw new Error(`STALE_NODE_REF: expected scene revision ${node.sceneRevision}, current revision is ${revisionFor(bridge, instanceId)}`);
  }
  if (Number.isInteger(Number(node.handle)) && Number(node.handle) > 0) return `(maxOps.getNodeByHandle ${Number(node.handle)})`;
  if (typeof node.name === "string" && node.name.trim()) return `(getNodeByName ${maxString(node.name.trim())} exact:true)`;
  throw new Error("NodeRef requires handle or name");
}

function dryRunResult(toolName, instance, script, extra = {}) {
  return { instanceId: instance.instanceId, dryRun: true, tool: toolName, script, ...extra };
}

async function executeMutation(bridge, instance, script, timeoutMs = 60000, extra = {}) {
  const execution = await bridge.request(instance.instanceId, "execute", script, timeoutMs);
  return { instanceId: instance.instanceId, execution, sceneRevision: incrementRevision(bridge, instance.instanceId), ...extra };
}
async function executeNodeMutation(bridge, instance, script, fallbackName, timeoutMs = 30000, extra = {}) {
  const result = await executeMutation(bridge, instance, script, timeoutMs, extra);
  const resultText = String(result.execution?.result || "");
  const parsed = /^(\d+)\|(.+)$/.exec(resultText);
  result.node = {
    ...(parsed ? { handle: Number(parsed[1]) } : {}),
    name: parsed?.[2] || fallbackName || null,
    sceneRevision: result.sceneRevision,
  };
  return result;
}

async function executePolygonMeshMutation(bridge, instance, script, validation) {
  const mutation = await executeMutation(bridge, instance, script, 600000);
  const resultText = String(mutation.execution?.result || "");
  const parsed = /^(\d+)\|([^|]+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(.+)$/.exec(resultText);
  if (!parsed) throw new Error("3ds Max returned an unexpected polygon mesh post-state");
  const actualTopology = {
    vertices: Number(parsed[3]),
    edges: Number(parsed[4]),
    faces: Number(parsed[5]),
    openEdges: Number(parsed[6]),
  };
  return {
    ...mutation,
    node: { handle: Number(parsed[1]), name: parsed[2], sceneRevision: mutation.sceneRevision },
    baseObjectClass: parsed[7],
    topology: actualTopology,
    expectedTopology: validation.counts,
    boundingBox: validation.boundingBox,
    validationToken: validation.validationToken,
    validationWarnings: validation.warnings,
  };
}


function renderSnapshot(job) {
  const common = snapshotJob(job);
  return {
    jobId: common.jobId,
    instanceId: common.instanceId,
    mode: job.mode,
    renderer: job.renderer,
    state: common.state,
    createdAt: common.createdAt,
    startedAt: common.startedAt,
    completedAt: common.completedAt,
    elapsedMs: common.elapsedMs,
    progress: common.progress,
    cancelRequested: common.cancelRequested,
    error: common.error,
    warnings: common.warnings,
  };
}

function requireRenderJob(session, jobId) {
  const job = session.jobRegistry.require(jobId);
  if (job.type !== "render") throw new Error(`JOB_TYPE_MISMATCH: job '${jobId}' is '${job.type}', not 'render'`);
  return job;
}

function verifiedRenderResult(job) {
  if (job.state !== "completed") throw new Error(`JOB_NOT_COMPLETE: job '${job.jobId}' is '${job.state}'`);
  if (!fs.existsSync(job.outputPath)) throw new Error("Completed renderer did not create the output image");
  return { ...renderSnapshot(job), image: { filePath: job.outputPath, mimeType: "image/png" } };
}

function commonJobResult(session, jobId) {
  const job = session.jobRegistry.require(jobId);
  const completed = session.jobRegistry.getResult(jobId);
  if (job.type === "render") {
    const render = verifiedRenderResult(job);
    return { ...completed, image: render.image };
  }
  return completed;
}

function waitDelay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function createPrimitiveScript(args) {
  const name = String(args.name || "").trim();
  if (!name || name.length > 128) throw new Error("name must contain 1 to 128 characters");
  const type = String(args.type || "").toLowerCase();
  const position = vector3(args.position, [0, 0, 0], "position");
  const parameters = args.parameters && typeof args.parameters === "object" ? args.parameters : {};
  const properties = Object.entries(parameters).map(([key, value]) => {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) throw new Error(`Invalid primitive parameter '${key}'`);
    const literal = typeof value === "string" ? maxString(value) : typeof value === "boolean" ? String(value) : String(finite(value, undefined, `parameters.${key}`));
    return `${key}:${literal}`;
  }).join(" ");
  const constructors = {
    box: "box", sphere: "sphere", cylinder: "cylinder", plane: "plane", teapot: "teapot",
    camera: "freeCamera", omni: "omniLight", spot: "freeSpot", directional: "freeDirectional",
  };
  const constructor = constructors[type];
  if (!constructor) throw new Error(`Unsupported primitive type '${type}'`);
  return `(
  if getNodeByName ${maxString(name)} exact:true != undefined do throw ${maxString(`${name} already exists`)}
  undo "Max Ultra MCP: Create primitive" on (
    local n = ${constructor} name:${maxString(name)} pos:${vectorScript(position)} ${properties}
    select n
    ((getHandleByAnim n) as string) + "|" + n.name
  )
)`;
}

async function invokeV1Tool(bridge, toolName, args = {}, session = bridge) {
  if (!allToolNames.has(toolName)) return NOT_HANDLED;
  bridge = withActivityLabel(bridge, activityLabelForTool(toolName, args));
  ensureRuntime(bridge, session);

  if (toolName === "max_validate_polygon_mesh") return validatePolygonMesh(args.mesh);
  if (toolName === "max_validate_floor_plan") return validateFloorPlan(args.plan);

  if (toolName === "max_job_list") {
    const jobs = session.jobRegistry.list(args);
    return { jobs, count: jobs.length };
  }
  if (toolName === "max_job_status") return session.jobRegistry.snapshot(args.jobId);
  if (toolName === "max_job_wait") return session.jobRegistry.wait(args.jobId, args.timeout_ms);
  if (toolName === "max_job_cancel") return session.jobRegistry.cancelJob(args.jobId);
  if (toolName === "max_job_result") return commonJobResult(session, args.jobId);

  if (["max_render_status", "max_render_wait", "max_render_cancel", "max_render_get_result"].includes(toolName)) {
    const job = requireRenderJob(session, args.jobId);
    if (toolName === "max_render_status") return renderSnapshot(job);
    if (toolName === "max_render_wait") {
      await session.jobRegistry.wait(args.jobId, args.timeout_ms);
      return renderSnapshot(job);
    }
    if (toolName === "max_render_get_result") return verifiedRenderResult(job);
    await session.jobRegistry.cancelJob(args.jobId);
    return renderSnapshot(job);
  }

  const instance = bridge.selectInstance(args.instance_id, session);
  const publicInstance = bridge.publicInstance(instance);

  if (toolName === "max_capabilities") {
    const info = await bridge.request(instance.instanceId, "get_info", "", 30000);
    const renderer = info?.scene?.render?.renderer || "Unknown";
    return {
      instance: publicInstance,
      profiles: ["core", "archviz", "full"],
      activeRenderer: renderer,
      units: info?.units || null,
      rendererAdapter: /corona/i.test(renderer) ? "corona" : /v-?ray/i.test(renderer) ? "vray" : "generic",
      uiAutomation: { processScoped: true, backend: "Windows UI Automation" },
      maxScript: { unrestricted: true },
      tools: [...allToolNames],
    };
  }
  if (toolName === "max_query_scene") {
    const currentRevision = revisionFor(bridge, instance.instanceId);
    const sinceRevision = Math.max(0, Math.trunc(Number(args.sinceRevision ?? 0)));
    if (sinceRevision === currentRevision) return { instanceId: instance.instanceId, changed: false, sinceRevision, sceneRevision: currentRevision, scene: null };
    const summary = await bridge.request(instance.instanceId, "scene_summary", "", 30000);
    return { instanceId: instance.instanceId, changed: true, sinceRevision, sceneRevision: currentRevision, scene: args.details ? summary : summary.scene };
  }

  if (toolName === "max_get_logs" || toolName === "max_get_listener_output") {
    const tail = Math.min(200, Math.max(1, Math.trunc(Number(args.tail ?? 20))));
    return { instance: publicInstance, bridgeLogs: instance.logs?.slice?.(-tail) || [], panelLog: await bridge.request(instance.instanceId, "logs") };
  }
  if (toolName === "max_capture_viewport") {
    const outputPath = path.join(os.tmpdir(), `max-ultra-mcp-viewport-${randomUUID()}.png`);
    const screenshot = await bridge.request(instance.instanceId, "screenshot", outputPath, 30000);
    if (args.width || args.height) {
      const resized = await resizePng(outputPath, Number(args.width || 0), Number(args.height || 0));
      Object.assign(screenshot, resized);
    }
    return { instanceId: instance.instanceId, screenshot, sceneRevision: revisionFor(bridge, instance.instanceId) };
  }

  if (toolName === "max_scene_new" || toolName === "max_scene_reset") {
    const script = "(resetMaxFile #noPrompt; true)";
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script);
  }
  if (toolName === "max_scene_open") {
    const script = `(loadMaxFile ${maxString(args.filePath)} useFileUnits:${args.useFileUnits !== false} quiet:true)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script, 600000);
  }
  if (toolName === "max_scene_save") {
    const script = args.filePath ? `(saveMaxFile ${maxString(args.filePath)} quiet:true)` : `(if maxFileName=="" do throw "filePath is required for an untitled scene"; saveMaxFile (maxFilePath + maxFileName) quiet:true)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script, 600000);
  }
  if (toolName === "max_scene_merge") {
    const script = `(mergeMAXFile ${maxString(args.filePath)} #noRedraw #autoRenameDups quiet:true)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script, 600000);
  }
  if (toolName === "max_undo" || toolName === "max_redo") {
    const script = toolName === "max_undo" ? "(max undo; true)" : "(max redo; true)";
    return executeMutation(bridge, instance, script);
  }

  if (toolName === "max_create_box") {
    if (args.dimensions && !Array.isArray(args.size)) return NOT_HANDLED;
    const name = String(args.name || "MaxUltraBox").trim();
    if (!name || name.length > 128) throw new Error("name must contain 1 to 128 characters");
    const position = Array.isArray(args.position)
      ? vector3(args.position, [0, 0, 0], "position")
      : [finite(args.position?.x, 0, "position.x"), finite(args.position?.y, 0, "position.y"), finite(args.position?.z, 0, "position.z")];
    const size = Array.isArray(args.size)
      ? vector3(args.size, [20, 20, 20], "size", { positive: true })
      : [
        finite(args.dimensions?.width, 20, "dimensions.width", { positive: true }),
        finite(args.dimensions?.length, 20, "dimensions.length", { positive: true }),
        finite(args.dimensions?.height, 20, "dimensions.height", { positive: true }),
      ];
    const selected = args.select !== false;
    const script = `(
  if getNodeByName ${maxString(name)} exact:true != undefined do throw ${maxString(`${name} already exists`)}
  undo "Max Ultra MCP: Create box" on (
    local n=box name:${maxString(name)} width:${size[0]} length:${size[1]} height:${size[2]} pos:${vectorScript(position)}
    if ${selected} do select n
    ((getHandleByAnim n) as string)+"|"+n.name
  )
)`;
    const box = { name, position: { x: position[0], y: position[1], z: position[2] }, dimensions: { width: size[0], length: size[1], height: size[2] }, selected };
    if (args.dryRun) return dryRunResult(toolName, instance, script, { box, node: { name } });
    return executeNodeMutation(bridge, instance, script, name, 30000, { box });
  }
  if (toolName === "max_create_primitive") {
    const script = createPrimitiveScript(args);
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeNodeMutation(bridge, instance, script, args.name);
  }
  if (toolName === "max_create_polygon_mesh") {
    const validation = validatePolygonMesh(args.mesh);
    if (validation.blockers.length) throw new Error(`VALIDATION_FAILED: ${validation.blockers.join("; ")}`);
    if (validation.validationToken !== args.validationToken) throw new Error("VALIDATION_FAILED: polygon mesh payload differs from the validated payload");
    const generated = generatePolygonMeshScript(validation.normalizedMesh);
    if (args.dryRun) {
      return dryRunResult(toolName, instance, generated.script, {
        validationToken: validation.validationToken,
        warnings: validation.warnings,
        counts: validation.counts,
        boundingBox: validation.boundingBox,
      });
    }
    return executePolygonMeshMutation(bridge, instance, generated.script, validation);
  }
  if (toolName === "max_clone_object") {
    const source = nodeExpression(args.node, bridge, instance.instanceId);
    const cloneType = args.cloneType || "copy";
    const cloneFunction = cloneType === "instance" ? "instance" : cloneType === "reference" ? "reference" : "copy";
    const rename = args.name ? `; n.name = ${maxString(args.name)}` : "";
    const script = `(local source=${source}; if source==undefined do throw "NodeRef not found"; undo "Max Ultra MCP: Clone" on (local n=${cloneFunction} source${rename}; select n; ((getHandleByAnim n) as string)+"|"+n.name))`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeNodeMutation(bridge, instance, script, args.name || args.node?.name);
  }
  if (toolName === "max_delete_objects") {
    const expressions = args.nodes.map((node) => nodeExpression(node, bridge, instance.instanceId));
    const script = `(local nodes=#(${expressions.join(",")}); if findItem nodes undefined > 0 do throw "NodeRef not found"; undo "Max Ultra MCP: Delete" on delete nodes; nodes.count)`;
    return args.dryRun ? dryRunResult(toolName, instance, script, { count: expressions.length }) : executeMutation(bridge, instance, script, 30000, { deletedCount: expressions.length });
  }
  if (toolName === "max_rename_object") {
    const expression = nodeExpression(args.node, bridge, instance.instanceId);
    const script = `(local n=${expression}; if n==undefined do throw "NodeRef not found"; if getNodeByName ${maxString(args.name)} exact:true != undefined do throw "Target name already exists"; undo "Max Ultra MCP: Rename" on n.name=${maxString(args.name)}; ((getHandleByAnim n) as string)+"|"+n.name)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeNodeMutation(bridge, instance, script, args.name);
  }
  if (toolName === "max_transform_object") {
    const expression = nodeExpression(args.node, bridge, instance.instanceId);
    const assignments = [];
    const mode = args.mode || "set";
    if (args.position) assignments.push(`n.pos = ${mode === "offset" ? "n.pos + " : ""}${vectorScript(vector3(args.position, undefined, "position"))}`);
    if (args.rotation) assignments.push(`n.rotation = ${mode === "offset" ? "n.rotation * " : ""}(eulerAngles ${vector3(args.rotation, undefined, "rotation").join(" ")})`);
    if (args.scale) assignments.push(`n.scale = ${mode === "offset" ? "n.scale * " : ""}${vectorScript(vector3(args.scale, undefined, "scale"))}`);
    if (!assignments.length) throw new Error("At least one transform component is required");
    const script = `(local n=${expression}; if n==undefined do throw "NodeRef not found"; undo "Max Ultra MCP: Transform" on (${assignments.join("; ")}); ((getHandleByAnim n) as string)+"|"+n.name)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeNodeMutation(bridge, instance, script, args.node?.name);
  }
  if (toolName === "max_select_objects") {
    const mode = args.mode || "replace";
    const expressions = (args.nodes || []).map((node) => nodeExpression(node, bridge, instance.instanceId));
    const command = mode === "clear" ? "clearSelection()" : mode === "add" ? `selectMore #(${expressions.join(",")})` : mode === "remove" ? `deselect #(${expressions.join(",")})` : `select #(${expressions.join(",")})`;
    return executeMutation(bridge, instance, `(${command}; selection.count)`, 30000, { selectionMode: mode });
  }
  if (toolName === "max_layer_create") {
    const script = `(local l=LayerManager.getLayerFromName ${maxString(args.name)}; if l==undefined do l=LayerManager.newLayerFromName ${maxString(args.name)}; l.name)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script);
  }
  if (toolName === "max_layer_assign") {
    const expressions = args.nodes.map((node) => nodeExpression(node, bridge, instance.instanceId));
    const script = `(local l=LayerManager.getLayerFromName ${maxString(args.name)}; if l==undefined do l=LayerManager.newLayerFromName ${maxString(args.name)}; local nodes=#(${expressions.join(",")}); if findItem nodes undefined>0 do throw "NodeRef not found"; undo "Max Ultra MCP: Layer" on for n in nodes do l.addNode n; nodes.count)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script);
  }
  if (toolName === "max_add_modifier") {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(args.modifier)) throw new Error("modifier must be a MaxScript class identifier");
    const expression = nodeExpression(args.node, bridge, instance.instanceId);
    const parameterAssignments = Object.entries(args.parameters || {}).map(([key, value]) => {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) throw new Error(`Invalid modifier parameter '${key}'`);
      const literal = typeof value === "string" ? maxString(value) : typeof value === "boolean" ? String(value) : String(finite(value, undefined, key));
      return `setProperty m #${key} ${literal}`;
    });
    const script = `(local n=${expression}; if n==undefined do throw "NodeRef not found"; local m=${args.modifier}(); ${parameterAssignments.join("; ")}; undo "Max Ultra MCP: Modifier" on addModifier n m; classof m as string)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script);
  }
  if (toolName === "max_material_create") {
    const diffuse = vector3(args.diffuse, [180, 180, 180], "diffuse");
    const script = `(local m=standardMaterial name:${maxString(args.name)} diffuse:(color ${diffuse.join(" ")}); meditMaterials[1]=m; m.name)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script);
  }
  if (toolName === "max_material_assign") {
    const expressions = args.nodes.map((node) => nodeExpression(node, bridge, instance.instanceId));
    const script = `(local m=for candidate in sceneMaterials where candidate.name==${maxString(args.materialName)} collect candidate; if m.count==0 do throw "Material not found"; local nodes=#(${expressions.join(",")}); if findItem nodes undefined>0 do throw "NodeRef not found"; undo "Max Ultra MCP: Material" on for n in nodes do n.material=m[1]; nodes.count)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script);
  }
  if (toolName === "max_add_normal_modifier") {
    const expression = nodeExpression(args.node, bridge, instance.instanceId);
    const flip = args.flip !== false;
    const modifierName = "Max Ultra MCP Normal Review";
    const script = `(
local n=${expression}
if n==undefined do throw "NodeRef not found"
local marker=${maxString(modifierName)}
local existing=for modifierValue in n.modifiers where ((classOf modifierValue)==Normalmodifier and modifierValue.name==marker) collect modifierValue
if existing.count>0 do throw "Normal review modifier already exists"
local m=Normalmodifier()
m.name=marker
m.unify=false
m.flip=${flip}
undo "Max Ultra MCP: Normal review" on addModifier n m
((getHandleByAnim n) as string)+"|"+n.name+"|"+m.name+"|flip="+(m.flip as string)
)`;
    const evidence = { modifierName, flip, unify: false, comparisonRequiresImmediateScreenshot: true };
    return args.dryRun ? dryRunResult(toolName, instance, script, evidence) : executeMutation(bridge, instance, script, 30000, evidence);
  }
  if (toolName === "max_material_find_unassigned") {
    const script = generateMaterialDiagnosticsScript(args);
    const execution = await bridge.request(instance.instanceId, "execute", script, 120000);
    return {
      instanceId: instance.instanceId,
      sceneRevision: revisionFor(bridge, instance.instanceId),
      ...parseMaterialDiagnostics(execution, revisionFor(bridge, instance.instanceId)),
    };
  }
  if (toolName === "max_import_file" || toolName === "max_export_file") {
    const script = toolName === "max_import_file"
      ? `(importFile ${maxString(args.filePath)} #noPrompt)`
      : `(exportFile ${maxString(args.filePath)} #noPrompt selectedOnly:${Boolean(args.selectedOnly)})`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script, 600000);
  }
  if (toolName === "max_animation_set_time") return executeMutation(bridge, instance, `(sliderTime=${finite(args.frame, undefined, "frame")}; sliderTime as string)`);
  if (toolName === "max_animation_key_transform") {
    const expression = nodeExpression(args.node, bridge, instance.instanceId);
    const assignments = [];
    if (args.position) assignments.push(`n.pos=${vectorScript(vector3(args.position, undefined, "position"))}`);
    if (args.rotation) assignments.push(`n.rotation=eulerAngles ${vector3(args.rotation, undefined, "rotation").join(" ")}`);
    if (args.scale) assignments.push(`n.scale=${vectorScript(vector3(args.scale, undefined, "scale"))}`);
    const script = `(local n=${expression}; if n==undefined do throw "NodeRef not found"; at time ${finite(args.frame, undefined, "frame")} with animate on (${assignments.join("; ")}); true)`;
    return executeMutation(bridge, instance, script);
  }

  const viewportScripts = {
    max_frame_selection: "(max zoomext sel; completeRedraw(); true)",
    max_zoom_extents: "(max tool zoomextents; completeRedraw(); true)",
    max_redraw_viewports: "(completeRedraw(); true)",
  };
  if (viewportScripts[toolName]) return { instanceId: instance.instanceId, execution: await bridge.request(instance.instanceId, "execute", viewportScripts[toolName], 30000), sceneRevision: revisionFor(bridge, instance.instanceId) };
  if (toolName === "max_set_view") {
    const commands = { top: "#view_top", bottom: "#view_bottom", front: "#view_front", back: "#view_back", left: "#view_left", right: "#view_right", perspective: "#view_persp_user", user: "#view_iso_user" };
    const command = commands[args.view];
    if (!command) throw new Error("Unsupported viewport view");
    return { instanceId: instance.instanceId, execution: await bridge.request(instance.instanceId, "execute", `(viewport.setType ${command}; completeRedraw(); true)`, 30000) };
  }
  if (toolName === "max_activate_camera") {
    const expression = nodeExpression(args.camera, bridge, instance.instanceId);
    return { instanceId: instance.instanceId, execution: await bridge.request(instance.instanceId, "execute", `(local c=${expression}; if c==undefined do throw "Camera not found"; viewport.setCamera c; completeRedraw(); c.name)`, 30000) };
  }
  if (toolName === "max_set_viewport_mode") {
    const modes = { wireframe: "#wireframe", smooth: "#smoothhighlights", realistic: "#realistic" };
    return { instanceId: instance.instanceId, execution: await bridge.request(instance.instanceId, "execute", `(viewport.setRenderLevel ${modes[args.mode]}; completeRedraw(); true)`, 30000) };
  }

  if (toolName === "max_render_settings_get") {
    const info = await bridge.request(instance.instanceId, "get_info", "", 30000);
    return { instanceId: instance.instanceId, render: info?.scene?.render || null, sceneRevision: revisionFor(bridge, instance.instanceId) };
  }
  if (toolName === "max_render_settings_set") {
    const assignments = [];
    if (args.width !== undefined) assignments.push(`renderWidth=${Math.trunc(finite(args.width, undefined, "width", { positive: true }))}`);
    if (args.height !== undefined) assignments.push(`renderHeight=${Math.trunc(finite(args.height, undefined, "height", { positive: true }))}`);
    if (args.outputPath !== undefined) assignments.push(`rendOutputFilename=${maxString(args.outputPath)}`);
    if (args.frame !== undefined) assignments.push(`sliderTime=${finite(args.frame, undefined, "frame")}`);
    if (!assignments.length) throw new Error("At least one render setting is required");
    const script = `(${assignments.join("; ")}; true)`;
    return args.dryRun ? dryRunResult(toolName, instance, script) : executeMutation(bridge, instance, script);
  }
  if (toolName === "max_render_start") {
    const mode = args.mode || "production";
    const info = await bridge.request(instance.instanceId, "get_info", "", 30000);
    const renderer = info?.scene?.render?.renderer || "Unknown";
    const outputPath = args.outputPath || path.join(os.tmpdir(), `max-ultra-mcp-render-${randomUUID()}.png`);
    const timeoutMs = Math.min(3600000, Math.max(1000, Number(args.timeout_ms ?? 600000)));
    let productionScript = `(local b=render(); if b==undefined do throw "Renderer returned no bitmap"; b.filename=${maxString(outputPath)}; save b; close b; ${maxString(outputPath)})`;
    if (mode === "region") {
      if (!args.region) throw new Error("region is required when mode is 'region'");
      const region = {
        x: Math.trunc(finite(args.region.x, undefined, "region.x")),
        y: Math.trunc(finite(args.region.y, undefined, "region.y")),
        width: Math.trunc(finite(args.region.width, undefined, "region.width", { positive: true })),
        height: Math.trunc(finite(args.region.height, undefined, "region.height", { positive: true })),
      };
      productionScript = `(local oldType=rendType; local oldX=rendRegionX; local oldY=rendRegionY; local oldW=rendRegionWidth; local oldH=rendRegionHeight; local b=undefined; local failure=""; try (rendType=#region; rendRegionX=${region.x}; rendRegionY=${region.y}; rendRegionWidth=${region.width}; rendRegionHeight=${region.height}; b=render()) catch (failure=getCurrentException() as string); rendType=oldType; rendRegionX=oldX; rendRegionY=oldY; rendRegionWidth=oldW; rendRegionHeight=oldH; if failure!="" do throw failure; if b==undefined do throw "Renderer returned no bitmap"; b.filename=${maxString(outputPath)}; save b; close b; ${maxString(outputPath)})`;
    }
    const interactiveScript = /corona/i.test(renderer)
      ? `(try (CoronaRenderer.CoronaFp.startInteractive(); "Corona interactive started") catch (throw ("RENDERER_UNSUPPORTED: " + (getCurrentException() as string))))`
      : /v-?ray/i.test(renderer)
        ? `(try (renderers.current.startIpr(); "V-Ray interactive started") catch (throw ("RENDERER_UNSUPPORTED: " + (getCurrentException() as string))))`
        : `(throw "RENDERER_UNSUPPORTED: active renderer has no Max Ultra MCP interactive adapter")`;
    if (path.extname(outputPath).toLowerCase() !== ".png") throw new Error("Render outputPath must use the .png extension in v1");
    const job = session.jobRegistry.create({
      type: "render",
      instanceId: instance.instanceId,
      metadata: { mode, renderer },
      cancel: async (activeJob) => {
        let warning = "";
        if (activeJob.startedAt) {
          try {
            await runUiAutomation(activeJob.pid, "sendKeys", { keys: "{ESC}" }, 5000);
          } catch (error) {
            warning = error.message;
          }
        }
        if (activeJob.state === "running_interactive") {
          const stopScript = /corona/i.test(activeJob.renderer)
            ? `(try (CoronaRenderer.CoronaFp.stopRender(); true) catch false)`
            : /v-?ray/i.test(activeJob.renderer) ? `(try (renderers.current.stopIpr(); true) catch false)` : "false";
          await bridge.request(activeJob.instanceId, "execute", stopScript, 10000).catch(() => {});
          activeJob.state = "cancelled";
          activeJob.completedAt = new Date().toISOString();
        }
        return warning ? { warning } : null;
      },
    });
    Object.assign(job, { pid: instance.pid, mode, renderer, outputPath });
    session.jobRegistry.start(job, async (activeJob) => {
      const execution = await bridge.request(instance.instanceId, "execute", mode === "interactive" ? interactiveScript : productionScript, timeoutMs);
      activeJob.execution = execution;
      if (mode === "interactive" && !activeJob.cancelRequested) {
        activeJob.phase = "interactive";
        activeJob.state = "running_interactive";
      }
      return { mode, renderer, outputPath: mode === "interactive" ? null : outputPath, execution };
    });
    return renderSnapshot(job);
  }
  if (toolName === "max_run_script" || toolName === "max_execute") {
    const timeoutMs = Math.min(MAX_EXECUTION_TIMEOUT_MS, Math.max(1000, Number(args.timeout_ms ?? 60000)));
    const result = await executeMutation(bridge, instance, args.script, timeoutMs);
    if (toolName === "max_execute") return { instance: publicInstance, ...result };
    return result;
  }
  if (toolName === "max_run_script_file") {
    if (!/\.(ms|mse)$/i.test(args.filePath)) throw new Error("max_run_script_file accepts .ms or .mse files");
    const script = `(fileIn ${maxString(args.filePath)} quiet:true)`;
    return executeMutation(bridge, instance, script, Math.min(MAX_EXECUTION_TIMEOUT_MS, Math.max(1000, Number(args.timeout_ms ?? 60000))));
  }
  if (toolName === "max_run_macro") return executeMutation(bridge, instance, `(macros.run ${maxString(args.category)} ${maxString(args.name)})`);
  if (toolName === "max_run_action") return executeMutation(bridge, instance, `(actionMan.executeAction ${Number(args.tableId)} ${maxString(args.actionId)})`);

  if (toolName === "max_ui_invoke" && args.target_hwnd) return NOT_HANDLED;
  const uiOperation = {
    max_ui_list_windows: "listWindows", max_ui_inspect: "inspect", max_ui_find: "find", max_ui_invoke: "invoke",
    max_ui_set_value: "setValue", max_ui_select: "select", max_ui_send_keys: "sendKeys", max_ui_close_window: "close", max_ui_capture_window: "capture",
  }[toolName];
  if (uiOperation) {
    const payload = { ...args };
    delete payload.instance_id;
    if (toolName === "max_ui_capture_window") payload.outputPath = path.join(os.tmpdir(), `max-ultra-mcp-window-${randomUUID()}.png`);
    const data = await runUiAutomation(instance.pid, uiOperation, payload, toolName === "max_ui_capture_window" ? 30000 : 15000);
    return { instanceId: instance.instanceId, ui: data };
  }
  if (toolName === "max_ui_wait") {
    const timeoutMs = Math.min(120000, Math.max(0, Number(args.timeout_ms ?? 10000)));
    const deadline = Date.now() + timeoutMs;
    const state = args.state || "exists";
    let lastError = null;
    do {
      try {
        const operation = args.control ? "find" : "find";
        const payload = args.control ? { window: args.window, control: args.control } : { control: args.window };
        const found = await runUiAutomation(instance.pid, operation, payload, 5000);
        const matches = state === "missing" || state === "closed" ? false : state === "enabled" ? found.enabled : state === "visible" ? !found.offscreen : true;
        if (matches) return { instanceId: instance.instanceId, state, matched: true, element: found };
      } catch (error) {
        lastError = error;
        if (state === "missing" || state === "closed") return { instanceId: instance.instanceId, state, matched: true };
      }
      await waitDelay(200);
    } while (Date.now() <= deadline);
    throw new Error(`TIMEOUT: UI state '${state}' was not reached${lastError ? `: ${lastError.message}` : ""}`);
  }

  if (toolName === "max_build_floor_plan") {
    const validation = validateFloorPlan(args.plan);
    if (validation.validationToken !== args.validationToken) throw new Error("VALIDATION_FAILED: floor-plan payload differs from the validated payload");
    const generated = generateFloorPlanScript(validation.normalizedPlan, { layer: args.layer, prefix: args.prefix });
    const buildEvidence = {
      validationToken: validation.validationToken,
      counts: validation.counts,
      boundingBox: validation.boundingBox,
      segmentCount: generated.segmentCount,
      placeholderCount: generated.placeholderCount,
      openingHelperCount: generated.openingHelperCount,
      sourceSplineName: generated.sourceSplineName,
      wallMeshName: generated.wallMeshName,
      modelingWorkflow: generated.modelingWorkflow,
      normalOrientation: generated.normalOrientation,
      junctions: generated.junctions,
    };
    if (args.dryRun) return dryRunResult(toolName, instance, generated.script, { validation, ...buildEvidence });
    const result = await executeMutation(bridge, instance, generated.script, 600000, buildEvidence);
    const resultText = String(result.execution?.result || "");
    const parsed = /sourceHandle=(\d+);sourceSpline=([^;]+);wallHandle=(\d+);wallMesh=([^;]+)/.exec(resultText);
    result.sourceSpline = {
      ...(parsed ? { handle: Number(parsed[1]) } : {}),
      name: parsed?.[2] || generated.sourceSplineName,
      sceneRevision: result.sceneRevision,
    };
    result.wallMesh = {
      ...(parsed ? { handle: Number(parsed[3]) } : {}),
      name: parsed?.[4] || generated.wallMeshName,
      sceneRevision: result.sceneRevision,
    };
    return result;
  }

  return NOT_HANDLED;
}

module.exports = { NOT_HANDLED, invokeV1Tool, revisionFor };
const { resizePng } = require("./image-utils");
