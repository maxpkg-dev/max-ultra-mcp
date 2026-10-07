-- Scene and viewport adapters executed exclusively on the Max main thread.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl

(
    struct MaxUltraSceneOperations (
        instanceId = "",
        processId = 0,
        responseBody = "",
        responseSuccess = true,
        activityCallback = undefined,
        fn decodeWireField sourceContent = return (python.import "max_ultra.wire").decode sourceContent,
        fn jsonEscape sourceContent = return (python.import "max_ultra.max_api").json_escape (sourceContent as string),
        fn jsonBoolean isEnabled = return (if (isEnabled) then "true" else "false"),
        fn currentMaxYear = return ((maxVersion())[8]),
        fn currentSceneFilePath = return (maxFilePath + maxFileName),
        fn currentSceneDisplayName = return (if (maxFileName == "") then "Untitled" else maxFileName),
        fn isSceneSaveRequired = return getSaveRequired(),
        fn sendSceneStatus = return true,
        fn addActivity category messageContent = (
            if (activityCallback != undefined) do activityCallback category messageContent
            return true
        ),
        fn sendBridgeResponse requestId isSuccess resultContent = (
            responseSuccess = isSuccess
            responseBody = resultContent
            return isSuccess
        ),
        fn buildSceneSummaryJson actionName = (
            local versionInfo = maxVersion()
            local currentTimestamp = (python.import "max_ultra.max_api").utc_now()
            local responseBody = "{\"action\":\"" + jsonEscape(actionName) + "\",\"ok\":true,\"instanceId\":\"" + jsonEscape(instanceId) + "\""
            responseBody += ",\"pid\":" + (processId as string) + ",\"maxVersion\":\"" + (currentMaxYear() as string) + "\""
            responseBody += ",\"productVersion\":\"" + jsonEscape(versionInfo as string) + "\",\"mainThread\":true,\"sampledAt\":\"" + jsonEscape(currentTimestamp) + "\""
            responseBody += ",\"scene\":{\"filePath\":\"" + jsonEscape(currentSceneFilePath()) + "\",\"saveRequired\":" + jsonBoolean(isSceneSaveRequired())
            responseBody += ",\"objectCount\":" + (objects.count as string) + ",\"selectionCount\":" + (selection.count as string) + ",\"frame\":\"" + jsonEscape(sliderTime as string) + "\"}}"
            return responseBody
        ),

        fn sceneNodeStateCounts = (
            local hiddenCount = 0
            local hiddenInViewportCount = 0
            local frozenCount = 0
            local renderableCount = 0
            local groupHeadCount = 0
            local groupMemberCount = 0
            for sceneNode in objects do (
                if (try (sceneNode.isHidden) catch (false)) do hiddenCount += 1
                if (try (sceneNode.isHiddenInVpt) catch (false)) do hiddenInViewportCount += 1
                if (try (sceneNode.isFrozen) catch (false)) do frozenCount += 1
                if (try (sceneNode.renderable) catch (false)) do renderableCount += 1
                if (try (isGroupHead sceneNode) catch (false)) do groupHeadCount += 1
                if (try (isGroupMember sceneNode) catch (false)) do groupMemberCount += 1
            )
            return #(hiddenCount, hiddenInViewportCount, frozenCount, renderableCount, groupHeadCount, groupMemberCount)
        ),

        fn evaluatedGeometryCounts nodeCollection = (
            local evaluatedNodeCount = 0
            local failedNodeCount = 0
            local polygonCount = 0
            local vertexCount = 0
            for sceneNode in nodeCollection do (
                local topologyCounts = try (getPolygonCount sceneNode) catch (undefined)
                if (topologyCounts != undefined and topologyCounts.count >= 2) then (
                    polygonCount += topologyCounts[1]
                    vertexCount += topologyCounts[2]
                    evaluatedNodeCount += 1
                ) else failedNodeCount += 1
            )
            return #(evaluatedNodeCount, failedNodeCount, polygonCount, vertexCount)
        ),

        fn buildGetInfoJson = (
            local versionInfo = maxVersion()
            local currentTimestamp = (python.import "max_ultra.max_api").utc_now()
            local nodeStateCounts = sceneNodeStateCounts()
            local geometryCounts = evaluatedGeometryCounts geometry
            local selectedGeometryNodes = for sceneNode in selection where (superClassOf sceneNode == GeometryClass) collect sceneNode
            local selectedGeometryCounts = evaluatedGeometryCounts selectedGeometryNodes
            local rendererClass = try ((classOf renderers.current) as string) catch ("Unknown")
            local layerCount = try (LayerManager.count) catch (0)
            local materialCount = try (sceneMaterials.count) catch (0)
            local systemUnitType = try (units.SystemType as string) catch ("Unknown")
            local systemUnitScale = try (units.SystemScale) catch (1.0)
            local displayUnitType = try (units.DisplayType as string) catch ("Unknown")
            local jsonQuote = bit.intAsChar 34
            local unitsFragment = "," + jsonQuote + "units" + jsonQuote + ":{" + jsonQuote + "systemType" + jsonQuote + ":" + jsonQuote + jsonEscape(systemUnitType) + jsonQuote
            unitsFragment += "," + jsonQuote + "systemScale" + jsonQuote + ":" + (systemUnitScale as string) + "," + jsonQuote + "displayType" + jsonQuote + ":" + jsonQuote + jsonEscape(displayUnitType) + jsonQuote + "}"
            local responseBody = "{\"action\":\"get_info\",\"ok\":true,\"instanceId\":\"" + jsonEscape(instanceId) + "\""
            responseBody += ",\"pid\":" + (processId as string) + ",\"maxVersion\":\"" + (currentMaxYear() as string) + "\""
            responseBody += ",\"productVersion\":\"" + jsonEscape(versionInfo as string) + "\",\"mainThread\":true,\"sampledAt\":\"" + jsonEscape(currentTimestamp) + "\""
            responseBody += ",\"scene\":{\"filePath\":\"" + jsonEscape(currentSceneFilePath()) + "\",\"displayName\":\"" + jsonEscape(currentSceneDisplayName()) + "\",\"saveRequired\":" + jsonBoolean(isSceneSaveRequired())
            responseBody += ",\"objectCount\":" + (objects.count as string) + ",\"selectionCount\":" + (selection.count as string) + ",\"frame\":\"" + jsonEscape(sliderTime as string) + "\""
            responseBody += ",\"animation\":{\"current\":\"" + jsonEscape(sliderTime as string) + "\",\"start\":\"" + jsonEscape(animationRange.start as string) + "\",\"end\":\"" + jsonEscape(animationRange.end as string) + "\"}"
            responseBody += ",\"statistics\":{\"objects\":{\"total\":" + (objects.count as string) + ",\"geometry\":" + (geometry.count as string) + ",\"shapes\":" + (shapes.count as string)
            responseBody += ",\"lights\":" + (lights.count as string) + ",\"cameras\":" + (cameras.count as string) + ",\"helpers\":" + (helpers.count as string) + ",\"spaceWarps\":" + (spaceWarps.count as string) + ",\"systems\":" + (systems.count as string)
            responseBody += ",\"selected\":" + (selection.count as string) + ",\"hidden\":" + (nodeStateCounts[1] as string) + ",\"hiddenInViewport\":" + (nodeStateCounts[2] as string) + ",\"frozen\":" + (nodeStateCounts[3] as string)
            responseBody += ",\"renderable\":" + (nodeStateCounts[4] as string) + ",\"groupHeads\":" + (nodeStateCounts[5] as string) + ",\"groupMembers\":" + (nodeStateCounts[6] as string) + "}"
            responseBody += ",\"geometry\":{\"nodes\":" + (geometry.count as string) + ",\"evaluatedNodes\":" + (geometryCounts[1] as string) + ",\"failedNodes\":" + (geometryCounts[2] as string)
            responseBody += ",\"vertices\":" + (geometryCounts[4] as string) + ",\"polygons\":" + (geometryCounts[3] as string) + ",\"meshFaces\":" + (geometryCounts[3] as string) + ",\"triangles\":" + (geometryCounts[3] as string) + ",\"countingMode\":\"evaluatedMesh/getPolygonCount\"}"
            responseBody += ",\"selection\":{\"total\":" + (selection.count as string) + ",\"geometryNodes\":" + (selectedGeometryNodes.count as string) + ",\"evaluatedNodes\":" + (selectedGeometryCounts[1] as string) + ",\"failedNodes\":" + (selectedGeometryCounts[2] as string)
            responseBody += ",\"vertices\":" + (selectedGeometryCounts[4] as string) + ",\"polygons\":" + (selectedGeometryCounts[3] as string) + ",\"triangles\":" + (selectedGeometryCounts[3] as string) + "}"
            responseBody += ",\"materials\":" + (materialCount as string) + ",\"layers\":" + (layerCount as string) + "}"
            responseBody += ",\"render\":{\"renderer\":\"" + jsonEscape(rendererClass) + "\",\"width\":" + (renderWidth as string) + ",\"height\":" + (renderHeight as string) + "}}}"
            responseBody = (substring responseBody 1 (responseBody.count - 1)) + unitsFragment + "}"
            return responseBody
        ),
        fn restoreViewportReviewSettings reviewState = (
            if (reviewState == undefined or reviewState.count != 13) do return false
            local restored = true
            try (reviewState[1].VisualStyleMode = reviewState[2]) catch (restored = false)
            try (reviewState[1].ShowSelectionBracketsEnabled = reviewState[3]) catch (restored = false)
            try (reviewState[1].ShowEdgedFacesEnabled = reviewState[4]) catch (restored = false)
            try (reviewState[1].SelectedEdgedFacesEnabled = reviewState[5]) catch (restored = false)
            try (reviewState[6].SelectionHighlightEnabled = reviewState[7]) catch (restored = false)
            try (reviewState[6].SelectionOutlineEnabled = reviewState[8]) catch (restored = false)
            try (reviewState[6].PreviewHighlightEnabled = reviewState[9]) catch (restored = false)
            try (reviewState[6].PreviewOutlineEnabled = reviewState[10]) catch (restored = false)
            try (NitrousGraphicsManager.AntialiasingQuality = reviewState[11]) catch (restored = false)
            try (viewport.setGridVisibility reviewState[12] reviewState[13]) catch (restored = false)
            try (completeRedraw()) catch (restored = false)
            return restored
        ),

        fn handleViewportScreenshot requestId screenshotPayload = (
            local viewportBitmap = undefined
            local reviewState = undefined
            local screenshotPath = ""
            local reviewPreset = "clean-realistic"
            try (
                local screenshotFields = filterString screenshotPayload "\t"
                if (screenshotFields.count >= 1) do screenshotPath = screenshotFields[1]
                if (screenshotFields.count >= 2) do reviewPreset = toLower screenshotFields[2]
                if (screenshotPath == undefined or screenshotPath == "") do throw "The screenshot file path is empty"
                if (findItem #("clean-realistic", "clean-shaded", "clean-current") reviewPreset == 0) do throw "Unsupported viewport review preset"
                local originalViewportSize = getViewSize()
                local originalViewportArea = originalViewportSize.x * originalViewportSize.y
                max tool maximize
                completeRedraw()
                local toggledViewportSize = getViewSize()
                local toggledViewportArea = toggledViewportSize.x * toggledViewportSize.y
                if (toggledViewportArea < originalViewportArea) do (
                    max tool maximize
                    completeRedraw()
                )
                local captureViewportSize = getViewSize()
                if ((captureViewportSize.x * captureViewportSize.y) < originalViewportArea) do throw "The active viewport could not be maximized"

                local activeViewportIndex = viewport.activeViewport
                if (activeViewportIndex < 1) do throw "The active view is not a capturable 3D viewport"
                local displaySettings = NitrousGraphicsManager.GetActiveViewportSetting()
                local selectionSettings = NitrousGraphicsManager.GetSelectionSetting()
                if (displaySettings == undefined or selectionSettings == undefined) do throw "Nitrous viewport settings are unavailable"
                reviewState = #(
                    displaySettings,
                    displaySettings.VisualStyleMode,
                    displaySettings.ShowSelectionBracketsEnabled,
                    displaySettings.ShowEdgedFacesEnabled,
                    displaySettings.SelectedEdgedFacesEnabled,
                    selectionSettings,
                    selectionSettings.SelectionHighlightEnabled,
                    selectionSettings.SelectionOutlineEnabled,
                    selectionSettings.PreviewHighlightEnabled,
                    selectionSettings.PreviewOutlineEnabled,
                    NitrousGraphicsManager.AntialiasingQuality,
                    activeViewportIndex,
                    viewport.getGridVisibility activeViewportIndex
                )
                if (reviewPreset == "clean-realistic") do displaySettings.VisualStyleMode = #Realistic
                if (reviewPreset == "clean-shaded") do displaySettings.VisualStyleMode = #Shaded
                displaySettings.ShowSelectionBracketsEnabled = false
                displaySettings.ShowEdgedFacesEnabled = false
                displaySettings.SelectedEdgedFacesEnabled = false
                selectionSettings.SelectionHighlightEnabled = false
                selectionSettings.SelectionOutlineEnabled = false
                selectionSettings.PreviewHighlightEnabled = false
                selectionSettings.PreviewOutlineEnabled = false
                NitrousGraphicsManager.AntialiasingQuality = #8X
                viewport.setGridVisibility activeViewportIndex false
                completeRedraw()

                viewportBitmap = gw.getViewportDib()
                if (viewportBitmap == undefined) do throw "The active viewport did not provide a bitmap"
                local bitmapWidth = viewportBitmap.width
                local bitmapHeight = viewportBitmap.height
                viewportBitmap.filename = screenshotPath
                save viewportBitmap
                if (not (doesFileExist screenshotPath)) do throw "3ds Max did not write the viewport PNG"
                close viewportBitmap
                viewportBitmap = undefined
                if (not (restoreViewportReviewSettings reviewState)) do throw "The viewport image was saved, but display settings could not be restored"
                reviewState = undefined
                local responseBody = "{\"action\":\"screenshot\",\"ok\":true,\"filePath\":\"" + jsonEscape(screenshotPath) + "\",\"mimeType\":\"image/png\",\"width\":" + (bitmapWidth as string) + ",\"height\":" + (bitmapHeight as string) + ",\"reviewPreset\":\"" + jsonEscape(reviewPreset) + "\",\"antialiasing\":\"8X\",\"displaySettingsRestored\":true,\"mainThread\":true}"
                addActivity "info" ("Viewport screenshot " + (bitmapWidth as string) + "x" + (bitmapHeight as string))
                return sendBridgeResponse requestId true responseBody
            ) catch (
                local errorMessage = getCurrentException()
                try (if (viewportBitmap != undefined) do close viewportBitmap) catch ()
                if (reviewState != undefined and not (restoreViewportReviewSettings reviewState)) do errorMessage += " | Viewport display settings could not be restored"
                try (if (screenshotPath != "" and doesFileExist screenshotPath) do deleteFile screenshotPath) catch ()
                addActivity "error" ("Screenshot failed: " + errorMessage)
                return sendBridgeResponse requestId false errorMessage
            )
        ),

        fn handleExecuteRequest requestId scriptContent activityLabel = (
            local startedAt = timestamp()
            local operationLabel = if (activityLabel != "") then activityLabel else "Run Max operation"
            local shortRequestId = requestId
            if (shortRequestId.count > 8) do shortRequestId = substring shortRequestId 1 8
            addActivity "info" (operationLabel + " [" + shortRequestId + "]")
            try (
                local executionResult = execute scriptContent
                local resultText = ""
                try (resultText = executionResult as string) catch (resultText = "<result cannot be converted to string>")
                local maximumResultCharacters = 500000
                local resultCharacterCount = resultText.count
                local resultTruncated = resultCharacterCount > maximumResultCharacters
                if (resultTruncated) do resultText = (substring resultText 1 maximumResultCharacters) + "..."
                local resultType = try ((classOf executionResult) as string) catch ("Unknown")
                local elapsedMilliseconds = timestamp() - startedAt
                local responseBody = "{\"action\":\"execute\",\"ok\":true,\"mainThread\":true,\"result\":\"" + jsonEscape(resultText) + "\",\"resultType\":\"" + jsonEscape(resultType) + "\",\"resultCharacterCount\":" + (resultCharacterCount as string) + ",\"truncated\":" + jsonBoolean(resultTruncated) + ",\"elapsedMs\":" + (elapsedMilliseconds as string) + "}"
                addActivity "info" (operationLabel + " completed in " + (elapsedMilliseconds as string) + " ms")
                sendSceneStatus()
                return sendBridgeResponse requestId true responseBody
            ) catch (
                local errorMessage = getCurrentException()
                addActivity "error" (operationLabel + " failed: " + errorMessage)
                sendSceneStatus()
                return sendBridgeResponse requestId false errorMessage
            )
        ),

        fn uiHandleText windowHandle = (
            local handleText = windowHandle as string
            handleText = substituteString handleText "L" ""
            handleText = substituteString handleText "P" ""
            return handleText
        ),

        fn parseUiHandle handleText = (
            local normalizedText = substituteString (handleText as string) "L" ""
            normalizedText = substituteString normalizedText "P" ""
            return (normalizedText as integer64)
        ),

        fn uiWindowText windowHandle = (
            try (
                local windowText = UIAccessor.GetWindowText windowHandle
                if (windowText == undefined) do return ""
                return windowText as string
            ) catch (
                return ""
            )
        ),

        fn uiWindowClass windowHandle = (
            try (
                local windowClass = UIAccessor.GetWindowClassName windowHandle
                if (windowClass == undefined) do return ""
                return windowClass as string
            ) catch (
                return ""
            )
        ),

        fn uiFilterMatches actualText filterText = (
            if (filterText == undefined or filterText == "") do return true
            return (findString (toLower (actualText as string)) (toLower (filterText as string))) != undefined
        ),

        fn buildUiWindowJson windowHandle parentWindowHandle currentDepth windowText windowClass = (
            local resourceId = ""
            local dllFileName = ""
            local windowRectangle = ""
            try (resourceId = (UIAccessor.GetWindowResourceID windowHandle) as string) catch ()
            try (dllFileName = (UIAccessor.GetWindowDllFileName windowHandle) as string) catch ()
            try (windowRectangle = (UIAccessor.GetWindowRect windowHandle) as string) catch ()
            local responseBody = "{\"hwnd\":\"" + jsonEscape(uiHandleText windowHandle) + "\",\"parentHwnd\":\"" + jsonEscape(uiHandleText parentWindowHandle) + "\""
            responseBody += ",\"depth\":" + (currentDepth as string) + ",\"text\":\"" + jsonEscape(windowText) + "\",\"className\":\"" + jsonEscape(windowClass) + "\""
            responseBody += ",\"resourceId\":\"" + jsonEscape(resourceId) + "\",\"dllFileName\":\"" + jsonEscape(dllFileName) + "\",\"rect\":\"" + jsonEscape(windowRectangle) + "\"}"
            return responseBody
        ),

        fn collectUiWindows windowHandle parentWindowHandle currentDepth maximumDepth maximumControls titleFilter classFilter controlRecords = (
            if (controlRecords.count >= maximumControls) do return false
            local windowText = uiWindowText windowHandle
            local windowClass = uiWindowClass windowHandle
            if ((uiFilterMatches windowText titleFilter) and (uiFilterMatches windowClass classFilter)) do (
                append controlRecords (buildUiWindowJson windowHandle parentWindowHandle currentDepth windowText windowClass)
            )
            if (currentDepth >= maximumDepth or controlRecords.count >= maximumControls) do return true
            local childWindowHandles = #()
            try (childWindowHandles = UIAccessor.GetChildWindows windowHandle) catch (childWindowHandles = #())
            if (childWindowHandles == undefined) do childWindowHandles = #()
            for childWindowHandle in childWindowHandles while controlRecords.count < maximumControls do (
                collectUiWindows childWindowHandle windowHandle (currentDepth + 1) maximumDepth maximumControls titleFilter classFilter controlRecords
            )
            return true
        ),

        fn buildUiControlsJson controlRecords = (
            local controlsBody = ""
            for controlRecord in controlRecords do (
                if (controlsBody != "") do controlsBody += ","
                controlsBody += controlRecord
            )
            return controlsBody
        ),

        fn handleUiListRequest requestId actionPayload = (
            local payloadFields = filterString actionPayload "\t"
            if (payloadFields.count < 5) do return sendBridgeResponse requestId false "Invalid ui_list payload"
            local uiScope = payloadFields[1]
            local maximumDepth = payloadFields[2] as integer
            local maximumControls = payloadFields[3] as integer
            local titleFilter = decodeWireField(payloadFields[4])
            local classFilter = decodeWireField(payloadFields[5])
            local rootWindowHandles = #()
            if (uiScope == "popups") then (
                try (rootWindowHandles = UIAccessor.GetPopupDialogs()) catch (rootWindowHandles = #())
                if (rootWindowHandles == undefined) do rootWindowHandles = #()
            ) else (
                append rootWindowHandles (windows.getMAXHWND())
            )
            local controlRecords = #()
            for rootWindowHandle in rootWindowHandles while controlRecords.count < maximumControls do (
                collectUiWindows rootWindowHandle 0 0 maximumDepth maximumControls titleFilter classFilter controlRecords
            )
            local responseBody = "{\"action\":\"ui_list\",\"ok\":true,\"mainThread\":true,\"scope\":\"" + jsonEscape(uiScope) + "\",\"count\":" + (controlRecords.count as string) + ",\"truncated\":" + jsonBoolean(controlRecords.count >= maximumControls) + ",\"controls\":[" + buildUiControlsJson(controlRecords) + "]}"
            addActivity "info" ("UI discovery returned " + (controlRecords.count as string) + " controls")
            return sendBridgeResponse requestId true responseBody
        ),

        fn uiHandleDescendsFrom targetWindowHandle rootWindowHandle = (
            local currentWindowHandle = targetWindowHandle
            for hierarchyDepth in 1 to 64 while (uiHandleText currentWindowHandle) != "0" do (
                if ((uiHandleText currentWindowHandle) == (uiHandleText rootWindowHandle)) do return true
                try (currentWindowHandle = UIAccessor.GetParentWindow currentWindowHandle) catch (return false)
                if (currentWindowHandle == undefined) do return false
            )
            return false
        ),

        fn uiHandleBelongsToMax targetWindowHandle = (
            return (python.import "max_ultra.max_api").owns_window (uiHandleText targetWindowHandle)
        ),
        fn handleUiInvokeRequest requestId actionPayload = (
            local payloadFields = filterString actionPayload "\t"
            if (payloadFields.count < 8) do return sendBridgeResponse requestId false "Invalid ui_invoke payload"
            local uiAction = payloadFields[1]
            local targetHandleText = decodeWireField(payloadFields[2])
            local expectedText = decodeWireField(payloadFields[3])
            local expectedClass = decodeWireField(payloadFields[4])
            local messageIdText = payloadFields[5]
            local wParamText = payloadFields[6]
            local lParamText = payloadFields[7]
            local valueText = decodeWireField(payloadFields[8])
            local targetWindowHandle = undefined
            try (targetWindowHandle = parseUiHandle targetHandleText) catch (return sendBridgeResponse requestId false ("Invalid target HWND: " + targetHandleText))
            if (not uiHandleBelongsToMax targetWindowHandle) do return sendBridgeResponse requestId false "Target HWND does not belong to the selected 3ds Max process"
            local actualText = uiWindowText targetWindowHandle
            local actualClass = uiWindowClass targetWindowHandle
            if (expectedText != "" and (toLower expectedText) != (toLower actualText)) do return sendBridgeResponse requestId false ("Target text changed. Expected '" + expectedText + "', found '" + actualText + "'")
            if (expectedClass != "" and (toLower expectedClass) != (toLower actualClass)) do return sendBridgeResponse requestId false ("Target class changed. Expected '" + expectedClass + "', found '" + actualClass + "'")
            local actionResult = ""
            try (
                if (not uiHandleBelongsToMax targetWindowHandle) do throw "Target ownership changed"
                case uiAction of (
                    "press_button": (
                        UIAccessor.PressButton targetWindowHandle
                        actionResult = "pressed"
                    )
                    "set_window_text": (
                        UIAccessor.SetWindowText targetWindowHandle valueText
                        actionResult = "text_set"
                    )
                    "send_message": (
                        local messageId = parseUiHandle messageIdText
                        local wParam = parseUiHandle wParamText
                        local lParam = parseUiHandle lParamText
                        actionResult = (windows.sendMessage targetWindowHandle messageId wParam lParam) as string
                    )
                    default: return sendBridgeResponse requestId false ("Unsupported UI action: " + uiAction)
                )
                local responseBody = "{\"action\":\"ui_invoke\",\"ok\":true,\"mainThread\":true,\"uiAction\":\"" + jsonEscape(uiAction) + "\",\"targetHwnd\":\"" + jsonEscape(targetHandleText) + "\",\"targetText\":\"" + jsonEscape(actualText) + "\",\"targetClass\":\"" + jsonEscape(actualClass) + "\",\"result\":\"" + jsonEscape(actionResult) + "\"}"
                addActivity "info" ("UI action " + uiAction + " on " + targetHandleText)
                return sendBridgeResponse requestId true responseBody
            ) catch (
                local errorMessage = getCurrentException()
                addActivity "error" ("UI action failed: " + errorMessage)
                return sendBridgeResponse requestId false errorMessage
            )
        )
    )
    MaxUltraSceneOperations()
)
