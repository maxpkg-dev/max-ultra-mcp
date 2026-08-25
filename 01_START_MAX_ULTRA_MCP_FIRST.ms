-- FIRST STEP: Run this file in 3ds Max to start Max Ultra MCP and connect/reconnect this Max.
-- Endpoint probing, lifecycle work, and retry waits run off the Max UI thread.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl

global MaxUltraMcpActiveClient

(
    local bridgeClient
    if (MaxUltraMcpActiveClient != undefined) do (
        try (
            MaxUltraMcpActiveClient.disposeForReload()
        ) catch (
            try (MaxUltraMcpActiveClient.stopBridge reason: "Replaced by first-step file re-run") catch ()
            try (MaxUltraMcpActiveClient.hidePanel()) catch ()
        )
        MaxUltraMcpActiveClient = undefined
    )

    struct MaxUltraMcpControlReply (
        controlState = #closed,
        responsePayload = "",
        failureMessage = ""
    )

    rollout MaxUltraMcpStatusDialog "3DGROUND - Max Ultra MCP | First Step" width: 680 height: 500 (
        dotNetControl lblStatus "System.Windows.Forms.Label" pos: [12,10] width: 560 height: 20
        dotNetControl lblContext "System.Windows.Forms.Label" pos: [12,34] width: 656 height: 20
        button btnHide "Hide panel" pos: [596,8] width: 72 height: 22

        dotNetControl pnlLogOutline "System.Windows.Forms.Panel" pos: [4,62] width: 672 height: 386
        dotNetControl rtbActivity "System.Windows.Forms.RichTextBox" pos: [5,63] width: 670 height: 384

        button btnReconnect "Reconnect" pos: [12,456] width: 120 height: 30
        button btnStop "Stop / Exit" pos: [140,456] width: 120 height: 30
        button btnStart "Connect only" pos: [268,456] width: 120 height: 30
        button btnSettings "Settings" pos: [548,456] width: 120 height: 30

        on MaxUltraMcpStatusDialog open do (
            if (bridgeClient != undefined) do (
                bridgeClient.configureActivityLog()
                bridgeClient.attachPanelFormClosing()
                bridgeClient.resizePanelControls [MaxUltraMcpStatusDialog.width, MaxUltraMcpStatusDialog.height]
                bridgeClient.refreshUserInterface()
            )
        )

        on MaxUltraMcpStatusDialog resized panelSize do if (bridgeClient != undefined) do bridgeClient.resizePanelControls panelSize
        on MaxUltraMcpStatusDialog close do if (bridgeClient != undefined) do bridgeClient.handlePanelRolloutClosed()
        on btnReconnect pressed do if (bridgeClient != undefined) do bridgeClient.reconnectBridge()
        on btnStop pressed do if (bridgeClient != undefined) do bridgeClient.closeForLifecycle reason: "Stop / Exit pressed"
        on btnStart pressed do if (bridgeClient != undefined) do bridgeClient.reconnectBridge()
        on btnHide pressed do if (bridgeClient != undefined) do bridgeClient.hidePanel()
        on btnSettings pressed do if (bridgeClient != undefined) do bridgeClient.showSettingsDialog()
    )

    rollout MaxUltraMcpSettingsDialog "Max Ultra MCP Settings" width: 360 height: 82 (
        groupBox grpAutostart "Autostart" pos: [12,10] width: 336 height: 58
        checkbox chkAutostart "Autostart with 3ds Max" pos: [24,34] width: 250 height: 20

        on MaxUltraMcpSettingsDialog open do if (bridgeClient != undefined) do bridgeClient.refreshSettingsDialog()
        on chkAutostart changed isChecked do if (bridgeClient != undefined) do bridgeClient.handleAutostartSettingChanged isChecked
    )
    struct MaxUltraMcpBridgeClient (
        hostAddress = "127.0.0.1",
        hostPort = 47635,
        instanceId = "",
        processId = 0,
        processStartedAt = "",
        bootstrapFilePath = "",
        serverLauncherPath = "",
        serverWorkingDirectory = "",
        serverShutdownHelperPath = "",
        serverOwnershipDirectory = "",
        serverOwnerToken = "",
        shutdownHelperStarted = false,
        uiStateDirectory = "",
        uiStateFilePath = "",
        lifecycleMutexName = @"Local\3DGround.MaxUltraMCP.ServerLifecycle",
        statusDialog,
        settingsDialog,
        transportWorker,
        inboundQueue,
        outboundQueue,
        pollTimer,
        panelForm,
        hiddenPanelPosition,
        hiddenPanelSize,
        lastNormalPanelPosition,
        lastNormalPanelSize,
        restoreBubbleForm,
        restoreBubbleLabel,
        restoreBubbleButton,
        restoreBubbleDragging = false,
        restoreBubbleDragOffset,
        restoreBubbleCloseAllowed = false,
        settingsRefreshInProgress = false,
        transportWorkerArguments,
        suppressPanelShutdown = false,
        panelCloseInProgress = false,
        isDisposed = false,
        maxShutdownCallbackId = #MaxUltraMcpLifecycle,
        tickCount = 0,
        connectionState = #stopped,
        connectionError = "",
        isStopped = true,
        pendingConnectOnly = false,
        hasConnectedThisSession = false,
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

        fn configureEndpointAndLauncher = (
            local environmentClass = dotNetClass "System.Environment"
            local configuredHost = environmentClass.GetEnvironmentVariable "MAX_ULTRA_MCP_HOST"
            local configuredPort = environmentClass.GetEnvironmentVariable "MAX_ULTRA_MCP_PORT"
            if (configuredHost != undefined and configuredHost != "") do hostAddress = configuredHost
            if (configuredPort != undefined and configuredPort != "") do (
                try (hostPort = configuredPort as integer) catch ()
            )

            serverLauncherPath = ""
            serverWorkingDirectory = ""
            serverShutdownHelperPath = ""
            uiStateDirectory = (ensureSlash (getDir #userScripts)) + @"MaxUltraMCP\"
            uiStateFilePath = uiStateDirectory + "panel-ui.ini"
            serverOwnershipDirectory = uiStateDirectory + @"ownership\"
            local launcherCandidates = #()
            if (bootstrapFilePath != undefined and bootstrapFilePath != "") do (
                append launcherCandidates ((ensureSlash (getFilenamePath bootstrapFilePath)) + @"scripts\start-server.bat")
            )
            local configuredRoot = environmentClass.GetEnvironmentVariable "MAX_ULTRA_MCP_ROOT"
            if (configuredRoot != undefined and configuredRoot != "") do (
                append launcherCandidates ((ensureSlash configuredRoot) + @"scripts\start-server.bat")
            )
            for launcherCandidate in launcherCandidates while serverLauncherPath == "" do (
                if (doesFileExist launcherCandidate) do (
                    serverLauncherPath = launcherCandidate
                    serverWorkingDirectory = ensureSlash (getFilenamePath launcherCandidate)
                    local helperCandidate = serverWorkingDirectory + "stop-owned-server.bat"
                    if (doesFileExist helperCandidate) do serverShutdownHelperPath = helperCandidate
                )
            )
            return serverLauncherPath != ""
        ),

        fn serverOwnershipFile portValue = (
            return serverOwnershipDirectory + "max-ultra-mcp-owned-" + (portValue as string) + ".json"
        ),

        fn launchDetachedShutdownHelper = (
            if (shutdownHelperStarted) do return true
            shutdownHelperStarted = true
            if (serverShutdownHelperPath == undefined or serverShutdownHelperPath == "" or not (doesFileExist serverShutdownHelperPath)) do (
                format "[3DGROUND | Max Ultra MCP] SHUTDOWN HELPER SKIPPED | scripts\\stop-owned-server.bat was not found\n"
                return false
            )
            try (
                local ownershipFilePath = serverOwnershipFile hostPort
                local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
                startInfo.FileName = "cmd.exe"
                startInfo.Arguments = "/d /c \"\"" + serverShutdownHelperPath + "\" -OwnershipFile \"" + ownershipFilePath + "\" -Port " + (hostPort as string) + " -OwnerToken \"" + serverOwnerToken + "\" -ClosingMaxPid " + (processId as string) + "\""
                startInfo.WorkingDirectory = serverWorkingDirectory
                startInfo.UseShellExecute = false
                startInfo.CreateNoWindow = true
                startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
                local helperProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
                if (helperProcess == undefined) do throw "Windows did not start the detached shutdown helper"
                helperProcess.Dispose()
                return true
            ) catch (
                format "[3DGROUND | Max Ultra MCP] SHUTDOWN HELPER ERROR | %\n" (getCurrentException() as string)
                return false
            )
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
                #restarting: return "Restarting local server"
                #error: return "Error"
                default: return "Stopped"
            )
        ),

        fn themeDrawingColor themeColorKey fallbackRed fallbackGreen fallbackBlue = (
            local colorClass = dotNetClass "System.Drawing.Color"
            try (
                local maxThemeColor = (colorMan.getColor themeColorKey) * 255
                local themeRed = amax 0 (amin 255 (maxThemeColor[1] as integer))
                local themeGreen = amax 0 (amin 255 (maxThemeColor[2] as integer))
                local themeBlue = amax 0 (amin 255 (maxThemeColor[3] as integer))
                return colorClass.FromArgb themeRed themeGreen themeBlue
            ) catch (
                return colorClass.FromArgb fallbackRed fallbackGreen fallbackBlue
            )
        ),

        fn lighterThemeSurface = (
            local colorClass = dotNetClass "System.Drawing.Color"
            local themeBackground = themeDrawingColor #background 68 68 68
            local surfaceRed = themeBackground.R + (((255 - themeBackground.R) * 0.08) as integer)
            local surfaceGreen = themeBackground.G + (((255 - themeBackground.G) * 0.08) as integer)
            local surfaceBlue = themeBackground.B + (((255 - themeBackground.B) * 0.08) as integer)
            return colorClass.FromArgb surfaceRed surfaceGreen surfaceBlue
        ),
        fn themeIsDark = (
            local themeBackground = themeDrawingColor #background 68 68 68
            local averageChannel = (themeBackground.R + themeBackground.G + themeBackground.B) / 3
            return averageChannel < 128
        ),

        fn statusTextColor = (
            local colorClass = dotNetClass "System.Drawing.Color"
            local darkTheme = themeIsDark()
            if (connectionState == #connected) do return if (darkTheme) then (colorClass.FromArgb 120 225 150) else (colorClass.FromArgb 0 110 65)
            if (connectionState == #connecting or connectionState == #starting or connectionState == #restarting or connectionState == #reconnecting) do return if (darkTheme) then (colorClass.FromArgb 255 195 80) else (colorClass.FromArgb 165 105 0)
            if (connectionState == #error or connectionState == #disconnected) do return if (darkTheme) then (colorClass.FromArgb 255 125 125) else (colorClass.FromArgb 180 0 0)
            return themeDrawingColor #text 220 220 220
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
            if (isDisposed or not panelIsOpen()) do return false
            try (
                statusDialog.rtbActivity.ReadOnly = true
                statusDialog.rtbActivity.WordWrap = true
                statusDialog.rtbActivity.DetectUrls = false
                statusDialog.rtbActivity.HideSelection = false
                statusDialog.rtbActivity.ScrollBars = (dotNetClass "System.Windows.Forms.RichTextBoxScrollBars").Vertical
                local colorClass = dotNetClass "System.Drawing.Color"
                statusDialog.pnlLogOutline.BackColor = (dotNetClass "System.Drawing.Color").Black
                statusDialog.pnlLogOutline.AccessibleName = "Flat black boundary for Max Ultra MCP activity log"
                statusDialog.rtbActivity.ForeColor = themeDrawingColor #text 220 220 220
                statusDialog.rtbActivity.BackColor = lighterThemeSurface()
                statusDialog.rtbActivity.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").None
                statusDialog.rtbActivity.AccessibleName = "Max Ultra MCP color-coded activity log"
                statusDialog.rtbActivity.TabStop = true
                statusDialog.rtbActivity.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0
                local panelThemeBackground = themeDrawingColor #background 68 68 68
                statusDialog.lblStatus.BackColor = panelThemeBackground
                statusDialog.lblContext.BackColor = panelThemeBackground
                local boldFontStyle = (dotNetClass "System.Drawing.FontStyle").Bold
                statusDialog.lblStatus.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0 boldFontStyle
                statusDialog.lblContext.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0
            ) catch (
            )
            return true
        ),

        fn activityEntryColor activityEntry = (
            local colorClass = dotNetClass "System.Drawing.Color"
            local normalizedEntry = toLower (activityEntry as string)
            local darkTheme = themeIsDark()
            if ((findString normalizedEntry " [error] ") != undefined) do return if (darkTheme) then (colorClass.FromArgb 255 125 125) else (colorClass.FromArgb 180 0 0)
            if ((findString normalizedEntry " [warning] ") != undefined) do return if (darkTheme) then (colorClass.FromArgb 255 195 80) else (colorClass.FromArgb 145 105 0)
            if ((findString normalizedEntry " [success] ") != undefined) do return if (darkTheme) then (colorClass.FromArgb 120 225 150) else (colorClass.FromArgb 0 100 0)
            if ((findString normalizedEntry " [debug] ") != undefined) do return if (darkTheme) then (colorClass.FromArgb 190 190 140) else (colorClass.FromArgb 90 90 0)
            return if (darkTheme) then (colorClass.FromArgb 110 205 235) else (colorClass.FromArgb 20 90 145)
        ),

        fn refreshActivityText = (
            if (isDisposed or not panelIsOpen()) do return false
            try (
                statusDialog.rtbActivity.SuspendLayout()
                statusDialog.rtbActivity.Clear()
                for activityIndex in 1 to activityEntries.count do (
                    local activityEntry = activityEntries[activityIndex]
                    statusDialog.rtbActivity.SelectionStart = statusDialog.rtbActivity.TextLength
                    statusDialog.rtbActivity.SelectionLength = 0
                    statusDialog.rtbActivity.SelectionColor = activityEntryColor activityEntry
                    statusDialog.rtbActivity.AppendText activityEntry
                    if (activityIndex < activityEntries.count) do statusDialog.rtbActivity.AppendText "\r\n"
                )
                statusDialog.rtbActivity.SelectionColor = statusDialog.rtbActivity.ForeColor
                statusDialog.rtbActivity.SelectionStart = statusDialog.rtbActivity.TextLength
                statusDialog.rtbActivity.SelectionLength = 0
                statusDialog.rtbActivity.ScrollToCaret()
                statusDialog.rtbActivity.ResumeLayout()
            ) catch (
                try (statusDialog.rtbActivity.ResumeLayout()) catch ()
            )
            return true
        ),
        fn resizePanelControls panelSize = (
            if (isDisposed or not panelIsOpen()) do return false
            local panelWidth = amax 540 panelSize.x
            local panelHeight = amax 420 panelSize.y
            local contentWidth = panelWidth - 24
            statusDialog.lblStatus.width = panelWidth - 108
            statusDialog.lblContext.width = contentWidth
            local logHeight = amax 260 (panelHeight - 114)
            statusDialog.pnlLogOutline.width = panelWidth - 8
            statusDialog.pnlLogOutline.height = logHeight
            statusDialog.rtbActivity.width = panelWidth - 10
            statusDialog.rtbActivity.height = logHeight - 2
            local buttonY = panelHeight - 44
            statusDialog.btnReconnect.pos.y = buttonY
            statusDialog.btnStop.pos.y = buttonY
            statusDialog.btnStart.pos.y = buttonY
            statusDialog.btnSettings.pos = [panelWidth - 132, buttonY]
            statusDialog.btnHide.pos = [panelWidth - 84, 8]
            return true
        ),

        fn requestedPanelSize panelSize = (
            local requestedWidth = 680
            local requestedHeight = 500
            if (panelSize != undefined) do (
                try (requestedWidth = panelSize.x as integer) catch (requestedWidth = 680)
                try (requestedHeight = panelSize.y as integer) catch (requestedHeight = 500)
            )
            return [requestedWidth, requestedHeight]
        ),

        fn clampPanelSizeToWorkingArea panelSize workingArea = (
            local requestedSize = requestedPanelSize panelSize
            local maximumWidth = amax 1 (workingArea.Width as integer)
            local maximumHeight = amax 1 (workingArea.Height as integer)
            local minimumWidth = amin 540 maximumWidth
            local minimumHeight = amin 420 maximumHeight
            local clampedWidth = amax minimumWidth (amin maximumWidth requestedSize.x)
            local clampedHeight = amax minimumHeight (amin maximumHeight requestedSize.y)
            return [clampedWidth as integer, clampedHeight as integer]
        ),

        fn defaultPanelGeometry panelSize = (
            local workingArea = (dotNetClass "System.Windows.Forms.Screen").PrimaryScreen.WorkingArea
            local clampedSize = clampPanelSizeToWorkingArea panelSize workingArea
            local centeredX = workingArea.Left + (amax 0 ((workingArea.Width - clampedSize.x) / 2))
            local centeredY = workingArea.Top + (amax 0 ((workingArea.Height - clampedSize.y) / 2))
            return #([centeredX as integer, centeredY as integer], clampedSize)
        ),

        fn normalizePanelGeometry panelPosition panelSize = (
            if (panelPosition == undefined) do return defaultPanelGeometry panelSize
            local requestedSize = requestedPanelSize panelSize
            try (
                local panelX = panelPosition.x as integer
                local panelY = panelPosition.y as integer
                local candidateWidth = amin 1000000 (amax 1 requestedSize.x)
                local candidateHeight = amin 1000000 (amax 1 requestedSize.y)
                local candidateBounds = dotNetObject "System.Drawing.Rectangle" panelX panelY candidateWidth candidateHeight
                local targetScreen = (dotNetClass "System.Windows.Forms.Screen").FromRectangle candidateBounds
                if (targetScreen == undefined) do return defaultPanelGeometry requestedSize
                local workingArea = targetScreen.WorkingArea
                local clampedSize = clampPanelSizeToWorkingArea requestedSize workingArea
                local maximumX = workingArea.Right - clampedSize.x
                local maximumY = workingArea.Bottom - clampedSize.y
                local clampedX = amax workingArea.Left (amin maximumX panelX)
                local clampedY = amax workingArea.Top (amin maximumY panelY)
                return #([clampedX as integer, clampedY as integer], clampedSize)
            ) catch (
                return defaultPanelGeometry requestedSize
            )
        ),

        fn loadPanelGeometry = (
            local storedPosition = undefined
            local storedSize = undefined
            if (uiStateFilePath == undefined or uiStateFilePath == "" or not (doesFileExist uiStateFilePath)) do return defaultPanelGeometry undefined
            try (
                local storedX = getINISetting uiStateFilePath "panel" "x"
                local storedY = getINISetting uiStateFilePath "panel" "y"
                if (storedX != "" and storedY != "") do storedPosition = [storedX as integer, storedY as integer]
            ) catch (storedPosition = undefined)
            try (
                local storedWidth = getINISetting uiStateFilePath "panel" "width"
                local storedHeight = getINISetting uiStateFilePath "panel" "height"
                if (storedWidth != "" and storedHeight != "") do storedSize = [storedWidth as integer, storedHeight as integer]
            ) catch (storedSize = undefined)
            return normalizePanelGeometry storedPosition storedSize
        ),

        fn persistPanelGeometry panelPosition panelSize = (
            if (panelPosition == undefined or uiStateDirectory == undefined or uiStateDirectory == "") do return false
            try (
                local panelGeometry = normalizePanelGeometry panelPosition panelSize
                local normalizedPosition = panelGeometry[1]
                local normalizedSize = panelGeometry[2]
                if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
                setINISetting uiStateFilePath "panel" "x" ((normalizedPosition.x as integer) as string)
                setINISetting uiStateFilePath "panel" "y" ((normalizedPosition.y as integer) as string)
                setINISetting uiStateFilePath "panel" "width" ((normalizedSize.x as integer) as string)
                setINISetting uiStateFilePath "panel" "height" ((normalizedSize.y as integer) as string)
                return true
            ) catch (
                return false
            )
        ),

        fn rememberNormalPanelGeometry formSender = (
            if (not panelIsOpen()) do return false
            try (
                local normalWindowState = (dotNetClass "System.Windows.Forms.FormWindowState").Normal
                if (formSender != undefined and formSender.WindowState != normalWindowState) do return false
                local currentGeometry = normalizePanelGeometry (getDialogPos statusDialog) [statusDialog.width, statusDialog.height]
                lastNormalPanelPosition = currentGeometry[1]
                lastNormalPanelSize = currentGeometry[2]
                return true
            ) catch (
                return false
            )
        ),

        fn capturePanelGeometry formSender = (
            rememberNormalPanelGeometry formSender
            if (lastNormalPanelPosition != undefined and lastNormalPanelSize != undefined) do return normalizePanelGeometry lastNormalPanelPosition lastNormalPanelSize
            try (
                if (formSender != undefined) do (
                    local restoreBounds = formSender.RestoreBounds
                    if (restoreBounds.Width > 0 and restoreBounds.Height > 0) do return normalizePanelGeometry [restoreBounds.X as integer, restoreBounds.Y as integer] undefined
                )
            ) catch ()
            return loadPanelGeometry()
        ),

        fn settingsDialogIsOpen = (
            if (settingsDialog == undefined) do return false
            try (
                return settingsDialog.open
            ) catch (
                return false
            )
        ),

        fn autostartScriptFilePath = (
            local startupDirectory = ensureSlash (getDir #userStartupScripts)
            if (startupDirectory == "") do return ""
            return startupDirectory + "3DGROUND-Max-Ultra-MCP-Autostart.ms"
        ),

        fn maxScriptStringLiteral sourceContent = (
            local backslashCharacter = bit.intAsChar 92
            local quoteCharacter = bit.intAsChar 34
            local escapedContent = sourceContent as string
            escapedContent = substituteString escapedContent backslashCharacter (backslashCharacter + backslashCharacter)
            escapedContent = substituteString escapedContent quoteCharacter (backslashCharacter + quoteCharacter)
            escapedContent = substituteString escapedContent (bit.intAsChar 13) (backslashCharacter + "r")
            escapedContent = substituteString escapedContent (bit.intAsChar 10) (backslashCharacter + "n")
            return quoteCharacter + escapedContent + quoteCharacter
        ),

        fn persistAutostartSetting isEnabled = (
            if (uiStateDirectory == undefined or uiStateDirectory == "") do return false
            try (
                if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
                setINISetting uiStateFilePath "settings" "autostart" (if (isEnabled) then "true" else "false")
                return true
            ) catch (
                return false
            )
        ),

        fn loadAutostartSetting = (
            local autostartFileExists = doesFileExist (autostartScriptFilePath())
            local storedSetting = ""
            try (
                if (uiStateFilePath != undefined and uiStateFilePath != "" and doesFileExist uiStateFilePath) do (
                    storedSetting = toLower (getINISetting uiStateFilePath "settings" "autostart")
                )
            ) catch (storedSetting = "")
            if (storedSetting == "") do (
                persistAutostartSetting autostartFileExists
                return autostartFileExists
            )
            if (storedSetting == "true" and not autostartFileExists) do (
                persistAutostartSetting false
                return false
            )
            if (storedSetting == "false" and autostartFileExists) do (
                persistAutostartSetting true
                return true
            )
            if (storedSetting != "true" and storedSetting != "false") do (
                persistAutostartSetting autostartFileExists
                return autostartFileExists
            )
            return storedSetting == "true" and autostartFileExists
        ),

        fn writeAutostartScript = (
            if (bootstrapFilePath == undefined or bootstrapFilePath == "" or not (doesFileExist bootstrapFilePath)) do return false
            local autostartFilePath = autostartScriptFilePath()
            if (autostartFilePath == "" or uiStateFilePath == undefined or uiStateFilePath == "") do return false
            local startupDirectory = getFilenamePath autostartFilePath
            local bootstrapLiteral = maxScriptStringLiteral bootstrapFilePath
            local uiStateLiteral = maxScriptStringLiteral uiStateFilePath
            local settingsSectionLiteral = maxScriptStringLiteral "settings"
            local autostartKeyLiteral = maxScriptStringLiteral "autostart"
            local falseLiteral = maxScriptStringLiteral "false"
            local errorPrefixLiteral = maxScriptStringLiteral "[3DGROUND | Max Ultra MCP] AUTOSTART ERROR | "
            local cleanupExpression = "try (deleteFile " + (maxScriptStringLiteral autostartFilePath) + ") catch ()"
            local cleanupLiteral = maxScriptStringLiteral cleanupExpression
            local sourceLines = #(
                "-- Launches 3DGROUND - Max Ultra MCP from the saved bootstrap path.",
                "-- Copyright (c) 2026 Lukianenko Vasyl",
                "-- Project website: https://3dground.net",
                "-- Developed by Lukianenko Vasyl",
                "",
                "(",
                "    local maxUltraMcpBootstrapPath = " + bootstrapLiteral,
                "    if (doesFileExist maxUltraMcpBootstrapPath) then (",
                "        try (",
                "            fileIn maxUltraMcpBootstrapPath quiet: true",
                "        ) catch (",
                "            print (" + errorPrefixLiteral + " + (getCurrentException() as string))",
                "        )",
                "    ) else (",
                "        try (setINISetting " + uiStateLiteral + " " + settingsSectionLiteral + " " + autostartKeyLiteral + " " + falseLiteral + ") catch ()",
                "        callbacks.removeScripts id: #MaxUltraMcpAutostartCleanup",
                "        callbacks.addScript #postSystemStartup " + cleanupLiteral + " id: #MaxUltraMcpAutostartCleanup persistent: false",
                "    )",
                ")"
            )
            local autostartStream = undefined
            try (
                if (not (doesDirectoryExist startupDirectory)) do makeDir startupDirectory
                autostartStream = createFile autostartFilePath
                if (autostartStream == undefined) do throw "Could not create the Max Ultra MCP autostart script"
                for sourceLineIndex in 1 to sourceLines.count do format (sourceLines[sourceLineIndex] + "\n") to: autostartStream
                close autostartStream
                autostartStream = undefined
                return true
            ) catch (
                try (if (autostartStream != undefined) do close autostartStream) catch ()
                try (if (doesFileExist autostartFilePath) do deleteFile autostartFilePath) catch ()
                return false
            )
        ),

        fn setAutostartEnabled isEnabled = (
            local autostartFilePath = autostartScriptFilePath()
            if (isEnabled) then (
                if (not (writeAutostartScript())) do return false
                if (persistAutostartSetting true) do return true
                try (deleteFile autostartFilePath) catch ()
                return false
            ) else (
                if (doesFileExist autostartFilePath) do (
                    try (if (not (deleteFile autostartFilePath)) do return false) catch (return false)
                )
                if (persistAutostartSetting false) do return true
                try (writeAutostartScript()) catch ()
                return false
            )
        ),

        fn disposeSettingsDialog = (
            settingsRefreshInProgress = true
            try (if (settingsDialogIsOpen()) do destroyDialog settingsDialog) catch ()
            settingsRefreshInProgress = false
            return true
        ),

        fn refreshSettingsDialog = (
            if (not (settingsDialogIsOpen())) do return false
            settingsRefreshInProgress = true
            try (settingsDialog.chkAutostart.checked = loadAutostartSetting()) catch ()
            settingsRefreshInProgress = false
            return true
        ),

        fn handleAutostartSettingChanged isEnabled = (
            if (settingsRefreshInProgress) do return true
            if (setAutostartEnabled isEnabled) do return true
            settingsRefreshInProgress = true
            try (if (settingsDialogIsOpen()) do settingsDialog.chkAutostart.checked = not isEnabled) catch ()
            settingsRefreshInProgress = false
            messageBox "Could not update the Max Ultra MCP autostart file or INI setting." title: "Max Ultra MCP Settings"
            return false
        ),

        fn showSettingsDialog = (
            if (isDisposed) do return false
            if (settingsDialogIsOpen()) do return true
            try (
                createDialog settingsDialog width: 360 height: 82 style: #(#style_titlebar, #style_sysmenu)
                return settingsDialogIsOpen()
            ) catch (
                format "[3DGROUND | Max Ultra MCP] SETTINGS ERROR | %\n" (getCurrentException() as string)
                return false
            )
        ),

        fn defaultRestoreBubblePosition = (
            local screenClass = dotNetClass "System.Windows.Forms.Screen"
            local targetScreen = undefined
            try (
                local maxWindowHandle = dotNetObject "System.IntPtr" (windows.getMAXHWND())
                targetScreen = screenClass.FromHandle maxWindowHandle
            ) catch ()
            if (targetScreen == undefined) do targetScreen = screenClass.PrimaryScreen
            local workingArea = targetScreen.WorkingArea
            return [(workingArea.Left + 12) as integer, (workingArea.Bottom - 64 - 12) as integer]
        ),

        fn normalizeRestoreBubblePosition bubblePosition = (
            if (bubblePosition == undefined) do return defaultRestoreBubblePosition()
            try (
                local bubbleX = bubblePosition.x as integer
                local bubbleY = bubblePosition.y as integer
                local bubbleBounds = dotNetObject "System.Drawing.Rectangle" bubbleX bubbleY 236 64
                local targetScreen = (dotNetClass "System.Windows.Forms.Screen").FromRectangle bubbleBounds
                if (targetScreen == undefined) do return defaultRestoreBubblePosition()
                local workingArea = targetScreen.WorkingArea
                local maximumX = workingArea.Right - 236
                local maximumY = workingArea.Bottom - 64
                local clampedX = amax workingArea.Left (amin maximumX bubbleX)
                local clampedY = amax workingArea.Top (amin maximumY bubbleY)
                return [clampedX as integer, clampedY as integer]
            ) catch (
                return defaultRestoreBubblePosition()
            )
        ),

        fn loadRestoreBubblePosition = (
            local storedPosition = undefined
            if (uiStateFilePath != undefined and uiStateFilePath != "" and doesFileExist uiStateFilePath) do (
                try (
                    local storedX = getINISetting uiStateFilePath "restoreBubble" "x"
                    local storedY = getINISetting uiStateFilePath "restoreBubble" "y"
                    if (storedX != "" and storedY != "") do storedPosition = [storedX as integer, storedY as integer]
                ) catch (storedPosition = undefined)
            )
            return normalizeRestoreBubblePosition storedPosition
        ),

        fn persistRestoreBubblePosition bubblePosition = (
            if (bubblePosition == undefined or uiStateDirectory == undefined or uiStateDirectory == "") do return false
            try (
                local normalizedPosition = normalizeRestoreBubblePosition bubblePosition
                if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
                setINISetting uiStateFilePath "restoreBubble" "x" ((normalizedPosition.x as integer) as string)
                setINISetting uiStateFilePath "restoreBubble" "y" ((normalizedPosition.y as integer) as string)
                return true
            ) catch (
                return false
            )
        ),

        fn handleRestoreBubbleMouseDown labelSender eventArgs = (
            if (eventArgs == undefined or eventArgs.Button != (dotNetClass "System.Windows.Forms.MouseButtons").Left) do return true
            local labelOffsetX = 0
            local labelOffsetY = 0
            if (labelSender != undefined) do (
                labelOffsetX = labelSender.Left as integer
                labelOffsetY = labelSender.Top as integer
            )
            restoreBubbleDragging = true
            restoreBubbleDragOffset = [labelOffsetX + (eventArgs.X as integer), labelOffsetY + (eventArgs.Y as integer)]
            try (if (labelSender != undefined) do labelSender.Capture = true) catch ()
            return true
        ),

        fn handleRestoreBubbleMouseMove labelSender eventArgs = (
            if (not restoreBubbleDragging or restoreBubbleForm == undefined or restoreBubbleDragOffset == undefined) do return true
            try (
                local cursorPosition = (dotNetClass "System.Windows.Forms.Cursor").Position
                local requestedPosition = [cursorPosition.X - restoreBubbleDragOffset.x, cursorPosition.Y - restoreBubbleDragOffset.y]
                local normalizedPosition = normalizeRestoreBubblePosition requestedPosition
                restoreBubbleForm.Location = dotNetObject "System.Drawing.Point" normalizedPosition.x normalizedPosition.y
            ) catch ()
            return true
        ),

        fn handleRestoreBubbleMouseUp labelSender eventArgs = (
            if (eventArgs != undefined and eventArgs.Button == (dotNetClass "System.Windows.Forms.MouseButtons").Left) do (
                restoreBubbleDragging = false
                restoreBubbleDragOffset = undefined
                try (if (labelSender != undefined) do labelSender.Capture = false) catch ()
                try (
                    if (restoreBubbleForm != undefined and not restoreBubbleForm.IsDisposed) do (
                        persistRestoreBubblePosition [restoreBubbleForm.Left as integer, restoreBubbleForm.Top as integer]
                    )
                ) catch ()
            )
            return true
        ),

        fn disposeRestoreBubble = (
            local bubbleLabelToDispose = restoreBubbleLabel
            local bubbleButtonToDispose = restoreBubbleButton
            local bubbleFormToDispose = restoreBubbleForm
            restoreBubbleLabel = undefined
            restoreBubbleButton = undefined
            restoreBubbleForm = undefined
            restoreBubbleDragging = false
            restoreBubbleDragOffset = undefined
            restoreBubbleCloseAllowed = true
            try (if (bubbleLabelToDispose != undefined) do dotNet.removeEventHandler bubbleLabelToDispose "MouseDown" handleRestoreBubbleMouseDown) catch ()
            try (if (bubbleLabelToDispose != undefined) do dotNet.removeEventHandler bubbleLabelToDispose "MouseMove" handleRestoreBubbleMouseMove) catch ()
            try (if (bubbleLabelToDispose != undefined) do dotNet.removeEventHandler bubbleLabelToDispose "MouseUp" handleRestoreBubbleMouseUp) catch ()
            try (if (bubbleButtonToDispose != undefined) do dotNet.removeEventHandler bubbleButtonToDispose "Click" handleRestoreBubbleClick) catch ()
            try (if (bubbleFormToDispose != undefined) do dotNet.removeEventHandler bubbleFormToDispose "FormClosing" handleRestoreBubbleFormClosing) catch ()
            try (
                if (bubbleFormToDispose != undefined) do (
                    bubbleFormToDispose.Hide()
                    bubbleFormToDispose.Close()
                    bubbleFormToDispose.Dispose()
                )
            ) catch ()
            try (if (bubbleLabelToDispose != undefined) do bubbleLabelToDispose.Dispose()) catch ()
            try (if (bubbleButtonToDispose != undefined) do bubbleButtonToDispose.Dispose()) catch ()
            restoreBubbleCloseAllowed = false
            return true
        ),

        fn handleRestoreBubbleFormClosing formSender eventArgs = (
            if (not restoreBubbleCloseAllowed and eventArgs != undefined) do eventArgs.Cancel = true
            return true
        ),

        fn handlePanelGeometryChanged formSender eventArgs = (
            if (not isDisposed and rememberNormalPanelGeometry formSender) do (
                persistPanelGeometry lastNormalPanelPosition lastNormalPanelSize
            )
            return true
        ),

        fn restoreHiddenPanel = (
            if (isDisposed) do return false
            if (not panelIsOpen()) do (
                local restoreGeometry = if (hiddenPanelPosition == undefined and hiddenPanelSize == undefined) then loadPanelGeometry() else normalizePanelGeometry hiddenPanelPosition hiddenPanelSize
                local restorePosition = restoreGeometry[1]
                local restoreSize = restoreGeometry[2]
                try (
                    createDialog statusDialog width: restoreSize.x height: restoreSize.y pos: restorePosition style: #(#style_titlebar, #style_sysmenu, #style_minimizebox, #style_resizing)
                ) catch (
                    format "[3DGROUND | Max Ultra MCP] RESTORE ERROR | %\n" (getCurrentException() as string)
                )
            )
            if (not panelIsOpen()) do return false
            hiddenPanelPosition = undefined
            hiddenPanelSize = undefined
            disposeRestoreBubble()
            return true
        ),

        fn handleRestoreBubbleClick bubbleSender eventArgs = (
            if (isDisposed) do return true
            if (not (restoreHiddenPanel())) do (
                try (addActivity "error" "Could not expand the MCP Server panel; the restore mini-panel remains available") catch ()
            )
            return true
        ),

        fn showRestoreBubble = (
            if (isDisposed) do return false
            if (restoreBubbleForm != undefined) do (
                try (
                    if (not restoreBubbleForm.IsDisposed) do (
                        if (not restoreBubbleForm.Visible) do restoreBubbleForm.Show()
                        restoreBubbleForm.BringToFront()
                        return true
                    )
                ) catch ()
                disposeRestoreBubble()
            )
            try (
                restoreBubbleForm = dotNetObject "System.Windows.Forms.Form"
                restoreBubbleLabel = dotNetObject "System.Windows.Forms.Label"
                restoreBubbleButton = dotNetObject "System.Windows.Forms.Button"
                restoreBubbleForm.FormBorderStyle = (dotNetClass "System.Windows.Forms.FormBorderStyle").None
                restoreBubbleForm.ControlBox = false
                restoreBubbleForm.MinimizeBox = false
                restoreBubbleForm.MaximizeBox = false
                restoreBubbleForm.ShowIcon = false
                restoreBubbleForm.ShowInTaskbar = false
                restoreBubbleForm.TopMost = true
                restoreBubbleForm.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").Manual
                restoreBubbleForm.Size = dotNetObject "System.Drawing.Size" 236 64
                local bubblePosition = loadRestoreBubblePosition()
                restoreBubbleForm.Location = dotNetObject "System.Drawing.Point" bubblePosition.x bubblePosition.y
                restoreBubbleForm.BackColor = themeDrawingColor #background 68 68 68
                restoreBubbleForm.Text = "Max Ultra MCP"
                restoreBubbleForm.AccessibleName = "Max Ultra MCP restore mini-panel"
                restoreBubbleLabel.Text = "Max Ultra MCP"
                restoreBubbleLabel.Location = dotNetObject "System.Drawing.Point" 8 5
                restoreBubbleLabel.Size = dotNetObject "System.Drawing.Size" 220 18
                restoreBubbleLabel.BackColor = restoreBubbleForm.BackColor
                restoreBubbleLabel.ForeColor = themeDrawingColor #text 220 220 220
                restoreBubbleLabel.TabStop = false
                restoreBubbleLabel.Cursor = (dotNetClass "System.Windows.Forms.Cursors").SizeAll
                restoreBubbleLabel.AccessibleDescription = "Drag to move the Max Ultra MCP restore mini-panel"
                restoreBubbleButton.Text = "Expand MCP Server"
                restoreBubbleButton.AccessibleName = "Expand MCP Server"
                restoreBubbleButton.Location = dotNetObject "System.Drawing.Point" 8 27
                restoreBubbleButton.Size = dotNetObject "System.Drawing.Size" 220 29
                restoreBubbleButton.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").Flat
                restoreBubbleButton.FlatAppearance.BorderSize = 1
                restoreBubbleButton.FlatAppearance.BorderColor = (dotNetClass "System.Drawing.Color").Black
                restoreBubbleButton.BackColor = lighterThemeSurface()
                restoreBubbleButton.ForeColor = statusTextColor()
                local boldFontStyle = (dotNetClass "System.Drawing.FontStyle").Bold
                restoreBubbleButton.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0 boldFontStyle
                dotNet.addEventHandler restoreBubbleLabel "MouseDown" handleRestoreBubbleMouseDown
                dotNet.addEventHandler restoreBubbleLabel "MouseMove" handleRestoreBubbleMouseMove
                dotNet.addEventHandler restoreBubbleLabel "MouseUp" handleRestoreBubbleMouseUp
                dotNet.addEventHandler restoreBubbleButton "Click" handleRestoreBubbleClick
                dotNet.addEventHandler restoreBubbleForm "FormClosing" handleRestoreBubbleFormClosing
                restoreBubbleForm.Controls.Add restoreBubbleLabel
                restoreBubbleForm.Controls.Add restoreBubbleButton
                restoreBubbleForm.Show()
                return true
            ) catch (
                format "[3DGROUND | Max Ultra MCP] RESTORE MINI-PANEL ERROR | %\n" (getCurrentException() as string)
                disposeRestoreBubble()
                return false
            )
        ),
        fn stopPollTimer = (
            local timerToDispose = pollTimer
            pollTimer = undefined
            if (timerToDispose == undefined) do return true
            try (timerToDispose.Stop()) catch ()
            try (dotNet.removeEventHandler timerToDispose "Tick" handleTimerTick) catch ()
            try (timerToDispose.Dispose()) catch ()
            return true
        ),

        fn performPanelFormClosing formSender eventArgs = (
            local wasAlreadyDisposed = isDisposed
            isDisposed = true
            isStopped = true
            pendingConnectOnly = false
            panelCloseInProgress = true
            stopPollTimer()
            if (formSender != undefined) do (
                try (
                    local finalGeometry = capturePanelGeometry formSender
                    persistPanelGeometry finalGeometry[1] finalGeometry[2]
                ) catch (
                    try (format "[3DGROUND | Max Ultra MCP] GEOMETRY SAVE ERROR | %\n" (getCurrentException() as string)) catch ()
                )
            )
            disposeSettingsDialog()
            disposeRestoreBubble()
            if (suppressPanelShutdown or wasAlreadyDisposed) do return true
            connectionState = #stopped
            launchDetachedShutdownHelper()
            try (if (transportWorker != undefined and transportWorker.IsBusy) do transportWorker.CancelAsync()) catch ()
            try (callbacks.removeScripts id: maxShutdownCallbackId) catch ()
            MaxUltraMcpActiveClient = undefined
            return true
        ),

        fn handlePanelFormClosing formSender eventArgs = (
            try (if (formSender != undefined) do dotNet.removeEventHandler formSender "FormClosing" handlePanelFormClosing) catch ()
            try (if (formSender != undefined) do dotNet.removeEventHandler formSender "LocationChanged" handlePanelGeometryChanged) catch ()
            try (if (formSender != undefined) do dotNet.removeEventHandler formSender "ResizeEnd" handlePanelGeometryChanged) catch ()
            local cleanupResult = true
            try (
                cleanupResult = performPanelFormClosing formSender eventArgs
            ) catch (
                try (format "[3DGROUND | Max Ultra MCP] FORM CLOSE ERROR | %\n" (getCurrentException() as string)) catch ()
            )
            return cleanupResult
        ),

        fn handlePanelRolloutClosed = (
            if (suppressPanelShutdown or isDisposed or panelCloseInProgress) do return true
            local closedPanelForm = panelForm
            local cleanupResult = handlePanelFormClosing closedPanelForm undefined
            panelForm = undefined
            return cleanupResult
        ),

        fn detachPanelFormEvents formSender = (
            if (formSender == undefined) do return true
            try (dotNet.removeEventHandler formSender "FormClosing" handlePanelFormClosing) catch ()
            try (dotNet.removeEventHandler formSender "LocationChanged" handlePanelGeometryChanged) catch ()
            try (dotNet.removeEventHandler formSender "ResizeEnd" handlePanelGeometryChanged) catch ()
            return true
        ),

        fn attachPanelFormClosing = (
            if (not panelIsOpen()) do return false
            try (
                local dialogHandle = dotNetObject "System.IntPtr" statusDialog.hwnd
                panelForm = (dotNetClass "System.Windows.Forms.Control").FromHandle dialogHandle
                if (panelForm == undefined) do return false
                detachPanelFormEvents panelForm
                dotNet.addEventHandler panelForm "FormClosing" handlePanelFormClosing
                dotNet.addEventHandler panelForm "LocationChanged" handlePanelGeometryChanged
                dotNet.addEventHandler panelForm "ResizeEnd" handlePanelGeometryChanged
                rememberNormalPanelGeometry panelForm
                return true
            ) catch (
                format "[3DGROUND | Max Ultra MCP] FORM HOOK ERROR | %\n" (getCurrentException() as string)
                return false
            )
        ),

        fn refreshUserInterface = (
            if (isDisposed or not panelIsOpen()) do return false
            local statusText = "Status: " + connectionStateText()
            if (connectionState == #error and connectionError != "") do statusText += " - " + connectionError
            statusDialog.lblStatus.Text = statusText
            statusDialog.lblStatus.ForeColor = statusTextColor()
            statusDialog.lblStatus.AccessibleName = "Max Ultra MCP connection status"
            statusDialog.lblStatus.AccessibleDescription = statusText
            local contextText = "Server " + hostAddress + ":" + (hostPort as string) + " | Max " + (currentMaxYear() as string) + " PID " + (processId as string)
            contextText += " | Scene " + currentSceneDisplayName() + " | Objects " + (objects.count as string) + " | Selection " + (selection.count as string) + " | Dirty " + jsonBoolean(isSceneSaveRequired())
            statusDialog.lblContext.Text = contextText
            statusDialog.lblContext.ForeColor = themeDrawingColor #text 220 220 220
            statusDialog.lblContext.AccessibleName = "Max Ultra MCP server and scene context"
            statusDialog.lblContext.AccessibleDescription = contextText
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
            if (isDisposed) do return false
            if (not panelIsOpen()) then (
                if (not (restoreHiddenPanel())) do return false
            ) else (
                try (if (panelForm != undefined) do panelForm.Show()) catch ()
                disposeRestoreBubble()
            )
            refreshUserInterface()
            return true
        ),

        fn hidePanel = (
            if (isDisposed) do return false
            if (panelIsOpen()) do (
                try (
                    local hideGeometry = capturePanelGeometry panelForm
                    hiddenPanelPosition = hideGeometry[1]
                    hiddenPanelSize = hideGeometry[2]
                    persistPanelGeometry hiddenPanelPosition hiddenPanelSize
                    if (not (showRestoreBubble())) do (
                        addActivity "error" "Could not create the restore mini-panel; the MCP Server panel was shown again"
                        return false
                    )
                    detachPanelFormEvents panelForm
                    suppressPanelShutdown = true
                    destroyDialog statusDialog
                    suppressPanelShutdown = false
                    panelForm = undefined
                    if (panelIsOpen()) do throw "The native MCP Server rollout did not close"
                    addActivity "info" "Panel hidden; use the lower-left Expand MCP Server mini-panel to restore it"
                ) catch (
                    suppressPanelShutdown = false
                    disposeRestoreBubble()
                    try (if (panelIsOpen()) do attachPanelFormClosing()) catch ()
                    addActivity "error" ("Could not hide panel: " + (getCurrentException() as string))
                    return false
                )
            )
            return true
        ),

        fn closeForLifecycle reason: "Stopped" = (
            if (isDisposed) do return true
            stopPollTimer()
            addActivity "warning" (reason + ": disconnecting Max and starting the detached single-Max shutdown check")
            connectionState = #stopped
            refreshUserInterface()
            if (panelIsOpen()) then (
                destroyDialog statusDialog
            ) else (
                handlePanelFormClosing panelForm undefined
            )
            return true
        ),

        fn minimizePanel = (
            if (isDisposed) do return false
            if (not (showPanel())) do return false
            try (
                windows.sendMessage statusDialog.hwnd 0x0112 0xF020 0
                return true
            ) catch (
                return false
            )
        ),

        fn restorePanel = (
            if (isDisposed) do return false
            if (not (showPanel())) do return false
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
            for hierarchyDepth in 1 to 64 while (uiHandleText currentWindowHandle) != "0" do (
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
            local eventMessage = if (wireFields.count >= 3) then decodeWireField(wireFields[3]) else ""
            case eventName of (
                "connected": (
                    hasConnectedThisSession = true
                    connectionState = #connected
                    connectionError = ""
                    addActivity "success" ("Connected to " + hostAddress + ":" + (hostPort as string))
                )
                "server_ready": addActivity "info" "Healthy Max Ultra MCP server already running"
                "legacy_server": addActivity "warning" "Compatible legacy Max Ultra MCP server detected; attached without terminating its process"
                "port_changed": (
                    local portChangeFields = filterString eventMessage "|"
                    if (portChangeFields.count >= 1) do (
                        try (hostPort = portChangeFields[1] as integer) catch ()
                    )
                    local portChangeReason = if (portChangeFields.count >= 2) then portChangeFields[2] else "the configured endpoint is unavailable"
                    addActivity "warning" ("Using safe fallback port " + (hostPort as string) + " because " + portChangeReason)
                    addActivity "info" ("MCP host setting: MAX_ULTRA_MCP_PORT=" + (hostPort as string))
                )
                "server_launching": (
                    connectionState = #starting
                    addActivity "info" ("Starting local server in a minimized console: " + eventMessage)
                )
                "server_waiting": (
                    connectionState = #starting
                    addActivity "warning" "Another Max instance is starting the local server; waiting"
                )
                "server_started": addActivity "success" "Fresh Max Ultra MCP server is healthy and recorded for detached ownership-verified shutdown"
                "error": (
                    connectionState = #error
                    connectionError = if (eventMessage != "") then eventMessage else "Transport error"
                    addActivity "error" connectionError
                )
                "disconnected": if (not isStopped) do (
                    if (pendingConnectOnly) then (
                        connectionState = #reconnecting
                    ) else (
                        isStopped = true
                        connectionState = #error
                        if (hasConnectedThisSession) then (
                            connectionError = "Server connection ended. Run 01_START_MAX_ULTRA_MCP_FIRST.ms to start it again."
                            addActivity "warning" connectionError
                        ) else if (connectionError == "") do (
                            connectionError = "Initial server connection ended before this Max registered. Run 01_START_MAX_ULTRA_MCP_FIRST.ms to retry."
                            addActivity "error" connectionError
                        )
                    )
                )
                default: ()
            )
            refreshUserInterface()
            return true
        ),
        fn stopTransportState reason: "Stopped" = (
            isStopped = true
            pendingConnectOnly = false
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

        fn workerEncodeEvent workerQueue eventName eventMessage = (
            local encodingClass = dotNetClass "System.Text.Encoding"
            local convertClass = dotNetClass "System.Convert"
            local encodedMessage = if (eventMessage == undefined or eventMessage == "") then "-" else convertClass.ToBase64String (encodingClass.UTF8.GetBytes (eventMessage as string))
            workerQueue.Enqueue ("EVENT\t" + eventName + "\t" + encodedMessage)
            return true
        ),

        fn workerControlRequest workerHost workerPort operationName timeoutMilliseconds requestPayload: "" = (
            local controlReply = MaxUltraMcpControlReply()
            local controlClient = undefined
            local controlStream = undefined
            local controlReader = undefined
            local controlWriter = undefined
            local connectedToEndpoint = false
            try (
                controlClient = dotNetObject "System.Net.Sockets.TcpClient"
                local connectTask = controlClient.ConnectAsync workerHost workerPort
                if (not (connectTask.Wait timeoutMilliseconds)) do throw "Endpoint connect timed out"
                connectedToEndpoint = true
                controlStream = controlClient.GetStream()
                controlStream.ReadTimeout = timeoutMilliseconds
                controlStream.WriteTimeout = timeoutMilliseconds
                local utf8Encoding = dotNetObject "System.Text.UTF8Encoding" false
                controlReader = dotNetObject "System.IO.StreamReader" controlStream utf8Encoding
                controlWriter = dotNetObject "System.IO.StreamWriter" controlStream utf8Encoding
                controlWriter.AutoFlush = true
                local requestLine = "CONTROL\t1\tbootstrap-control\t" + operationName
                if (requestPayload != "") do requestLine += "\t" + encodeWireField(requestPayload)
                controlWriter.WriteLine requestLine
                local responseLine = controlReader.ReadLine()
                if (responseLine == undefined) do throw "Endpoint closed without a control response"
                local responseFields = filterString responseLine "\t"
                if (responseFields.count < 4 or responseFields[1] != "CONTROL_RESPONSE" or responseFields[2] != "bootstrap-control") do throw "Endpoint did not return a Max Ultra MCP control frame"
                local encodingClass = dotNetClass "System.Text.Encoding"
                local convertClass = dotNetClass "System.Convert"
                controlReply.responsePayload = encodingClass.UTF8.GetString (convertClass.FromBase64String responseFields[4])
                if (responseFields[3] == "ok") then (
                    if (operationName == "probe") do (
                        if ((findString controlReply.responsePayload "\"server\":\"max-ultra-mcp\"") == undefined) do throw "Endpoint identity is not Max Ultra MCP"
                    )
                    controlReply.controlState = #verified
                ) else (
                    controlReply.failureMessage = controlReply.responsePayload
                    if (operationName == "probe" and (findString controlReply.responsePayload "Unknown control operation 'probe'") != undefined) then (
                        controlReply.controlState = #legacyCandidate
                    ) else (
                        controlReply.controlState = #occupied
                    )
                )
            ) catch (
                controlReply.failureMessage = getCurrentException() as string
                controlReply.controlState = if (connectedToEndpoint) then #occupied else #closed
            )
            try (if (controlWriter != undefined) do controlWriter.Close()) catch ()
            try (if (controlReader != undefined) do controlReader.Close()) catch ()
            try (if (controlStream != undefined) do controlStream.Close()) catch ()
            try (if (controlClient != undefined) do controlClient.Close()) catch ()
            return controlReply
        ),

        fn workerProbeEndpoint workerHost workerPort timeoutMilliseconds = (
            local probeReply = workerControlRequest workerHost workerPort "probe" timeoutMilliseconds
            if (probeReply.controlState == #verified) do (
                probeReply.controlState = if ((findString probeReply.responsePayload "\"healthy\":true") != undefined) then #healthy else #occupied
            )
            if (probeReply.controlState == #legacyCandidate) do (
                local inventoryReply = workerControlRequest workerHost workerPort "list" timeoutMilliseconds
                local hasLegacyInventory = inventoryReply.controlState == #verified and (findString inventoryReply.responsePayload "\"instances\"") != undefined and (findString inventoryReply.responsePayload "\"selectedInstanceId\"") != undefined
                if (hasLegacyInventory) then (
                    probeReply.controlState = #legacy
                    probeReply.responsePayload = inventoryReply.responsePayload
                    probeReply.failureMessage = ""
                ) else (
                    probeReply.controlState = #occupied
                    probeReply.failureMessage = "Endpoint rejected identity probe and did not provide a compatible Max Ultra MCP inventory"
                )
            )
            return probeReply
        ),

        fn workerHostIsLoopback workerHost = (
            local normalizedHost = toLower (workerHost as string)
            return normalizedHost == "127.0.0.1" or normalizedHost == "localhost" or normalizedHost == "::1"
        ),

        fn workerFindFreeFallbackPort workerHost configuredPort timeoutMilliseconds = (
            for portOffset in 1 to 10 do (
                local candidatePort = configuredPort + portOffset
                if (candidatePort <= 65535) do (
                    local candidateReply = workerProbeEndpoint workerHost candidatePort timeoutMilliseconds
                    if (candidateReply.controlState == #closed) do return candidatePort
                )
            )
            return 0
        ),

        fn workerLaunchServer workerLauncherPath workerWorkingDirectory workerPort workerOwnershipDirectory workerOwnerToken workerMaxPid = (
            if (workerLauncherPath == undefined or workerLauncherPath == "") do throw "scripts\\start-server.bat was not found below the project root; set MAX_ULTRA_MCP_ROOT if the first-step script was copied"
            local ownershipFilePath = workerOwnershipDirectory + "max-ultra-mcp-owned-" + (workerPort as string) + ".json"
            local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
            startInfo.FileName = "cmd.exe"
            startInfo.Arguments = "/d /c \"\"" + workerLauncherPath + "\" --no-pause --port " + (workerPort as string) + " --owner-file \"" + ownershipFilePath + "\" --owner-token \"" + workerOwnerToken + "\" --owner-max-pid " + (workerMaxPid as string) + "\""
            startInfo.WorkingDirectory = workerWorkingDirectory
            startInfo.UseShellExecute = true
            startInfo.CreateNoWindow = false
            startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Minimized
            local serverProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
            if (serverProcess == undefined) do throw "Windows did not start the Max Ultra MCP launcher"
            serverProcess.Dispose()
            return true
        ),

        fn transportDoWork workerSender eventArgs = (
            local workerArguments = eventArgs.Argument
            local workerHost = workerArguments.Item[0]
            local workerPort = workerArguments.Item[1]
            local workerInboundQueue = workerArguments.Item[2]
            local workerOutboundQueue = workerArguments.Item[3]
            local workerLauncherPath = workerArguments.Item[4]
            local workerWorkingDirectory = workerArguments.Item[5]
            local workerMutexName = workerArguments.Item[6]
            local workerAllowServerLaunch = workerArguments.Item[7]
            local workerOwnershipDirectory = workerArguments.Item[8]
            local workerOwnerToken = workerArguments.Item[9]
            local workerMaxPid = workerArguments.Item[10]
            local retryDelays = #(150, 250, 500, 750, 1000, 1500, 2000)
            local probeTimeoutMilliseconds = 500
            local lifecycleMutex = undefined
            local ownsLifecycleMutex = false
            local launchedServer = false
            local workerClient = undefined
            local workerStream = undefined
            local workerReader = undefined
            local workerWriter = undefined

            try (
                local probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                local needsFallbackPort = probeReply.controlState == #occupied
                local fallbackReason = ""

                if (needsFallbackPort) do (
                    if (not workerHostIsLoopback workerHost) do throw "Automatic fallback-port selection is allowed only for a configured loopback endpoint"
                    lifecycleMutex = dotNetObject "System.Threading.Mutex" false workerMutexName
                    try (ownsLifecycleMutex = lifecycleMutex.WaitOne 3000 false) catch (ownsLifecycleMutex = false)
                    if (not ownsLifecycleMutex) do throw "Another Max Ultra MCP lifecycle operation is still running; retry after its bounded startup completes"
                    probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                    needsFallbackPort = probeReply.controlState == #occupied
                )

                if (needsFallbackPort) do (
                    fallbackReason = if (probeReply.controlState == #legacy) then "a compatible legacy server cannot perform verified self-restart" else "the configured endpoint is occupied by an unverified service"
                    local fallbackPort = workerFindFreeFallbackPort workerHost workerPort probeTimeoutMilliseconds
                    if (fallbackPort == 0) do throw ("No free fallback port was found in the next 10 loopback ports. Set MAX_ULTRA_MCP_PORT to a known free port and run the first-step file again")
                    workerPort = fallbackPort
                    workerEncodeEvent workerInboundQueue "port_changed" ((workerPort as string) + "|" + fallbackReason)
                    probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                )

                local serverUsable = probeReply.controlState == #healthy or probeReply.controlState == #legacy
                if (not serverUsable) then (
                    if (not workerAllowServerLaunch) do throw "Server is not running. Run 01_START_MAX_ULTRA_MCP_FIRST.ms to launch it explicitly."
                    if (not workerHostIsLoopback workerHost) do throw "Automatic server launch is allowed only for a configured loopback endpoint"
                    if (not ownsLifecycleMutex) do (
                        lifecycleMutex = dotNetObject "System.Threading.Mutex" false workerMutexName
                        try (ownsLifecycleMutex = lifecycleMutex.WaitOne 3000 false) catch (ownsLifecycleMutex = false)
                    )
                    if (ownsLifecycleMutex) then (
                        probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                        if (probeReply.controlState == #occupied) do throw "The chosen loopback endpoint became occupied by an unverified service; no process was terminated"
                        if (probeReply.controlState == #closed) do (
                            if (workerSender.CancellationPending) do throw "Server startup cancelled"
                            workerEncodeEvent workerInboundQueue "server_launching" (workerLauncherPath + "|automatic minimized console")
                            workerLaunchServer workerLauncherPath workerWorkingDirectory workerPort workerOwnershipDirectory workerOwnerToken workerMaxPid
                            launchedServer = true
                        )
                    ) else (
                        workerEncodeEvent workerInboundQueue "server_waiting" ""
                    )

                    serverUsable = probeReply.controlState == #healthy or probeReply.controlState == #legacy
                    for retryDelay in retryDelays while not serverUsable do (
                        if (workerSender.CancellationPending) do throw "Server startup cancelled"
                        (dotNetClass "System.Threading.Thread").Sleep retryDelay
                        probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                        if (probeReply.controlState == #occupied) do throw "The selected loopback endpoint was taken by an unverified service during startup; no process was terminated"
                        serverUsable = probeReply.controlState == #healthy or probeReply.controlState == #legacy
                    )
                    if (not serverUsable) do throw "Max Ultra MCP server did not become healthy within the bounded startup timeout"
                )

                if (probeReply.controlState == #legacy) then (
                    workerEncodeEvent workerInboundQueue "legacy_server" ""
                ) else if (launchedServer) then (
                    workerEncodeEvent workerInboundQueue "server_started" probeReply.responsePayload
                ) else (
                    workerEncodeEvent workerInboundQueue "server_ready" ""
                )

                if (ownsLifecycleMutex) do (
                    lifecycleMutex.ReleaseMutex()
                    ownsLifecycleMutex = false
                )
                try (if (lifecycleMutex != undefined) do lifecycleMutex.Dispose()) catch ()
                lifecycleMutex = undefined

                workerClient = dotNetObject "System.Net.Sockets.TcpClient"
                workerClient.Connect workerHost workerPort
                workerStream = workerClient.GetStream()
                local utf8Encoding = dotNetObject "System.Text.UTF8Encoding" false
                workerReader = dotNetObject "System.IO.StreamReader" workerStream utf8Encoding
                workerWriter = dotNetObject "System.IO.StreamWriter" workerStream utf8Encoding
                workerWriter.AutoFlush = true
                workerInboundQueue.Enqueue "EVENT\tconnected\t-"
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
                workerEncodeEvent workerInboundQueue "error" (getCurrentException() as string)
            )
            try (if (workerWriter != undefined) do workerWriter.Close()) catch ()
            try (if (workerReader != undefined) do workerReader.Close()) catch ()
            try (if (workerStream != undefined) do workerStream.Close()) catch ()
            try (if (workerClient != undefined) do workerClient.Close()) catch ()
            if (ownsLifecycleMutex) do try (lifecycleMutex.ReleaseMutex()) catch ()
            try (if (lifecycleMutex != undefined) do lifecycleMutex.Dispose()) catch ()
            workerInboundQueue.Enqueue "EVENT\tdisconnected\t-"
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
            local guidClass = dotNetClass "System.Guid"
            local ownerGuid = guidClass.NewGuid()
            serverOwnerToken = ownerGuid.ToString()
            configureEndpointAndLauncher()
            return true
        ),

        fn buildHelloLine = (
            local versionInfo = maxVersion()
            local helloLine = "HELLO\t1\t" + encodeWireField(instanceId) + "\t" + (processId as string) + "\t"
            helloLine += encodeWireField(currentMaxYear()) + "\t" + encodeWireField(versionInfo as string) + "\t" + encodeWireField(processStartedAt)
            return helloLine
        ),

        fn startTransport allowServerLaunch: true = (
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
            workerArguments.Add serverLauncherPath
            workerArguments.Add serverWorkingDirectory
            workerArguments.Add lifecycleMutexName
            workerArguments.Add allowServerLaunch
            workerArguments.Add serverOwnershipDirectory
            workerArguments.Add serverOwnerToken
            workerArguments.Add processId
            transportWorkerArguments = workerArguments
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

        fn disposeForReload = (
            if (isDisposed) do (
                stopPollTimer()
                return true
            )
            isDisposed = true
            isStopped = true
            pendingConnectOnly = false
            stopPollTimer()
            disposeSettingsDialog()
            disposeRestoreBubble()
            try (if (transportWorker != undefined and transportWorker.IsBusy) do transportWorker.CancelAsync()) catch ()
            try (if (transportWorker != undefined) do dotNet.removeEventHandler transportWorker "DoWork" transportDoWork) catch ()
            pendingRequestLines = #()
            cancelledRequestIds = #()
            try (
                if (panelIsOpen()) do (
                    suppressPanelShutdown = true
                    if (panelForm != undefined) then panelForm.Close() else destroyDialog statusDialog
                    suppressPanelShutdown = false
                )
            ) catch (
                suppressPanelShutdown = false
            )
            detachPanelFormEvents panelForm
            panelForm = undefined
            transportWorker = undefined
            transportWorkerArguments = undefined
            try (callbacks.removeScripts id: maxShutdownCallbackId) catch ()
            return true
        ),

        fn registerMaxShutdownCallback = (
            try (
                callbacks.removeScripts id: maxShutdownCallbackId
                local callbackScript = "try (if MaxUltraMcpActiveClient != undefined do MaxUltraMcpActiveClient.closeForLifecycle reason:\"3ds Max is exiting\") catch (format \"[3DGROUND | Max Ultra MCP] MAX EXIT ERROR | %\\n\" (getCurrentException() as string))"
                callbacks.addScript #preSystemShutdown callbackScript id: maxShutdownCallbackId persistent: false
                return true
            ) catch (
                addActivity "error" ("Could not register Max shutdown cleanup: " + (getCurrentException() as string))
                return false
            )
        ),

        fn reconnectBridge = (
            initializeIdentity()
            isStopped = false
            pendingConnectOnly = true
            connectionState = #reconnecting
            connectionError = ""
            try (
                if (transportWorker != undefined and transportWorker.IsBusy) then (
                    transportWorker.CancelAsync()
                ) else (
                    pendingConnectOnly = false
                    startTransport allowServerLaunch: false
                )
            ) catch (
                pendingConnectOnly = false
                connectionState = #error
                connectionError = getCurrentException() as string
            )
            addActivity "info" "Connect-only retry requested; a stopped server will not be launched"
            refreshUserInterface()
            return true
        ),

        fn handleTimerTick timerSender eventArgs = (
            if (isDisposed or pollTimer == undefined or timerSender != pollTimer) do return true
            try (
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
                if (pendingConnectOnly and not isStopped and (transportWorker == undefined or not transportWorker.IsBusy)) do (
                    pendingConnectOnly = false
                    startTransport allowServerLaunch: false
                )
                if (mod tickCount 4 == 0) do refreshUserInterface()
            ) catch (
                local timerFailure = getCurrentException() as string
                isStopped = true
                pendingConnectOnly = false
                connectionState = #error
                connectionError = timerFailure
                stopPollTimer()
                try (if (transportWorker != undefined and transportWorker.IsBusy) do transportWorker.CancelAsync()) catch ()
                try (format "[3DGROUND | Max Ultra MCP] TIMER STOPPED AFTER CALLBACK ERROR | %\n" timerFailure) catch ()
            )
            return true
        ),

        fn startBridge = (
            initializeIdentity()
            isDisposed = false
            registerMaxShutdownCallback()
            if (not isStopped and transportWorker != undefined and transportWorker.IsBusy) do return true
            isStopped = false
            pendingConnectOnly = false
            hasConnectedThisSession = false
            shutdownHelperStarted = false
            connectionState = #starting
            connectionError = ""
            showPanel()
            addActivity "info" "First-step file started: ensuring local server is healthy"
            if (serverLauncherPath == "") do addActivity "warning" "scripts\\start-server.bat not found below this file; MAX_ULTRA_MCP_ROOT fallback will be required if launch is needed"
            startTransport allowServerLaunch: true
            try (
                pollTimer = dotNetObject "System.Windows.Forms.Timer"
                pollTimer.Interval = 250
                dotNet.addEventHandler pollTimer "Tick" handleTimerTick
                pollTimer.Start()
            ) catch (
                local timerStartFailure = getCurrentException() as string
                isDisposed = true
                isStopped = true
                stopPollTimer()
                try (if (transportWorker != undefined and transportWorker.IsBusy) do transportWorker.CancelAsync()) catch ()
                try (format "[3DGROUND | Max Ultra MCP] TIMER START ERROR | %\n" timerStartFailure) catch ()
                return false
            )
            return true
        )
    )

    bridgeClient = MaxUltraMcpBridgeClient statusDialog: MaxUltraMcpStatusDialog settingsDialog: MaxUltraMcpSettingsDialog
    MaxUltraMcpActiveClient = bridgeClient
    bridgeClient.startBridge()
    bridgeClient
)
