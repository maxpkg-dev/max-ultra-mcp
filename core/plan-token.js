/*
 * Canonical validation and operation-plan tokens for Max Ultra MCP.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { createHash, timingSafeEqual } = require("node:crypto");

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

function canonicalString(value) {
  return JSON.stringify(canonicalize(value));
}

function hashCanonical(value) {
  return createHash("sha256").update(canonicalString(value)).digest("hex");
}

function createPlanToken(binding) {
  if (!binding || typeof binding !== "object") throw new Error("Plan-token binding is required");
  const normalized = {
    operation: String(binding.operation || "").trim(),
    instanceId: String(binding.instanceId || "").trim(),
    sceneRevision: Number(binding.sceneRevision),
    request: binding.request ?? null,
    targets: binding.targets ?? [],
    capabilities: binding.capabilities ?? {},
    externalState: binding.externalState ?? {},
  };
  if (!normalized.operation) throw new Error("Plan-token operation is required");
  if (!normalized.instanceId) throw new Error("Plan-token instanceId is required");
  if (!Number.isInteger(normalized.sceneRevision) || normalized.sceneRevision < 0) throw new Error("Plan-token sceneRevision must be a non-negative integer");
  return hashCanonical(normalized);
}

function tokensEqual(actual, expected) {
  if (typeof actual !== "string" || typeof expected !== "string") return false;
  const actualBytes = Buffer.from(actual, "utf8");
  const expectedBytes = Buffer.from(expected, "utf8");
  return actualBytes.length === expectedBytes.length && timingSafeEqual(actualBytes, expectedBytes);
}

function verifyPlanToken(token, binding) {
  if (!tokensEqual(token, createPlanToken(binding))) throw new Error("STALE_PLAN: plan token no longer matches the instance, scene, targets, capabilities, or external state");
  return true;
}

module.exports = { canonicalString, createPlanToken, hashCanonical, tokensEqual, verifyPlanToken };
