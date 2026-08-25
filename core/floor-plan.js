/* Structured architectural floor-plan validation and MaxScript generation. */

"use strict";

const { createHash } = require("node:crypto");

function finite(value, field, { positive = false, minimum = -Infinity } = {}) {
  const number = Number(value);
  if (!Number.isFinite(number) || (positive && number <= 0) || number < minimum) {
    throw new Error(`${field} must be ${positive ? "a positive " : "a "}finite number`);
  }
  return number;
}

function point2(value, field) {
  if (!Array.isArray(value) || value.length !== 2) throw new Error(`${field} must contain [x,y]`);
  return [finite(value[0], `${field}[0]`), finite(value[1], `${field}[1]`)];
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function canonicalString(value) {
  return JSON.stringify(stable(value));
}

function validateFloorPlan(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("plan must be an object");
  if ((input.units || "mm") !== "mm") throw new Error("plan.units must be 'mm' in v1");
  const wallHeight = finite(input.wallHeight ?? input.wall_height ?? 3000, "wallHeight", { positive: true });
  const origin = point2(input.origin || [0, 0], "origin");
  if (!Array.isArray(input.walls) || input.walls.length === 0) throw new Error("plan.walls must contain at least one wall");

  const wallIds = new Set();
  const walls = input.walls.map((entry, index) => {
    const id = String(entry?.id || `W${index + 1}`).trim();
    if (!id) throw new Error(`walls[${index}].id is empty`);
    if (wallIds.has(id)) throw new Error(`Duplicate wall id '${id}'`);
    wallIds.add(id);
    const start = point2(entry.start, `walls[${index}].start`);
    const end = point2(entry.end, `walls[${index}].end`);
    const thickness = finite(entry.thickness, `walls[${index}].thickness`, { positive: true });
    const length = Math.hypot(end[0] - start[0], end[1] - start[1]);
    if (length < 1e-6) throw new Error(`Wall '${id}' has zero length`);
    return { id, start, end, thickness, length };
  });
  const wallById = new Map(walls.map((wall) => [wall.id, wall]));

  const openingIds = new Set();
  const warnings = [];
  const openings = (Array.isArray(input.openings) ? input.openings : []).map((entry, index) => {
    const id = String(entry?.id || `O${index + 1}`).trim();
    if (!id) throw new Error(`openings[${index}].id is empty`);
    if (openingIds.has(id)) throw new Error(`Duplicate opening id '${id}'`);
    openingIds.add(id);
    const wallId = String(entry.wallId ?? entry.wall_id ?? "");
    const wall = wallById.get(wallId);
    if (!wall) throw new Error(`Opening '${id}' references unknown wall '${wallId}'`);
    const type = String(entry.type || "").toLowerCase();
    if (type !== "door" && type !== "window") throw new Error(`Opening '${id}' type must be door or window`);
    const offsetFromStart = finite(entry.offsetFromStart ?? entry.offset_from_start, `opening '${id}' offsetFromStart`, { minimum: 0 });
    const width = finite(entry.width, `opening '${id}' width`, { positive: true });
    const height = finite(entry.height, `opening '${id}' height`, { positive: true });
    const sillHeight = finite(entry.sillHeight ?? entry.sill_height ?? (type === "window" ? 900 : 0), `opening '${id}' sillHeight`, { minimum: 0 });
    if (offsetFromStart + width > wall.length + 1e-6) throw new Error(`Opening '${id}' extends past wall '${wallId}'`);
    if (sillHeight + height > wallHeight + 1e-6) throw new Error(`Opening '${id}' exceeds wall height`);
    if (type === "door" && sillHeight !== 0) warnings.push(`Door '${id}' sillHeight was normalized to 0`);
    return { id, wallId, type, offsetFromStart, width, height, sillHeight: type === "door" ? 0 : sillHeight };
  });

  for (const wall of walls) {
    const wallOpenings = openings.filter((opening) => opening.wallId === wall.id).sort((a, b) => a.offsetFromStart - b.offsetFromStart);
    for (let index = 1; index < wallOpenings.length; index += 1) {
      const previous = wallOpenings[index - 1];
      const current = wallOpenings[index];
      if (current.offsetFromStart < previous.offsetFromStart + previous.width - 1e-6) {
        throw new Error(`Openings '${previous.id}' and '${current.id}' overlap on wall '${wall.id}'`);
      }
    }
  }

  const floorInput = input.floor || {};
  const floor = {
    enabled: floorInput.enabled !== false,
    thickness: finite(floorInput.thickness ?? 200, "floor.thickness", { positive: true }),
    outline: Array.isArray(floorInput.outline) ? floorInput.outline.map((point, index) => point2(point, `floor.outline[${index}]`)) : [],
  };
  if (floor.enabled && floor.outline.length > 0 && floor.outline.length < 3) throw new Error("floor.outline must contain at least three points");

  const normalizedPlan = { units: "mm", origin, wallHeight, walls: walls.map(({ length: _length, ...wall }) => wall), openings, floor };
  const allPoints = walls.flatMap((wall) => [wall.start, wall.end]).concat(floor.outline);
  const xs = allPoints.map((point) => point[0] + origin[0]);
  const ys = allPoints.map((point) => point[1] + origin[1]);
  const boundingBox = { min: [Math.min(...xs), Math.min(...ys), -floor.thickness], max: [Math.max(...xs), Math.max(...ys), wallHeight] };
  const validationToken = createHash("sha256").update(canonicalString(normalizedPlan)).digest("hex");
  return {
    normalizedPlan,
    validationToken,
    warnings,
    blockers: [],
    boundingBox,
    counts: { walls: walls.length, openings: openings.length, doors: openings.filter((item) => item.type === "door").length, windows: openings.filter((item) => item.type === "window").length },
  };
}

function quoteMax(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n")}"`;
}

function safeName(value) {
  return String(value).replace(/[^A-Za-z0-9_-]+/g, "_").slice(0, 80) || "Item";
}

function mm(value) {
  return `mm ${Number(value).toFixed(6)}`;
}

function generateFloorPlanScript(normalizedPlan, options = {}) {
  const prefix = safeName(options.prefix || "MCP");
  const layerName = String(options.layer || "MCP_ARCHVIZ");
  const statements = [];
  let segmentCount = 0;
  let placeholderCount = 0;
  statements.push("(");
  statements.push("  fn mm value = units.decodeValue ((value as string) + \"mm\")");
  statements.push(`  local targetLayer = LayerManager.getLayerFromName ${quoteMax(layerName)}`);
  statements.push(`  if targetLayer == undefined do targetLayer = LayerManager.newLayerFromName ${quoteMax(layerName)}`);
  statements.push("  local createdNodes = #()");
  statements.push("  undo \"Max Ultra MCP: Build floor plan\" on (");

  for (const wall of normalizedPlan.walls) {
    const dx = wall.end[0] - wall.start[0];
    const dy = wall.end[1] - wall.start[1];
    const length = Math.hypot(dx, dy);
    const angle = Math.atan2(dy, dx) * 180 / Math.PI;
    const openings = normalizedPlan.openings.filter((opening) => opening.wallId === wall.id);
    const bounds = [-wall.thickness / 2, 0, length, length + wall.thickness / 2];
    for (const opening of openings) bounds.push(opening.offsetFromStart, opening.offsetFromStart + opening.width);
    const sorted = [...new Set(bounds.map((value) => Number(value.toFixed(6))))].sort((a, b) => a - b);
    for (let index = 0; index < sorted.length - 1; index += 1) {
      const from = sorted[index];
      const to = sorted[index + 1];
      if (to - from < 1e-6) continue;
      const midpoint = (from + to) / 2;
      const opening = openings.find((item) => midpoint >= item.offsetFromStart && midpoint <= item.offsetFromStart + item.width);
      const verticalRanges = opening
        ? (opening.type === "door" ? [[opening.height, normalizedPlan.wallHeight]] : [[0, opening.sillHeight], [opening.sillHeight + opening.height, normalizedPlan.wallHeight]])
        : [[0, normalizedPlan.wallHeight]];
      for (const [zFrom, zTo] of verticalRanges) {
        if (zTo - zFrom < 1e-6) continue;
        segmentCount += 1;
        const centerDistance = (from + to) / 2;
        const centerX = normalizedPlan.origin[0] + wall.start[0] + (dx / length) * centerDistance;
        const centerY = normalizedPlan.origin[1] + wall.start[1] + (dy / length) * centerDistance;
        const name = `${prefix}_${safeName(wall.id)}_S${String(segmentCount).padStart(3, "0")}`;
        statements.push(`    local n = box name:${quoteMax(name)} width:(${mm(to - from)}) length:(${mm(wall.thickness)}) height:(${mm(zTo - zFrom)}) pos:[${mm(centerX)},${mm(centerY)},${mm((zFrom + zTo) / 2)}]`);
        statements.push(`    n.rotation = eulerAngles 0 0 ${angle.toFixed(6)}`);
        statements.push("    targetLayer.addNode n");
        statements.push("    append createdNodes n");
      }
    }
    for (const opening of openings) {
      placeholderCount += 1;
      const centerDistance = opening.offsetFromStart + opening.width / 2;
      const centerX = normalizedPlan.origin[0] + wall.start[0] + (dx / length) * centerDistance;
      const centerY = normalizedPlan.origin[1] + wall.start[1] + (dy / length) * centerDistance;
      const centerZ = opening.sillHeight + opening.height / 2;
      const name = `${prefix}_${opening.type === "door" ? "Door" : "Window"}_${safeName(opening.id)}`;
      statements.push(`    local p = dummy name:${quoteMax(name)} boxsize:[${mm(opening.width)},${mm(wall.thickness)},${mm(opening.height)}] pos:[${mm(centerX)},${mm(centerY)},${mm(centerZ)}]`);
      statements.push(`    p.rotation = eulerAngles 0 0 ${angle.toFixed(6)}`);
      statements.push("    targetLayer.addNode p");
      statements.push("    append createdNodes p");
    }
  }

  if (normalizedPlan.floor.enabled) {
    const outline = normalizedPlan.floor.outline.length >= 3
      ? normalizedPlan.floor.outline
      : (() => {
        const points = normalizedPlan.walls.flatMap((wall) => [wall.start, wall.end]);
        const xs = points.map((point) => point[0]);
        const ys = points.map((point) => point[1]);
        return [[Math.min(...xs), Math.min(...ys)], [Math.max(...xs), Math.min(...ys)], [Math.max(...xs), Math.max(...ys)], [Math.min(...xs), Math.max(...ys)]];
      })();
    statements.push(`    local floorShape = splineShape name:${quoteMax(`${prefix}_Floor`)}`);
    statements.push("    addNewSpline floorShape");
    for (const point of outline) {
      statements.push(`    addKnot floorShape 1 #corner #line [${mm(point[0] + normalizedPlan.origin[0])},${mm(point[1] + normalizedPlan.origin[1])},0]`);
    }
    statements.push("    close floorShape 1");
    statements.push("    updateShape floorShape");
    statements.push(`    addModifier floorShape (Extrude amount:(-(${mm(normalizedPlan.floor.thickness)})))`);
    statements.push("    targetLayer.addNode floorShape");
    statements.push("    append createdNodes floorShape");
  }

  statements.push("    select createdNodes");
  statements.push("  )");
  statements.push(`  ${quoteMax(`walls=${normalizedPlan.walls.length};segments=${segmentCount};openings=${placeholderCount};floor=${normalizedPlan.floor.enabled ? 1 : 0}`)}`);
  statements.push(")");
  return { script: statements.join("\n"), segmentCount, placeholderCount };
}

module.exports = { canonicalString, generateFloorPlanScript, validateFloorPlan };
