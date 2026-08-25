-- Connects one running 3ds Max process to the local Max Ultra MCP bridge.
-- Copyright (c) 2026 Lukianenko Vasyl
-- https://3dground.net
-- Developed by https://3dground.net (3DGROUND)

(
    local bridgeClient


    rollout MaxUltraMcpStatusDialog "3D Ground - Max Ultra MCP" width: 520 height: 400 (
        groupBox grpConnection "Connection" pos: [12,8] width: 496 height: 96
        label lblStatus "Status: starting" pos: [24,28] width: 470 height: 18
        label lblEndpoint "Server: 127.0.0.1:47635" pos: [24,50] width: 470 height: 18
        label lblIdentity "Max: detecting process identity" pos: [24,72] width: 470 height: 18

        groupBox grpScene "Current scene" pos: [12,110] width: 496 height: 66
        label lblScene "Scene: Untitled" pos: [24,132] width: 470 height: 18
        label lblSceneStats "Objects: 0 | Selection: 0 | Save required: false" pos: [24,152] width: 470 height: 18

        groupBox grpActivity "Recent activity / errors" pos: [12,182] width: 496 height: 158
        dotNetControl rtbActivity "System.Windows.Forms.RichTextBox" pos: [22,202] width: 476 height: 126

        button btnReconnect "Reconnect" pos: [12,350] width: 112 height: 30
        button btnStop "Stop Max Ultra" pos: [132,350] width: 112 height: 30
        button btnStart "Start Max Ultra" pos: [252,350] width: 112 height: 30
        button btnHide "Hide panel" pos: [396,350] width: 112 height: 30

        on MaxUltraMcpStatusDialog open do (
            if (bridgeClient != undefined) do (
                bridgeClient.configureActivityLog()
                bridgeClient.refreshUserInterface()
            )
        )

        on btnReconnect pressed do (
            if (bridgeClient != undefined) do bridgeClient.reconnectBridge()
        )

        on btnStop pressed do (
            if (bridgeClient != undefined) do bridgeClient.stopBridge reason: "Stopped from status panel"
        )

        on btnStart pressed do (
            if (bridgeClient != undefined) do bridgeClient.startBridge()
        )

        on btnHide pressed do (
            if (bridgeClient != undefined) do bridgeClient.hidePanel()
        )
    )

    struct MaxUltraMcpBridgeClient (
        hostAddress = "127.0.0.1",
        hostPort = 47635,
        instanceId = "",
        processId = 0,
        processStartedAt = "",
        bootstrapFilePath = "",
        statusDialog,
        transportWorker,
        inboundQueue,
        outboundQueue,
        pollTimer,
        tickCount = 0,
        connectionState = #stopped,
        connectionError = "",
        isStopped = true,
        pendingRequestLines = #(),
        cancelledRequestIds = #(),
        activityEntries = #(),
        maximumActivityEntries = 30,
        maximumPendingRequests = 100,
        maximumInboundLinesPerTick = 16,
        maximumRequestsPerTick = 1,

        fn encodeWireField sourceContent = (
            local normalizedContent = sourceContent as string
            if (normalizedContent.count == 0) do return "-"
            local encodingClass = dotNetClass "System.Text.Encoding"
            local convertClass = dotNetClass "System.Convert"
            return convertClass.ToBase64String (encodingClass.UTF8.GetBytes normalizedContent)
        ),

        fn decodeWireField sourceContent = (
            if (sourceContent == undefined or sourceContent == "" or sourceContent == "-") do return ""
            local encodingClass = dotNetClass "System.Text.Encoding"
            local convertClass = dotNetClass "System.Convert"
            return encodingClass.UTF8.GetString (convertClass.FromBase64String sourceContent)
        ),

        fn jsonEscape sourceContent = (
            local escapedContent = sourceContent as string
            escapedContent = substituteString escapedContent @"\" @"\\"
            escapedContent = substituteString escapedContent "\"" "\\\""
            escapedContent = substituteString escapedContent "\r" "\\r"
            escapedContent = substituteString escapedContent "\n" "\\n"
            escapedContent = substituteString escapedContent "\t" "\\t"
            return escapedContent
        ),

        fn jsonBoolean isEnabled = (
            if (isEnabled) then return "true" else return "false"
        ),

        fn ensureSlash folderPath = (
            if (folderPath == undefined or folderPath == "") do return ""
            local normalizedPath = substituteString (folderPath as string) "/" @"\"
            if ((substring normalizedPath normalizedPath.count 1) == @"\") do return normalizedPath
            return normalizedPath + @"\"
        ),

        fn currentSceneFilePath = (
            return maxFilePath + maxFileName
        ),

        fn currentSceneDisplayName = (
            local sceneFilePath = currentSceneFilePath()
            if (sceneFilePath == "") do return "Untitled"
            return sceneFilePath
        ),

        fn isSceneSaveRequired = (
            return getSaveRequired()
        ),

        fn currentMaxYear = (
            local versionInfo = maxVersion()
            if (versionInfo.count >= 8) do return versionInfo[8]
            return 1998 + ((versionInfo[1] / 1000) as integer)
        ),

        fn connectionStateText = (
            case connectionState of (
                #starting: return "Starting"
                #connecting: return "Connecting"
                #connected: return "Running / connected"
                #reconnecting: return "Reconnecting"
                #error: return "Error"
                default: return "Stopped"
            )
        ),

        fn panelIsOpen = (
            if (statusDialog == undefined) do return false
            try (
                return statusDialog.open
            ) catch (
                return false
            )
        ),

        fn activityText = (
            local outputText = ""
            for activityEntry in activityEntries do (
                if (outputText != "") do outputText += "\r\n"
                outputText += activityEntry
            )
            return outputText
        ),

        fn configureActivityLog = (
            if (not panelIsOpen()) do return false
            try (
                statusDialog.rtbActivity.ReadOnly = true
                statusDialog.rtbActivity.WordWrap = true
                statusDialog.rtbActivity.DetectUrls = false
                statusDialog.rtbActivity.HideSelection = false
                statusDialog.rtbActivity.ScrollBars = (dotNetClass "System.Windows.Forms.RichTextBoxScrollBars").Vertical
                statusDialog.rtbActivity.BackColor = (dotNetClass "System.Drawing.SystemColors").Window
                statusDialog.rtbActivity.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0
            ) catch (
            )
            return true
        ),

        fn refreshActivityText = (
            if (not panelIsOpen()) do return false
            local currentActivityText = activityText()
            statusDialog.rtbActivity.Text = currentActivityText
            statusDialog.rtbActivity.SelectionStart = statusDialog.rtbActivity.TextLength
            statusDialog.rtbActivity.SelectionLength = 0
            statusDialog.rtbActivity.ScrollToCaret()
            return true
        ),

        fn refreshUserInterface = (
            if (not panelIsOpen()) do return false
            local statusText = "Status: " + connectionStateText()
            if (connectionState == #error and connectionError != "") do statusText += " - " + connectionError
            statusDialog.lblStatus.text = statusText
            statusDialog.lblEndpoint.text = "Server: " + hostAddress + ":" + (hostPort as string)
            statusDialog.lblIdentity.text = "Max " + (currentMaxYear() as string) + " | PID " + (processId as string) + " | " + instanceId
            statusDialog.lblScene.text = "Scene: " + currentSceneDisplayName()
            statusDialog.lblSceneStats.text = "Objects: " + (objects.count as string) + " | Selection: " + (selection.count as string) + " | Save required: " + jsonBoolean(isSceneSaveRequired())
            statusDialog.btnStop.enabled = not isStopped
            statusDialog.btnStart.enabled = isStopped
            refreshActivityText()
            return true
        ),

        fn addActivity activityLevel activityMessage = (
            local timestampText = (dotNetClass "System.DateTime").Now.ToString("HH:mm:ss")
            append activityEntries (timestampText + " [" + activityLevel + "] " + (activityMessage as string))
            while (activityEntries.count > maximumActivityEntries) do deleteItem activityEntries 1
            refreshActivityText()
            return true
        ),

        fn showPanel = (
            if (not panelIsOpen()) do (
                createDialog statusDialog width: 520 height: 400 style: #(#style_titlebar, #style_sysmenu, #style_minimizebox)
            )
            refreshUserInterface()
            return true
        ),

        fn hidePanel = (
            if (panelIsOpen()) do destroyDialog statusDialog
            return true
        ),

        fn minimizePanel = (
            if (not panelIsOpen()) do showPanel()
            try (
                windows.sendMessage statusDialog.hwnd 0x0112 0xF020 0
                return true
            ) catch (
                return false
            )
        ),

        fn restorePanel = (
            if (not panelIsOpen()) do showPanel()
            try (
                windows.sendMessage statusDialog.hwnd 0x0112 0xF120 0
            ) catch (
            )
            refreshUserInterface()
            return true
        ),

        fn createSynchronizedQueue = (
            local queueClass = dotNetClass "System.Collections.Queue"
            return queueClass.Synchronized (dotNetObject "System.Collections.Queue")
        ),

        fn sendWireLine wireLine = (
            if (outboundQueue == undefined or isStopped) do return false
            outboundQueue.Enqueue wireLine
            return true
        ),

        fn sendSceneStatus = (
            local wireLine = "STATUS\t" + encodeWireField(currentSceneFilePath()) + "\t" + jsonBoolean(isSceneSaveRequired()) + "\t"
            wireLine += (objects.count as string) + "\t" + (selection.count as string) + "\t" + encodeWireField(sliderTime as string)
            return sendWireLine wireLine
        ),

        fn buildActivityLogJson = (
            local responseBody = "{\"action\":\"logs\",\"available\":true,\"source\":\"Max Ultra MCP panel\""
            responseBody += ",\"content\":\"" + jsonEscape(activityText()) + "\",\"entryCount\":" + (activityEntries.count as string)
            responseBody += ",\"maximumEntries\":" + (maximumActivityEntries as string) + "}"
            return responseBody
        ),

        fn buildSnapshotJson actionName = (
            local versionInfo = maxVersion()
            local currentTimestamp = (dotNetClass "System.DateTime").UtcNow.ToString("o")
            local responseBody = "{\"action\":\"" + jsonEscape(actionName) + "\",\"ok\":true,\"instanceId\":\"" + jsonEscape(instanceId) + "\""
            responseBody += ",\"pid\":" + (processId as string) + ",\"maxVersion\":\"" + (currentMaxYear() as string) + "\""
            responseBody += ",\"productVersion\":\"" + jsonEscape(versionInfo as string) + "\",\"mainThread\":true,\"sampledAt\":\"" + jsonEscape(currentTimestamp) + "\""
            responseBody += ",\"scene\":{\"filePath\":\"" + jsonEscape(currentSceneFilePath()) + "\",\"saveRequired\":" + jsonBoolean(isSceneSaveRequired())
            responseBody += ",\"objectCount\":" + (objects.count as string) + ",\"selectionCount\":" + (selection.count as string) + ",\"frame\":\"" + jsonEscape(sliderTime as string) + "\"}}"
            return responseBody
        ),

        fn sendBridgeResponse requestId isSuccess responseBody = (
            local responseState = if (isSuccess) then "ok" else "error"
            return sendWireLine ("RESPONSE\t" + requestId + "\t" + responseState + "\t" + encodeWireField(responseBody))
        ),

        fn handlePanelAction requestId panelAction = (
            local actionSucceeded = false
            case panelAction of (
                "show": actionSucceeded = showPanel()
                "hide": actionSucceeded = hidePanel()
                "minimize": actionSucceeded = minimizePanel()
                "restore": actionSucceeded = restorePanel()
                default: return sendBridgeResponse requestId false ("Unsupported panel action: " + panelAction)
            )
            local responseBody = "{\"action\":\"panel\",\"ok\":" + jsonBoolean(actionSucceeded) + ",\"requestedAction\":\"" + jsonEscape(panelAction) + "\",\"state\":\"" + jsonEscape(panelAction) + "\",\"mainThread\":true}"
            return sendBridgeResponse requestId actionSucceeded responseBody
        ),

        fn handleViewportScreenshot requestId screenshotPath = (
            local viewportBitmap = undefined
            try (
                viewportBitmap = gw.getViewportDib()
                if (viewportBitmap == undefined) do throw "The active viewport did not provide a bitmap"
                local bitmapWidth = viewportBitmap.width
                local bitmapHeight = viewportBitmap.height
                save viewportBitmap screenshotPath
                close viewportBitmap
                viewportBitmap = undefined
                local responseBody = "{\"action\":\"screenshot\",\"ok\":true,\"filePath\":\"" + jsonEscape(screenshotPath) + "\",\"mimeType\":\"image/png\",\"width\":" + (bitmapWidth as string) + ",\"height\":" + (bitmapHeight as string) + ",\"mainThread\":true}"
                addActivity "info" ("Viewport screenshot " + (bitmapWidth as string) + "x" + (bitmapHeight as string))
                return sendBridgeResponse requestId true responseBody
            ) catch (
                try (if (viewportBitmap != undefined) do close viewportBitmap) catch ()
                local errorMessage = getCurrentException()
                addActivity "error" ("Screenshot failed: " + errorMessage)
                return sendBridgeResponse requestId false errorMessage
            )
        ),

        fn handleExecuteRequest requestId scriptContent = (
            local startedAt = timestamp()
            addActivity "info" ("Executing MaxScript request " + requestId)
            try (
                local executionResult = execute scriptContent
                local resultText = ""
                try (resultText = executionResult as string) catch (resultText = "<result cannot be converted to string>")
                if (resultText.count > 16000) do resultText = (substring resultText 1 16000) + "..."
                local resultType = try ((classOf executionResult) as string) catch ("Unknown")
                local elapsedMilliseconds = timestamp() - startedAt
                local responseBody = "{\"action\":\"execute\",\"ok\":true,\"mainThread\":true,\"result\":\"" + jsonEscape(resultText) + "\",\"resultType\":\"" + jsonEscape(resultType) + "\",\"elapsedMs\":" + (elapsedMilliseconds as string) + "}"
                addActivity "info" ("MaxScript completed in " + (elapsedMilliseconds as string) + " ms")
                sendSceneStatus()
                return sendBridgeResponse requestId true responseBody
            ) catch (
                local errorMessage = getCurrentException()
                addActivity "error" ("MaxScript failed: " + errorMessage)
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
            return (dotNetClass "System.Int64").Parse normalizedText
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
            for hierarchyDepth = 1 to 64 while (uiHandleText currentWindowHandle) != "0" do (
                if ((uiHandleText currentWindowHandle) == (uiHandleText rootWindowHandle)) do return true
                try (currentWindowHandle = UIAccessor.GetParentWindow currentWindowHandle) catch (return false)
                if (currentWindowHandle == undefined) do return false
            )
            return false
        ),

        fn uiHandleBelongsToMax targetWindowHandle = (
            if (uiHandleDescendsFrom targetWindowHandle (windows.getMAXHWND())) do return true
            local popupWindowHandles = #()
            try (popupWindowHandles = UIAccessor.GetPopupDialogs()) catch (popupWindowHandles = #())
            if (popupWindowHandles == undefined) do popupWindowHandles = #()
            for popupWindowHandle in popupWindowHandles do (
                if (uiHandleDescendsFrom targetWindowHandle popupWindowHandle) do return true
            )
            return false
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
        ),
        fn requestWasCancelled requestId = (
            local cancelledIndex = findItem cancelledRequestIds requestId
            if (cancelledIndex == 0) do return false
            deleteItem cancelledRequestIds cancelledIndex
            return true
        ),

        fn handleRequestLine wireLine = (
            local wireFields = filterString wireLine "\t"
            if (wireFields.count < 3) do return false
            local requestId = wireFields[2]
            local actionName = wireFields[3]
            local actionPayload = if (wireFields.count >= 4) then decodeWireField(wireFields[4]) else ""
            if (requestWasCancelled requestId) do (
                addActivity "info" ("Cancelled queued request " + requestId)
                return sendBridgeResponse requestId false "Request was cancelled before main-thread execution"
            )
            case actionName of (
                "logs": return sendBridgeResponse requestId true (buildActivityLogJson())
                "health": (
                    sendSceneStatus()
                    return sendBridgeResponse requestId true (buildSnapshotJson actionName)
                )
                "snapshot": (
                    sendSceneStatus()
                    return sendBridgeResponse requestId true (buildSnapshotJson actionName)
                )
                "smoke": (
                    sendSceneStatus()
                    return sendBridgeResponse requestId true (buildSnapshotJson actionName)
                )
                "execute": return handleExecuteRequest requestId actionPayload
                "panel": return handlePanelAction requestId actionPayload
                "screenshot": return handleViewportScreenshot requestId actionPayload
                "ui_list": return handleUiListRequest requestId actionPayload
                "ui_invoke": return handleUiInvokeRequest requestId actionPayload
                default: return sendBridgeResponse requestId false ("Unsupported action: " + actionName)
            )
        ),

        fn enqueueMainThreadRequest wireLine = (
            if (pendingRequestLines.count >= maximumPendingRequests) do (
                local wireFields = filterString wireLine "\t"
                if (wireFields.count >= 2) do sendBridgeResponse wireFields[2] false "Main-thread request queue is full"
                addActivity "error" "Request queue limit reached"
                return false
            )
            append pendingRequestLines wireLine
            return true
        ),

        fn handleTransportEvent wireFields = (
            local eventName = if (wireFields.count >= 2) then wireFields[2] else "unknown"
            if (eventName == "connected") then (
                connectionState = #connected
                connectionError = ""
                addActivity "info" ("Connected to " + hostAddress + ":" + (hostPort as string))
            ) else if (eventName == "error") then (
                connectionState = #error
                connectionError = if (wireFields.count >= 3) then decodeWireField(wireFields[3]) else "Transport error"
                addActivity "error" connectionError
            ) else if (eventName == "disconnected") then (
                if (not isStopped) do connectionState = #reconnecting
            )
            return true
        ),

        fn stopTransportState reason: "Stopped" = (
            isStopped = true
            connectionState = #stopped
            connectionError = ""
            try (
                if (transportWorker != undefined and transportWorker.IsBusy) do transportWorker.CancelAsync()
            ) catch (
            )
            pendingRequestLines = #()
            cancelledRequestIds = #()
            addActivity "info" reason
            refreshUserInterface()
            return true
        ),

        fn handleInboundLine wireLine = (
            local wireFields = filterString wireLine "\t"
            if (wireFields.count < 1) do return false
            if (wireFields[1] == "EVENT") do return handleTransportEvent wireFields
            if (wireFields[1] == "REQUEST") do return enqueueMainThreadRequest wireLine
            if (wireFields[1] == "CANCEL" and wireFields.count >= 2) do (
                if ((findItem cancelledRequestIds wireFields[2]) == 0) do append cancelledRequestIds wireFields[2]
                while (cancelledRequestIds.count > maximumPendingRequests) do deleteItem cancelledRequestIds 1
                return true
            )
            if (wireFields[1] == "STOP") do (
                stopTransportState reason: "Stopped because this instance registration was replaced"
                hidePanel()
                return true
            )
            return false
        ),

        fn transportDoWork workerSender eventArgs = (
            local workerArguments = eventArgs.Argument
            local workerHost = workerArguments.Item[0]
            local workerPort = workerArguments.Item[1]
            local workerInboundQueue = workerArguments.Item[2]
            local workerOutboundQueue = workerArguments.Item[3]
            local workerClient = undefined
            local workerStream = undefined
            local workerReader = undefined
            local workerWriter = undefined
            try (
                workerClient = dotNetObject "System.Net.Sockets.TcpClient"
                workerClient.Connect workerHost workerPort
                workerStream = workerClient.GetStream()
                local utf8Encoding = dotNetObject "System.Text.UTF8Encoding" false
                workerReader = dotNetObject "System.IO.StreamReader" workerStream utf8Encoding
                workerWriter = dotNetObject "System.IO.StreamWriter" workerStream utf8Encoding
                workerWriter.AutoFlush = true
                workerInboundQueue.Enqueue "EVENT\tconnected"
                while (not workerSender.CancellationPending) do (
                    while (workerOutboundQueue.Count > 0) do workerWriter.WriteLine (workerOutboundQueue.Dequeue())
                    if (workerStream.DataAvailable) do (
                        local receivedLine = workerReader.ReadLine()
                        if (receivedLine == undefined) do throw "Max Ultra MCP server closed the connection"
                        workerInboundQueue.Enqueue receivedLine
                    )
                    (dotNetClass "System.Threading.Thread").Sleep 10
                )
            ) catch (
                local encodingClass = dotNetClass "System.Text.Encoding"
                local convertClass = dotNetClass "System.Convert"
                local encodedError = convertClass.ToBase64String (encodingClass.UTF8.GetBytes (getCurrentException() as string))
                workerInboundQueue.Enqueue ("EVENT\terror\t" + encodedError)
            )
            try (if (workerWriter != undefined) do workerWriter.Close()) catch ()
            try (if (workerReader != undefined) do workerReader.Close()) catch ()
            try (if (workerStream != undefined) do workerStream.Close()) catch ()
            try (if (workerClient != undefined) do workerClient.Close()) catch ()
            workerInboundQueue.Enqueue "EVENT\tdisconnected"
            return true
        ),

        fn initializeIdentity = (
            if (processId != 0) do return true
            local processInfo = (dotNetClass "System.Diagnostics.Process").GetCurrentProcess()
            processId = processInfo.Id
            local processStartTime = processInfo.StartTime.ToUniversalTime()
            processStartedAt = processStartTime.ToString("o")
            instanceId = "max-" + (currentMaxYear() as string) + "-pid-" + (processId as string) + "-" + (processStartTime.Ticks as string)
            processInfo.Dispose()
            bootstrapFilePath = getSourceFileName()
            return true
        ),

        fn buildHelloLine = (
            local versionInfo = maxVersion()
            local helloLine = "HELLO\t1\t" + encodeWireField(instanceId) + "\t" + (processId as string) + "\t"
            helloLine += encodeWireField(currentMaxYear()) + "\t" + encodeWireField(versionInfo as string) + "\t" + encodeWireField(processStartedAt)
            return helloLine
        ),

        fn startTransport = (
            if (isStopped) do return false
            if (transportWorker != undefined) do (
                try (if (transportWorker.IsBusy) do return false) catch ()
            )
            inboundQueue = createSynchronizedQueue()
            outboundQueue = createSynchronizedQueue()
            pendingRequestLines = #()
            cancelledRequestIds = #()
            transportWorker = dotNetObject "CSharpUtilities.SynchronizingBackgroundWorker"
            transportWorker.WorkerSupportsCancellation = true
            dotNet.addEventHandler transportWorker "DoWork" transportDoWork
            local workerArguments = dotNetObject "System.Collections.ArrayList"
            workerArguments.Add hostAddress
            workerArguments.Add hostPort
            workerArguments.Add inboundQueue
            workerArguments.Add outboundQueue
            outboundQueue.Enqueue (buildHelloLine())
            sendSceneStatus()
            connectionState = #connecting
            transportWorker.RunWorkerAsync workerArguments
            refreshUserInterface()
            return true
        ),

        fn stopBridge reason: "Stopped" = (
            return stopTransportState reason: reason
        ),

        fn reconnectBridge = (
            initializeIdentity()
            isStopped = false
            connectionState = #reconnecting
            connectionError = ""
            try (
                if (transportWorker != undefined and transportWorker.IsBusy) do transportWorker.CancelAsync()
            ) catch (
            )
            addActivity "info" "Reconnect requested"
            refreshUserInterface()
            return true
        ),

        fn handleTimerTick timerSender eventArgs = (
            tickCount += 1
            local handledInboundLines = 0
            while (inboundQueue != undefined and inboundQueue.Count > 0 and handledInboundLines < maximumInboundLinesPerTick) do (
                handleInboundLine (inboundQueue.Dequeue())
                handledInboundLines += 1
            )
            local handledRequests = 0
            while (not isStopped and pendingRequestLines.count > 0 and handledRequests < maximumRequestsPerTick) do (
                local requestLine = pendingRequestLines[1]
                deleteItem pendingRequestLines 1
                handleRequestLine requestLine
                handledRequests += 1
            )
            if (not isStopped and mod tickCount 10 == 0) do sendSceneStatus()
            if (not isStopped and (transportWorker == undefined or not transportWorker.IsBusy) and mod tickCount 20 == 1) do startTransport()
            if (mod tickCount 4 == 0) do refreshUserInterface()
            return true
        ),

        fn startBridge = (
            initializeIdentity()
            if (pollTimer == undefined) do (
                pollTimer = dotNetObject "System.Windows.Forms.Timer"
                pollTimer.Interval = 250
                dotNet.addEventHandler pollTimer "Tick" handleTimerTick
                pollTimer.Start()
            )
            if (not isStopped and transportWorker != undefined and transportWorker.IsBusy) do return true
            isStopped = false
            connectionState = #starting
            connectionError = ""
            showPanel()
            addActivity "info" "Max Ultra MCP starting"
            startTransport()
            return true
        )
    )

    bridgeClient = MaxUltraMcpBridgeClient statusDialog: MaxUltraMcpStatusDialog
    bridgeClient.startBridge()
    bridgeClient
)
