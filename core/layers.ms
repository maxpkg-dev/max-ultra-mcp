/*
 * Executes validated layer reads, previews and transactions on the Max main thread.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
fn layerArg keyName fallbackValue: undefined = (
    for pairValue in layerRequest where (pairValue[1] == keyName) do return pairValue[2]
    return fallbackValue
)
fn layerField recordValue keyName fallbackValue: undefined = (
    if (recordValue != undefined) do (
        for pairValue in recordValue where (pairValue[1] == keyName) do return pairValue[2]
    )
    return fallbackValue
)
fn layerObject pairsValue = (return #(#object, pairsValue))
fn layerJson inputValue = (
    if (inputValue == undefined) do return "null"
    if ((classOf inputValue) == String or (classOf inputValue) == Name) do (
        local escapedValue = inputValue as string
        escapedValue = substituteString escapedValue "\\" "\\\\"
        escapedValue = substituteString escapedValue "\"" "\\\""
        for characterIndex in 1 to 31 do (
            local characterValue = (dotNetClass "System.Char").ConvertFromUtf32 characterIndex
            local unicodeEscape = "\\u" + (formattedPrint characterIndex format: "04x")
            escapedValue = substituteString escapedValue characterValue unicodeEscape
        )
        return "\"" + escapedValue + "\""
    )
    if ((classOf inputValue) == BooleanClass) do return (if (inputValue) then "true" else "false")
    if ((classOf inputValue) == Color) do return layerJson #(inputValue.r as integer, inputValue.g as integer, inputValue.b as integer)
    if ((classOf inputValue) == Array) do (
        local objectMode = (inputValue.count == 2 and inputValue[1] == #object)
        local members = if (objectMode) then inputValue[2] else inputValue
        local jsonText = if (objectMode) then "{" else "["
        for memberIndex in 1 to members.count do (
            if (memberIndex > 1) do jsonText += ","
            jsonText += if (objectMode) then ((layerJson members[memberIndex][1]) + ":" + (layerJson members[memberIndex][2])) else (layerJson members[memberIndex])
        )
        return jsonText + (if (objectMode) then "}" else "]")
    )
    if ((findItem #("Integer", "Integer64", "IntegerPtr") ((classOf inputValue) as string)) > 0) do return trimRight (inputValue as string) "LP"
    return formattedPrint (inputValue as float) format: ".12g"
)
fn layerFail codeValue messageValue = (throw (codeValue + ": " + messageValue))
fn layerHandle layerValue = (
    if (layerValue == undefined) do return 0
    return (getHandleByAnim layerValue.layerAsRefTarg) as integer64
)
local layerUniverse = #()
local layerSceneId = ""
local layerZero
fn layerResolve selectorValue allowNull: false = (
    if (selectorValue == undefined) then (
        if (allowNull) do return undefined
        layerFail "VALIDATION_FAILED" "Layer selector is required"
    )
    local requestedHandle = layerField selectorValue "handle"
    if (requestedHandle != undefined) then (
        if ((layerField selectorValue "instanceId") != layerInstanceId or (layerField selectorValue "sceneId") != layerSceneId) do layerFail "STALE_LAYER_REF" "Layer belongs to another scene or instance"
        for candidateLayer in layerUniverse where ((layerHandle candidateLayer) == requestedHandle) do return candidateLayer
        layerFail "STALE_LAYER_REF" "Layer no longer belongs to the current scene"
    ) else (
        local requestedName = layerField selectorValue "name"
        local namedLayer = LayerManager.getLayerFromName requestedName
        if (namedLayer == undefined) do layerFail "LAYER_NOT_FOUND" "Named layer does not exist"
        return namedLayer
    )
)
fn layerReference layerValue = (
    if (layerValue == undefined) do return undefined
    return layerObject #(#("handle", layerHandle layerValue), #("name", layerValue.name), #("instanceId", layerInstanceId), #("sceneId", layerSceneId))
)
local layerPropertyNames = #("isHidden", "isFrozen", "wireColor", "renderable", "inheritVisibility", "primaryVisibility", "secondaryVisibility", "receiveShadows", "castShadows", "applyAtmospherics", "renderOccluded", "boxMode", "backfaceCull", "allEdges", "vertexTicks", "showTrajectory", "xray", "ignoreExtents", "showFrozenInGray", "isGIExcluded", "visibility")
fn layerProperties layerValue = (
    local propertyPairs = #()
    for propertyName in layerPropertyNames do (
        if (isProperty layerValue (propertyName as name)) do append propertyPairs #(propertyName, getProperty layerValue (propertyName as name))
    )
    return layerObject propertyPairs
)
fn layerRecord layerValue = (
    return layerObject #(#("layer", layerReference layerValue), #("parent", layerReference (layerValue.getParent())), #("nodeCount", layerValue.getNumNodes()), #("childCount", layerValue.getNumChildren()), #("current", layerValue.current), #("hasSceneXRefs", layerValue.hasSceneXRefNodesInHierarchy()), #("properties", layerProperties layerValue))
)
fn layerDescendants rootLayer = (
    local branchLayers = #(rootLayer)
    local branchIndex = 1
    while (branchIndex <= branchLayers.count) do (
        local branchLayer = branchLayers[branchIndex]
        for childIndex in 1 to branchLayer.getNumChildren() do (
            local childLayer = branchLayer.getChild childIndex
            if (childLayer != undefined and (findItem branchLayers childLayer) == 0) do append branchLayers childLayer
        )
        if (branchLayers.count > 5000) do layerFail "LAYER_LIMIT_EXCEEDED" "Layer hierarchy exceeds 5000 layers"
        branchIndex += 1
    )
    return branchLayers
)
fn layerOwnNodes layerValue = (
    local ownNodes = #()
    if (not (layerValue.nodes &ownNodes)) do layerFail "LAYER_OPERATION_FAILED" "Could not inspect layer nodes"
    return ownNodes
)
fn layerNodes layerValues maximumCount: 2000 = (
    local combinedNodes = #()
    for layerValue in layerValues do (
        if ((combinedNodes.count + layerValue.getNumNodes()) > maximumCount) do layerFail "LAYER_LIMIT_EXCEEDED" "Node batch is too large; narrow layer scope"
        join combinedNodes (layerOwnNodes layerValue)
    )
    return combinedNodes
)
fn layerCheckEditable layerValue protectZero: false = (
    if (protectZero and (layerHandle layerValue) == (layerHandle layerZero)) do layerFail "LAYER_PROTECTED" "Layer 0 cannot be renamed, parented or removed"
    if (layerValue.hasSceneXRefNodesInHierarchy()) do layerFail "LAYER_XREF_UNSUPPORTED" "Mutation of a hierarchy containing scene XRefs is not supported"
    return true
)
fn layerCheckNodes nodeValues = (
    for nodeValue in nodeValues do (
        if (not (isValidNode nodeValue)) do layerFail "STALE_NODE_REF" "Node is missing"
        if (nodeValue.isSceneXRefNode or (objXRefMgr.IsNodeXRefed nodeValue) != undefined) do layerFail "LAYER_XREF_UNSUPPORTED" "XRef node mutation is not supported"
    )
    return true
)
fn layerCheckParent childLayer parentLayer = (
    if (parentLayer != undefined) do (
        layerCheckEditable parentLayer
        local ancestorLayer = parentLayer
        local ancestorCount = 0
        while (ancestorLayer != undefined) do (
            if ((layerHandle ancestorLayer) == (layerHandle childLayer)) do layerFail "LAYER_CYCLE" "A layer cannot become its own ancestor"
            ancestorLayer = ancestorLayer.getParent()
            ancestorCount += 1
            if (ancestorCount > 5000) do layerFail "LAYER_CYCLE" "Invalid layer ancestry"
        )
    )
    return true
)
fn layerSetParentVerified childLayer parentLayer = (
    if (not (childLayer.setParent parentLayer)) do layerFail "LAYER_OPERATION_FAILED" "Layer parent change failed"
    if ((layerHandle (childLayer.getParent())) != (layerHandle parentLayer)) do layerFail "LAYER_OPERATION_FAILED" "Layer parent post-state differs"
    return true
)
fn layerNodeReference nodeValue = (
    return layerObject #(#("kind", "node"), #("handle", nodeValue.handle as integer64), #("name", nodeValue.name))
)
fn layerPage recordsValue offsetValue limitValue = (
    local selectedRecords = #()
    local finalIndex = amin recordsValue.count (offsetValue + limitValue)
    if (offsetValue < recordsValue.count) do (
        for recordIndex in (offsetValue + 1) to finalIndex do append selectedRecords recordsValue[recordIndex]
    )
    return selectedRecords
)
fn layerFingerprint nodeValues = (
    local statePieces = #(layerSceneId, ((layerHandle LayerManager.current) as string))
    for layerValue in layerUniverse do (
        append statePieces (layerJson (layerRecord layerValue))
    )
    for nodeValue in nodeValues do (
        local childHandles = for childNode in nodeValue.children collect ((getHandleByAnim childNode) as integer64)
        sort childHandles
        append statePieces (layerJson #((getHandleByAnim nodeValue) as integer64, nodeValue.name, layerHandle nodeValue.layer, childHandles, nodeValue.isHidden, nodeValue.isFrozen, nodeValue.transform as string))
    )
    local stateText = layerJson statePieces
    local hashProvider = (dotNetClass "System.Security.Cryptography.SHA256").Create()
    local stateBytes = (dotNetClass "System.Text.Encoding").UTF8.GetBytes stateText
    local hashText = (dotNetClass "System.BitConverter").ToString (hashProvider.ComputeHash stateBytes)
    hashProvider.Dispose()
    return hashText
)
local layerHolding = false
local layerParentRollback = #()
local layerCurrentRollback
try (
    if (layerSceneEpoch == "") do layerFail "LAYER_BOOTSTRAP_REQUIRED" "Restart the updated Max Ultra MCP bootstrap before using layer tools"
    if (LayerManager.count > 5000) do layerFail "LAYER_LIMIT_EXCEEDED" "Scene exceeds 5000 layers"
    for layerIndex in 0 to (LayerManager.count - 1) do append layerUniverse (LayerManager.getLayer layerIndex)
    layerZero = LayerManager.getLayer 0
    layerSceneId = layerSceneEpoch + ":" + ((getHandleByAnim rootNode) as string) + ":" + ((layerHandle layerZero) as string)
    local operationName = layerArg "operation"
    local requestedLayer = if ((layerArg "layer") != undefined) then (layerResolve (layerArg "layer")) else undefined
    local parentSupplied = (findItem (for requestPair in layerRequest collect requestPair[1]) "parent") > 0
    local targetParent = if (parentSupplied) then (layerResolve (layerArg "parent") allowNull: true) else undefined
    local targetName = layerArg "name"
    local offsetValue = layerArg "offset" fallbackValue: 0
    local limitValue = layerArg "limit" fallbackValue: 100
    local recursiveScope = layerArg "includeDescendants" fallbackValue: false
    local affectedLayers = if (requestedLayer == undefined) then #() else (if (recursiveScope) then (layerDescendants requestedLayer) else #(requestedLayer))
    local affectedNodes = #()
    local deletedLayers = #()
    local movedChildren = #()
    local destinationLayer = if ((layerArg "destination") != undefined) then (layerResolve (layerArg "destination")) else undefined
    local replacementLayer = if ((layerArg "replacementCurrent") != undefined) then (layerResolve (layerArg "replacementCurrent")) else undefined
    local childPolicy = layerArg "childPolicy" fallbackValue: "reject"
    local nodePolicy = layerArg "nodePolicy" fallbackValue: "reject"
    local changedState = false
    local appliedValues = #()
    local unchangedValues = #()
    local unsupportedValues = #()
    local warningValues = #()
    local responsePairs = #(#("ok", true), #("operation", operationName), #("preview", layerPreview), #("sceneId", layerSceneId))

    case operationName of (
        "list": (
            local candidates = layerUniverse
            if (parentSupplied) do (
                if (targetParent == undefined) then (
                    candidates = for candidateLayer in layerUniverse where (candidateLayer.getParent() == undefined) collect candidateLayer
                    if (recursiveScope) do candidates = layerUniverse
                ) else (
                    candidates = if (recursiveScope) then (layerDescendants targetParent) else (for childIndex in 1 to targetParent.getNumChildren() collect (targetParent.getChild childIndex))
                    if (recursiveScope) do deleteItem candidates 1
                )
            )
            local filterValue = toLower (layerArg "filter" fallbackValue: "")
            if (filterValue != "") do candidates = for candidateLayer in candidates where ((findString (toLower candidateLayer.name) filterValue) != undefined) collect candidateLayer
            local recordsValue = for candidateLayer in (layerPage candidates offsetValue limitValue) collect (layerRecord candidateLayer)
            join responsePairs #(#("layers", recordsValue), #("total", candidates.count), #("offset", offsetValue), #("nextOffset", if (offsetValue + recordsValue.count < candidates.count) then (offsetValue + recordsValue.count) else undefined))
        )
        "get": (append responsePairs #("record", layerRecord requestedLayer))
        "get_nodes": (
            local totalNodes = 0
            local nodeRecords = #()
            for scopeLayer in affectedLayers do (
                local scopeCount = scopeLayer.getNumNodes()
                if (totalNodes + scopeCount > offsetValue and nodeRecords.count < limitValue) do (
                    local ownNodes = layerOwnNodes scopeLayer
                    for nodeIndex in 1 to ownNodes.count where (totalNodes + nodeIndex > offsetValue and nodeRecords.count < limitValue) do (
                        local nodeValue = ownNodes[nodeIndex]
                        append nodeRecords (layerObject #(#("node", layerNodeReference nodeValue), #("layer", layerReference scopeLayer), #("isHidden", nodeValue.isHidden), #("isFrozen", nodeValue.isFrozen), #("displayByLayer", nodeValue.displayByLayer), #("renderByLayer", nodeValue.renderByLayer), #("colorByLayer", nodeValue.colorByLayer)))
                    )
                )
                totalNodes += scopeCount
            )
            join responsePairs #(#("nodes", nodeRecords), #("total", totalNodes), #("offset", offsetValue), #("nextOffset", if (offsetValue + nodeRecords.count < totalNodes) then (offsetValue + nodeRecords.count) else undefined))
        )
        default: (
            -- Resolve and validate the entire operation before starting an undo hold.
            if (requestedLayer != undefined) do layerCheckEditable requestedLayer protectZero: ((findItem #("rename", "set_parent", "delete") operationName) > 0)
            if (targetParent != undefined) do layerCheckEditable targetParent
            if (destinationLayer != undefined) do layerCheckEditable destinationLayer
            if (replacementLayer != undefined) do layerCheckEditable replacementLayer
            if (operationName == "create" or (operationName == "assign" and requestedLayer == undefined)) do (
                requestedLayer = LayerManager.getLayerFromName targetName
                if (requestedLayer != undefined) do (
                    layerCheckEditable requestedLayer
                    if (parentSupplied and ((layerHandle (requestedLayer.getParent())) != (layerHandle targetParent))) do layerFail "LAYER_CONFLICT" "Existing layer has a different parent"
                )
            )
            if (operationName == "assign") do (
                for nodeSelector in (layerArg "nodes") do (
                    local nodeHandle = layerField nodeSelector "handle"
                    local nodeValue
                    if (nodeHandle != undefined) then (nodeValue = maxOps.getNodeByHandle nodeHandle) else (
                        local matchedNodes = for sceneNode in objects where (sceneNode.name == (layerField nodeSelector "name")) collect sceneNode
                        if (matchedNodes.count != 1) do layerFail "STALE_NODE_REF" "Node name is missing or ambiguous; use a handle"
                        nodeValue = matchedNodes[1]
                    )
                    if (nodeValue == undefined) do layerFail "STALE_NODE_REF" "Node is missing"
                    appendIfUnique affectedNodes nodeValue
                )
                layerCheckNodes affectedNodes
            )
            if (operationName == "rename") do (
                local conflictingLayer = LayerManager.getLayerFromName targetName
                if (conflictingLayer != undefined and (layerHandle conflictingLayer) != (layerHandle requestedLayer)) do layerFail "LAYER_CONFLICT" "Layer name already exists"
            )
            if (operationName == "set_parent") do layerCheckParent requestedLayer targetParent
            local propertyPairs = layerArg "properties" fallbackValue: #()
            local byLayerPairs = layerArg "byLayer" fallbackValue: #()
            if (operationName == "set_properties") do (
                for scopeLayer in affectedLayers do (
                    layerCheckEditable scopeLayer
                    for propertyPair in propertyPairs where (not (isProperty scopeLayer (propertyPair[1] as name))) do appendIfUnique unsupportedValues propertyPair[1]
                )
                if (unsupportedValues.count > 0) do layerFail "LAYER_PROPERTY_UNSUPPORTED" (layerJson unsupportedValues)
                if (byLayerPairs.count > 0) do (
                    affectedNodes = layerNodes affectedLayers
                    layerCheckNodes affectedNodes
                    for nodeValue in affectedNodes do (
                        for propertyPair in byLayerPairs where (not (isProperty nodeValue (propertyPair[1] as name))) do layerFail "LAYER_PROPERTY_UNSUPPORTED" propertyPair[1]
                    )
                )
                append warningValues "Layer settings are not effective object visibility; node By Layer flags, ancestors and viewport state may differ."
            )
            if (operationName == "select_nodes") do affectedNodes = layerNodes affectedLayers
            if (operationName == "delete") do (
                deletedLayers = if (childPolicy == "deleteBranch") then (layerDescendants requestedLayer) else #(requestedLayer)
                if (childPolicy == "reject" and requestedLayer.getNumChildren() > 0) do layerFail "LAYER_NOT_EMPTY" "Layer has children; choose a child policy"
                if (childPolicy == "reparent") do (
                    if ((findItem (for requestPair in layerRequest collect requestPair[1]) "childParent") == 0) do layerFail "VALIDATION_FAILED" "childParent is required for reparent; use null for roots"
                    targetParent = layerResolve (layerArg "childParent") allowNull: true
                    for childIndex in 1 to requestedLayer.getNumChildren() do (
                        local childLayer = requestedLayer.getChild childIndex
                        layerCheckEditable childLayer
                        layerCheckParent childLayer targetParent
                        append movedChildren childLayer
                    )
                )
                affectedNodes = layerNodes deletedLayers
                if (affectedNodes.count > 0 and nodePolicy == "reject") do layerFail "LAYER_NOT_EMPTY" "Layer contains nodes; choose move or delete explicitly"
                if (nodePolicy == "move" and destinationLayer == undefined) do layerFail "VALIDATION_FAILED" "destination is required for move"
            )
            if (operationName == "merge") do (
                for layerSelector in (layerArg "sources") do (
                    local sourceLayer = layerResolve layerSelector
                    if (sourceLayer.getNumChildren() > 0 and childPolicy == "reject") do layerFail "LAYER_NOT_EMPTY" "Merge source has children; choose reparent or flatten"
                    local sourceBranch = if (childPolicy == "flatten") then (layerDescendants sourceLayer) else #(sourceLayer)
                    for branchLayer in sourceBranch do (
                        if ((findItem deletedLayers branchLayer) > 0) do layerFail "LAYER_CONFLICT" "Merge sources overlap"
                        append deletedLayers branchLayer
                    )
                    if (childPolicy == "reparent") do (
                        for childIndex in 1 to sourceLayer.getNumChildren() do (
                            local childLayer = sourceLayer.getChild childIndex
                            layerCheckEditable childLayer
                            layerCheckParent childLayer destinationLayer
                            append movedChildren childLayer
                        )
                    )
                )
                affectedNodes = layerNodes deletedLayers
                nodePolicy = "move"
                targetParent = destinationLayer
            )
            if (operationName == "remove_empty") do (
                local rootLayer = layerResolve (layerArg "root") allowNull: true
                local candidateLayers = if (rootLayer == undefined) then layerUniverse else (layerDescendants rootLayer)
                for candidateLayer in candidateLayers where ((layerHandle candidateLayer) != (layerHandle layerZero)) do (
                    if (not (LayerManager.doesLayerHierarchyContainNodes candidateLayer.name)) do append deletedLayers candidateLayer
                )
            )
            if (deletedLayers.count > 500 or affectedLayers.count > 500 or movedChildren.count > 500) do layerFail "LAYER_LIMIT_EXCEEDED" "Mutation exceeds 500 layers; narrow the scope"
            for deletedLayer in deletedLayers do layerCheckEditable deletedLayer protectZero: true
            if (deletedLayers.count > 0) do (
                layerCheckNodes affectedNodes
                if ((findItem deletedLayers destinationLayer) > 0 or (findItem deletedLayers targetParent) > 0 or (findItem deletedLayers replacementLayer) > 0) do layerFail "LAYER_CONFLICT" "Destination, child parent or replacement current would be deleted"
                for movedChild in movedChildren where ((findItem deletedLayers movedChild) > 0) do layerFail "LAYER_CONFLICT" "Child reparent conflicts with deletion"
                if ((findItem deletedLayers LayerManager.current) > 0 and replacementLayer == undefined) do layerFail "VALIDATION_FAILED" "replacementCurrent is required when deleting the current layer"
                if (nodePolicy == "delete") do (
                    for nodeValue in affectedNodes do (
                        if (isGroupHead nodeValue or isGroupMember nodeValue) do layerFail "LAYER_DELETE_UNSUPPORTED" "Ungroup explicitly before deleting layer contents"
                        for childNode in nodeValue.children where ((findItem affectedNodes childNode) == 0) do layerFail "LAYER_DELETE_UNSUPPORTED" "Node has children outside the deletion set"
                        if (isProperty nodeValue #target) do (
                            if (isValidNode nodeValue.target and (findItem affectedNodes nodeValue.target) == 0) do layerFail "LAYER_DELETE_UNSUPPORTED" "Node target is outside the deletion set"
                        )
                    )
                )
            )
            local planFingerprint = layerFingerprint affectedNodes
            if (layerExpectedFingerprint != "" and planFingerprint != layerExpectedFingerprint) do layerFail "STALE_PLAN" "Layer state changed after preview"
            local removedRecords = for deletedLayer in deletedLayers collect (layerReference deletedLayer)
            append responsePairs #("effect", layerObject #(#("layersToRemove", removedRecords), #("nodeCount", affectedNodes.count), #("nodesToDelete", if (nodePolicy == "delete") then affectedNodes.count else 0), #("nodesToMove", if (nodePolicy == "move" or operationName == "assign") then affectedNodes.count else 0), #("childrenToReparent", for movedChild in movedChildren collect (layerReference movedChild)), #("destination", layerReference destinationLayer), #("childParent", layerReference targetParent), #("replacementCurrent", layerReference replacementLayer)))
            append responsePairs #("fingerprint", planFingerprint)
            local hierarchyBefore = #()
            local hierarchyScope = for scopeLayer in affectedLayers collect scopeLayer
            for scopeLayer in deletedLayers do appendIfUnique hierarchyScope scopeLayer
            for scopeLayer in movedChildren do appendIfUnique hierarchyScope scopeLayer
            for scopeLayer in hierarchyScope do append hierarchyBefore (layerObject #(#("layer", layerReference scopeLayer), #("parent", layerReference (scopeLayer.getParent()))))
            append responsePairs #("hierarchyBefore", hierarchyBefore)
            if (not layerPreview) do (
                if (theHold.Holding()) do layerFail "LAYER_OPERATION_FAILED" "Another undo transaction is active"
                theHold.Begin()
                layerHolding = true
                layerCurrentRollback = LayerManager.current
                for rollbackLayer in layerUniverse do append layerParentRollback #(rollbackLayer, rollbackLayer.getParent())
                case operationName of (
                    "create": (
                        if (requestedLayer == undefined) then (
                            requestedLayer = LayerManager.newLayerFromName targetName
                            if (requestedLayer == undefined) do layerFail "LAYER_OPERATION_FAILED" "Could not create layer"
                            if (targetParent != undefined) do layerSetParentVerified requestedLayer targetParent
                            append appliedValues "created"
                        ) else append unchangedValues "existing layer"
                    )
                    "rename": (
                        if (requestedLayer.name == targetName) then (append unchangedValues "name") else (
                            if (not (requestedLayer.setName targetName)) do layerFail "LAYER_OPERATION_FAILED" "Rename failed"
                            if (requestedLayer.name != targetName) do layerFail "LAYER_OPERATION_FAILED" "Rename post-state differs"
                            append appliedValues "name"
                        )
                    )
                    "set_parent": (
                        if ((layerHandle (requestedLayer.getParent())) == (layerHandle targetParent)) then (append unchangedValues "parent") else (
                            layerSetParentVerified requestedLayer targetParent
                            append appliedValues "parent"
                        )
                    )
                    "set_current": (
                        if (requestedLayer.current) then (append unchangedValues "current") else (
                            requestedLayer.current = true
                            if (not requestedLayer.current) do layerFail "LAYER_OPERATION_FAILED" "Current layer post-state differs"
                            append appliedValues "current"
                        )
                    )
                    "assign": (
                        if (requestedLayer == undefined) do (
                            requestedLayer = LayerManager.newLayerFromName targetName
                            if (requestedLayer == undefined) do layerFail "LAYER_OPERATION_FAILED" "Could not create assignment layer"
                            append appliedValues "created"
                        )
                        local nodesToMove = for nodeValue in affectedNodes where ((layerHandle nodeValue.layer) != (layerHandle requestedLayer)) collect nodeValue
                        if (nodesToMove.count > 0) then (
                            requestedLayer.addNodes nodesToMove
                            for nodeValue in nodesToMove where ((layerHandle nodeValue.layer) != (layerHandle requestedLayer)) do layerFail "LAYER_OPERATION_FAILED" "Assignment post-state differs"
                            append appliedValues "nodes assigned"
                        ) else append unchangedValues "node membership"
                    )
                    "set_properties": (
                        for scopeLayer in affectedLayers do (
                            for propertyPair in propertyPairs do (
                                local propertyName = propertyPair[1] as name
                                local desiredValue = propertyPair[2]
                                if (propertyName == #wireColor) do desiredValue = color desiredValue[1] desiredValue[2] desiredValue[3]
                                local evidenceKey = ((layerHandle scopeLayer) as string) + "." + propertyPair[1]
                                if ((getProperty scopeLayer propertyName) == desiredValue) then (append unchangedValues evidenceKey) else (
                                    setProperty scopeLayer propertyName desiredValue
                                    if ((getProperty scopeLayer propertyName) != desiredValue) do layerFail "LAYER_OPERATION_FAILED" "Layer property post-state differs"
                                    append appliedValues evidenceKey
                                )
                            )
                        )
                        for nodeValue in affectedNodes do (
                            for propertyPair in byLayerPairs do (
                                local propertyName = propertyPair[1] as name
                                if ((getProperty nodeValue propertyName) != propertyPair[2]) then (
                                    setProperty nodeValue propertyName propertyPair[2]
                                    if ((getProperty nodeValue propertyName) != propertyPair[2]) do layerFail "LAYER_OPERATION_FAILED" "By Layer post-state differs"
                                    appendIfUnique appliedValues ("nodes." + propertyPair[1])
                                ) else appendIfUnique unchangedValues ("nodes." + propertyPair[1])
                            )
                        )
                    )
                    "select_nodes": (
                        local desiredSelection = selection as array
                        local selectionMode = layerArg "mode" fallbackValue: "replace"
                        case selectionMode of (
                            "replace": (desiredSelection = affectedNodes)
                            "add": (for nodeValue in affectedNodes do appendIfUnique desiredSelection nodeValue)
                            "remove": (desiredSelection = for nodeValue in desiredSelection where ((findItem affectedNodes nodeValue) == 0) collect nodeValue)
                        )
                        local selectionChanged = selection.count != desiredSelection.count
                        for nodeValue in desiredSelection where (not nodeValue.isSelected) do selectionChanged = true
                        if (selectionChanged) do (
                            if (desiredSelection.count == 0) then clearSelection() else select desiredSelection
                        )
                        if (selection.count != desiredSelection.count) do layerFail "LAYER_OPERATION_FAILED" ("Selection post-state differs: expected " + (desiredSelection.count as string) + ", actual " + (selection.count as string) + " (hidden/frozen nodes may not be selectable)")
                        for nodeValue in desiredSelection where (not nodeValue.isSelected) do layerFail "LAYER_OPERATION_FAILED" "Selection post-state differs"
                        if (selectionChanged) then append appliedValues "selection" else append unchangedValues "selection"
                        append responsePairs #("selectedCount", selection.count)
                    )
                    default: (
                        if (replacementLayer != undefined and (findItem deletedLayers LayerManager.current) > 0) do (
                            replacementLayer.current = true
                            if (not replacementLayer.current) do layerFail "LAYER_OPERATION_FAILED" "Could not replace current layer"
                        )
                        if (nodePolicy == "move" and affectedNodes.count > 0) do (
                            destinationLayer.addNodes affectedNodes
                            for nodeValue in affectedNodes where ((layerHandle nodeValue.layer) != (layerHandle destinationLayer)) do layerFail "LAYER_OPERATION_FAILED" "Move did not finish; source layers retained"
                        )
                        for childLayer in movedChildren do layerSetParentVerified childLayer targetParent
                        if (nodePolicy == "delete" and affectedNodes.count > 0) do (
                            delete affectedNodes
                            for nodeValue in affectedNodes where (isValidNode nodeValue) do layerFail "LAYER_OPERATION_FAILED" "Content deletion did not finish"
                        )
                        -- Delete leaves only, after all moves are verified. Never forceDelete.
                        local remainingLayers = for deletedLayer in deletedLayers collect deletedLayer
                        while (remainingLayers.count > 0) do (
                            local removedInPass = false
                            for deleteIndex in remainingLayers.count to 1 by -1 do (
                                local deletedLayer = remainingLayers[deleteIndex]
                                if (deletedLayer.getNumChildren() == 0) do (
                                    local deletedName = deletedLayer.name
                                    if (deletedLayer.getNumNodes() > 0 or not (LayerManager.deleteLayerByName deletedName)) do layerFail "LAYER_OPERATION_FAILED" "Empty layer removal failed"
                                    if ((LayerManager.getLayerFromName deletedName) != undefined) do layerFail "LAYER_OPERATION_FAILED" "Removed layer still exists"
                                    deleteItem remainingLayers deleteIndex
                                    removedInPass = true
                                )
                            )
                            if (not removedInPass) do layerFail "LAYER_OPERATION_FAILED" "No removable leaf remains"
                        )
                        if (deletedLayers.count > 0) then (append appliedValues "layers removed") else (append unchangedValues "no empty layers")
                    )
                )
                changedState = appliedValues.count > 0
                if (changedState) then theHold.Accept "Max Ultra MCP: Layers" else theHold.Cancel()
                layerHolding = false
            )
            if (requestedLayer != undefined and deletedLayers.count == 0) do append responsePairs #("record", layerRecord requestedLayer)
            local hierarchyChanged = operationName == "set_parent" or movedChildren.count > 0 or deletedLayers.count > 0
            append responsePairs #("undo", layerObject #(#("transaction", "Max undo hold"), #("hierarchyRestorationGuaranteed", false), #("limitation", "Native setParent does not create an undo record. Undo may restore nodes/layers without restoring their parent hierarchy.")))
            if (hierarchyChanged) do append warningValues "Native Undo does not guarantee parent hierarchy restoration; retain the preview hierarchy before reorganizing layers."
        )
    )
    join responsePairs #(#("changed", changedState), #("applied", appliedValues), #("unchanged", unchangedValues), #("unsupported", unsupportedValues), #("warnings", warningValues))
    layerJson (layerObject responsePairs)
) catch (
    local failureMessage = getCurrentException() as string
    if (layerHolding) do (
        try (theHold.Cancel()) catch (failureMessage += " | Rollback failed; inspect the scene before retrying")
        -- setParent is not recorded by native Undo. Restore surviving original layers explicitly.
        try (
            for rollbackPair in layerParentRollback do (
                local survivingLayer = LayerManager.getLayerFromName rollbackPair[1].name
                if (survivingLayer != undefined and (layerHandle survivingLayer) == (layerHandle rollbackPair[1])) do (
                    if ((layerHandle (survivingLayer.getParent())) != (layerHandle rollbackPair[2])) do layerSetParentVerified survivingLayer rollbackPair[2]
                )
            )
            if (layerCurrentRollback != undefined) do layerCurrentRollback.current = true
        ) catch (failureMessage += " | Hierarchy rollback failed; inspect the scene before retrying")
        layerHolding = false
    )
    local errorCode = "LAYER_OPERATION_FAILED"
    for knownCode in #("VALIDATION_FAILED", "STALE_LAYER_REF", "STALE_NODE_REF", "STALE_PLAN", "LAYER_NOT_FOUND", "LAYER_CONFLICT", "LAYER_CYCLE", "LAYER_PROTECTED", "LAYER_NOT_EMPTY", "LAYER_XREF_UNSUPPORTED", "LAYER_PROPERTY_UNSUPPORTED", "LAYER_DELETE_UNSUPPORTED", "LAYER_LIMIT_EXCEEDED", "LAYER_BOOTSTRAP_REQUIRED") do (
        if ((findString failureMessage knownCode) != undefined) do errorCode = knownCode
    )
    layerJson (layerObject #(#("ok", false), #("code", errorCode), #("message", failureMessage)))
)
