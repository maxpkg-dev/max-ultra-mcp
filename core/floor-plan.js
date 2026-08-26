/*
 * Validates structured architectural plans and generates spline-first MaxScript wall geometry.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { canonicalString, hashCanonical } = require("./plan-token");

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
  const validationToken = hashCanonical(normalizedPlan);
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

function wallFrame(wall) {
  const dx = wall.end[0] - wall.start[0];
  const dy = wall.end[1] - wall.start[1];
  const length = Math.hypot(dx, dy);
  return { length, along: [dx / length, dy / length], normal: [-dy / length, dx / length] };
}

function wallPoint(normalizedPlan, wall, frame, distance, lateral, height) {
  return [
    normalizedPlan.origin[0] + wall.start[0] + frame.along[0] * distance + frame.normal[0] * lateral,
    normalizedPlan.origin[1] + wall.start[1] + frame.along[1] * distance + frame.normal[1] * lateral,
    height,
  ];
}

function buildWallFootprints(normalizedPlan) {
  return normalizedPlan.walls.map((wall) => {
    const frame = wallFrame(wall);
    const halfThickness = wall.thickness / 2;
    return [
      wallPoint(normalizedPlan, wall, frame, -halfThickness, -halfThickness, 0),
      wallPoint(normalizedPlan, wall, frame, frame.length + halfThickness, -halfThickness, 0),
      wallPoint(normalizedPlan, wall, frame, frame.length + halfThickness, halfThickness, 0),
      wallPoint(normalizedPlan, wall, frame, -halfThickness, halfThickness, 0),
    ];
  });
}

function buildOpeningAwareWallTopology(normalizedPlan) {
  const vertices = [];
  const faces = [];
  const pieces = [];
  for (const wall of normalizedPlan.walls) {
    const frame = wallFrame(wall);
    const openings = normalizedPlan.openings.filter((opening) => opening.wallId === wall.id);
    const bounds = [-wall.thickness / 2, 0, frame.length, frame.length + wall.thickness / 2];
    for (const opening of openings) bounds.push(opening.offsetFromStart, opening.offsetFromStart + opening.width);
    const sortedBounds = [...new Set(bounds.map((value) => Number(value.toFixed(6))))].sort((left, right) => left - right);
    for (let index = 0; index < sortedBounds.length - 1; index += 1) {
      const from = sortedBounds[index];
      const to = sortedBounds[index + 1];
      if (to - from < 1e-6) continue;
      const midpoint = (from + to) / 2;
      const opening = openings.find((candidate) => midpoint >= candidate.offsetFromStart && midpoint <= candidate.offsetFromStart + candidate.width);
      const verticalRanges = opening
        ? (opening.type === "door" ? [[opening.height, normalizedPlan.wallHeight]] : [[0, opening.sillHeight], [opening.sillHeight + opening.height, normalizedPlan.wallHeight]])
        : [[0, normalizedPlan.wallHeight]];
      for (const [zFrom, zTo] of verticalRanges) {
        if (zTo - zFrom < 1e-6) continue;
        const halfThickness = wall.thickness / 2;
        const baseVertex = vertices.length;
        vertices.push(
          wallPoint(normalizedPlan, wall, frame, from, halfThickness, zFrom),
          wallPoint(normalizedPlan, wall, frame, to, halfThickness, zFrom),
          wallPoint(normalizedPlan, wall, frame, to, -halfThickness, zFrom),
          wallPoint(normalizedPlan, wall, frame, from, -halfThickness, zFrom),
          wallPoint(normalizedPlan, wall, frame, from, halfThickness, zTo),
          wallPoint(normalizedPlan, wall, frame, to, halfThickness, zTo),
          wallPoint(normalizedPlan, wall, frame, to, -halfThickness, zTo),
          wallPoint(normalizedPlan, wall, frame, from, -halfThickness, zTo),
        );
        const localFaces = [
          [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
          [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
        ];
        faces.push(...localFaces.map((face) => face.map((vertexIndex) => baseVertex + vertexIndex)));
        pieces.push({ wallId: wall.id, openingId: opening?.id || null, from, to, zFrom, zTo });
      }
    }
  }
  return { vertices, faces, pieces };
}

function generateFloorPlanScript(normalizedPlan, options = {}) {
  const prefix = safeName(options.prefix || "MCP");
  const layerName = String(options.layer || "MCP_ARCHVIZ");
  const sourceSplineName = `${prefix}_WallPlan_SOURCE`;
  const wallMeshName = `${prefix}_Walls`;
  const wallFootprints = buildWallFootprints(normalizedPlan);
  const wallTopology = buildOpeningAwareWallTopology(normalizedPlan);
  const statements = [];
  const segmentCount = wallTopology.pieces.length;
  let placeholderCount = 0;
  statements.push("(");
  statements.push("  fn mm value = units.decodeValue ((value as string) + \"mm\")");
  statements.push("  fn addWallPolygon targetMesh polygonIndices = (");
  statements.push("    local previousFaceCount = meshop.getNumFaces targetMesh");
  statements.push("    meshop.createPolygon targetMesh polygonIndices");
  statements.push("    if ((meshop.getNumFaces targetMesh) <= previousFaceCount) do throw \"meshop.createPolygon did not create wall geometry\"");
  statements.push("    return true");
  statements.push("  )");
  statements.push(`  local targetLayer = LayerManager.getLayerFromName ${quoteMax(layerName)}`);
  statements.push(`  if targetLayer == undefined do targetLayer = LayerManager.newLayerFromName ${quoteMax(layerName)}`);
  statements.push(`  local sourceSplineName = ${quoteMax(sourceSplineName)}`);
  statements.push(`  local wallMeshName = ${quoteMax(wallMeshName)}`);
  statements.push("  if (getNodeByName sourceSplineName exact:true != undefined) do throw (sourceSplineName + \" already exists\")");
  statements.push("  if (getNodeByName wallMeshName exact:true != undefined) do throw (wallMeshName + \" already exists\")");
  statements.push(`  local wallVertexValues = #(${wallTopology.vertices.map((point) => `[${mm(point[0])},${mm(point[1])},${mm(point[2])}]`).join(",")})`);
  statements.push(`  local wallPolygonValues = #(${wallTopology.faces.map((face) => `#(${face.map((vertexIndex) => vertexIndex + 1).join(",")})`).join(",")})`);
  statements.push("  local createdNodes = #()");
  statements.push("  local visibleNodes = #()");
  statements.push("  undo \"Max Ultra MCP: Build floor plan\" on (");
  statements.push("    local wallPlanSource = splineShape name:sourceSplineName");
  for (let footprintIndex = 0; footprintIndex < wallFootprints.length; footprintIndex += 1) {
    statements.push("    addNewSpline wallPlanSource");
    for (const point of wallFootprints[footprintIndex]) {
      statements.push(`    addKnot wallPlanSource ${footprintIndex + 1} #corner #line [${mm(point[0])},${mm(point[1])},0]`);
    }
    statements.push(`    close wallPlanSource ${footprintIndex + 1}`);
  }
  statements.push("    updateShape wallPlanSource");
  statements.push("    setUserProp wallPlanSource \"MaxUltraMCPRole\" \"FloorPlanSourceSpline\"");
  statements.push("    targetLayer.addNode wallPlanSource");
  statements.push("    append createdNodes wallPlanSource");
  statements.push("    local wallMesh = copy wallPlanSource");
  statements.push("    wallMesh.name = wallMeshName");
  statements.push("    setUserProp wallMesh \"MaxUltraMCPSourceHandle\" ((getHandleByAnim wallPlanSource) as string)");
  statements.push("    addModifier wallMesh (Extrude amount:(mm " + Number(normalizedPlan.wallHeight).toFixed(6) + "))");
  statements.push("    convertToMesh wallMesh");
  statements.push("    undo off (");
  statements.push("      if ((meshop.getNumFaces wallMesh) > 0) do meshop.deleteFaces wallMesh #{1..(meshop.getNumFaces wallMesh)} delIsoVerts:true");
  statements.push("      if ((meshop.getNumVerts wallMesh) > 0) do meshop.deleteVerts wallMesh #{1..(meshop.getNumVerts wallMesh)}");
  statements.push("      meshop.setNumVerts wallMesh wallVertexValues.count");
  statements.push("      for vertexIndex in 1 to wallVertexValues.count do meshop.setVert wallMesh vertexIndex wallVertexValues[vertexIndex]");
  statements.push("      for polygonIndices in wallPolygonValues do addWallPolygon wallMesh polygonIndices");
  statements.push("      update wallMesh");
  statements.push("    )");
  statements.push("    convertToPoly wallMesh");
  statements.push("    if ((classOf wallMesh.baseObject) != Editable_Poly) do throw \"Wall object could not be converted to Editable Poly\"");
  statements.push("    targetLayer.addNode wallMesh");
  statements.push("    append createdNodes wallMesh");
  statements.push("    append visibleNodes wallMesh");
  statements.push("    wallPlanSource.isHidden = true");
  statements.push("    wallMesh.isHidden = false");

  for (const wall of normalizedPlan.walls) {
    const frame = wallFrame(wall);
    const angle = Math.atan2(frame.along[1], frame.along[0]) * 180 / Math.PI;
    const openings = normalizedPlan.openings.filter((opening) => opening.wallId === wall.id);
    for (const opening of openings) {
      placeholderCount += 1;
      const centerDistance = opening.offsetFromStart + opening.width / 2;
      const centerX = normalizedPlan.origin[0] + wall.start[0] + frame.along[0] * centerDistance;
      const centerY = normalizedPlan.origin[1] + wall.start[1] + frame.along[1] * centerDistance;
      const centerZ = opening.sillHeight + opening.height / 2;
      const name = `${prefix}_${opening.type === "door" ? "Door" : "Window"}_${safeName(opening.id)}`;
      statements.push(`    local p = dummy name:${quoteMax(name)} boxsize:[${mm(opening.width)},${mm(wall.thickness)},${mm(opening.height)}] pos:[${mm(centerX)},${mm(centerY)},${mm(centerZ)}]`);
      statements.push(`    p.rotation = eulerAngles 0 0 ${angle.toFixed(6)}`);
      statements.push("    targetLayer.addNode p");
      statements.push("    append createdNodes p");
      statements.push("    append visibleNodes p");
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
    statements.push("    append visibleNodes floorShape");
  }

  statements.push("    select visibleNodes");
  statements.push("  )");
  statements.push(`  ${quoteMax(`sourceSpline=${sourceSplineName};wallMesh=${wallMeshName};walls=${normalizedPlan.walls.length};segments=${segmentCount};openings=${placeholderCount};floor=${normalizedPlan.floor.enabled ? 1 : 0}`)}`);
  statements.push(")");
  return {
    script: statements.join("\n"),
    segmentCount,
    placeholderCount,
    sourceSplineName,
    wallMeshName,
    modelingWorkflow: "spline-copy-extrude-meshop",
  };
}

module.exports = { canonicalString, generateFloorPlanScript, validateFloorPlan };
