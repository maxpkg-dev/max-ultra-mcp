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
    outlineMode: String(floorInput.outlineMode ?? floorInput.outline_mode ?? "wall_centerline"),
  };
  if (floor.enabled && floor.outline.length > 0 && floor.outline.length < 3) throw new Error("floor.outline must contain at least three points");
  if (!["wall_centerline", "finished"].includes(floor.outlineMode)) throw new Error("floor.outlineMode must be 'wall_centerline' or 'finished'");

  const normalizedPlan = { units: "mm", origin, wallHeight, walls: walls.map(({ length: _length, ...wall }) => wall), openings, floor };
  const junctions = buildWallJoinProfiles(normalizedPlan).summary;
  if (junctions.complexJunctions > 0) warnings.push(`${junctions.complexJunctions} complex wall junction(s) require visual review`);
  const allPoints = walls.flatMap((wall) => [wall.start, wall.end]).concat(floor.enabled ? buildFloorOutline(normalizedPlan) : floor.outline);
  const xs = allPoints.map((point) => point[0] + origin[0]);
  const ys = allPoints.map((point) => point[1] + origin[1]);
  const boundingBox = { min: [Math.min(...xs), Math.min(...ys), -floor.thickness], max: [Math.max(...xs), Math.max(...ys), wallHeight] };
  const validationToken = hashCanonical(normalizedPlan);
  return {
    normalizedPlan,
    validationToken,
    warnings,
    blockers: [],
    junctions,
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

const JOIN_EPSILON = 1e-5;

function add2(left, right) {
  return [left[0] + right[0], left[1] + right[1]];
}

function subtract2(left, right) {
  return [left[0] - right[0], left[1] - right[1]];
}

function scale2(value, scale) {
  return [value[0] * scale, value[1] * scale];
}

function dot2(left, right) {
  return left[0] * right[0] + left[1] * right[1];
}

function cross2(left, right) {
  return left[0] * right[1] - left[1] * right[0];
}

function leftNormal2(direction) {
  return [-direction[1], direction[0]];
}

function lineIntersection(pointA, directionA, pointB, directionB) {
  const denominator = cross2(directionA, directionB);
  if (Math.abs(denominator) < JOIN_EPSILON) return null;
  const factor = cross2(subtract2(pointB, pointA), directionB) / denominator;
  return add2(pointA, scale2(directionA, factor));
}

function pointKey(point) {
  return point.map((value) => Number(value).toFixed(5)).join("|");
}

function pointOnWallInterior(point, wall, frame) {
  const relative = subtract2(point, wall.start);
  const distance = dot2(relative, frame.along);
  const lateral = Math.abs(dot2(relative, frame.normal));
  return lateral <= JOIN_EPSILON && distance > JOIN_EPSILON && distance < frame.length - JOIN_EPSILON;
}

function buildWallJoinProfiles(normalizedPlan) {
  const frames = new Map(normalizedPlan.walls.map((wall) => [wall.id, wallFrame(wall)]));
  const profiles = new Map();
  const endpoints = [];
  const endpointGroups = new Map();
  for (const wall of normalizedPlan.walls) {
    const frame = frames.get(wall.id);
    profiles.set(wall.id, {
      start: { negative: 0, positive: 0, kind: "cap" },
      end: { negative: frame.length, positive: frame.length, kind: "cap" },
    });
    for (const endpoint of ["start", "end"]) {
      const record = { wall, frame, endpoint, point: wall[endpoint], key: `${wall.id}:${endpoint}` };
      endpoints.push(record);
      const key = pointKey(record.point);
      if (!endpointGroups.has(key)) endpointGroups.set(key, []);
      endpointGroups.get(key).push(record);
    }
  }

  const resolved = new Set();
  const summary = { miteredJunctions: 0, buttedEnds: 0, cappedEnds: 0, complexJunctions: 0 };
  const baseDistance = (record) => record.endpoint === "start" ? 0 : record.frame.length;
  const awayDirection = (record) => record.endpoint === "start" ? record.frame.along : scale2(record.frame.along, -1);
  const travelDirection = (record) => scale2(awayDirection(record), -1);
  const projectedDistance = (record, point) => dot2(subtract2(point, record.wall.start), record.frame.along);
  const joinDistanceIsBounded = (record, otherWall, distance) => (
    Math.abs(distance - baseDistance(record)) <= Math.max(record.wall.thickness, otherWall.thickness) * 8
  );

  const applyButt = (record, hostWall) => {
    const hostFrame = frames.get(hostWall.id);
    const away = awayDirection(record);
    const hostSide = dot2(hostFrame.normal, away);
    if (Math.abs(hostSide) < JOIN_EPSILON) return false;
    const boundaryPoint = add2(record.point, scale2(hostFrame.normal, Math.sign(hostSide) * hostWall.thickness / 2));
    const negativePoint = add2(record.point, scale2(record.frame.normal, -record.wall.thickness / 2));
    const positivePoint = add2(record.point, scale2(record.frame.normal, record.wall.thickness / 2));
    const negativeIntersection = lineIntersection(negativePoint, record.frame.along, boundaryPoint, hostFrame.along);
    const positiveIntersection = lineIntersection(positivePoint, record.frame.along, boundaryPoint, hostFrame.along);
    if (!negativeIntersection || !positiveIntersection) return false;
    const negative = projectedDistance(record, negativeIntersection);
    const positive = projectedDistance(record, positiveIntersection);
    if (!joinDistanceIsBounded(record, hostWall, negative) || !joinDistanceIsBounded(record, hostWall, positive)) return false;
    Object.assign(profiles.get(record.wall.id)[record.endpoint], { negative, positive, kind: "butt", hostWallId: hostWall.id });
    return true;
  };

  const applyMiter = (record, other) => {
    const travel = travelDirection(record);
    const otherAway = awayDirection(other);
    const currentLeft = leftNormal2(travel);
    const otherLeft = leftNormal2(otherAway);
    const leftIntersection = lineIntersection(
      add2(record.point, scale2(currentLeft, record.wall.thickness / 2)),
      travel,
      add2(other.point, scale2(otherLeft, other.wall.thickness / 2)),
      otherAway,
    );
    const rightIntersection = lineIntersection(
      add2(record.point, scale2(currentLeft, -record.wall.thickness / 2)),
      travel,
      add2(other.point, scale2(otherLeft, -other.wall.thickness / 2)),
      otherAway,
    );
    if (!leftIntersection || !rightIntersection) return false;
    const leftDistance = projectedDistance(record, leftIntersection);
    const rightDistance = projectedDistance(record, rightIntersection);
    if (!joinDistanceIsBounded(record, other.wall, leftDistance) || !joinDistanceIsBounded(record, other.wall, rightDistance)) return false;
    const positiveIsLeft = dot2(record.frame.normal, currentLeft) > 0;
    Object.assign(profiles.get(record.wall.id)[record.endpoint], {
      negative: positiveIsLeft ? rightDistance : leftDistance,
      positive: positiveIsLeft ? leftDistance : rightDistance,
      kind: "miter",
      joinedWallId: other.wall.id,
    });
    return true;
  };

  for (const record of endpoints) {
    const hosts = normalizedPlan.walls
      .filter((wall) => wall.id !== record.wall.id && pointOnWallInterior(record.point, wall, frames.get(wall.id)))
      .sort((left, right) => right.thickness - left.thickness);
    if (hosts.length === 0) continue;
    if (applyButt(record, hosts[0])) {
      resolved.add(record.key);
      summary.buttedEnds += 1;
    }
    if (hosts.length > 1) summary.complexJunctions += 1;
  }

  for (const group of endpointGroups.values()) {
    const pending = group.filter((record) => !resolved.has(record.key));
    if (pending.length === 2 && group.length === 2) {
      const firstApplied = applyMiter(pending[0], pending[1]);
      const secondApplied = applyMiter(pending[1], pending[0]);
      if (firstApplied && secondApplied) {
        resolved.add(pending[0].key);
        resolved.add(pending[1].key);
        summary.miteredJunctions += 1;
      }
      continue;
    }
    if (pending.length < 3) continue;
    let hostPair = null;
    for (let leftIndex = 0; leftIndex < pending.length && hostPair === null; leftIndex += 1) {
      for (let rightIndex = leftIndex + 1; rightIndex < pending.length; rightIndex += 1) {
        if (dot2(awayDirection(pending[leftIndex]), awayDirection(pending[rightIndex])) < -0.9999) {
          hostPair = [pending[leftIndex], pending[rightIndex]];
          break;
        }
      }
    }
    if (!hostPair) {
      summary.complexJunctions += 1;
      continue;
    }
    resolved.add(hostPair[0].key);
    resolved.add(hostPair[1].key);
    const hostWall = hostPair[0].wall.thickness >= hostPair[1].wall.thickness ? hostPair[0].wall : hostPair[1].wall;
    for (const branch of pending.filter((record) => !hostPair.includes(record))) {
      if (applyButt(branch, hostWall)) {
        resolved.add(branch.key);
        summary.buttedEnds += 1;
      } else {
        summary.complexJunctions += 1;
      }
    }
  }

  summary.cappedEnds = endpoints.length - resolved.size;
  return { profiles, summary };
}

function polygonSignedArea(points) {
  let twiceArea = 0;
  for (let index = 0; index < points.length; index += 1) {
    const current = points[index];
    const next = points[(index + 1) % points.length];
    twiceArea += current[0] * next[1] - next[0] * current[1];
  }
  return twiceArea / 2;
}

function floorEdgeThickness(start, end, walls) {
  const edge = subtract2(end, start);
  const edgeLength = Math.hypot(edge[0], edge[1]);
  if (edgeLength < JOIN_EPSILON) return 0;
  const edgeDirection = scale2(edge, 1 / edgeLength);
  const matching = walls.filter((wall) => {
    const frame = wallFrame(wall);
    if (Math.abs(cross2(edgeDirection, frame.along)) > JOIN_EPSILON) return false;
    const startLateral = Math.abs(dot2(subtract2(start, wall.start), frame.normal));
    const endLateral = Math.abs(dot2(subtract2(end, wall.start), frame.normal));
    return startLateral <= JOIN_EPSILON && endLateral <= JOIN_EPSILON;
  });
  if (matching.length > 0) return Math.max(...matching.map((wall) => wall.thickness));
  return Math.max(...walls.map((wall) => wall.thickness));
}

function offsetFloorOutline(points, walls) {
  if (points.length < 3) return points;
  const orientation = polygonSignedArea(points) >= 0 ? 1 : -1;
  const edges = points.map((start, index) => {
    const end = points[(index + 1) % points.length];
    const delta = subtract2(end, start);
    const length = Math.hypot(delta[0], delta[1]);
    const direction = scale2(delta, 1 / length);
    const outward = orientation > 0 ? [direction[1], -direction[0]] : [-direction[1], direction[0]];
    const offset = floorEdgeThickness(start, end, walls) / 2;
    return { direction, offset, point: add2(start, scale2(outward, offset)), outward };
  });
  return points.map((point, index) => {
    const previous = edges[(index - 1 + edges.length) % edges.length];
    const current = edges[index];
    const intersection = lineIntersection(previous.point, previous.direction, current.point, current.direction);
    const maximumMiter = Math.max(previous.offset, current.offset, 1) * 8;
    if (intersection && Math.hypot(...subtract2(intersection, point)) <= maximumMiter) return intersection;
    const averageOutward = add2(scale2(previous.outward, previous.offset), scale2(current.outward, current.offset));
    return add2(point, scale2(averageOutward, 0.5));
  });
}

function buildFloorOutline(normalizedPlan) {
  const baseOutline = normalizedPlan.floor.outline.length >= 3
    ? normalizedPlan.floor.outline
    : (() => {
      const points = normalizedPlan.walls.flatMap((wall) => [wall.start, wall.end]);
      const xs = points.map((point) => point[0]);
      const ys = points.map((point) => point[1]);
      return [[Math.min(...xs), Math.min(...ys)], [Math.max(...xs), Math.min(...ys)], [Math.max(...xs), Math.max(...ys)], [Math.min(...xs), Math.max(...ys)]];
    })();
  return normalizedPlan.floor.outlineMode === "finished"
    ? baseOutline.map((point) => [...point])
    : offsetFloorOutline(baseOutline, normalizedPlan.walls);
}

function wallPoint(normalizedPlan, wall, frame, distance, lateral, height) {
  return [
    normalizedPlan.origin[0] + wall.start[0] + frame.along[0] * distance + frame.normal[0] * lateral,
    normalizedPlan.origin[1] + wall.start[1] + frame.along[1] * distance + frame.normal[1] * lateral,
    height,
  ];
}

function buildWallFootprints(normalizedPlan, joinProfiles = buildWallJoinProfiles(normalizedPlan).profiles) {
  return normalizedPlan.walls.map((wall) => {
    const frame = wallFrame(wall);
    const halfThickness = wall.thickness / 2;
    const profile = joinProfiles.get(wall.id);
    return [
      wallPoint(normalizedPlan, wall, frame, profile.start.negative, -halfThickness, 0),
      wallPoint(normalizedPlan, wall, frame, profile.end.negative, -halfThickness, 0),
      wallPoint(normalizedPlan, wall, frame, profile.end.positive, halfThickness, 0),
      wallPoint(normalizedPlan, wall, frame, profile.start.positive, halfThickness, 0),
    ];
  });
}

function buildOpeningAwareWallTopology(normalizedPlan, joinProfiles = buildWallJoinProfiles(normalizedPlan).profiles) {
  const vertices = [];
  const faces = [];
  const pieces = [];
  for (const wall of normalizedPlan.walls) {
    const frame = wallFrame(wall);
    const profile = joinProfiles.get(wall.id);
    const openings = normalizedPlan.openings.filter((opening) => opening.wallId === wall.id);
    const bounds = [0, frame.length];
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
        const positiveFrom = Math.abs(from) < JOIN_EPSILON ? profile.start.positive : from;
        const negativeFrom = Math.abs(from) < JOIN_EPSILON ? profile.start.negative : from;
        const positiveTo = Math.abs(to - frame.length) < JOIN_EPSILON ? profile.end.positive : to;
        const negativeTo = Math.abs(to - frame.length) < JOIN_EPSILON ? profile.end.negative : to;
        vertices.push(
          wallPoint(normalizedPlan, wall, frame, positiveFrom, halfThickness, zFrom),
          wallPoint(normalizedPlan, wall, frame, positiveTo, halfThickness, zFrom),
          wallPoint(normalizedPlan, wall, frame, negativeTo, -halfThickness, zFrom),
          wallPoint(normalizedPlan, wall, frame, negativeFrom, -halfThickness, zFrom),
          wallPoint(normalizedPlan, wall, frame, positiveFrom, halfThickness, zTo),
          wallPoint(normalizedPlan, wall, frame, positiveTo, halfThickness, zTo),
          wallPoint(normalizedPlan, wall, frame, negativeTo, -halfThickness, zTo),
          wallPoint(normalizedPlan, wall, frame, negativeFrom, -halfThickness, zTo),
        );
        const localFaces = [
          [0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1],
          [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0],
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
  const joinAnalysis = buildWallJoinProfiles(normalizedPlan);
  const wallFootprints = buildWallFootprints(normalizedPlan, joinAnalysis.profiles);
  const wallTopology = buildOpeningAwareWallTopology(normalizedPlan, joinAnalysis.profiles);
  const statements = [];
  const segmentCount = wallTopology.pieces.length;
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
  statements.push("  local buildResult = \\");
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

  if (normalizedPlan.floor.enabled) {
    const outline = buildFloorOutline(normalizedPlan);
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
  statements.push(`    buildResult = "sourceHandle=" + ((getHandleByAnim wallPlanSource) as string) + ";sourceSpline=" + sourceSplineName + ";wallHandle=" + ((getHandleByAnim wallMesh) as string) + ";wallMesh=" + wallMeshName + ";walls=${normalizedPlan.walls.length};segments=${segmentCount};openings=${normalizedPlan.openings.length};helpers=0;floor=${normalizedPlan.floor.enabled ? 1 : 0}"`);
  statements.push("  )");
  statements.push("  buildResult");
  statements.push(")");
  return {
    script: statements.join("\n"),
    segmentCount,
    placeholderCount: 0,
    openingHelperCount: 0,
    sourceSplineName,
    wallMeshName,
    modelingWorkflow: "spline-copy-extrude-meshop",
    normalOrientation: "outward",
    junctions: joinAnalysis.summary,
  };
}

module.exports = {
  buildOpeningAwareWallTopology,
  buildFloorOutline,
  buildWallJoinProfiles,
  canonicalString,
  generateFloorPlanScript,
  validateFloorPlan,
};
