/*
 * Validates structured polygon meshes and generates bounded MaxScript creation code.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { canonicalString, hashCanonical } = require("./plan-token");

const MAX_VERTICES = 10000;
const MAX_FACES = 20000;
const MAX_FACE_VERTICES = 256;
const MAX_FACE_VERTEX_REFERENCES = 100000;
const SUPPORTED_UNITS = new Set(["scene", "mm", "cm", "m", "in", "ft"]);

function finite(value, field) {
  const number = Number(value);
  if (!Number.isFinite(number)) throw new Error(`${field} must be a finite number`);
  return Object.is(number, -0) ? 0 : number;
}

function integer(value, field, minimum, maximum) {
  const number = Number(value);
  if (!Number.isInteger(number) || number < minimum || number > maximum) {
    throw new Error(`${field} must be an integer from ${minimum} to ${maximum}`);
  }
  return number;
}

function point3(value, field) {
  if (!Array.isArray(value) || value.length !== 3) throw new Error(`${field} must contain exactly three numbers`);
  return value.map((coordinate, axis) => finite(coordinate, `${field}[${axis}]`));
}

function faceNormal(points) {
  const normal = [0, 0, 0];
  for (let index = 0; index < points.length; index += 1) {
    const current = points[index];
    const next = points[(index + 1) % points.length];
    normal[0] += (current[1] - next[1]) * (current[2] + next[2]);
    normal[1] += (current[2] - next[2]) * (current[0] + next[0]);
    normal[2] += (current[0] - next[0]) * (current[1] + next[1]);
  }
  return normal;
}

function validatePolygonMesh(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("mesh must be an object");
  const name = String(input.name || "").trim();
  if (!name || name.length > 128 || /[|\r\n\t]/.test(name)) throw new Error("mesh.name must contain 1 to 128 characters and no control or pipe characters");
  const units = String(input.units || "scene").toLowerCase();
  if (!SUPPORTED_UNITS.has(units)) throw new Error("mesh.units must be scene, mm, cm, m, in, or ft");
  if (!Array.isArray(input.vertices) || input.vertices.length < 3) throw new Error("mesh.vertices must contain at least three points");
  if (!Array.isArray(input.faces) || input.faces.length < 1) throw new Error("mesh.faces must contain at least one face");

  const vertices = input.vertices.map((vertex, index) => point3(vertex, `mesh.vertices[${index}]`));
  const faces = input.faces.map((faceInput, faceIndex) => {
    const faceObject = Array.isArray(faceInput) ? { vertices: faceInput } : faceInput;
    if (!faceObject || typeof faceObject !== "object") throw new Error(`mesh.faces[${faceIndex}] must be an index array or face object`);
    if (!Array.isArray(faceObject.vertices) || faceObject.vertices.length < 3 || faceObject.vertices.length > MAX_FACE_VERTICES) {
      throw new Error(`mesh.faces[${faceIndex}].vertices must contain 3 to ${MAX_FACE_VERTICES} indices`);
    }
    return {
      vertices: faceObject.vertices.map((vertexIndex, index) => integer(vertexIndex, `mesh.faces[${faceIndex}].vertices[${index}]`, 0, Number.MAX_SAFE_INTEGER)),
      materialId: integer(faceObject.materialId ?? 1, `mesh.faces[${faceIndex}].materialId`, 1, 65535),
      smoothingGroup: integer(faceObject.smoothingGroup ?? 0, `mesh.faces[${faceIndex}].smoothingGroup`, 0, 2147483647),
    };
  });
  const position = point3(input.position || [0, 0, 0], "mesh.position");
  const layer = String(input.layer || "").trim();
  if (layer.length > 128 || /[\r\n\t]/.test(layer)) throw new Error("mesh.layer must contain at most 128 characters and no control characters");
  const normalizedMesh = {
    name,
    units,
    vertices,
    faces,
    position,
    layer,
    select: input.select !== false,
    allowNonManifold: input.allowNonManifold === true,
    subdivisionReady: input.subdivisionReady === true,
    requireSingleShell: input.requireSingleShell === true,
  };

  const warnings = [];
  const blockers = [];
  if (vertices.length > MAX_VERTICES) blockers.push(`Mesh has ${vertices.length} vertices; the synchronous v1 limit is ${MAX_VERTICES}`);
  if (faces.length > MAX_FACES) blockers.push(`Mesh has ${faces.length} faces; the synchronous v1 limit is ${MAX_FACES}`);

  const minimum = [...vertices[0]];
  const maximum = [...vertices[0]];
  for (const vertex of vertices) {
    for (let axis = 0; axis < 3; axis += 1) {
      minimum[axis] = Math.min(minimum[axis], vertex[axis]);
      maximum[axis] = Math.max(maximum[axis], vertex[axis]);
    }
  }
  const size = maximum.map((coordinate, axis) => coordinate - minimum[axis]);
  const diagonal = Math.max(Math.hypot(...size), 1);
  const areaTolerance = diagonal * diagonal * 1e-12;
  const planarityTolerance = diagonal * 1e-6;
  const referencedVertices = new Set();
  const faceKeys = new Set();
  const edgeUses = new Map();
  const vertexNeighbors = Array.from({ length: vertices.length }, () => new Set());
  let faceVertexReferences = 0;
  let nonPlanarFaces = 0;
  let triangles = 0;
  let quads = 0;
  let ngons = 0;

  faces.forEach((face, faceIndex) => {
    faceVertexReferences += face.vertices.length;
    if (face.vertices.length === 3) triangles += 1;
    else if (face.vertices.length === 4) quads += 1;
    else ngons += 1;
    const uniqueIndices = new Set(face.vertices);
    if (uniqueIndices.size !== face.vertices.length) blockers.push(`Face ${faceIndex} repeats a vertex index`);
    const invalidIndices = face.vertices.filter((vertexIndex) => vertexIndex >= vertices.length);
    if (invalidIndices.length) {
      blockers.push(`Face ${faceIndex} references vertex ${invalidIndices[0]}, but the highest valid index is ${vertices.length - 1}`);
      return;
    }
    const faceKey = [...face.vertices].sort((left, right) => left - right).join(",");
    if (faceKeys.has(faceKey)) blockers.push(`Face ${faceIndex} duplicates another face`);
    faceKeys.add(faceKey);
    face.vertices.forEach((vertexIndex) => referencedVertices.add(vertexIndex));

    const points = face.vertices.map((vertexIndex) => vertices[vertexIndex]);
    const normal = faceNormal(points);
    const normalLength = Math.hypot(...normal);
    if (normalLength <= areaTolerance) {
      blockers.push(`Face ${faceIndex} is degenerate or has near-zero area`);
    } else if (points.length > 3) {
      const unitNormal = normal.map((coordinate) => coordinate / normalLength);
      const planeOffset = unitNormal[0] * points[0][0] + unitNormal[1] * points[0][1] + unitNormal[2] * points[0][2];
      const maximumDistance = Math.max(...points.map((point) => Math.abs(unitNormal[0] * point[0] + unitNormal[1] * point[1] + unitNormal[2] * point[2] - planeOffset)));
      if (maximumDistance > planarityTolerance) nonPlanarFaces += 1;
    }

    for (let edgeIndex = 0; edgeIndex < face.vertices.length; edgeIndex += 1) {
      const from = face.vertices[edgeIndex];
      const to = face.vertices[(edgeIndex + 1) % face.vertices.length];
      if (from === to) continue;
      const low = Math.min(from, to);
      const high = Math.max(from, to);
      const key = `${low}:${high}`;
      const edge = edgeUses.get(key) || { count: 0, directions: [], faceIndices: [], low, high };
      edge.count += 1;
      edge.directions.push(from === low ? 1 : -1);
      edge.faceIndices.push(faceIndex);
      edgeUses.set(key, edge);
      vertexNeighbors[from].add(to);
      vertexNeighbors[to].add(from);
    }
  });

  if (faceVertexReferences > MAX_FACE_VERTEX_REFERENCES) {
    blockers.push(`Mesh has ${faceVertexReferences} face-vertex references; the synchronous v1 limit is ${MAX_FACE_VERTEX_REFERENCES}`);
  }
  const boundaryEdges = [...edgeUses.values()].filter((edge) => edge.count === 1).length;
  const nonManifoldEdges = [...edgeUses.values()].filter((edge) => edge.count > 2).length;
  const inconsistentEdges = [...edgeUses.values()].filter((edge) => edge.count === 2 && edge.directions[0] === edge.directions[1]).length;
  const isolatedVertices = vertices.length - referencedVertices.size;
  const faceParents = faces.map((face, faceIndex) => faceIndex);
  const findFaceRoot = (faceIndex) => {
    let root = faceIndex;
    while (faceParents[root] !== root) root = faceParents[root];
    while (faceParents[faceIndex] !== faceIndex) {
      const parent = faceParents[faceIndex];
      faceParents[faceIndex] = root;
      faceIndex = parent;
    }
    return root;
  };
  const unionFaces = (leftFace, rightFace) => {
    const leftRoot = findFaceRoot(leftFace);
    const rightRoot = findFaceRoot(rightFace);
    if (leftRoot !== rightRoot) faceParents[rightRoot] = leftRoot;
  };
  for (const edge of edgeUses.values()) {
    for (let faceUseIndex = 1; faceUseIndex < edge.faceIndices.length; faceUseIndex += 1) {
      unionFaces(edge.faceIndices[0], edge.faceIndices[faceUseIndex]);
    }
  }
  const elements = new Set(faces.map((face, faceIndex) => findFaceRoot(faceIndex))).size;
  const maximumValence = Math.max(...vertexNeighbors.map((neighbors) => neighbors.size));
  const highValenceVertices = vertexNeighbors.filter((neighbors) => neighbors.size >= 6).length;
  const quadRatio = faces.length ? quads / faces.length : 0;
  if (boundaryEdges) warnings.push(`Mesh has ${boundaryEdges} boundary edges and is open`);
  if (nonManifoldEdges) {
    const message = `Mesh has ${nonManifoldEdges} non-manifold edges used by more than two faces`;
    if (normalizedMesh.allowNonManifold) warnings.push(message);
    else blockers.push(`${message}; set allowNonManifold only when this topology is intentional`);
  }
  if (inconsistentEdges) {
    const message = `Mesh has ${inconsistentEdges} shared edges with inconsistent face winding`;
    if (normalizedMesh.subdivisionReady) blockers.push(message);
    else warnings.push(message);
  }
  if (isolatedVertices) {
    const message = `Mesh has ${isolatedVertices} isolated vertices`;
    if (normalizedMesh.subdivisionReady) blockers.push(message);
    else warnings.push(message);
  }
  if (nonPlanarFaces) warnings.push(`Mesh has ${nonPlanarFaces} non-planar n-gons; triangulate them when exact tessellation matters`);
  if (normalizedMesh.requireSingleShell && elements !== 1) blockers.push(`Mesh has ${elements} edge-connected polygon Elements; one continuous shell is required`);
  if (normalizedMesh.subdivisionReady) {
    if (ngons) blockers.push(`Subdivision-ready mesh has ${ngons} n-gons; use quads or controlled triangles`);
    if (triangles) warnings.push(`Subdivision-ready mesh has ${triangles} triangles; verify each diagonal and pole placement`);
    if (quadRatio < 0.8) warnings.push(`Subdivision-ready mesh is ${Math.round(quadRatio * 100)}% quads; review edge flow before creation`);
    if (highValenceVertices) warnings.push(`Subdivision-ready mesh has ${highValenceVertices} vertices with valence 6 or higher; keep them away from deformation and silhouette regions`);
  }

  const boundingBox = { min: minimum, max: maximum, size };
  const counts = {
    vertices: vertices.length,
    faces: faces.length,
    edges: edgeUses.size,
    boundaryEdges,
    nonManifoldEdges,
    isolatedVertices,
    faceVertexReferences,
    triangles,
    quads,
    ngons,
    quadRatio,
    elements,
    maximumValence,
    highValenceVertices,
  };
  const validationToken = hashCanonical(normalizedMesh);
  return { normalizedMesh, validationToken, warnings, blockers, boundingBox, counts, valid: blockers.length === 0 };
}

function maxString(value) {
  return JSON.stringify(String(value));
}

function maxNumber(value) {
  const number = Number(value);
  return Object.is(number, -0) ? "0" : String(number);
}

function generatePolygonMeshScript(normalizedMesh) {
  const unitScale = normalizedMesh.units === "scene" ? "1.0" : `units.decodeValue ${maxString(`1${normalizedMesh.units}`)}`;
  const vertexValues = normalizedMesh.vertices.map((vertex) => `([${vertex.map(maxNumber).join(",")}] * unitScale)`).join(",");
  const polygonValues = normalizedMesh.faces.map((face) => `#(${face.vertices.map((index) => index + 1).join(",")})`).join(",");
  const materialIds = normalizedMesh.faces.map((face) => face.materialId).join(",");
  const smoothingGroups = normalizedMesh.faces.map((face) => face.smoothingGroup).join(",");
  const positionValue = normalizedMesh.position.map(maxNumber).join(",");
  const layerStatements = normalizedMesh.layer ? [
    `      local targetLayer = LayerManager.getLayerFromName ${maxString(normalizedMesh.layer)}`,
    `      if (targetLayer == undefined) do targetLayer = LayerManager.newLayerFromName ${maxString(normalizedMesh.layer)}`,
    "      targetLayer.addNode createdNode",
  ] : [];
  const statements = [
    "(",
    "  fn addPolygon targetMesh polygonIndices smoothingGroup materialId = (",
    "    local previousFaceCount = meshop.getNumFaces targetMesh",
    "    meshop.createPolygon targetMesh polygonIndices smGroup:smoothingGroup matID:materialId",
    `    if ((meshop.getNumFaces targetMesh) <= previousFaceCount) do throw ${maxString("meshop.createPolygon did not create geometry")}`,
    "    return true",
    "  )",
    `  local nodeName = ${maxString(normalizedMesh.name)}`,
    `  local unitScale = ${unitScale}`,
    `  local vertexValues = #(${vertexValues})`,
    `  local polygonValues = #(${polygonValues})`,
    `  local materialIds = #(${materialIds})`,
    `  local smoothingGroups = #(${smoothingGroups})`,
    "  local createdNode = undefined",
    '  if (getNodeByName nodeName exact:true != undefined) do throw (nodeName + " already exists")',
    '  undo "Max Ultra MCP: Create polygon mesh" on (',
    "    try (",
    "      createdNode = mesh name:nodeName vertices:vertexValues faces:#()",
    "      if (polygonValues.count > 1) do undo off (",
    "        for polygonIndex = 1 to (polygonValues.count - 1) do addPolygon createdNode polygonValues[polygonIndex] smoothingGroups[polygonIndex] materialIds[polygonIndex]",
    "      )",
    "      addPolygon createdNode polygonValues[polygonValues.count] smoothingGroups[polygonValues.count] materialIds[polygonValues.count]",
    "      update createdNode",
    "      convertToPoly createdNode",
    '      if ((classOf createdNode.baseObject) != Editable_Poly) do throw "Created object could not be converted to Editable Poly"',
    `      createdNode.pos = ([${positionValue}] * unitScale)`,
    ...layerStatements,
    `      if (${normalizedMesh.select}) do select createdNode`,
    "    ) catch (",
    "      local failureMessage = getCurrentException() as string",
    "      if (isValidNode createdNode) do delete createdNode",
    "      throw failureMessage",
    "    )",
    "  )",
    "  local vertexCount = polyop.getNumVerts createdNode",
    "  local edgeCount = polyop.getNumEdges createdNode",
    "  local faceCount = polyop.getNumFaces createdNode",
    "  local openEdgeCount = (polyop.getOpenEdges createdNode).numberSet",
    '  ((getHandleByAnim createdNode) as string) + "|" + createdNode.name + "|" + (vertexCount as string) + "|" + (edgeCount as string) + "|" + (faceCount as string) + "|" + (openEdgeCount as string) + "|" + ((classOf createdNode.baseObject) as string)',
    ")",
  ];
  return { script: statements.join("\n") };
}

module.exports = {
  MAX_FACES,
  MAX_FACE_VERTICES,
  MAX_FACE_VERTEX_REFERENCES,
  MAX_VERTICES,
  canonicalString,
  generatePolygonMeshScript,
  validatePolygonMesh,
};
