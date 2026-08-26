/*
 * Generates and parses bounded read-only 3ds Max material diagnostics.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

function maxBoolean(value) {
  return value === true ? "true" : "false";
}

function boundedLimit(value) {
  const parsed = Number(value ?? 100);
  if (!Number.isFinite(parsed)) throw new Error("limit must be a finite number");
  return Math.min(200, Math.max(1, Math.trunc(parsed)));
}

function generateMaterialDiagnosticsScript(options = {}) {
  const limit = boundedLimit(options.limit);
  const script = `(
  -- Max Ultra MCP: Find material diagnostics
  local includeHidden = ${maxBoolean(options.includeHidden !== false)}
  local includeFrozen = ${maxBoolean(options.includeFrozen !== false)}
  local includeXRefs = ${maxBoolean(options.includeXRefs === true)}
  local includeNonGeometry = ${maxBoolean(options.includeNonGeometry === true)}
  local includeMissingMaps = ${maxBoolean(options.includeMissingMaps !== false)}
  local maximumRecords = ${limit}
  local maximumJsonCharacters = 12000

  fn mcpJsonEscape inputValue = (
    local escapedValue = inputValue as string
    escapedValue = substituteString escapedValue "\\\\" "\\\\\\\\"
    escapedValue = substituteString escapedValue "\\\"" "\\\\\""
    escapedValue = substituteString escapedValue "\\r" "\\\\r"
    escapedValue = substituteString escapedValue "\\n" "\\\\n"
    escapedValue = substituteString escapedValue "\\t" "\\\\t"
    return escapedValue
  )

  fn mcpJoinStrings stringValues separatorValue = (
    local joinedValue = ""
    for stringIndex in 1 to stringValues.count do (
      if (stringIndex > 1) do joinedValue += separatorValue
      joinedValue += stringValues[stringIndex]
    )
    return joinedValue
  )

  fn mcpJsonStringArray stringValues = (
    local jsonValues = #()
    for stringValue in stringValues do append jsonValues ("\\"" + (mcpJsonEscape stringValue) + "\\"")
    return "[" + (mcpJoinStrings jsonValues ",") + "]"
  )

  fn mcpNodeRecord nodeValue materialClassValue emptySlotCount missingPaths = (
    local nodeHandle = (getHandleByAnim nodeValue) as string
    local layerName = try (nodeValue.layer.name as string) catch ("")
    local className = try ((classOf nodeValue) as string) catch ("Unknown")
    return "{\\"node\\":{\\"handle\\":" + nodeHandle + ",\\"name\\":\\"" + (mcpJsonEscape nodeValue.name) + "\\"}," +
      "\\"className\\":\\"" + (mcpJsonEscape className) + "\\",\\"layer\\":\\"" + (mcpJsonEscape layerName) + "\\"," +
      "\\"materialClass\\":\\"" + (mcpJsonEscape materialClassValue) + "\\",\\"emptySlots\\":" + (emptySlotCount as string) + "," +
      "\\"missingPaths\\":" + (mcpJsonStringArray missingPaths) + "}"
  )

  local noMaterialRecords = #()
  local invalidMaterialRecords = #()
  local emptyMultiSubSlotRecords = #()
  local unsupportedMaterialRecords = #()
  local materialMissingMapsRecords = #()
  local scannedCount = 0
  local matchedCount = 0
  local returnedCount = 0
  local jsonCharacterCount = 0

  for nodeValue in objects do (
    local geometryAllowed = includeNonGeometry or ((superClassOf nodeValue) == GeometryClass)
    local hiddenAllowed = includeHidden or (not nodeValue.isHidden)
    local frozenAllowed = includeFrozen or (not nodeValue.isFrozen)
    local xrefNode = try (isXRefObject nodeValue) catch (false)
    local xrefAllowed = includeXRefs or (not xrefNode)
    if (geometryAllowed and hiddenAllowed and frozenAllowed and xrefAllowed) do (
      scannedCount += 1
      local noMaterialMatch = false
      local invalidMaterialMatch = false
      local emptyMultiSubSlotMatch = false
      local unsupportedMaterialMatch = false
      local missingMapsMatch = false
      local materialValue = undefined
      local materialReadSucceeded = true
      local materialClassValue = ""
      local emptySlotCount = 0
      local missingPaths = #()

      try (materialValue = nodeValue.material) catch (materialReadSucceeded = false)
      if (not materialReadSucceeded) then (
        invalidMaterialMatch = true
      ) else if (materialValue == undefined) then (
        noMaterialMatch = true
      ) else (
        materialClassValue = try ((classOf materialValue) as string) catch ("Unknown")
        if (not (isKindOf materialValue Material)) do invalidMaterialMatch = true
        if ((matchPattern materialClassValue pattern:"*Missing*" ignoreCase:true) or (matchPattern materialClassValue pattern:"*Unknown*" ignoreCase:true)) do unsupportedMaterialMatch = true
        if (isProperty materialValue #numsubs) do (
          local materialSlotCount = try (materialValue.numsubs as integer) catch (0)
          for slotIndex in 1 to materialSlotCount do (
            local slotMaterial = try (materialValue[slotIndex]) catch (undefined)
            if (slotMaterial == undefined) do emptySlotCount += 1
          )
          if (emptySlotCount > 0) do emptyMultiSubSlotMatch = true
        )
        if (includeMissingMaps) do (
          local bitmapMaps = try (getClassInstances Bitmaptexture target:materialValue) catch (#())
          for bitmapMap in bitmapMaps do (
            local bitmapPath = try (bitmapMap.filename as string) catch ("")
            if ((bitmapPath != "") and (not (doesFileExist bitmapPath))) do appendIfUnique missingPaths bitmapPath
          )
          if (missingPaths.count > 0) do missingMapsMatch = true
        )
      )

      local categoryCount = 0
      if (noMaterialMatch) do categoryCount += 1
      if (invalidMaterialMatch) do categoryCount += 1
      if (emptyMultiSubSlotMatch) do categoryCount += 1
      if (unsupportedMaterialMatch) do categoryCount += 1
      if (missingMapsMatch) do categoryCount += 1
      if (categoryCount > 0) do (
        matchedCount += 1
        local recordValue = mcpNodeRecord nodeValue materialClassValue emptySlotCount missingPaths
        local recordCost = recordValue.count * categoryCount
        if ((returnedCount < maximumRecords) and ((jsonCharacterCount + recordCost) <= maximumJsonCharacters)) do (
          if (noMaterialMatch) do append noMaterialRecords recordValue
          if (invalidMaterialMatch) do append invalidMaterialRecords recordValue
          if (emptyMultiSubSlotMatch) do append emptyMultiSubSlotRecords recordValue
          if (unsupportedMaterialMatch) do append unsupportedMaterialRecords recordValue
          if (missingMapsMatch) do append materialMissingMapsRecords recordValue
          returnedCount += 1
          jsonCharacterCount += recordCost
        )
      )
    )
  )

  return "{\\"scanned\\":" + (scannedCount as string) +
    ",\\"matched\\":" + (matchedCount as string) +
    ",\\"returned\\":" + (returnedCount as string) +
    ",\\"truncated\\":" + ((matchedCount > returnedCount) as string) +
    ",\\"categories\\":{" +
      "\\"noMaterial\\":[" + (mcpJoinStrings noMaterialRecords ",") + "]," +
      "\\"invalidMaterial\\":[" + (mcpJoinStrings invalidMaterialRecords ",") + "]," +
      "\\"emptyMultiSubSlot\\":[" + (mcpJoinStrings emptyMultiSubSlotRecords ",") + "]," +
      "\\"unsupportedMaterial\\":[" + (mcpJoinStrings unsupportedMaterialRecords ",") + "]," +
      "\\"materialMissingMaps\\":[" + (mcpJoinStrings materialMissingMapsRecords ",") + "]" +
    "},\\"coverage\\":{\\"missingMaps\\":\\"Bitmaptexture file inputs; renderer-specific assets require max_assets_scan\\"}}"
)`;
  const scriptLines = script.split("\n");
  const escapeLineIndexes = scriptLines
    .map((line, index) => line.includes("substituteString escapedValue") ? index : -1)
    .filter((index) => index >= 0);
  if (escapeLineIndexes.length !== 5) throw new Error("Material diagnostic escape helper is incomplete");
  scriptLines[escapeLineIndexes[1]] = "    escapedValue = substituteString escapedValue " +
    JSON.stringify(String.fromCharCode(34)) + " " +
    JSON.stringify(String.fromCharCode(92, 34));
  return scriptLines.join("\n");
}

function parseMaterialDiagnostics(execution, sceneRevision) {
  const rawResult = String(execution?.result || "");
  let parsed;
  try {
    parsed = JSON.parse(rawResult);
  } catch {
    throw new Error("MATERIAL_DIAGNOSTICS_INVALID: 3ds Max returned an invalid or oversized material report");
  }
  const categoryNames = ["noMaterial", "invalidMaterial", "emptyMultiSubSlot", "unsupportedMaterial", "materialMissingMaps"];
  const categories = {};
  for (const categoryName of categoryNames) {
    const records = Array.isArray(parsed.categories?.[categoryName]) ? parsed.categories[categoryName] : [];
    categories[categoryName] = records.map((record) => ({
      ...record,
      node: { ...record.node, sceneRevision },
    }));
  }
  return {
    scanned: Number(parsed.scanned || 0),
    matched: Number(parsed.matched || 0),
    returned: Number(parsed.returned || 0),
    truncated: parsed.truncated === true,
    categories,
    counts: Object.fromEntries(categoryNames.map((categoryName) => [categoryName, categories[categoryName].length])),
    coverage: parsed.coverage || {},
  };
}

module.exports = { generateMaterialDiagnosticsScript, parseMaterialDiagnostics };
