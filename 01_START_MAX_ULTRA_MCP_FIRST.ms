-- FIRST STEP: Run this file in 3ds Max to start Max Ultra MCP and connect/reconnect this Max.
-- Endpoint probing, lifecycle work, and retry waits run off the Max UI thread.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl

global MaxUltraMcpActiveClient

(
    local bridgeClient
    local restartServerForReload = MaxUltraMcpActiveClient != undefined
    local stagedUpdateStatus = ""
    local bootstrapRestartedAfterUpdate = false
    local updateStateDirectory = (getDir #userScripts) + @"\MaxUltraMCP\"
    local updateStateFilePath = updateStateDirectory + "panel-ui.ini"
    local pendingPackagePath = ""
    try (
        if (doesFileExist updateStateFilePath) do (
            stagedUpdateStatus = getINISetting updateStateFilePath "updates" "lastStatus"
            setINISetting updateStateFilePath "updates" "lastStatus" ""
            pendingPackagePath = getINISetting updateStateFilePath "updates" "pendingPackage"
        )
    ) catch (
        stagedUpdateStatus = ""
        pendingPackagePath = ""
    )

    if (pendingPackagePath != "") do (
        local pendingPackageIsValid = false
        try (
            local pathClass = dotNetClass "System.IO.Path"
            local comparisonClass = dotNetClass "System.StringComparison"
            local normalizedPackagePath = pathClass.GetFullPath pendingPackagePath
            local normalizedUpdateRoot = pathClass.GetFullPath (updateStateDirectory + @"updates\")
            pendingPackageIsValid = normalizedPackagePath.StartsWith normalizedUpdateRoot comparisonClass.OrdinalIgnoreCase
            pendingPackageIsValid = pendingPackageIsValid and doesFileExist normalizedPackagePath
            pendingPackageIsValid = pendingPackageIsValid and (toLower (getFilenameType normalizedPackagePath)) == ".mzp"
            pendingPackageIsValid = pendingPackageIsValid and matchPattern (getFilenameFile normalizedPackagePath) pattern: "max-ultra-mcp@*@c6977570-25a6-41b0-b9bb-b3be8101123c" ignoreCase: true
            pendingPackagePath = normalizedPackagePath
        ) catch (
            pendingPackageIsValid = false
        )

        if (not pendingPackageIsValid) then (
            try (setINISetting updateStateFilePath "updates" "pendingPackage" "") catch ()
            stagedUpdateStatus = "The staged update package was rejected by local path validation"
        ) else (
            if (MaxUltraMcpActiveClient != undefined) do (
                try (MaxUltraMcpActiveClient.disposeForReload()) catch ()
                MaxUltraMcpActiveClient = undefined
            )
            try (
                local restartBootstrapPath = getSourceFileName()
                if (restartBootstrapPath == undefined or restartBootstrapPath == "" or not (doesFileExist restartBootstrapPath)) do throw "The bootstrap file could not be resolved before installation."
                setINISetting updateStateFilePath "updates" "pendingPackage" ""
                fileIn pendingPackagePath quiet: true
                local dateTimeClass = dotNetClass "System.DateTime"
                setINISetting updateStateFilePath "updates" "lastInstallerLaunch" (dateTimeClass.UtcNow.ToString "o")
                setINISetting updateStateFilePath "updates" "lastStatus" "A verified update was installed through MaxPkg and Max Ultra MCP restarted"
                if (not (doesFileExist restartBootstrapPath)) do throw "The updated bootstrap file could not be resolved."
                fileIn restartBootstrapPath quiet: true
                bootstrapRestartedAfterUpdate = true
            ) catch (
                try (setINISetting updateStateFilePath "updates" "pendingPackage" pendingPackagePath) catch ()
                stagedUpdateStatus = "The staged update could not be installed or restarted: " + (getCurrentException() as string)
            )
        )
    )

    if (not bootstrapRestartedAfterUpdate) do (
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

    struct MaxUltraMcpThemeStruct (
        backgroundPoint = [68, 68, 68],
        rolloutPoint = [81, 81, 81],
        textPoint = [225, 225, 225],
        neutralPoint = [96, 96, 96],
        passPoint = [66, 125, 75],
        issuePoint = [145, 58, 58],
        warningPoint = [160, 119, 68],
        bridgePassTextPoint = [112, 210, 125],
        bridgeIssueTextPoint = [238, 126, 126],
        linkPoint = [255, 127, 0],
        footerPoint = [84, 84, 84],
        buttonPoint = [96, 96, 96],
        disabledPoint = [76, 76, 76],
        disabledTextPoint = [140, 140, 140],
        supportPoint = [170, 82, 52],
        outlinePoint = [40, 40, 40],
        backgroundColor = undefined,
        rolloutColor = undefined,
        textColor = undefined,
        neutralColor = undefined,
        passColor = undefined,
        issueColor = undefined,
        warningColor = undefined,
        bridgePassTextColor = undefined,
        bridgeIssueTextColor = undefined,
        footerColor = undefined,
        buttonColor = undefined,
        disabledColor = undefined,
        disabledTextColor = undefined,
        linkColor = undefined,
        supportColor = undefined,
        outlineColor = undefined,

        fn normalizeThemePoint themeValue fallbackPoint = (
            if (themeValue == undefined) do return fallbackPoint
            local convertedPoint = fallbackPoint
            try (convertedPoint = [themeValue.x as float, themeValue.y as float, themeValue.z as float]) catch (
                try (convertedPoint = [themeValue[1] as float, themeValue[2] as float, themeValue[3] as float]) catch ()
            )
            if (convertedPoint.x <= 1.001 and convertedPoint.y <= 1.001 and convertedPoint.z <= 1.001) do convertedPoint *= 255.0
            return [amin #(255.0, amax #(0.0, convertedPoint.x)), amin #(255.0, amax #(0.0, convertedPoint.y)), amin #(255.0, amax #(0.0, convertedPoint.z))]
        ),

        fn getThemePoint colorId fallbackPoint = (
            local rawThemeValue = try (colorMan.getColor colorId) catch (undefined)
            return this.normalizeThemePoint rawThemeValue fallbackPoint
        ),

        fn toDotNetColor pointValue = (
            local drawingColorClass = dotNetClass "System.Drawing.Color"
            return drawingColorClass.FromArgb (pointValue.x as integer) (pointValue.y as integer) (pointValue.z as integer)
        ),

        fn initialize = (
            backgroundPoint = this.getThemePoint #window [68, 68, 68]
            rolloutPoint = this.getThemePoint #rollupTitleFace [81, 81, 81]
            textPoint = this.getThemePoint #text [225, 225, 225]
            neutralPoint = (backgroundPoint * 0.78) + (textPoint * 0.22)
            passPoint = (backgroundPoint * 0.20) + ([54, 132, 66] * 0.80)
            issuePoint = (backgroundPoint * 0.20) + ([164, 52, 52] * 0.80)
            warningPoint = (backgroundPoint * 0.32) + ([184, 132, 62] * 0.68)
            bridgePassTextPoint = [112, 210, 125]
            bridgeIssueTextPoint = [238, 126, 126]
            footerPoint = backgroundPoint
            buttonPoint = (backgroundPoint * 0.74) + (textPoint * 0.26)
            disabledPoint = (backgroundPoint * 0.90) + (textPoint * 0.10)
            disabledTextPoint = (backgroundPoint * 0.48) + (textPoint * 0.52)
            linkPoint = [255, 127, 0]
            supportPoint = (backgroundPoint * 0.18) + ([184, 88, 52] * 0.82)
            outlinePoint = (backgroundPoint * 0.62) + ([20, 20, 20] * 0.38)
            backgroundColor = this.toDotNetColor backgroundPoint
            rolloutColor = this.toDotNetColor rolloutPoint
            textColor = this.toDotNetColor textPoint
            neutralColor = this.toDotNetColor neutralPoint
            passColor = this.toDotNetColor passPoint
            issueColor = this.toDotNetColor issuePoint
            warningColor = this.toDotNetColor warningPoint
            bridgePassTextColor = this.toDotNetColor bridgePassTextPoint
            bridgeIssueTextColor = this.toDotNetColor bridgeIssueTextPoint
            footerColor = this.toDotNetColor footerPoint
            buttonColor = this.toDotNetColor buttonPoint
            disabledColor = this.toDotNetColor disabledPoint
            disabledTextColor = this.toDotNetColor disabledTextPoint
            linkColor = this.toDotNetColor linkPoint
            supportColor = this.toDotNetColor supportPoint
            outlineColor = this.toDotNetColor outlinePoint
            return true
        ),

        fn statusColor statusState = (
            case statusState of (
                #pass: passColor
                #issue: issueColor
                #warning: warningColor
                #support: supportColor
                default: neutralColor
            )
        )
    )

    local MaxUltraMcpTheme = MaxUltraMcpThemeStruct()
    MaxUltraMcpTheme.initialize()

    struct MaxUltraMcpUiKitStruct (
        theme = undefined,

        fn point xValue yValue = dotNetObject "System.Drawing.Point" (xValue as integer) (yValue as integer),
        fn size widthValue heightValue = dotNetObject "System.Drawing.Size" (widthValue as integer) (heightValue as integer),
        fn padding leftValue: 0 topValue: 0 rightValue: 0 bottomValue: 0 = dotNetObject "System.Windows.Forms.Padding" leftValue topValue rightValue bottomValue,
        fn messageFont = (dotNetClass "System.Drawing.SystemFonts").MessageBoxFont,
        fn applyIndependentBoldFont targetControl = (
            if (targetControl == undefined) do return false
            local baseFont = messageFont()
            local controlFont = dotNetObject "System.Drawing.Font" baseFont.FontFamily baseFont.SizeInPoints (dotNetClass "System.Drawing.FontStyle").Bold
            targetControl.Font = controlFont
            -- Keep the control-specific Font rooted for exactly as long as its control.
            targetControl.Tag = controlFont
            return true
        ),

        fn createPngIcon pngFilePath = (
            local iconBitmap = undefined
            local temporaryBitmap = undefined
            try (
                if (pngFilePath == undefined or pngFilePath == "" or not (doesFileExist pngFilePath)) do return undefined
                temporaryBitmap = dotNetObject "System.Drawing.Bitmap" pngFilePath
                iconBitmap = dotNetObject "System.Drawing.Bitmap" temporaryBitmap
                temporaryBitmap.Dispose()
                temporaryBitmap = undefined
                return iconBitmap
            ) catch (
                try (if (temporaryBitmap != undefined) do temporaryBitmap.Dispose()) catch ()
                try (if (iconBitmap != undefined) do iconBitmap.Dispose()) catch ()
                return undefined
            )
        ),

        fn styleButton buttonControl baseColorValue: undefined enabledState: true tabStop: true = (
            local resolvedBaseColor = if (baseColorValue == undefined) then theme.buttonColor else baseColorValue
            local controlPaintClass = dotNetClass "System.Windows.Forms.ControlPaint"
            buttonControl.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").Flat
            buttonControl.FlatAppearance.BorderSize = 0
            buttonControl.UseVisualStyleBackColor = false
            buttonControl.Font = messageFont()
            buttonControl.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
            -- Avoid the GDI+ MeasureString path that can receive an invalidated
            -- custom Font during 3ds Max 2022 garbage collection.
            buttonControl.UseCompatibleTextRendering = false
            buttonControl.AutoEllipsis = true
            buttonControl.Padding = padding()
            buttonControl.TabStop = tabStop
            buttonControl.Enabled = enabledState
            buttonControl.BackColor = if (enabledState) then resolvedBaseColor else theme.disabledColor
            buttonControl.ForeColor = if (enabledState) then theme.textColor else theme.disabledTextColor
            buttonControl.FlatAppearance.MouseOverBackColor = controlPaintClass.Light resolvedBaseColor
            buttonControl.FlatAppearance.MouseDownBackColor = controlPaintClass.Dark resolvedBaseColor
            buttonControl.Cursor = if (enabledState) then (dotNetClass "System.Windows.Forms.Cursors").Hand else (dotNetClass "System.Windows.Forms.Cursors").Default
            return true
        ),

        fn updateButtonState buttonControl isEnabled baseColorValue: undefined = (
            if (buttonControl == undefined) do return false
            local resolvedBaseColor = if (baseColorValue == undefined) then theme.buttonColor else baseColorValue
            buttonControl.Enabled = isEnabled
            buttonControl.BackColor = if (isEnabled) then resolvedBaseColor else theme.disabledColor
            buttonControl.ForeColor = if (isEnabled) then theme.textColor else theme.disabledTextColor
            buttonControl.Cursor = if (isEnabled) then (dotNetClass "System.Windows.Forms.Cursors").Hand else (dotNetClass "System.Windows.Forms.Cursors").Default
            return true
        ),

        fn styleLabel labelControl backgroundValue: undefined = (
            labelControl.BackColor = if (backgroundValue == undefined) then theme.backgroundColor else backgroundValue
            labelControl.ForeColor = theme.textColor
            labelControl.Font = messageFont()
            labelControl.AutoSize = false
            -- Max enables compatible GDI+ text rendering globally. On Max 2022 that
            -- path can call Graphics.MeasureString with an invalidated Font during GC.
            labelControl.UseCompatibleTextRendering = false
            labelControl.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleLeft
            labelControl.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").None
            return true
        ),

        fn inheritParentBackColor targetControl fallbackColor: undefined = (
            if (targetControl == undefined) do return false
            local parentControl = undefined
            local inheritedColor = undefined
            local parentDepth = 0
            local maximumThemeChannelDelta = 32
            try (parentControl = targetControl.Parent) catch ()
            while (parentControl != undefined and inheritedColor == undefined and parentDepth < 8) do (
                try (
                    local candidateColor = parentControl.BackColor
                    if (candidateColor != undefined and not candidateColor.IsEmpty and candidateColor.A > 0) do (
                        local rolloutDelta = amax #((abs ((candidateColor.R as integer) - (theme.rolloutColor.R as integer))), (abs ((candidateColor.G as integer) - (theme.rolloutColor.G as integer))), (abs ((candidateColor.B as integer) - (theme.rolloutColor.B as integer))))
                        local backgroundDelta = amax #((abs ((candidateColor.R as integer) - (theme.backgroundColor.R as integer))), (abs ((candidateColor.G as integer) - (theme.backgroundColor.G as integer))), (abs ((candidateColor.B as integer) - (theme.backgroundColor.B as integer))))
                        if (amin rolloutDelta backgroundDelta) <= maximumThemeChannelDelta do inheritedColor = candidateColor
                    )
                    parentControl = parentControl.Parent
                ) catch (
                    parentControl = undefined
                )
                parentDepth += 1
            )
            if (inheritedColor == undefined) do inheritedColor = if (fallbackColor == undefined) then theme.rolloutColor else fallbackColor
            try (
                targetControl.BackColor = inheritedColor
                return true
            ) catch (
                return false
            )
        ),

        fn styleLink linkControl = (
            styleLabel linkControl backgroundValue: theme.rolloutColor
            inheritParentBackColor linkControl fallbackColor: theme.rolloutColor
            linkControl.LinkColor = theme.linkColor
            linkControl.ActiveLinkColor = (dotNetClass "System.Windows.Forms.ControlPaint").Light theme.linkColor
            linkControl.VisitedLinkColor = theme.linkColor
            linkControl.LinkBehavior = (dotNetClass "System.Windows.Forms.LinkBehavior").HoverUnderline
            linkControl.Cursor = (dotNetClass "System.Windows.Forms.Cursors").Hand
            linkControl.TabStop = true
            return true
        )
    )

    local MaxUltraMcpUiKit = MaxUltraMcpUiKitStruct theme: MaxUltraMcpTheme

    rollout MaxUltraMcpAiStatusDialog "" width: 720 height: 44 (
        dotNetControl btnAiStatus "System.Windows.Forms.Button" pos: [8,7] width: 444 height: 30
        dotNetControl btnRefreshAgents "System.Windows.Forms.Button" pos: [462,7] width: 38 height: 30
        dotNetControl btnHide "System.Windows.Forms.Button" pos: [592,7] width: 120 height: 30

        on MaxUltraMcpAiStatusDialog moved panelPosition do if (bridgeClient != undefined) do bridgeClient.handlePanelMoved panelPosition
        on MaxUltraMcpAiStatusDialog close do (
            enableAccelerators = true
            if (bridgeClient != undefined) do bridgeClient.handlePanelRolloutClosed()
        )
        on btnAiStatus Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.showOnboardingDialog refreshStatus: false
        on btnRefreshAgents Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.refreshAgentIntegrationStatus()
        on btnHide Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.hidePanel()
    )

    rollout MaxUltraMcpServerStatusDialog "" width: 720 height: 36 (
        dotNetControl lblConnectionIndicator "System.Windows.Forms.Label" pos: [8,6] width: 18 height: 24
        dotNetControl lblEndpoint "System.Windows.Forms.Label" pos: [26,6] width: 273 height: 24
        dotNetControl lblContext "System.Windows.Forms.Label" pos: [307,6] width: 405 height: 24
    )

    rollout MaxUltraMcpActivityDialog "" width: 720 height: 484 (
        dotNetControl pnlActivityOutline "System.Windows.Forms.Panel" pos: [0,5] width: 720 height: 433
        dotNetControl rtbActivity "System.Windows.Forms.RichTextBox" pos: [0,0] width: 718 height: 431
        dotNetControl btnReconnect "System.Windows.Forms.Button" pos: [8,446] width: 120 height: 30
        dotNetControl btnStop "System.Windows.Forms.Button" pos: [134,446] width: 120 height: 30
        dotNetControl btnSettings "System.Windows.Forms.Button" pos: [592,446] width: 120 height: 30

        on rtbActivity MouseEnter eventSender eventArgs do (
            enableAccelerators = false
            if (bridgeClient != undefined) do bridgeClient.handleActivityLogMouseEnter()
        )
        on rtbActivity MouseLeave eventSender eventArgs do (
            enableAccelerators = true
            if (bridgeClient != undefined) do bridgeClient.handleActivityLogMouseLeave()
        )
        on rtbActivity GotFocus eventSender eventArgs do enableAccelerators = false
        on rtbActivity LostFocus eventSender eventArgs do enableAccelerators = true
        on rtbActivity VScroll eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.handleActivityLogScrolled()
        on btnReconnect Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.reconnectBridge()
        on btnStop Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.closeForLifecycle reason: "Stop / Exit pressed"
        on btnSettings Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.showSettingsDialog()
    )

    rollout MaxUltraMcpSupportDialog "" width: 720 height: 44 (
        dotNetControl lnkMaxPkg "System.Windows.Forms.LinkLabel" pos: [8,7] width: 90 height: 30
        dotNetControl lnk3DGround "System.Windows.Forms.LinkLabel" pos: [104,7] width: 104 height: 30
        dotNetControl btnDonate "System.Windows.Forms.Button" pos: [592,7] width: 120 height: 30

        on lnkMaxPkg LinkClicked eventSender eventArgs do try (shellLaunch "https://maxpkg.dev/catalog/max-ultra-mcp" "") catch ()
        on lnk3DGround LinkClicked eventSender eventArgs do try (shellLaunch "https://3dground.net" "") catch ()
        on btnDonate Click eventSender eventArgs do try (shellLaunch "https://store.payproglobal.com/checkout?products[1][id]=137366" "") catch ()
    )

    rollout MaxUltraMcpSettingsDialog "Max Ultra MCP Settings" width: 380 height: 516 (
        groupBox grpAutostart "Autostart" pos: [12,10] width: 356 height: 58
        checkbox chkAutostart "Autostart with 3ds Max" pos: [24,34] width: 250 height: 20
        groupBox grpServerConsole "Server console" pos: [12,78] width: 356 height: 58
        checkbox chkShowServerConsole "Show server console when starting" pos: [24,102] width: 300 height: 20
        groupBox grpUpdates "Updates" pos: [12,146] width: 356 height: 94
        checkbox chkAutomaticUpdates "Check and install updates automatically" pos: [24,168] width: 250 height: 20
        dotNetControl btnCheckUpdates "System.Windows.Forms.Button" pos: [276,166] width: 80 height: 24
        dotNetControl lblUpdateStatus "System.Windows.Forms.Label" pos: [24,198] width: 332 height: 24
        groupBox grpAgents "AI client integration" pos: [12,250] width: 356 height: 60
        dotNetControl btnAgentSetup "System.Windows.Forms.Button" pos: [24,272] width: 210 height: 26
        groupBox grpAbout "About" pos: [12,320] width: 356 height: 184
        label lblAboutProduct "3DGROUND - Max Ultra MCP" pos: [24,342] width: 332 height: 18 align: #center
        label lblAboutVersion "Unknown" pos: [24,362] width: 332 height: 18 align: #center
        label lblAboutAuthor "Lukianenko Vasyl" pos: [24,382] width: 332 height: 18 align: #center
        hyperLink lnkAboutWebsite "3dground.net" address: "https://3dground.net" pos: [24,406] width: 332 height: 18 align: #center color: orange hoverColor: orange visitedColor: orange
        hyperLink lnkAboutPackageManager "maxpkg.dev" address: "https://maxpkg.dev" pos: [24,428] width: 332 height: 18 align: #center color: orange hoverColor: orange visitedColor: orange
        dotNetControl btnAboutDonate "System.Windows.Forms.Button" pos: [130,458] width: 120 height: 30

        on MaxUltraMcpSettingsDialog open do if (bridgeClient != undefined) do bridgeClient.refreshSettingsDialog()
        on chkAutostart changed isChecked do if (bridgeClient != undefined) do bridgeClient.handleAutostartSettingChanged isChecked
        on chkShowServerConsole changed isChecked do if (bridgeClient != undefined) do bridgeClient.handleServerConsoleVisibilityChanged isChecked
        on chkAutomaticUpdates changed isChecked do if (bridgeClient != undefined) do bridgeClient.handleAutomaticUpdateSettingChanged isChecked
        on btnCheckUpdates Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.startUpdateCheck automaticCheck: false
        on btnAgentSetup Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.showOnboardingDialog()
        on btnAboutDonate Click eventSender eventArgs do try (shellLaunch "https://store.payproglobal.com/checkout?products[1][id]=137366" "") catch ()
    )
    rollout MaxUltraMcpOnboardingTabsDialog "" width: 540 height: 36 (
        dotNetControl dncPages "System.Windows.Forms.TabControl" pos: [8,2] width: 524 height: 30

        on MaxUltraMcpOnboardingTabsDialog open do if (bridgeClient != undefined) do bridgeClient.configureOnboardingTabsDialog()
        on MaxUltraMcpOnboardingTabsDialog close do if (bridgeClient != undefined) do bridgeClient.handleOnboardingRolloutClosed()
        on dncPages SelectedIndexChanged eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.handleOnboardingTabChanged eventSender.SelectedIndex
    )

    rollout MaxUltraMcpOnboardingSetupDialog "" width: 540 height: 350 (
        label lblOnboardingIntro "Connect this 3ds Max bridge to one or more AI clients." pos: [16,8] width: 508 height: 18
        label lblOnboardingHint "Automatic setup uses official client CLIs and never edits their config files directly." pos: [16,28] width: 508 height: 18

        groupBox grpSupportedAgents "Supported clients" pos: [12,50] width: 516 height: 126
        checkbox chkOpenAI "ChatGPT Desktop / Codex" pos: [28,74] width: 230 height: 20 checked: true
        dotNetControl lblOpenAIStatus "System.Windows.Forms.Label" pos: [48,96] width: 462 height: 18
        checkbox chkClaudeCode "Claude Code" pos: [28,122] width: 230 height: 20 checked: true
        dotNetControl lblClaudeCodeStatus "System.Windows.Forms.Label" pos: [48,144] width: 462 height: 18

        groupBox grpManual "Manual / other STDIO clients" pos: [12,184] width: 516 height: 94
        dotNetControl txtManual "System.Windows.Forms.TextBox" pos: [24,206] width: 492 height: 58

        dotNetControl lblOnboardingOperation "System.Windows.Forms.Label" pos: [16,282] width: 508 height: 20
        dotNetControl btnInstallAgents "System.Windows.Forms.Button" pos: [12,308] width: 152 height: 28
        dotNetControl btnRefreshAgents "System.Windows.Forms.Button" pos: [172,308] width: 112 height: 28
        dotNetControl btnCopyManual "System.Windows.Forms.Button" pos: [292,308] width: 128 height: 28

        on MaxUltraMcpOnboardingSetupDialog open do if (bridgeClient != undefined) do bridgeClient.configureOnboardingSetupDialog()
        on btnInstallAgents Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.installSelectedAgentIntegrations()
        on btnRefreshAgents Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.refreshAgentIntegrationStatus()
        on btnCopyManual Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.copyManualAgentConfiguration()
    )

    rollout MaxUltraMcpOnboardingTestDialog "" width: 540 height: 350 (
        label lblTestIntro "Use this prompt after setup to verify the MCP connection safely." pos: [16,8] width: 508 height: 18
        label lblTestHint "Copy it into the configured AI client. It does not modify the current scene." pos: [16,30] width: 508 height: 18
        groupBox grpTestPrompt "Connection test prompt" pos: [12,54] width: 516 height: 246
        dotNetControl txtTestPrompt "System.Windows.Forms.TextBox" pos: [24,78] width: 492 height: 210
        dotNetControl btnCopyTestPrompt "System.Windows.Forms.Button" pos: [12,308] width: 128 height: 28

        on MaxUltraMcpOnboardingTestDialog open do if (bridgeClient != undefined) do bridgeClient.configureOnboardingTestDialog()
        on btnCopyTestPrompt Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.copyOnboardingTestPrompt()
    )
    struct MaxUltraMcpBridgeClient (
        hostAddress = "127.0.0.1",
        hostPort = 47635,
        instanceId = "",
        processId = 0,
        processStartedAt = "",
        bootstrapFilePath = "",
        productVersion = "Unknown",
        serverLauncherPath = "",
        serverWorkingDirectory = "",
        serverShutdownHelperPath = "",
        controlTokenFilePath = "",
        serverOwnershipDirectory = "",
        serverOwnerToken = "",
        shutdownHelperStarted = false,
        restartExistingServer = false,
        uiStateDirectory = "",
        uiStateFilePath = "",
        lifecycleMutexName = @"Local\3DGround.MaxUltraMCP.ServerLifecycle",
        statusDialog,
        serverStatusDialog,
        activityDialog,
        supportDialog,
        panelFloater,
        settingsDialog,
        onboardingTabsDialog,
        onboardingSetupDialog,
        onboardingTestDialog,
        onboardingFloater,
        onboardingPage = #none,
        transportWorker,
        inboundQueue,
        outboundQueue,
        pollTimer,
        panelForm,
        panelToolTip,
        refreshIconImage,
        donateIconImage,
        hideIconImage,
        settingsIconImage,
        stopIconImage,
        reconnectIconImage,
        hiddenPanelPosition,
        lastNormalPanelPosition,
        restoreBubbleForm,
        restoreBubbleSurface,
        restoreBubbleLabel,
        restoreBubbleButton,
        restoreBubbleDragging = false,
        restoreBubbleDragOffset,
        restoreBubbleCloseAllowed = false,
        settingsRefreshInProgress = false,
        clipboardFeedbackTimer,
        clipboardFeedbackButton,
        clipboardFeedbackDefaultText = "",
        integrationProcess,
        integrationResultFilePath = "",
        integrationAutomaticCheck = false,
        integrationBusy = false,
        integrationAutomaticCheckPending = false,
        integrationAutomaticCheckDueAt,
        integrationOperationStartedAt,
        integrationOperationTimeoutSeconds = 30,
        integrationOperationName = #status,
        integrationLastCheckFailed = false,
        updateProcess,
        updateResultFilePath = "",
        updateBusy = false,
        updateAutomaticCheck = false,
        updateState = #idle,
        updateMessage = "Not checked",
        updateLatestVersion = "",
        suppressOnboardingDismissal = false,
        integrationOpenAIConfigured = false,
        integrationClaudeCodeConfigured = false,
        transportWorkerArguments,
        suppressPanelShutdown = false,
        panelCloseInProgress = false,
        disposeInProgress = false,
        isDisposed = false,
        maxShutdownCallbackId = #MaxUltraMcpLifecycle,
        tickCount = 0,
        connectionState = #stopped,
        connectionError = "",
        isStopped = true,
        pendingConnectOnly = false,
        hasConnectedThisSession = false,
        supportReminderCount = 0,
        supportReminderDueAt,
        firstSupportReminderMinutes = 1,
        secondSupportReminderMinutes = 10,
        finalSupportReminderMinutes = 60,
        maximumSupportReminders = 3,
        supportReminderMessage = "Max Ultra MCP is maintained independently in personal time. Without community support, continued development may not be sustainable. If it helps your work, please use Donate to support it.",
        pendingRequestLines = #(),
        cancelledRequestIds = #(),
        activityEntries = #(),
        maximumActivityEntries = 30,
        activityStatusColumnWidth = 7,
        activityStatusLeadingGap = "  ",
        activityStatusSeparator = "  >  ",
        activityBadgeFont,
        activityBottomPadding = "\r\n\r\n\r\n",
        activityLogDirty = true,
        activityAutoScroll = true,
        activityLogUpdating = false,
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

        fn readIniValueWithoutMutation filePath sectionName keyName = (
            if (filePath == undefined or filePath == "" or not (doesFileExist filePath)) do return ""
            try (
                local fileText = (dotNetClass "System.IO.File").ReadAllText filePath
                local regexClass = dotNetClass "System.Text.RegularExpressions.Regex"
                local escapedSection = regexClass.Escape (sectionName as string)
                local escapedKey = regexClass.Escape (keyName as string)
                local sectionPattern = "(?ims)(?:\\A|\\r?\\n)[ \\t]*\\[" + escapedSection + "\\][ \\t]*\\r?\\n(?<body>.*?)(?=\\r?\\n[ \\t]*\\[|\\z)"
                local sectionMatch = regexClass.Match fileText sectionPattern
                if (not sectionMatch.Success) do return ""
                local keyPattern = "(?im)^[ \\t]*" + escapedKey + "[ \\t]*=[ \\t]*(?<value>[^\\r\\n]*)"
                local keyMatch = regexClass.Match (sectionMatch.Groups.Item["body"].Value as string) keyPattern
                if (not keyMatch.Success) do return ""
                return trimLeft (trimRight (keyMatch.Groups.Item["value"].Value as string))
            ) catch (
                return ""
            )
        ),

        fn loadProductVersion = (
            local resolvedVersion = ""
            if (bootstrapFilePath != undefined and bootstrapFilePath != "") do (
                local packageRoot = ensureSlash (getFilenamePath bootstrapFilePath)
                local manifestFilePath = packageRoot + "manifest.ini"
                local versionFilePath = packageRoot + "version.ini"
                resolvedVersion = readIniValueWithoutMutation manifestFilePath "package" "version"
                if (resolvedVersion == "") do resolvedVersion = readIniValueWithoutMutation versionFilePath "MaxUltraMCP" "Version"
            )
            if (resolvedVersion == undefined or resolvedVersion == "") do resolvedVersion = "Unknown"
            productVersion = resolvedVersion as string
            return productVersion
        ),

        fn productWindowTitle = (
            if (productVersion == "" or productVersion == "Unknown") do return "3DGROUND - Max Ultra MCP"
            return "3DGROUND - Max Ultra MCP " + productVersion
        ),

        fn applyProductVersionToUi = (
            local expectedTitle = productWindowTitle()
            local panelOpen = false
            local settingsOpen = false
            try (panelOpen = panelFloater != undefined and panelFloater.open) catch ()
            try (settingsOpen = settingsDialog != undefined and settingsDialog.open) catch ()
            try (
                if (panelOpen) do (
                    local currentTitle = UIAccessor.GetWindowText panelFloater.hwnd
                    if (currentTitle != expectedTitle) do UIAccessor.SetWindowText panelFloater.hwnd expectedTitle
                )
            ) catch ()
            try (if (settingsOpen) do settingsDialog.lblAboutVersion.caption = productVersion) catch ()
            return true
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
            controlTokenFilePath = ""
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
            local configuredTokenFile = environmentClass.GetEnvironmentVariable "MAX_ULTRA_MCP_TOKEN_FILE"
            if (configuredTokenFile != undefined and configuredTokenFile != "") then (
                try (controlTokenFilePath = (dotNetClass "System.IO.Path").GetFullPath configuredTokenFile) catch (controlTokenFilePath = "")
            ) else (
                local legacyTokenFilePath = ""
                if (serverWorkingDirectory != "") do (
                    try (legacyTokenFilePath = (dotNetClass "System.IO.Path").GetFullPath (serverWorkingDirectory + @"..\runtime\state\control-token")) catch (legacyTokenFilePath = "")
                )
                local localAppDataDirectory = environmentClass.GetEnvironmentVariable "LOCALAPPDATA"
                if (localAppDataDirectory != undefined and localAppDataDirectory != "") then (
                    try (controlTokenFilePath = (dotNetClass "System.IO.Path").GetFullPath ((ensureSlash localAppDataDirectory) + @"3DGROUND\MaxUltraMCP\runtime\state\control-token")) catch (controlTokenFilePath = "")
                ) else (
                    controlTokenFilePath = legacyTokenFilePath
                )
                if (controlTokenFilePath != "" and legacyTokenFilePath != "" and controlTokenFilePath != legacyTokenFilePath and doesFileExist legacyTokenFilePath) do (
                    try (
                        (dotNetClass "System.IO.Directory").CreateDirectory (getFilenamePath controlTokenFilePath)
                        (dotNetClass "System.IO.File").Copy legacyTokenFilePath controlTokenFilePath true
                    ) catch ()
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

        fn currentSceneUiName = (
            if (maxFileName == undefined or maxFileName == "") do return "Untitled"
            return maxFileName
        ),

        fn safeSingleLineUiText sourceContent fallbackContent = (
            local safeContent = if (sourceContent == undefined or sourceContent == "") then fallbackContent else (sourceContent as string)
            safeContent = substituteString safeContent "\r" " "
            safeContent = substituteString safeContent "\n" " "
            safeContent = substituteString safeContent "\t" " "
            return safeContent
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
            local normalizedPoint = MaxUltraMcpTheme.getThemePoint themeColorKey [fallbackRed, fallbackGreen, fallbackBlue]
            return MaxUltraMcpTheme.toDotNetColor normalizedPoint
        ),

        fn lighterThemeSurface = (
            local colorClass = dotNetClass "System.Drawing.Color"
            local themeBackground = MaxUltraMcpTheme.backgroundColor
            local surfaceRed = themeBackground.R + (((255 - themeBackground.R) * 0.08) as integer)
            local surfaceGreen = themeBackground.G + (((255 - themeBackground.G) * 0.08) as integer)
            local surfaceBlue = themeBackground.B + (((255 - themeBackground.B) * 0.08) as integer)
            return colorClass.FromArgb surfaceRed surfaceGreen surfaceBlue
        ),
        fn themeIsDark = (
            local themeBackground = MaxUltraMcpTheme.backgroundColor
            local averageChannel = (themeBackground.R + themeBackground.G + themeBackground.B) / 3
            return averageChannel < 128
        ),

        fn connectionStatusState = (
            if (connectionState == #connected) do return #pass
            if (connectionState == #connecting or connectionState == #starting or connectionState == #restarting or connectionState == #reconnecting) do return #warning
            if (connectionState == #error or connectionState == #disconnected or connectionState == #stopped) do return #issue
            return #neutral
        ),

        fn statusTextColor = (
            return MaxUltraMcpTheme.statusColor (connectionStatusState())
        ),

        fn bridgeStatusTextColor = (
            case (connectionStatusState()) of (
                #pass: MaxUltraMcpTheme.bridgePassTextColor
                #issue: MaxUltraMcpTheme.bridgeIssueTextColor
                default: statusTextColor()
            )
        ),

        fn panelIsOpen = (
            if (panelFloater == undefined) do return false
            try (
                return panelFloater.open
            ) catch (
                return false
            )
        ),

        fn panelIsVisible = (
            if (not panelIsOpen()) do return false
            try (return panelFloater.visible) catch (return false)
        ),

        fn activityText = (
            local outputText = ""
            for activityEntry in activityEntries do (
                if (outputText != "") do outputText += "\r\n"
                outputText += activityEntry
            )
            return outputText
        ),

        fn activityDisplayEntryText activityEntry = (
            local normalizedEntry = activityEntry as string
            local statusStart = findString normalizedEntry "["
            local statusEnd = findString normalizedEntry "]"
            if (statusStart == undefined or statusEnd == undefined or statusEnd <= statusStart) do return normalizedEntry
            local suffixText = if (statusEnd < normalizedEntry.count) then (substring normalizedEntry (statusEnd + 1) -1) else ""
            if (suffixText.count >= activityStatusSeparator.count and (substring suffixText 1 activityStatusSeparator.count) == activityStatusSeparator) do return normalizedEntry
            local statusNameLength = statusEnd - statusStart - 1
            local statusName = if (statusNameLength > 0) then (substring normalizedEntry (statusStart + 1) statusNameLength) else ""
            while (statusName.count < activityStatusColumnWidth) do statusName += " "
            local prefixText = if (statusStart > 1) then ((substring normalizedEntry 1 (statusStart - 1)) + activityStatusLeadingGap + "[") else "["
            if (suffixText.count > 0 and (substring suffixText 1 1) == " ") do (
                suffixText = if (suffixText.count > 1) then (substring suffixText 2 -1) else ""
            )
            return prefixText + statusName + "]" + activityStatusSeparator + suffixText
        ),

        fn activityDisplayCoreText = (
            local outputText = ""
            for activityEntry in activityEntries do (
                if (outputText != "") do outputText += "\r\n"
                outputText += activityDisplayEntryText activityEntry
            )
            return outputText
        ),

        fn activityDisplayText = (
            local outputText = activityDisplayCoreText()
            if (outputText == "") do return ""
            return outputText + activityBottomPadding
        ),

        fn activityTextWithoutBottomPadding sourceText = (
            local normalizedText = sourceText as string
            if (normalizedText.count < activityBottomPadding.count) do return normalizedText
            local suffixStart = normalizedText.count - activityBottomPadding.count + 1
            if ((substring normalizedText suffixStart activityBottomPadding.count) != activityBottomPadding) do return normalizedText
            local contentLength = normalizedText.count - activityBottomPadding.count
            if (contentLength <= 0) do return ""
            return substring normalizedText 1 contentLength
        ),

        fn applyActivityLogPadding = (
            if (isDisposed or not panelIsOpen()) do return false
            try (
                local richEditMessageSetMargins = 0x00D3
                local bothHorizontalMargins = 0x0003
                local horizontalPadding = 6
                local packedMargins = horizontalPadding + (horizontalPadding * 65536)
                local logWindowHandle = activityDialog.rtbActivity.Handle.ToInt64()
                windows.sendMessage logWindowHandle richEditMessageSetMargins bothHorizontalMargins packedMargins
                return true
            ) catch (
                return false
            )
        ),

        fn ensureActivityBadgeFont = (
            if (activityBadgeFont != undefined) do return activityBadgeFont
            try (
                local baseFont = MaxUltraMcpUiKit.messageFont()
                local monospaceFamily = (dotNetClass "System.Drawing.FontFamily").GenericMonospace
                activityBadgeFont = dotNetObject "System.Drawing.Font" monospaceFamily baseFont.SizeInPoints (dotNetClass "System.Drawing.FontStyle").Regular
            ) catch (
                activityBadgeFont = undefined
            )
            return activityBadgeFont
        ),

        fn configureActivityLog = (
            if (isDisposed or not panelIsOpen()) do return false
            try (
                activityDialog.pnlActivityOutline.BackColor = lighterThemeSurface()
                activityDialog.pnlActivityOutline.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").None
                if (activityDialog.rtbActivity.Parent != activityDialog.pnlActivityOutline) do activityDialog.pnlActivityOutline.Controls.Add activityDialog.rtbActivity
                activityDialog.rtbActivity.Location = MaxUltraMcpUiKit.point 1 1
                activityDialog.rtbActivity.ReadOnly = true
                activityDialog.rtbActivity.WordWrap = true
                activityDialog.rtbActivity.DetectUrls = false
                activityDialog.rtbActivity.HideSelection = false
                activityDialog.rtbActivity.ScrollBars = (dotNetClass "System.Windows.Forms.RichTextBoxScrollBars").Vertical
                activityDialog.rtbActivity.ForeColor = MaxUltraMcpTheme.textColor
                activityDialog.rtbActivity.BackColor = lighterThemeSurface()
                activityDialog.rtbActivity.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").None
                activityDialog.rtbActivity.AccessibleName = "Max Ultra MCP color-coded activity log"
                activityDialog.rtbActivity.AccessibleDescription = "Recent bridge, setup, request, and support activity"
                activityDialog.rtbActivity.TabStop = true
                activityLogDirty = true
                activityAutoScroll = true
                activityDialog.rtbActivity.Font = MaxUltraMcpUiKit.messageFont()
                ensureActivityBadgeFont()
                applyActivityLogPadding()
            ) catch (
            )
            return true
        ),

        fn activityEntryColor activityEntry = (
            local colorClass = dotNetClass "System.Drawing.Color"
            local normalizedEntry = toLower (activityEntry as string)
            local darkTheme = themeIsDark()
            if ((findString normalizedEntry " [error") != undefined) do return if (darkTheme) then (colorClass.FromArgb 255 125 125) else (colorClass.FromArgb 180 0 0)
            if ((findString normalizedEntry " [warning") != undefined) do return if (darkTheme) then (colorClass.FromArgb 255 195 80) else (colorClass.FromArgb 145 105 0)
            if ((findString normalizedEntry " [success") != undefined) do return if (darkTheme) then (colorClass.FromArgb 120 225 150) else (colorClass.FromArgb 0 100 0)
            if ((findString normalizedEntry " [support") != undefined) do return if (darkTheme) then ((dotNetClass "System.Windows.Forms.ControlPaint").Light MaxUltraMcpTheme.supportColor) else ((dotNetClass "System.Windows.Forms.ControlPaint").Dark MaxUltraMcpTheme.supportColor)
            if ((findString normalizedEntry " [system") != undefined) do return if (darkTheme) then (colorClass.FromArgb 190 165 255) else (colorClass.FromArgb 80 55 140)
            if ((findString normalizedEntry " [debug") != undefined) do return if (darkTheme) then (colorClass.FromArgb 190 190 140) else (colorClass.FromArgb 90 90 0)
            return if (darkTheme) then (colorClass.FromArgb 110 205 235) else (colorClass.FromArgb 20 90 145)
        ),

        fn activityEntryBadgeBackgroundColor activityEntry = (
            local entryColor = activityEntryColor activityEntry
            if (themeIsDark()) do return entryColor
            return (dotNetClass "System.Windows.Forms.ControlPaint").Light entryColor 0.65
        ),

        fn activityEntryBadgeTextColor activityEntry = (
            local entryColor = activityEntryColor activityEntry
            return (dotNetClass "System.Windows.Forms.ControlPaint").Dark entryColor 0.55
        ),

        fn activityLogIsNearBottom = (
            if (isDisposed or not panelIsOpen()) do return true
            try (
                if (activityDialog.rtbActivity.SelectionLength > 0) do return false
                if (activityDialog.rtbActivity.TextLength <= 0) do return true
                local lastCharacterIndex = amax 0 (activityDialog.rtbActivity.TextLength - 1)
                local lastCharacterPosition = activityDialog.rtbActivity.GetPositionFromCharIndex lastCharacterIndex
                local lastLineBottom = lastCharacterPosition.Y + activityDialog.rtbActivity.Font.Height
                local bottomTolerance = amax 2 (activityDialog.rtbActivity.Font.Height / 2)
                return lastCharacterPosition.Y >= 0 and lastLineBottom <= (activityDialog.rtbActivity.ClientSize.Height + bottomTolerance)
            ) catch (
                return true
            )
        ),

        fn activityLogFirstVisibleLine = (
            if (isDisposed or not panelIsOpen()) do return 0
            try (
                local logWindowHandle = activityDialog.rtbActivity.Handle.ToInt64()
                local richEditMessageGetFirstVisibleLine = 0x00CE
                return windows.sendMessage logWindowHandle richEditMessageGetFirstVisibleLine 0 0
            ) catch (
                return 0
            )
        ),

        fn restoreActivityLogFirstVisibleLine lineNumber = (
            if (isDisposed or not panelIsOpen()) do return false
            try (
                local logWindowHandle = activityDialog.rtbActivity.Handle.ToInt64()
                local richEditMessageGetFirstVisibleLine = 0x00CE
                local richEditMessageLineScroll = 0x00B6
                local currentFirstVisibleLine = windows.sendMessage logWindowHandle richEditMessageGetFirstVisibleLine 0 0
                windows.sendMessage logWindowHandle richEditMessageLineScroll 0 (lineNumber - currentFirstVisibleLine)
                return true
            ) catch (
                return false
            )
        ),

        fn handleActivityLogMouseEnter = (
            if (isDisposed or not panelIsOpen()) do return false
            try (activityDialog.rtbActivity.Focus()) catch ()
            activityAutoScroll = activityLogIsNearBottom()
            return true
        ),

        fn handleActivityLogMouseLeave = (
            activityAutoScroll = activityLogIsNearBottom()
            return true
        ),

        fn handleActivityLogScrolled = (
            if (activityLogUpdating) do return true
            activityAutoScroll = activityLogIsNearBottom()
            return true
        ),

        fn activityTextStartsWith sourceText prefixText = (
            if (prefixText == "") do return true
            if (sourceText.count < prefixText.count) do return false
            return (substring sourceText 1 prefixText.count) == prefixText
        ),

        fn scrollActivityLogToBottom = (
            if (isDisposed or not panelIsOpen()) do return false
            activityDialog.rtbActivity.SelectionStart = activityDialog.rtbActivity.TextLength
            activityDialog.rtbActivity.SelectionLength = 0
            activityDialog.rtbActivity.ScrollToCaret()
            try (
                local logWindowHandle = activityDialog.rtbActivity.Handle.ToInt64()
                local windowsMessageVerticalScroll = 0x0115
                local scrollBarBottom = 7
                windows.sendMessage logWindowHandle windowsMessageVerticalScroll scrollBarBottom 0
            ) catch (
            )
            return true
        ),

        fn appendColoredActivityText activityEntry = (
            local normalizedActivityEntry = activityDisplayEntryText activityEntry
            local entryColor = activityEntryColor normalizedActivityEntry
            local badgeBackgroundColor = activityEntryBadgeBackgroundColor normalizedActivityEntry
            local badgeTextColor = activityEntryBadgeTextColor normalizedActivityEntry
            local badgeFont = ensureActivityBadgeFont()
            local statusStart = findString normalizedActivityEntry "["
            local statusEnd = findString normalizedActivityEntry "]"
            local hasStatusToken = statusStart != undefined and statusEnd != undefined and statusEnd >= statusStart
            local badgeStart = if (hasStatusToken and statusStart > 1 and (substring normalizedActivityEntry (statusStart - 1) 1) == " ") then (statusStart - 1) else statusStart
            local badgeEnd = if (hasStatusToken and statusEnd < normalizedActivityEntry.count and (substring normalizedActivityEntry (statusEnd + 1) 1) == " ") then (statusEnd + 1) else statusEnd
            local prefixText = if (hasStatusToken and badgeStart > 1) then (substring normalizedActivityEntry 1 (badgeStart - 1)) else if (hasStatusToken) then "" else normalizedActivityEntry
            local statusText = if (hasStatusToken) then (substring normalizedActivityEntry badgeStart (badgeEnd - badgeStart + 1)) else ""
            local suffixText = if (hasStatusToken and badgeEnd < normalizedActivityEntry.count) then (substring normalizedActivityEntry (badgeEnd + 1) -1) else ""
            if (activityDialog.rtbActivity.TextLength > 0) do activityDialog.rtbActivity.AppendText "\r\n"
            activityDialog.rtbActivity.SelectionStart = activityDialog.rtbActivity.TextLength
            activityDialog.rtbActivity.SelectionLength = 0
            activityDialog.rtbActivity.SelectionBackColor = activityDialog.rtbActivity.BackColor
            activityDialog.rtbActivity.SelectionColor = entryColor
            activityDialog.rtbActivity.SelectionFont = activityDialog.rtbActivity.Font
            if (prefixText != "") do activityDialog.rtbActivity.AppendText prefixText
            activityDialog.rtbActivity.SelectionBackColor = badgeBackgroundColor
            activityDialog.rtbActivity.SelectionColor = badgeTextColor
            if (badgeFont != undefined) do activityDialog.rtbActivity.SelectionFont = badgeFont
            if (statusText != "") do activityDialog.rtbActivity.AppendText statusText
            activityDialog.rtbActivity.SelectionBackColor = activityDialog.rtbActivity.BackColor
            activityDialog.rtbActivity.SelectionColor = entryColor
            activityDialog.rtbActivity.SelectionFont = activityDialog.rtbActivity.Font
            if (suffixText != "") do activityDialog.rtbActivity.AppendText suffixText
            activityDialog.rtbActivity.SelectionColor = activityDialog.rtbActivity.ForeColor
            return true
        ),

        fn refreshActivityText = (
            if (isDisposed or not panelIsOpen()) do return false
            try (
                local expectedActivityCoreText = activityDisplayCoreText()
                local expectedActivityText = activityDisplayText()
                local currentActivityText = activityDialog.rtbActivity.Text as string
                if (not activityLogDirty and currentActivityText == expectedActivityText) do return true
                if (currentActivityText == expectedActivityText) then (
                    activityLogDirty = false
                    return true
                )
                activityLogUpdating = true
                local shouldAutoScroll = activityAutoScroll and activityLogIsNearBottom()
                local savedSelectionStart = activityDialog.rtbActivity.SelectionStart
                local savedSelectionLength = activityDialog.rtbActivity.SelectionLength
                local savedFirstVisibleLine = activityLogFirstVisibleLine()
                local removedCharacterCount = 0
                local removedLineCount = 0
                local appendedActivityText = ""
                local changedIncrementally = false
                local currentActivityCoreText = activityTextWithoutBottomPadding currentActivityText
                local appendPrefix = currentActivityCoreText + "\r\n"
                if (currentActivityCoreText != "" and activityTextStartsWith expectedActivityCoreText appendPrefix) then (
                    appendedActivityText = substring expectedActivityCoreText (appendPrefix.count + 1) -1
                    changedIncrementally = appendedActivityText != ""
                ) else if (currentActivityCoreText != "") do (
                    local firstLineBreak = findString currentActivityCoreText "\r\n"
                    if (firstLineBreak != undefined) do (
                        local remainingActivityText = substring currentActivityCoreText (firstLineBreak + 2) -1
                        local rollingPrefix = remainingActivityText + "\r\n"
                        if (activityTextStartsWith expectedActivityCoreText rollingPrefix) do (
                            appendedActivityText = substring expectedActivityCoreText (rollingPrefix.count + 1) -1
                            removedCharacterCount = firstLineBreak + 1
                            removedLineCount = 1
                            changedIncrementally = appendedActivityText != ""
                        )
                    )
                )
                activityDialog.rtbActivity.SuspendLayout()
                if (changedIncrementally) then (
                    local bottomPaddingLength = currentActivityText.count - currentActivityCoreText.count
                    if (bottomPaddingLength > 0) do (
                        activityDialog.rtbActivity.Select currentActivityCoreText.count bottomPaddingLength
                        activityDialog.rtbActivity.SelectedText = ""
                    )
                    if (removedCharacterCount > 0) do (
                        activityDialog.rtbActivity.Select 0 removedCharacterCount
                        activityDialog.rtbActivity.SelectedText = ""
                    )
                    appendColoredActivityText appendedActivityText
                    activityDialog.rtbActivity.AppendText activityBottomPadding
                ) else (
                    activityDialog.rtbActivity.Clear()
                    for activityIndex in 1 to activityEntries.count do (
                        appendColoredActivityText activityEntries[activityIndex]
                    )
                    if (activityEntries.count > 0) do activityDialog.rtbActivity.AppendText activityBottomPadding
                    activityDialog.rtbActivity.SelectionBackColor = activityDialog.rtbActivity.BackColor
                    activityDialog.rtbActivity.SelectionColor = activityDialog.rtbActivity.ForeColor
                )
                activityLogDirty = false
                activityDialog.rtbActivity.ResumeLayout()
                if (shouldAutoScroll) then (
                    scrollActivityLogToBottom()
                    activityAutoScroll = true
                ) else (
                    local adjustedSelectionStart = amax 0 (savedSelectionStart - removedCharacterCount)
                    adjustedSelectionStart = amin adjustedSelectionStart activityDialog.rtbActivity.TextLength
                    local availableSelectionLength = activityDialog.rtbActivity.TextLength - adjustedSelectionStart
                    activityDialog.rtbActivity.Select adjustedSelectionStart (amin savedSelectionLength availableSelectionLength)
                    restoreActivityLogFirstVisibleLine (amax 0 (savedFirstVisibleLine - removedLineCount))
                )
                activityDialog.rtbActivity.Invalidate true
                activityLogUpdating = false
            ) catch (
                try (activityDialog.rtbActivity.ResumeLayout()) catch ()
                try (activityDialog.rtbActivity.Invalidate true) catch ()
                activityLogUpdating = false
            )
            return true
        ),
        fn addActivity activityLevel activityMessage = (
            local timestampText = (dotNetClass "System.DateTime").Now.ToString("HH:mm:ss")
            local singleLineActivityMessage = substituteString (activityMessage as string) "\r" " "
            singleLineActivityMessage = substituteString singleLineActivityMessage "\n" " "
            append activityEntries (timestampText + " [" + activityLevel + "] " + singleLineActivityMessage)
            while (activityEntries.count > maximumActivityEntries) do deleteItem activityEntries 1
            activityLogDirty = true
            refreshActivityText()
            return true
        ),

        fn armSupportReminders = (
            if (supportReminderCount > 0 or supportReminderDueAt != undefined) do return true
            supportReminderDueAt = (dotNetClass "System.DateTime").UtcNow.AddMinutes (firstSupportReminderMinutes as double)
            return true
        ),

        fn pollSupportReminder = (
            if (supportReminderDueAt == undefined or supportReminderCount >= maximumSupportReminders) do return true
            local deadlineReached = false
            try (deadlineReached = ((dotNetClass "System.DateTime").UtcNow.CompareTo supportReminderDueAt) >= 0) catch ()
            if (not deadlineReached) do return true
            addActivity "support" supportReminderMessage
            supportReminderCount += 1
            if (supportReminderCount < maximumSupportReminders) then (
                local nextReminderMinutes = if (supportReminderCount == 1) then secondSupportReminderMinutes else finalSupportReminderMinutes
                supportReminderDueAt = (dotNetClass "System.DateTime").UtcNow.AddMinutes (nextReminderMinutes as double)
            ) else (
                supportReminderDueAt = undefined
            )
            return true
        ),

        fn releasePanelIconImages = (
            try (statusDialog.btnRefreshAgents.Image = undefined) catch ()
            try (statusDialog.btnHide.Image = undefined) catch ()
            try (activityDialog.btnReconnect.Image = undefined) catch ()
            try (activityDialog.btnStop.Image = undefined) catch ()
            try (activityDialog.btnSettings.Image = undefined) catch ()
            try (supportDialog.btnDonate.Image = undefined) catch ()
            try (settingsDialog.btnAboutDonate.Image = undefined) catch ()
            refreshIconImage = undefined
            donateIconImage = undefined
            hideIconImage = undefined
            settingsIconImage = undefined
            stopIconImage = undefined
            reconnectIconImage = undefined
            return true
        ),

        fn uiIconAssetPath iconFileName = (
            if (bootstrapFilePath == undefined or bootstrapFilePath == "") do return ""
            local iconPath = (ensureSlash (getFilenamePath bootstrapFilePath)) + @"assets\icons\" + iconFileName
            if (doesFileExist iconPath) do return iconPath
            return ""
        ),

        fn ensurePanelIconImages = (
            if (refreshIconImage == undefined) do refreshIconImage = MaxUltraMcpUiKit.createPngIcon (uiIconAssetPath "refresh-cw.png")
            if (donateIconImage == undefined) do donateIconImage = MaxUltraMcpUiKit.createPngIcon (uiIconAssetPath "heart.png")
            if (hideIconImage == undefined) do hideIconImage = MaxUltraMcpUiKit.createPngIcon (uiIconAssetPath "panel-top-close.png")
            if (settingsIconImage == undefined) do settingsIconImage = MaxUltraMcpUiKit.createPngIcon (uiIconAssetPath "settings.png")
            if (stopIconImage == undefined) do stopIconImage = MaxUltraMcpUiKit.createPngIcon (uiIconAssetPath "power.png")
            if (reconnectIconImage == undefined) do reconnectIconImage = MaxUltraMcpUiKit.createPngIcon (uiIconAssetPath "plug-zap.png")
            return true
        ),

        fn configureMainPanelControls = (
            if (isDisposed or not panelIsOpen()) do return false
            try (
                MaxUltraMcpTheme.initialize()
                MaxUltraMcpUiKit.styleButton statusDialog.btnAiStatus baseColorValue: MaxUltraMcpTheme.neutralColor
                MaxUltraMcpUiKit.styleButton statusDialog.btnRefreshAgents baseColorValue: (lighterThemeSurface())
                MaxUltraMcpUiKit.styleButton statusDialog.btnHide
                ensurePanelIconImages()
                statusDialog.btnAiStatus.Text = "AI client | Waiting..."
                statusDialog.btnRefreshAgents.Text = if (refreshIconImage == undefined) then ((dotNetClass "System.Char").ConvertFromUtf32 0x21BB) else ""
                statusDialog.btnRefreshAgents.Image = refreshIconImage
                statusDialog.btnRefreshAgents.ImageAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                statusDialog.btnRefreshAgents.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                statusDialog.btnRefreshAgents.UseCompatibleTextRendering = false
                statusDialog.btnRefreshAgents.AccessibleName = "Refresh AI client readiness"
                statusDialog.btnRefreshAgents.AccessibleDescription = "Check ChatGPT, Codex, and Claude Code MCP registration now"
                statusDialog.btnHide.Text = if (hideIconImage == undefined) then "Hide panel" else "  Hide panel"
                statusDialog.btnHide.Image = hideIconImage
                statusDialog.btnHide.ImageAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                statusDialog.btnHide.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                statusDialog.btnHide.TextImageRelation = (dotNetClass "System.Windows.Forms.TextImageRelation").ImageBeforeText
                statusDialog.btnHide.AccessibleName = "Hide Max Ultra MCP panel"
                statusDialog.btnAiStatus.AccessibleName = "AI client readiness and setup"

                MaxUltraMcpUiKit.styleLabel serverStatusDialog.lblConnectionIndicator
                MaxUltraMcpUiKit.styleLabel serverStatusDialog.lblEndpoint
                MaxUltraMcpUiKit.styleLabel serverStatusDialog.lblContext
                MaxUltraMcpUiKit.applyIndependentBoldFont serverStatusDialog.lblEndpoint
                MaxUltraMcpUiKit.inheritParentBackColor serverStatusDialog.lblConnectionIndicator fallbackColor: MaxUltraMcpTheme.rolloutColor
                MaxUltraMcpUiKit.inheritParentBackColor serverStatusDialog.lblEndpoint fallbackColor: MaxUltraMcpTheme.rolloutColor
                MaxUltraMcpUiKit.inheritParentBackColor serverStatusDialog.lblContext fallbackColor: MaxUltraMcpTheme.rolloutColor
                serverStatusDialog.lblConnectionIndicator.Text = (dotNetClass "System.Char").ConvertFromUtf32 0x25CF
                serverStatusDialog.lblConnectionIndicator.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                serverStatusDialog.lblConnectionIndicator.AccessibleName = "Bridge connection indicator"
                serverStatusDialog.lblEndpoint.AutoEllipsis = true
                serverStatusDialog.lblEndpoint.AccessibleName = "Max Ultra MCP endpoint or connection problem"
                serverStatusDialog.lblContext.AutoEllipsis = true
                serverStatusDialog.lblContext.AccessibleName = "3ds Max scene context"

                MaxUltraMcpUiKit.styleButton activityDialog.btnReconnect
                MaxUltraMcpUiKit.styleButton activityDialog.btnStop
                MaxUltraMcpUiKit.styleButton activityDialog.btnSettings
                activityDialog.btnReconnect.Text = if (reconnectIconImage == undefined) then "Reconnect" else "  Reconnect"
                activityDialog.btnReconnect.Image = reconnectIconImage
                activityDialog.btnReconnect.ImageAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                activityDialog.btnReconnect.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                activityDialog.btnReconnect.TextImageRelation = (dotNetClass "System.Windows.Forms.TextImageRelation").ImageBeforeText
                activityDialog.btnReconnect.AccessibleName = "Reconnect to running MCP server"
                activityDialog.btnStop.Text = if (stopIconImage == undefined) then "Stop / Exit" else "  Stop / Exit"
                activityDialog.btnStop.Image = stopIconImage
                activityDialog.btnStop.ImageAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                activityDialog.btnStop.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                activityDialog.btnStop.TextImageRelation = (dotNetClass "System.Windows.Forms.TextImageRelation").ImageBeforeText
                activityDialog.btnStop.AccessibleName = "Stop Max Ultra MCP and close this panel"
                activityDialog.btnSettings.Text = if (settingsIconImage == undefined) then "Settings" else "  Settings"
                activityDialog.btnSettings.Image = settingsIconImage
                activityDialog.btnSettings.ImageAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                activityDialog.btnSettings.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                activityDialog.btnSettings.TextImageRelation = (dotNetClass "System.Windows.Forms.TextImageRelation").ImageBeforeText
                activityDialog.btnSettings.AccessibleName = "Open Max Ultra MCP settings"

                MaxUltraMcpUiKit.styleLink supportDialog.lnkMaxPkg
                MaxUltraMcpUiKit.styleLink supportDialog.lnk3DGround
                MaxUltraMcpUiKit.styleButton supportDialog.btnDonate baseColorValue: MaxUltraMcpTheme.linkColor
                supportDialog.lnkMaxPkg.Text = "maxpkg.dev"
                supportDialog.lnkMaxPkg.AccessibleName = "Open Max Ultra MCP on maxpkg.dev"
                supportDialog.lnk3DGround.Text = "3dground.net"
                supportDialog.lnk3DGround.AccessibleName = "Open 3DGROUND website"
                supportDialog.btnDonate.Text = "  Donate"
                supportDialog.btnDonate.Image = donateIconImage
                supportDialog.btnDonate.ImageAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                supportDialog.btnDonate.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                supportDialog.btnDonate.TextImageRelation = (dotNetClass "System.Windows.Forms.TextImageRelation").ImageBeforeText
                supportDialog.btnDonate.Padding = MaxUltraMcpUiKit.padding leftValue: 10
                supportDialog.btnDonate.AccessibleName = "Donate to support Max Ultra MCP"
                supportDialog.btnDonate.AccessibleDescription = "Open the secure donation checkout in the default browser"

                if (panelToolTip == undefined) do (
                    panelToolTip = dotNetObject "System.Windows.Forms.ToolTip"
                    panelToolTip.AutoPopDelay = 12000
                    panelToolTip.InitialDelay = 350
                    panelToolTip.ReshowDelay = 100
                )
                panelToolTip.SetToolTip statusDialog.btnRefreshAgents "Refresh AI client readiness"
                panelToolTip.SetToolTip statusDialog.btnHide "Hide the panel without stopping the bridge"
                panelToolTip.SetToolTip statusDialog.btnAiStatus "Open AI Client Setup"
                panelToolTip.SetToolTip supportDialog.btnDonate "Support continued independent development"
                configureActivityLog()
                return true
            ) catch (
                format "[3DGROUND | Max Ultra MCP] PANEL STYLE ERROR | %\n" (getCurrentException() as string)
                return false
            )
        ),

        fn defaultPanelPosition = (
            local workingArea = (dotNetClass "System.Windows.Forms.Screen").PrimaryScreen.WorkingArea
            local centeredX = workingArea.Left + (amax 0 ((workingArea.Width - 720) / 2))
            local centeredY = workingArea.Top + (amax 0 ((workingArea.Height - 640) / 2))
            return [centeredX as integer, centeredY as integer]
        ),

        fn normalizePanelPosition panelPosition = (
            if (panelPosition == undefined) do return defaultPanelPosition()
            try (
                local panelX = panelPosition.x as integer
                local panelY = panelPosition.y as integer
                local candidateBounds = dotNetObject "System.Drawing.Rectangle" panelX panelY 720 640
                local targetScreen = (dotNetClass "System.Windows.Forms.Screen").FromRectangle candidateBounds
                if (targetScreen == undefined) do return defaultPanelPosition()
                local workingArea = targetScreen.WorkingArea
                local maximumX = workingArea.Right - 720
                local maximumY = workingArea.Bottom - 640
                local clampedX = amax workingArea.Left (amin maximumX panelX)
                local clampedY = amax workingArea.Top (amin maximumY panelY)
                return [clampedX as integer, clampedY as integer]
            ) catch (
                return defaultPanelPosition()
            )
        ),

        fn loadPanelPosition = (
            local storedPosition = undefined
            if (uiStateFilePath == undefined or uiStateFilePath == "" or not (doesFileExist uiStateFilePath)) do return defaultPanelPosition()
            try (
                local storedX = getINISetting uiStateFilePath "panel" "x"
                local storedY = getINISetting uiStateFilePath "panel" "y"
                if (storedX != "" and storedY != "") do storedPosition = [storedX as integer, storedY as integer]
            ) catch (storedPosition = undefined)
            return normalizePanelPosition storedPosition
        ),

        fn persistPanelPosition panelPosition = (
            if (panelPosition == undefined or uiStateDirectory == undefined or uiStateDirectory == "") do return false
            try (
                local normalizedPosition = normalizePanelPosition panelPosition
                if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
                setINISetting uiStateFilePath "panel" "x" ((normalizedPosition.x as integer) as string)
                setINISetting uiStateFilePath "panel" "y" ((normalizedPosition.y as integer) as string)
                return true
            ) catch (
                return false
            )
        ),

        fn persistPanelHiddenState isHidden = (
            if (uiStateDirectory == undefined or uiStateDirectory == "") do return false
            try (
                if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
                setINISetting uiStateFilePath "panel" "hidden" (if (isHidden) then "true" else "false")
                return true
            ) catch (
                return false
            )
        ),

        fn loadPanelHiddenState = (
            local storedHiddenState = ""
            try (
                if (uiStateFilePath != undefined and uiStateFilePath != "" and doesFileExist uiStateFilePath) do (
                    storedHiddenState = toLower (getINISetting uiStateFilePath "panel" "hidden")
                )
            ) catch (storedHiddenState = "")
            if (storedHiddenState == "true") do return true
            if (storedHiddenState != "false") do persistPanelHiddenState false
            return false
        ),

        fn rememberNormalPanelPosition formSender = (
            if (not panelIsOpen()) do return false
            try (
                local currentPlacement = panelFloater.placementName
                if (currentPlacement != undefined and currentPlacement != #normal) do return false
                local normalWindowState = (dotNetClass "System.Windows.Forms.FormWindowState").Normal
                if (formSender != undefined and formSender.WindowState != normalWindowState) do return false
                lastNormalPanelPosition = normalizePanelPosition panelFloater.pos
                return true
            ) catch (
                return false
            )
        ),

        fn capturePanelPosition formSender = (
            rememberNormalPanelPosition formSender
            if (lastNormalPanelPosition != undefined) do return normalizePanelPosition lastNormalPanelPosition
            try (
                if (formSender != undefined) do (
                    local restoreBounds = formSender.RestoreBounds
                    if (restoreBounds.Width > 0 and restoreBounds.Height > 0) do return normalizePanelPosition [restoreBounds.X as integer, restoreBounds.Y as integer]
                )
            ) catch ()
            return loadPanelPosition()
        ),

        fn handlePanelMoved panelPosition = (
            if (isDisposed or not panelIsOpen()) do return false
            try (
                persistPanelPosition (capturePanelPosition panelForm)
                return true
            ) catch (
                return false
            )
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

        fn persistServerConsoleVisibleSetting isVisible = (
            if (uiStateDirectory == undefined or uiStateDirectory == "") do return false
            try (
                if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
                setINISetting uiStateFilePath "settings" "showServerConsole" (if (isVisible) then "true" else "false")
                return true
            ) catch (
                return false
            )
        ),

        fn loadServerConsoleVisibleSetting = (
            local storedSetting = ""
            try (
                if (uiStateFilePath != undefined and uiStateFilePath != "" and doesFileExist uiStateFilePath) do (
                    storedSetting = toLower (getINISetting uiStateFilePath "settings" "showServerConsole")
                )
            ) catch (storedSetting = "")
            if (storedSetting != "true" and storedSetting != "false") do (
                persistServerConsoleVisibleSetting false
                return false
            )
            return storedSetting == "true"
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

        fn updateHelperFilePath = (
            if (bootstrapFilePath == undefined or bootstrapFilePath == "") do return ""
            local helperPath = (ensureSlash (getFilenamePath bootstrapFilePath)) + @"scripts\update-manager.ps1"
            if (doesFileExist helperPath) do return helperPath
            return ""
        ),

        fn ensureUpdateResultFilePath = (
            if (uiStateDirectory == undefined or uiStateDirectory == "") do return ""
            if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
            local guidClass = dotNetClass "System.Guid"
            local updateGuid = guidClass.NewGuid()
            updateResultFilePath = uiStateDirectory + "update-result-" + updateGuid.ToString() + ".ini"
            return updateResultFilePath
        ),

        fn quoteProcessArgument sourceContent = (
            local quoteCharacter = bit.intAsChar 34
            local argumentContent = sourceContent as string
            if ((findString argumentContent quoteCharacter) != undefined or (findString argumentContent "\r") != undefined or (findString argumentContent "\n") != undefined) do throw "A process argument contains unsupported characters"

            -- Windows command-line parsing consumes a backslash immediately before
            -- a closing quote. Double every trailing backslash so directory paths
            -- remain one complete argument instead of swallowing the next switch.
            local trailingBackslashCount = 0
            local characterIndex = argumentContent.count
            while (characterIndex > 0 and (substring argumentContent characterIndex 1) == "\\") do (
                trailingBackslashCount += 1
                characterIndex -= 1
            )
            if (trailingBackslashCount > 0) do (
                for slashIndex in 1 to trailingBackslashCount do argumentContent += "\\"
            )
            return quoteCharacter + argumentContent + quoteCharacter
        ),

        fn readUpdateValue keyName fallbackValue: "" = (
            if (updateResultFilePath == undefined or updateResultFilePath == "" or not (doesFileExist updateResultFilePath)) do return fallbackValue
            try (
                local storedValue = getINISetting updateResultFilePath "update" keyName
                if (storedValue == undefined or storedValue == "") do return fallbackValue
                return storedValue
            ) catch (return fallbackValue)
        ),

        fn persistAutomaticUpdateSetting isEnabled = (
            if (uiStateDirectory == undefined or uiStateDirectory == "") do return false
            try (
                if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
                setINISetting uiStateFilePath "updates" "automatic" (if (isEnabled) then "true" else "false")
                return true
            ) catch (return false)
        ),

        fn loadAutomaticUpdateSetting = (
            local storedSetting = ""
            try (
                if (uiStateFilePath != undefined and uiStateFilePath != "" and doesFileExist uiStateFilePath) do storedSetting = toLower (getINISetting uiStateFilePath "updates" "automatic")
            ) catch (storedSetting = "")
            if (storedSetting != "true" and storedSetting != "false") do (
                persistAutomaticUpdateSetting true
                return true
            )
            return storedSetting == "true"
        ),

        fn refreshUpdateStatusControl = (
            if (not (settingsDialogIsOpen())) do return false
            try (
                local rolloutBackground = MaxUltraMcpTheme.backgroundColor
                local statusColor = MaxUltraMcpTheme.textColor
                if (updateState == #current or updateState == #ready) do statusColor = MaxUltraMcpTheme.passColor
                if (updateState == #checking) do statusColor = MaxUltraMcpTheme.warningColor
                if (updateState == #error) do statusColor = MaxUltraMcpTheme.issueColor
                settingsDialog.lblUpdateStatus.BackColor = rolloutBackground
                settingsDialog.lblUpdateStatus.ForeColor = statusColor
                settingsDialog.lblUpdateStatus.Text = updateMessage
                MaxUltraMcpUiKit.updateButtonState settingsDialog.btnCheckUpdates (not updateBusy)
                return true
            ) catch (return false)
        ),

        fn startUpdateCheck automaticCheck: false = (
            if (isDisposed or updateBusy) do return false
            local helperPath = updateHelperFilePath()
            local resultPath = ensureUpdateResultFilePath()
            if (helperPath == "" or resultPath == "") do (
                updateState = #error
                updateMessage = "Update helper is missing."
                refreshUpdateStatusControl()
                return false
            )
            try (if (doesFileExist resultPath) do deleteFile resultPath) catch ()
            try (
                local projectRoot = ensureSlash (getFilenamePath bootstrapFilePath)
                local argumentText = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + quoteProcessArgument helperPath + " -Action CheckAndStage -ProjectRoot " + quoteProcessArgument projectRoot + " -ResultFile " + quoteProcessArgument resultPath
                local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
                startInfo.FileName = "powershell.exe"
                startInfo.Arguments = argumentText
                startInfo.WorkingDirectory = projectRoot
                startInfo.UseShellExecute = false
                startInfo.CreateNoWindow = true
                startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
                updateProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
                if (updateProcess == undefined) do throw "Windows did not start the update helper"
                updateBusy = true
                updateAutomaticCheck = automaticCheck
                updateState = #checking
                updateMessage = "Checking for updates..."
                refreshUpdateStatusControl()
                return true
            ) catch (
                updateProcess = undefined
                updateBusy = false
                updateAutomaticCheck = false
                updateState = #error
                updateMessage = "Could not start the update check."
                addActivity "error" ("Could not start update check: " + (getCurrentException() as string))
                refreshUpdateStatusControl()
                return false
            )
        ),

        fn pollUpdateOperation = (
            if (updateProcess == undefined or not updateBusy) do return true
            local hasExited = false
            try (hasExited = updateProcess.HasExited) catch (hasExited = true)
            if (not hasExited) do return true
            local helperExitCode = -1
            try (helperExitCode = updateProcess.ExitCode) catch ()
            try (updateProcess.Dispose()) catch ()
            updateProcess = undefined
            updateBusy = false
            updateAutomaticCheck = false
            local updateResultExists = updateResultFilePath != undefined and updateResultFilePath != "" and doesFileExist updateResultFilePath
            local stateValue = toLower (readUpdateValue "state" fallbackValue: "error")
            updateLatestVersion = readUpdateValue "latestVersion" fallbackValue: ""
            updateMessage = readUpdateValue "message" fallbackValue: (if updateResultExists then "Update check failed." else ("Update helper exited before writing a result (exit code " + (helperExitCode as string) + ")."))
            if (stateValue == "current" and helperExitCode == 0) then (
                updateState = #current
                addActivity "success" ("Update check completed: version " + updateLatestVersion + " is up to date")
            ) else if (stateValue == "ready" and helperExitCode == 0) then (
                local stagedPackagePath = readUpdateValue "packagePath" fallbackValue: ""
                local normalizedPackagePath = ""
                local normalizedUpdatesRoot = ""
                local stringComparisonClass = dotNetClass "System.StringComparison"
                try (
                    normalizedPackagePath = (dotNetClass "System.IO.Path").GetFullPath stagedPackagePath
                    normalizedUpdatesRoot = ensureSlash ((dotNetClass "System.IO.Path").GetFullPath (uiStateDirectory + "updates"))
                ) catch ()
                if (normalizedPackagePath != "" and normalizedUpdatesRoot != "" and normalizedPackagePath.StartsWith normalizedUpdatesRoot stringComparisonClass.OrdinalIgnoreCase and doesFileExist normalizedPackagePath and matchPattern (getFilenameFile normalizedPackagePath) pattern: "max-ultra-mcp@*@c6977570-25a6-41b0-b9bb-b3be8101123c" ignoreCase: true) then (
                    setINISetting uiStateFilePath "updates" "pendingPackage" normalizedPackagePath
                    updateState = #ready
                    updateMessage = "Update " + updateLatestVersion + " is verified. Installing through MaxPkg..."
                    addActivity "success" updateMessage
                    refreshUpdateStatusControl()
                    local restartBootstrapPath = bootstrapFilePath
                    if (restartBootstrapPath == undefined or restartBootstrapPath == "" or not (doesFileExist restartBootstrapPath)) then (
                        updateState = #error
                        updateMessage = "The bootstrap file could not be resolved for the update restart."
                        addActivity "error" updateMessage
                    ) else (
                        try (
                            fileIn restartBootstrapPath quiet: true
                        ) catch (
                            updateState = #error
                            updateMessage = "The verified update could not restart Max Ultra MCP."
                            addActivity "error" (updateMessage + " " + (getCurrentException() as string))
                        )
                    )
                ) else (
                    updateState = #error
                    updateMessage = "The staged package path failed local validation."
                    addActivity "error" updateMessage
                )
            ) else (
                updateState = #error
                if (updateMessage == "") do updateMessage = "Update check failed."
                addActivity "warning" ("Update check failed: " + updateMessage)
            )
            try (if (updateResultFilePath != "" and doesFileExist updateResultFilePath) do deleteFile updateResultFilePath) catch ()
            updateResultFilePath = ""
            refreshUpdateStatusControl()
            return true
        ),

        fn handleAutomaticUpdateSettingChanged isEnabled = (
            if (settingsRefreshInProgress) do return true
            if (persistAutomaticUpdateSetting isEnabled) do (
                if (isEnabled) do startUpdateCheck automaticCheck: false
                return true
            )
            settingsRefreshInProgress = true
            try (if (settingsDialogIsOpen()) do settingsDialog.chkAutomaticUpdates.checked = not isEnabled) catch ()
            settingsRefreshInProgress = false
            messageBox "Could not update the automatic update setting." title: "Max Ultra MCP Settings"
            return false
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
            applyProductVersionToUi()
            try (
                MaxUltraMcpUiKit.styleButton settingsDialog.btnCheckUpdates
                MaxUltraMcpUiKit.styleButton settingsDialog.btnAgentSetup
                MaxUltraMcpUiKit.styleButton settingsDialog.btnAboutDonate baseColorValue: MaxUltraMcpTheme.linkColor
                ensurePanelIconImages()
                settingsDialog.btnCheckUpdates.Text = "Check now"
                settingsDialog.btnAgentSetup.Text = "Open AI client setup..."
                settingsDialog.btnAboutDonate.Text = if (donateIconImage == undefined) then "Donate" else "  Donate"
                settingsDialog.btnAboutDonate.Image = donateIconImage
                settingsDialog.btnAboutDonate.ImageAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                settingsDialog.btnAboutDonate.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter
                settingsDialog.btnAboutDonate.TextImageRelation = (dotNetClass "System.Windows.Forms.TextImageRelation").ImageBeforeText
                settingsDialog.btnCheckUpdates.AccessibleName = "Check for Max Ultra MCP updates"
                settingsDialog.btnAgentSetup.AccessibleName = "Open AI client setup"
                settingsDialog.btnAboutDonate.AccessibleName = "Donate to support Max Ultra MCP"
            ) catch ()
            try (settingsDialog.chkAutostart.checked = loadAutostartSetting()) catch ()
            try (settingsDialog.chkShowServerConsole.checked = loadServerConsoleVisibleSetting()) catch ()
            try (settingsDialog.chkAutomaticUpdates.checked = loadAutomaticUpdateSetting()) catch ()
            refreshUpdateStatusControl()
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

        fn handleServerConsoleVisibilityChanged isVisible = (
            if (settingsRefreshInProgress) do return true
            if (persistServerConsoleVisibleSetting isVisible) do (
                addActivity "info" (if (isVisible) then "Future server launches will use a visible console" else "Future server launches will be hidden")
                return true
            )
            settingsRefreshInProgress = true
            try (if (settingsDialogIsOpen()) do settingsDialog.chkShowServerConsole.checked = not isVisible) catch ()
            settingsRefreshInProgress = false
            messageBox "Could not update the server console visibility setting." title: "Max Ultra MCP Settings"
            return false
        ),

        fn showSettingsDialog = (
            if (isDisposed) do return false
            if (settingsDialogIsOpen()) do return true
            try (
                createDialog settingsDialog width: 380 height: 516 style: #(#style_titlebar, #style_sysmenu)
                return settingsDialogIsOpen()
            ) catch (
                format "[3DGROUND | Max Ultra MCP] SETTINGS ERROR | %\n" (getCurrentException() as string)
                return false
            )
        ),

        fn onboardingDialogIsOpen = (
            if (onboardingFloater == undefined or onboardingTabsDialog == undefined) do return false
            try (return onboardingTabsDialog.open) catch (return false)
        ),

        fn persistOnboardingDismissed isDismissed = (
            if (uiStateDirectory == undefined or uiStateDirectory == "") do return false
            try (
                if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory
                setINISetting uiStateFilePath "onboarding" "dismissed" (if (isDismissed) then "true" else "false")
                return true
            ) catch (return false)
        ),

        fn loadOnboardingDismissed = (
            local storedValue = ""
            try (
                if (uiStateFilePath != undefined and uiStateFilePath != "" and doesFileExist uiStateFilePath) do storedValue = toLower (getINISetting uiStateFilePath "onboarding" "dismissed")
            ) catch (storedValue = "")
            if (storedValue == "true") do return true
            if (storedValue != "false") do persistOnboardingDismissed false
            return false
        ),

        fn integrationHelperFilePath = (
            local helperCandidate = ""
            if (bootstrapFilePath != undefined and bootstrapFilePath != "") do helperCandidate = (ensureSlash (getFilenamePath bootstrapFilePath)) + @"scripts\agent-integration.ps1"
            if (helperCandidate != "" and doesFileExist helperCandidate) do return helperCandidate
            if (serverWorkingDirectory != undefined and serverWorkingDirectory != "") do helperCandidate = serverWorkingDirectory + "agent-integration.ps1"
            if (helperCandidate != "" and doesFileExist helperCandidate) do return helperCandidate
            return ""
        ),

        fn ensureIntegrationResultFilePath = (
            if (integrationResultFilePath != "") do return integrationResultFilePath
            if (uiStateDirectory == undefined or uiStateDirectory == "") do return ""
            try (if (not (doesDirectoryExist uiStateDirectory)) do makeDir uiStateDirectory) catch (return "")
            integrationResultFilePath = uiStateDirectory + "agent-integration-" + (processId as string) + "-" + serverOwnerToken + ".ini"
            return integrationResultFilePath
        ),

        fn readIntegrationValue sectionName keyName fallbackValue: "" = (
            local resultPath = ensureIntegrationResultFilePath()
            if (resultPath == "" or not (doesFileExist resultPath)) do return fallbackValue
            local storedValue = ""
            try (storedValue = getINISetting resultPath sectionName keyName) catch (storedValue = "")
            if (storedValue == "") then fallbackValue else storedValue
        ),

        fn integrationValueIsTrue sectionName keyName = (
            return (toLower (readIntegrationValue sectionName keyName fallbackValue: "false")) == "true"
        ),

        fn integrationEffectiveState sectionName = (
            local stateValue = toLower (readIntegrationValue sectionName "state" fallbackValue: "not_checked")
            local operationState = toLower (readIntegrationValue "operation" "state" fallbackValue: "")
            local runtimeSensitiveStates = #("configured", "not_configured", "restart_required")
            if (operationState == "complete" and not (integrationValueIsTrue "runtime" "ready") and (findItem runtimeSensitiveStates stateValue) > 0) do return "runtime_missing"
            return stateValue
        ),

        fn integrationStateText sectionName = (
            local stateValue = integrationEffectiveState sectionName
            case stateValue of (
                "configured": "Ready - MCP configured"
                "not_configured": "Setup required - client found, MCP not configured"
                "restart_required": "Restart required - reconnect this AI client"
                "cli_missing": "Client not found - install it or use manual setup"
                "runtime_missing": "Runtime missing - portable Node.js is unavailable"
                "install_failed": "Setup failed - refresh status and retry"
                "check_failed": "Check failed - refresh status to retry"
                default: "Not checked"
            )
        ),

        fn integrationStateShortText sectionName = (
            if (integrationBusy) do return "Checking..."
            if (integrationLastCheckFailed) do return "Check failed"
            local stateValue = integrationEffectiveState sectionName
            case stateValue of (
                "configured": "MCP ready"
                "not_configured": "Setup required"
                "restart_required": "Restart required"
                "cli_missing": "Client not found"
                "runtime_missing": "Runtime missing"
                "install_failed": "Setup failed"
                "check_failed": "Check failed"
                default: "Waiting..."
            )
        ),

        fn integrationStateThemeState sectionName = (
            if (integrationBusy) do return #warning
            if (integrationLastCheckFailed) do return #issue
            local stateValue = integrationEffectiveState sectionName
            case stateValue of (
                "configured": #pass
                "not_configured": #warning
                "restart_required": #warning
                "cli_missing": #issue
                "runtime_missing": #issue
                "install_failed": #issue
                "check_failed": #issue
                default: #neutral
            )
        ),

        fn integrationStateColor sectionName = (
            return MaxUltraMcpTheme.statusColor (integrationStateThemeState sectionName)
        ),

        fn refreshAiStatusControls = (
            if (isDisposed or not panelIsOpen()) do return false
            try (
                local openAIStateValue = integrationEffectiveState "openai"
                local claudeStateValue = integrationEffectiveState "claudeCode"
                local readyClientText = ""
                local restartClientText = ""
                if (openAIStateValue == "configured") do readyClientText = "ChatGPT / Codex"
                if (claudeStateValue == "configured") do readyClientText = if (readyClientText == "") then "Claude Code" else readyClientText + " + Claude Code"
                if (openAIStateValue == "restart_required") do restartClientText = "ChatGPT / Codex"
                if (claudeStateValue == "restart_required") do restartClientText = if (restartClientText == "") then "Claude Code" else restartClientText + " + Claude Code"

                local combinedStatusText = "Click to set up AI agent"
                local combinedStatusState = #warning
                if (integrationBusy) then (
                    combinedStatusText = "AI clients | Checking..."
                    combinedStatusState = #warning
                ) else if (readyClientText != "") then (
                    combinedStatusText = readyClientText + " | MCP ready"
                    combinedStatusState = #pass
                ) else if (restartClientText != "") then (
                    combinedStatusText = restartClientText + " | Restart required"
                    combinedStatusState = #warning
                ) else if (integrationLastCheckFailed or openAIStateValue == "check_failed" or claudeStateValue == "check_failed") then (
                    combinedStatusText = "AI status | Check failed"
                    combinedStatusState = #issue
                ) else if (openAIStateValue == "runtime_missing" or claudeStateValue == "runtime_missing") then (
                    combinedStatusText = "AI runtime | Missing"
                    combinedStatusState = #issue
                ) else if (openAIStateValue == "install_failed" or claudeStateValue == "install_failed") then (
                    combinedStatusText = "AI setup | Failed"
                    combinedStatusState = #issue
                ) else if (toLower (readIntegrationValue "operation" "state" fallbackValue: "") == "") then (
                    combinedStatusText = "AI client | Waiting..."
                    combinedStatusState = #neutral
                )

                local combinedStatusColor = MaxUltraMcpTheme.statusColor combinedStatusState
                local combinedStatusDescription = "ChatGPT / Codex: " + (integrationStateText "openai") + " | Claude Code: " + (integrationStateText "claudeCode") + ". Click to open AI Client Setup."
                MaxUltraMcpUiKit.styleButton statusDialog.btnAiStatus baseColorValue: combinedStatusColor
                MaxUltraMcpUiKit.updateButtonState statusDialog.btnRefreshAgents (not integrationBusy)
                statusDialog.btnAiStatus.Text = combinedStatusText
                statusDialog.btnAiStatus.AccessibleDescription = combinedStatusDescription
                if (panelToolTip != undefined) do panelToolTip.SetToolTip statusDialog.btnAiStatus combinedStatusDescription
                return true
            ) catch (
                return false
            )
        ),

        fn manualAgentConfigurationText = (
            local commandValue = readIntegrationValue "runtime" "command" fallbackValue: ""
            local serverValue = readIntegrationValue "runtime" "server" fallbackValue: ((ensureSlash (getFilenamePath bootstrapFilePath)) + @"core\server.js")
            local argumentsValue = readIntegrationValue "runtime" "arguments" fallbackValue: ((quoteProcessArgument serverValue) + " --stdio")
            local environmentValue = readIntegrationValue "runtime" "environment" fallbackValue: "MAX_ULTRA_MCP_TOOL_PROFILE=archviz"
            if (commandValue == "") do commandValue = "<bundled runtime\\win-x64\\node.exe or Node.js 22+>"
            return "Name: max-ultra-mcp\r\nCommand: " + commandValue + "\r\nArguments: " + argumentsValue + "\r\nEnvironment: " + environmentValue
        ),

        fn refreshOnboardingDialog = (
            local mainStatusRefreshed = refreshAiStatusControls()
            if (not (onboardingDialogIsOpen()) or onboardingPage != #setup or not onboardingSetupDialog.open) do return mainStatusRefreshed
            integrationOpenAIConfigured = integrationValueIsTrue "openai" "configured"
            integrationClaudeCodeConfigured = integrationValueIsTrue "claudeCode" "configured"
            local openAIAvailable = integrationValueIsTrue "openai" "cliAvailable"
            local claudeAvailable = integrationValueIsTrue "claudeCode" "cliAvailable"
            try (
                if (integrationBusy) then (
                    local warningColor = MaxUltraMcpTheme.warningColor
                    onboardingSetupDialog.lblOpenAIStatus.Text = "Checking client and MCP registration..."
                    onboardingSetupDialog.lblClaudeCodeStatus.Text = "Checking client and MCP registration..."
                    onboardingSetupDialog.lblOpenAIStatus.ForeColor = warningColor
                    onboardingSetupDialog.lblClaudeCodeStatus.ForeColor = warningColor
                ) else (
                    onboardingSetupDialog.lblOpenAIStatus.Text = integrationStateText "openai"
                    onboardingSetupDialog.lblClaudeCodeStatus.Text = integrationStateText "claudeCode"
                    onboardingSetupDialog.lblOpenAIStatus.ForeColor = integrationStateColor "openai"
                    onboardingSetupDialog.lblClaudeCodeStatus.ForeColor = integrationStateColor "claudeCode"
                )
                onboardingSetupDialog.chkOpenAI.enabled = openAIAvailable and not integrationOpenAIConfigured and not integrationBusy
                onboardingSetupDialog.chkClaudeCode.enabled = claudeAvailable and not integrationClaudeCodeConfigured and not integrationBusy
                onboardingSetupDialog.chkOpenAI.checked = integrationOpenAIConfigured or (openAIAvailable and not integrationBusy)
                onboardingSetupDialog.chkClaudeCode.checked = integrationClaudeCodeConfigured or (claudeAvailable and not integrationBusy)
                MaxUltraMcpUiKit.updateButtonState onboardingSetupDialog.btnInstallAgents (not integrationBusy and ((openAIAvailable and not integrationOpenAIConfigured) or (claudeAvailable and not integrationClaudeCodeConfigured)))
                MaxUltraMcpUiKit.updateButtonState onboardingSetupDialog.btnRefreshAgents (not integrationBusy)
                MaxUltraMcpUiKit.updateButtonState onboardingSetupDialog.btnCopyManual (not integrationBusy)
                onboardingSetupDialog.txtManual.Text = manualAgentConfigurationText()
                onboardingSetupDialog.lblOnboardingOperation.Text = if (integrationBusy) then "Checking installed clients and MCP registrations..." else readIntegrationValue "operation" "message" fallbackValue: ""
            ) catch ()
            return true
        ),

        fn onboardingTestPromptText = (
            return "Use Max Ultra MCP to verify this connection without modifying the open 3ds Max scene.\r\n\r\n1. Call max_list_instances.\r\n2. If more than one instance is connected, ask me which one to select. Otherwise use the only instance.\r\n3. Call max_health and max_scene_summary.\r\n4. Call max_capture_viewport for the active viewport.\r\n5. Inspect the returned image and report the selected 3ds Max version, scene object count, selection count, viewport type, and image dimensions.\r\n\r\nIf a call returns Control authentication failed, tell me to restart or reconnect this AI client so it reloads the MCP host. Do not ask me to restart the 3ds Max bridge for that error.\r\n\r\nDo not run arbitrary MaxScript, change the scene, start a render, or save any file during this test."
        ),

        fn showOnboardingPage pageName = (
            if (not (onboardingDialogIsOpen())) do return false
            local targetPage = if (pageName == #test) then #test else #setup
            if (targetPage == onboardingPage) do return true
            try (
                if (onboardingPage == #setup and onboardingSetupDialog.open) do removeRollout onboardingSetupDialog onboardingFloater
                if (onboardingPage == #test and onboardingTestDialog.open) do removeRollout onboardingTestDialog onboardingFloater
                onboardingPage = targetPage
                if (targetPage == #test) then addRollout onboardingTestDialog onboardingFloater rolledUp: false border: false else addRollout onboardingSetupDialog onboardingFloater rolledUp: false border: false
                return true
            ) catch (
                format "[3DGROUND | Max Ultra MCP] ONBOARDING PAGE ERROR | %\n" (getCurrentException() as string)
                return false
            )
        ),

        fn handleOnboardingTabChanged selectedIndex = (
            if (selectedIndex == 1) then return showOnboardingPage #test else return showOnboardingPage #setup
        ),

        fn configureOnboardingTabsDialog = (
            if (not (onboardingDialogIsOpen())) do return false
            try (
                local tabAppearanceClass = dotNetClass "System.Windows.Forms.TabAppearance"
                local tabSizeModeClass = dotNetClass "System.Windows.Forms.TabSizeMode"
                onboardingTabsDialog.dncPages.TabPages.Clear()
                onboardingTabsDialog.dncPages.Appearance = tabAppearanceClass.Normal
                onboardingTabsDialog.dncPages.SizeMode = tabSizeModeClass.Fixed
                onboardingTabsDialog.dncPages.ItemSize = dotNetObject "System.Drawing.Size" 132 24
                onboardingTabsDialog.dncPages.Multiline = false
                onboardingTabsDialog.dncPages.TabPages.Add (dotNetObject "System.Windows.Forms.TabPage" "Setup")
                onboardingTabsDialog.dncPages.TabPages.Add (dotNetObject "System.Windows.Forms.TabPage" "Test prompt")
                onboardingTabsDialog.dncPages.SelectedIndex = 0
                showOnboardingPage #setup
                return true
            ) catch (
                format "[3DGROUND | Max Ultra MCP] ONBOARDING TABS ERROR | %\n" (getCurrentException() as string)
                return false
            )
        ),

        fn configureOnboardingSetupDialog = (
            if (not (onboardingDialogIsOpen()) or not onboardingSetupDialog.open) do return false
            try (
                local rolloutBackground = MaxUltraMcpTheme.backgroundColor
                local onboardingTextColor = MaxUltraMcpTheme.textColor
                MaxUltraMcpUiKit.styleButton onboardingSetupDialog.btnInstallAgents
                MaxUltraMcpUiKit.styleButton onboardingSetupDialog.btnRefreshAgents
                MaxUltraMcpUiKit.styleButton onboardingSetupDialog.btnCopyManual
                onboardingSetupDialog.btnInstallAgents.Text = "Install selected"
                onboardingSetupDialog.btnRefreshAgents.Text = "Refresh status"
                onboardingSetupDialog.btnCopyManual.Text = "Copy manual setup"
                onboardingSetupDialog.btnInstallAgents.AccessibleName = "Install selected AI client integrations"
                onboardingSetupDialog.btnRefreshAgents.AccessibleName = "Refresh AI client readiness"
                onboardingSetupDialog.btnCopyManual.AccessibleName = "Copy manual STDIO setup"
                onboardingSetupDialog.txtManual.Multiline = true
                onboardingSetupDialog.txtManual.ReadOnly = true
                onboardingSetupDialog.txtManual.WordWrap = false
                onboardingSetupDialog.txtManual.ScrollBars = (dotNetClass "System.Windows.Forms.ScrollBars").Vertical
                onboardingSetupDialog.lblOpenAIStatus.Text = "Not checked"
                onboardingSetupDialog.lblClaudeCodeStatus.Text = "Not checked"
                onboardingSetupDialog.lblOpenAIStatus.BackColor = rolloutBackground
                onboardingSetupDialog.lblClaudeCodeStatus.BackColor = rolloutBackground
                onboardingSetupDialog.lblOnboardingOperation.BackColor = rolloutBackground
                onboardingSetupDialog.lblOnboardingOperation.ForeColor = onboardingTextColor
            ) catch ()
            refreshOnboardingDialog()
            return true
        ),

        fn configureOnboardingTestDialog = (
            if (not (onboardingDialogIsOpen()) or not onboardingTestDialog.open) do return false
            try (
                MaxUltraMcpUiKit.styleButton onboardingTestDialog.btnCopyTestPrompt
                onboardingTestDialog.btnCopyTestPrompt.Text = "Copy test prompt"
                onboardingTestDialog.btnCopyTestPrompt.AccessibleName = "Copy safe AI connection test prompt"
                onboardingTestDialog.txtTestPrompt.Multiline = true
                onboardingTestDialog.txtTestPrompt.ReadOnly = true
                onboardingTestDialog.txtTestPrompt.WordWrap = true
                onboardingTestDialog.txtTestPrompt.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle
                onboardingTestDialog.txtTestPrompt.BackColor = lighterThemeSurface()
                onboardingTestDialog.txtTestPrompt.ForeColor = MaxUltraMcpTheme.textColor
                onboardingTestDialog.txtTestPrompt.ScrollBars = (dotNetClass "System.Windows.Forms.ScrollBars").Vertical
                onboardingTestDialog.txtTestPrompt.Text = onboardingTestPromptText()
                return true
            ) catch (return false)
        ),

        fn startIntegrationOperation actionName installOpenAI: false installClaudeCode: false automaticCheck: false = (
            if (isDisposed or integrationBusy) do return false
            integrationAutomaticCheckPending = false
            integrationAutomaticCheckDueAt = undefined
            local helperPath = integrationHelperFilePath()
            local resultPath = ensureIntegrationResultFilePath()
            if (helperPath == "" or resultPath == "") do (
                integrationLastCheckFailed = true
                addActivity "error" "AI integration helper was not found below the first-step file"
                if (onboardingDialogIsOpen() and onboardingPage == #setup and onboardingSetupDialog.open) do onboardingSetupDialog.lblOnboardingOperation.Text = "Setup helper is missing from this package."
                refreshOnboardingDialog()
                return false
            )
            try (if (doesFileExist resultPath) do deleteFile resultPath) catch ()
            try (
                local profileValue = (dotNetClass "System.Environment").GetEnvironmentVariable "MAX_ULTRA_MCP_TOOL_PROFILE"
                if (profileValue == undefined or findItem #("core", "archviz", "full") (toLower profileValue) == 0) do profileValue = "archviz"
                local actionValue = if (actionName == #install) then "Install" else "Status"
                local argumentText = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + quoteProcessArgument helperPath + " -Action " + actionValue + " -ResultPath " + quoteProcessArgument resultPath + " -Profile " + profileValue
                if (installOpenAI) do argumentText += " -InstallOpenAI"
                if (installClaudeCode) do argumentText += " -InstallClaudeCode"
                local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
                startInfo.FileName = "powershell.exe"
                startInfo.Arguments = argumentText
                startInfo.WorkingDirectory = getFilenamePath helperPath
                startInfo.UseShellExecute = false
                startInfo.CreateNoWindow = true
                startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
                integrationProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
                if (integrationProcess == undefined) do throw "Windows did not start the integration helper"
                integrationAutomaticCheck = automaticCheck
                integrationOperationName = actionName
                integrationOperationTimeoutSeconds = if (actionName == #install) then 90 else 30
                integrationOperationStartedAt = (dotNetClass "System.DateTime").UtcNow
                integrationLastCheckFailed = false
                integrationBusy = true
                refreshOnboardingDialog()
                return true
            ) catch (
                integrationProcess = undefined
                integrationBusy = false
                integrationAutomaticCheck = false
                integrationOperationStartedAt = undefined
                integrationLastCheckFailed = true
                addActivity "error" ("Could not start AI integration setup: " + (getCurrentException() as string))
                refreshOnboardingDialog()
                return false
            )
        ),

        fn refreshAgentIntegrationStatus = (
            integrationAutomaticCheckPending = false
            integrationAutomaticCheckDueAt = undefined
            return startIntegrationOperation #status automaticCheck: false
        ),

        fn installSelectedAgentIntegrations = (
            if (not (onboardingDialogIsOpen())) do return false
            if (readIntegrationValue "operation" "state" fallbackValue: "" == "") do (
                if (not integrationBusy) do refreshAgentIntegrationStatus()
                try (onboardingSetupDialog.lblOnboardingOperation.Text = "Finish the status check before installing.") catch ()
                return false
            )
            local installOpenAI = false
            local installClaudeCode = false
            try (
                installOpenAI = onboardingSetupDialog.chkOpenAI.enabled and onboardingSetupDialog.chkOpenAI.checked
                installClaudeCode = onboardingSetupDialog.chkClaudeCode.enabled and onboardingSetupDialog.chkClaudeCode.checked
            ) catch ()
            if (not installOpenAI and not installClaudeCode) do (
                messageBox "No available client CLI is selected. Use the manual STDIO values for clients without a CLI." title: "Max Ultra MCP - AI Client Setup"
                return false
            )
            addActivity "info" "Installing selected AI client integrations"
            return startIntegrationOperation #install installOpenAI: installOpenAI installClaudeCode: installClaudeCode automaticCheck: false
        ),

        fn resetClipboardFeedback = (
            if (clipboardFeedbackTimer != undefined) do (
                try (clipboardFeedbackTimer.Stop()) catch ()
                try (clipboardFeedbackTimer.Dispose()) catch ()
            )
            try (if (clipboardFeedbackButton != undefined) do clipboardFeedbackButton.text = clipboardFeedbackDefaultText) catch ()
            clipboardFeedbackTimer = undefined
            clipboardFeedbackButton = undefined
            clipboardFeedbackDefaultText = ""
            return true
        ),

        fn handleClipboardFeedbackTick eventSender eventArgs = (
            return resetClipboardFeedback()
        ),

        fn showClipboardCopiedFeedback targetButton defaultButtonText = (
            resetClipboardFeedback()
            if (targetButton == undefined) do return false
            try (
                clipboardFeedbackButton = targetButton
                clipboardFeedbackDefaultText = defaultButtonText
                clipboardFeedbackButton.text = "Copied"
                clipboardFeedbackTimer = dotNetObject "System.Windows.Forms.Timer"
                clipboardFeedbackTimer.Interval = 1600
                dotNet.addEventHandler clipboardFeedbackTimer "Tick" handleClipboardFeedbackTick
                clipboardFeedbackTimer.Start()
                return true
            ) catch (
                resetClipboardFeedback()
                return false
            )
        ),

        fn copyManualAgentConfiguration = (
            try (
                (dotNetClass "System.Windows.Forms.Clipboard").SetText (manualAgentConfigurationText())
                showClipboardCopiedFeedback onboardingSetupDialog.btnCopyManual "Copy manual setup"
                if (onboardingDialogIsOpen() and onboardingPage == #setup and onboardingSetupDialog.open) do onboardingSetupDialog.lblOnboardingOperation.Text = "Manual STDIO settings copied to the clipboard."
                return true
            ) catch (
                messageBox "Could not access the Windows clipboard. Try again after closing another clipboard operation." title: "Max Ultra MCP - AI Client Setup"
                return false
            )
        ),

        fn handleOnboardingRolloutClosed = (
            resetClipboardFeedback()
            onboardingPage = #none
            onboardingFloater = undefined
            if (not suppressOnboardingDismissal) do persistOnboardingDismissed true
            return true
        ),

        fn closeOnboardingDialog = (
            resetClipboardFeedback()
            try (if (onboardingDialogIsOpen()) do closeRolloutFloater onboardingFloater) catch ()
            onboardingPage = #none
            onboardingFloater = undefined
            return true
        ),

        fn disposeOnboardingDialog = (
            resetClipboardFeedback()
            suppressOnboardingDismissal = true
            try (if (onboardingDialogIsOpen()) do closeRolloutFloater onboardingFloater) catch ()
            onboardingPage = #none
            onboardingFloater = undefined
            suppressOnboardingDismissal = false
            return true
        ),

        fn showOnboardingDialog refreshStatus: true = (
            if (isDisposed) do return false
            if (not (onboardingDialogIsOpen())) do (
                try (
                    onboardingPage = #none
                    onboardingFloater = newRolloutFloater "Max Ultra MCP - AI Client Setup" 548 430
                    addRollout onboardingTabsDialog onboardingFloater rolledUp: false border: false
                ) catch (
                    onboardingFloater = undefined
                    onboardingPage = #none
                    format "[3DGROUND | Max Ultra MCP] ONBOARDING ERROR | %\n" (getCurrentException() as string)
                    return false
                )
            )
            if (onboardingPage == #setup) do refreshOnboardingDialog()
            if (refreshStatus and not integrationBusy) do refreshAgentIntegrationStatus()
            return true
        ),

        fn pollIntegrationOperation = (
            if (integrationProcess == undefined or not integrationBusy) do return true
            local hasExited = false
            try (hasExited = integrationProcess.HasExited) catch (hasExited = true)
            if (not hasExited) do (
                local operationTimedOut = false
                try (
                    if (integrationOperationStartedAt != undefined) do (
                        local elapsedTime = (dotNetClass "System.DateTime").UtcNow.Subtract integrationOperationStartedAt
                        operationTimedOut = elapsedTime.TotalSeconds >= integrationOperationTimeoutSeconds
                    )
                ) catch ()
                if (not operationTimedOut) do return true
                try (integrationProcess.Kill()) catch ()
                try (integrationProcess.Dispose()) catch ()
                integrationProcess = undefined
                integrationBusy = false
                integrationAutomaticCheck = false
                integrationOperationStartedAt = undefined
                integrationLastCheckFailed = true
                addActivity "error" ("AI integration " + (if (integrationOperationName == #install) then "setup" else "status check") + " timed out after " + (integrationOperationTimeoutSeconds as string) + " seconds")
                refreshOnboardingDialog()
                return true
            )
            local wasAutomaticCheck = integrationAutomaticCheck
            local helperExitCode = -1
            try (helperExitCode = integrationProcess.ExitCode) catch ()
            try (integrationProcess.Dispose()) catch ()
            integrationProcess = undefined
            integrationBusy = false
            integrationAutomaticCheck = false
            integrationAutomaticCheckPending = false
            integrationAutomaticCheckDueAt = undefined
            integrationOperationStartedAt = undefined
            integrationOpenAIConfigured = integrationValueIsTrue "openai" "configured"
            integrationClaudeCodeConfigured = integrationValueIsTrue "claudeCode" "configured"
            local openAIStateValue = readIntegrationValue "openai" "state" fallbackValue: ""
            local claudeStateValue = readIntegrationValue "claudeCode" "state" fallbackValue: ""
            local conclusiveStates = #("configured", "not_configured", "restart_required", "cli_missing", "runtime_missing")
            local automaticCheckConclusive = (findItem conclusiveStates openAIStateValue) > 0 and (findItem conclusiveStates claudeStateValue) > 0
            integrationLastCheckFailed = helperExitCode != 0 and openAIStateValue == "" and claudeStateValue == ""
            if (integrationOpenAIConfigured or integrationClaudeCodeConfigured) do persistOnboardingDismissed true
            refreshOnboardingDialog()
            if (helperExitCode != 0) do addActivity "error" ("AI integration helper failed: " + readIntegrationValue "operation" "message" fallbackValue: "unknown error")
            if (wasAutomaticCheck and helperExitCode == 0 and automaticCheckConclusive and not integrationOpenAIConfigured and not integrationClaudeCodeConfigured and not (loadOnboardingDismissed())) do showOnboardingDialog refreshStatus: false
            return true
        ),

        fn copyOnboardingTestPrompt = (
            try (
                (dotNetClass "System.Windows.Forms.Clipboard").SetText (onboardingTestPromptText())
                showClipboardCopiedFeedback onboardingTestDialog.btnCopyTestPrompt "Copy test prompt"
                return true
            ) catch (
                messageBox "Could not access the Windows clipboard. Try again after closing another clipboard operation." title: "Max Ultra MCP - AI Client Setup"
                return false
            )
        ),

        fn beginAutomaticOnboardingCheck = (
            if (isDisposed) do return false
            integrationAutomaticCheckPending = true
            integrationAutomaticCheckDueAt = (dotNetClass "System.DateTime").UtcNow.AddSeconds 2.0
            refreshAiStatusControls()
            return true
        ),

        fn runPendingAutomaticOnboardingCheck = (
            if (not integrationAutomaticCheckPending or integrationAutomaticCheckDueAt == undefined or integrationBusy) do return true
            local deadlineReached = false
            try (deadlineReached = (((dotNetClass "System.DateTime").UtcNow.CompareTo integrationAutomaticCheckDueAt) >= 0)) catch (deadlineReached = true)
            if (not deadlineReached) do return true
            integrationAutomaticCheckPending = false
            integrationAutomaticCheckDueAt = undefined
            return startIntegrationOperation #status automaticCheck: true
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
                local minimumVisibleDragHeight = 24
                local maximumX = workingArea.Right - 236
                local maximumY = workingArea.Bottom - minimumVisibleDragHeight
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
            if (restoreBubbleSurface != undefined) do (
                labelOffsetX += restoreBubbleSurface.Left as integer
                labelOffsetY += restoreBubbleSurface.Top as integer
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
            local bubbleSurfaceToDispose = restoreBubbleSurface
            local bubbleLabelToDispose = restoreBubbleLabel
            local bubbleButtonToDispose = restoreBubbleButton
            local bubbleFormToDispose = restoreBubbleForm
            local formOwnsSurface = false
            local surfaceOwnsLabel = false
            local surfaceOwnsButton = false
            try (formOwnsSurface = bubbleFormToDispose != undefined and bubbleSurfaceToDispose != undefined and bubbleSurfaceToDispose.Parent == bubbleFormToDispose) catch ()
            try (surfaceOwnsLabel = bubbleSurfaceToDispose != undefined and bubbleLabelToDispose != undefined and bubbleLabelToDispose.Parent == bubbleSurfaceToDispose) catch ()
            try (surfaceOwnsButton = bubbleSurfaceToDispose != undefined and bubbleButtonToDispose != undefined and bubbleButtonToDispose.Parent == bubbleSurfaceToDispose) catch ()
            restoreBubbleSurface = undefined
            restoreBubbleLabel = undefined
            restoreBubbleButton = undefined
            restoreBubbleForm = undefined
            restoreBubbleDragging = false
            restoreBubbleDragOffset = undefined
            restoreBubbleCloseAllowed = true
            try (if (bubbleLabelToDispose != undefined) do dotNet.removeAllEventHandlers bubbleLabelToDispose) catch ()
            try (if (bubbleButtonToDispose != undefined) do dotNet.removeAllEventHandlers bubbleButtonToDispose) catch ()
            try (if (bubbleFormToDispose != undefined) do dotNet.removeAllEventHandlers bubbleFormToDispose) catch ()
            try (
                if (bubbleFormToDispose != undefined) do (
                    bubbleFormToDispose.Hide()
                    bubbleFormToDispose.Close()
                    bubbleFormToDispose.Dispose()
                )
            ) catch ()
            try (if (not surfaceOwnsLabel and bubbleLabelToDispose != undefined) do bubbleLabelToDispose.Dispose()) catch ()
            try (if (not surfaceOwnsButton and bubbleButtonToDispose != undefined) do bubbleButtonToDispose.Dispose()) catch ()
            try (if (not formOwnsSurface and bubbleSurfaceToDispose != undefined) do bubbleSurfaceToDispose.Dispose()) catch ()
            restoreBubbleCloseAllowed = false
            return true
        ),

        fn handleRestoreBubbleFormClosing formSender eventArgs = (
            if (not restoreBubbleCloseAllowed and eventArgs != undefined) do eventArgs.Cancel = true
            return true
        ),

        fn handlePanelGeometryChanged formSender eventArgs = (
            if (not isDisposed and rememberNormalPanelPosition formSender) do (
                persistPanelPosition lastNormalPanelPosition
            )
            return true
        ),

        fn createPanelFloater panelPosition = (
            if (isDisposed) do return false
            if (panelIsOpen()) do return true
            local resolvedPosition = normalizePanelPosition panelPosition
            try (
                panelCloseInProgress = false
                panelFloater = newRolloutFloater (productWindowTitle()) 720 640 lockWidth: true lockHeight: true autoLayoutOnResize: false scrollBar: #off
                panelFloater.pos = resolvedPosition
                addRollout statusDialog panelFloater rolledUp: false border: false
                addRollout serverStatusDialog panelFloater rolledUp: false border: false
                addRollout activityDialog panelFloater rolledUp: false border: false
                addRollout supportDialog panelFloater rolledUp: false border: false
                configureMainPanelControls()
                return panelIsOpen()
            ) catch (
                format "[3DGROUND | Max Ultra MCP] PANEL CREATE ERROR | %\n" (getCurrentException() as string)
                try (
                    suppressPanelShutdown = true
                    if (panelFloater != undefined and panelFloater.open) do closeRolloutFloater panelFloater
                    suppressPanelShutdown = false
                ) catch (
                    suppressPanelShutdown = false
                )
                panelFloater = undefined
                panelForm = undefined
                return false
            )
        ),

        fn restoreHiddenPanel = (
            if (isDisposed) do return false
            local wasPersistedHidden = loadPanelHiddenState()
            if (not panelIsOpen()) do (
                local restorePosition = if (hiddenPanelPosition == undefined) then loadPanelPosition() else normalizePanelPosition hiddenPanelPosition
                if (not (this.createPanelFloater restorePosition)) do (
                    if (wasPersistedHidden) do persistPanelHiddenState true
                    return false
                )
            )
            try (panelFloater.visible = true) catch ()
            if (not panelIsVisible()) do (
                if (wasPersistedHidden) do persistPanelHiddenState true
                return false
            )
            if (not (persistPanelHiddenState false)) do (
                addActivity "error" "Could not save the visible panel state; the restored panel remains available"
                disposeRestoreBubble()
                return true
            )
            hiddenPanelPosition = undefined
            disposeRestoreBubble()
            try (panelFloater.placementName = #normal) catch ()
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
                restoreBubbleSurface = dotNetObject "System.Windows.Forms.Panel"
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
                restoreBubbleForm.BackColor = MaxUltraMcpTheme.outlineColor
                restoreBubbleForm.Text = "Max Ultra MCP"
                restoreBubbleForm.AccessibleName = "Max Ultra MCP restore mini-panel"
                restoreBubbleSurface.Location = dotNetObject "System.Drawing.Point" 1 1
                restoreBubbleSurface.Size = dotNetObject "System.Drawing.Size" 234 62
                restoreBubbleSurface.BackColor = MaxUltraMcpTheme.backgroundColor
                restoreBubbleSurface.AccessibleName = "Max Ultra MCP restore mini-panel surface inside a one-pixel theme outline"
                restoreBubbleLabel.Text = "Max Ultra MCP"
                restoreBubbleLabel.Location = dotNetObject "System.Drawing.Point" 7 4
                restoreBubbleLabel.Size = dotNetObject "System.Drawing.Size" 220 18
                restoreBubbleLabel.BackColor = restoreBubbleSurface.BackColor
                restoreBubbleLabel.ForeColor = MaxUltraMcpTheme.textColor
                restoreBubbleLabel.AutoSize = false
                restoreBubbleLabel.UseCompatibleTextRendering = false
                MaxUltraMcpUiKit.applyIndependentBoldFont restoreBubbleLabel
                restoreBubbleLabel.TabStop = false
                restoreBubbleLabel.Cursor = (dotNetClass "System.Windows.Forms.Cursors").SizeAll
                restoreBubbleLabel.AccessibleDescription = "Drag to move the Max Ultra MCP restore mini-panel"
                restoreBubbleButton.Text = "Expand MCP Server"
                restoreBubbleButton.AccessibleName = "Expand MCP Server"
                restoreBubbleButton.Location = dotNetObject "System.Drawing.Point" 7 26
                restoreBubbleButton.Size = dotNetObject "System.Drawing.Size" 220 29
                MaxUltraMcpUiKit.styleButton restoreBubbleButton baseColorValue: (statusTextColor())
                MaxUltraMcpUiKit.applyIndependentBoldFont restoreBubbleButton
                restoreBubbleButton.ForeColor = MaxUltraMcpTheme.textColor
                dotNet.addEventHandler restoreBubbleLabel "MouseDown" handleRestoreBubbleMouseDown
                dotNet.addEventHandler restoreBubbleLabel "MouseMove" handleRestoreBubbleMouseMove
                dotNet.addEventHandler restoreBubbleLabel "MouseUp" handleRestoreBubbleMouseUp
                dotNet.addEventHandler restoreBubbleButton "Click" handleRestoreBubbleClick
                dotNet.addEventHandler restoreBubbleForm "FormClosing" handleRestoreBubbleFormClosing
                restoreBubbleSurface.Controls.Add restoreBubbleLabel
                restoreBubbleSurface.Controls.Add restoreBubbleButton
                restoreBubbleForm.Controls.Add restoreBubbleSurface
                restoreBubbleForm.Show()
                return true
            ) catch (
                format "[3DGROUND | Max Ultra MCP] RESTORE MINI-PANEL ERROR | %\n" (getCurrentException() as string)
                disposeRestoreBubble()
                return false
            )
        ),

        fn refreshRestoreBubbleStatus = (
            if (isDisposed or restoreBubbleForm == undefined or restoreBubbleButton == undefined) do return false
            try (
                if (restoreBubbleForm.IsDisposed or restoreBubbleButton.IsDisposed) do return false
                local bubbleStatusColor = statusTextColor()
                local controlPaintClass = dotNetClass "System.Windows.Forms.ControlPaint"
                restoreBubbleButton.BackColor = bubbleStatusColor
                restoreBubbleButton.ForeColor = MaxUltraMcpTheme.textColor
                restoreBubbleButton.FlatAppearance.MouseOverBackColor = controlPaintClass.Light bubbleStatusColor
                restoreBubbleButton.FlatAppearance.MouseDownBackColor = controlPaintClass.Dark bubbleStatusColor
                restoreBubbleButton.AccessibleDescription = "Connection status: " + connectionStateText()
                restoreBubbleButton.Refresh()
                return true
            ) catch (
                return false
            )
        ),

        fn stopPollTimer = (
            local timerToDispose = pollTimer
            pollTimer = undefined
            if (timerToDispose == undefined) do return true
            try (timerToDispose.Stop()) catch ()
            try (dotNet.removeEventHandlers timerToDispose "Tick") catch ()
            try (timerToDispose.Dispose()) catch ()
            return true
        ),

        fn disposePanelToolTip = (
            local tooltipToDispose = panelToolTip
            panelToolTip = undefined
            try (if (tooltipToDispose != undefined) do tooltipToDispose.Dispose()) catch ()
            return true
        ),

        fn performPanelFormClosing formSender eventArgs = (
            local wasAlreadyDisposed = isDisposed
            isDisposed = true
            isStopped = true
            pendingConnectOnly = false
            panelCloseInProgress = true
            stopPollTimer()
            try (
                persistPanelPosition (capturePanelPosition formSender)
                persistPanelHiddenState false
            ) catch (
                try (format "[3DGROUND | Max Ultra MCP] GEOMETRY SAVE ERROR | %\n" (getCurrentException() as string)) catch ()
            )
            disposeSettingsDialog()
            disposeOnboardingDialog()
            disposeRestoreBubble()
            releasePanelIconImages()
            disposePanelToolTip()
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
            local cleanupResult = true
            try (
                cleanupResult = performPanelFormClosing formSender eventArgs
            ) catch (
                try (format "[3DGROUND | Max Ultra MCP] FORM CLOSE ERROR | %\n" (getCurrentException() as string)) catch ()
            )
            return cleanupResult
        ),

        fn handlePanelRolloutClosed = (
            if (suppressPanelShutdown or isDisposed or panelCloseInProgress) do (
                panelFloater = undefined
                panelForm = undefined
                return true
            )
            local closedPanelForm = panelForm
            local cleanupResult = handlePanelFormClosing closedPanelForm undefined
            panelFloater = undefined
            panelForm = undefined
            return cleanupResult
        ),

        fn detachPanelFormEvents formSender = (
            if (formSender == undefined) do return true
            try (dotNet.removeEventHandler formSender "FormClosing" handlePanelFormClosing) catch ()
            try (dotNet.removeEventHandler formSender "LocationChanged" handlePanelGeometryChanged) catch ()
            return true
        ),

        fn configurePanelWindowChrome formSender = (
            if (formSender == undefined) do return false
            try (
                formSender.FormBorderStyle = (dotNetClass "System.Windows.Forms.FormBorderStyle").FixedToolWindow
                formSender.ControlBox = true
                formSender.MinimizeBox = false
                formSender.MaximizeBox = false
                formSender.ShowIcon = false
                return true
            ) catch (
                return false
            )
        ),

        fn attachPanelFormClosing = (
            if (not panelIsOpen()) do return false
            try (
                local dialogHandle = dotNetObject "System.IntPtr" panelFloater.hwnd
                panelForm = (dotNetClass "System.Windows.Forms.Control").FromHandle dialogHandle
                if (panelForm == undefined) do return false
                configurePanelWindowChrome panelForm
                detachPanelFormEvents panelForm
                dotNet.addEventHandler panelForm "FormClosing" handlePanelFormClosing
                dotNet.addEventHandler panelForm "LocationChanged" handlePanelGeometryChanged
                applyProductVersionToUi()
                rememberNormalPanelPosition panelForm
                return true
            ) catch (
                format "[3DGROUND | Max Ultra MCP] FORM HOOK ERROR | %\n" (getCurrentException() as string)
                return false
            )
        ),

        fn refreshUserInterface = (
            if (isDisposed) do return false
            applyProductVersionToUi()
            local miniPanelRefreshed = refreshRestoreBubbleStatus()
            if (not panelIsOpen()) do return miniPanelRefreshed
            refreshAiStatusControls()
            local endpointText = ""
            local endpointDetails = ""
            case connectionState of (
                #connected: endpointText = "Server " + hostAddress + ":" + (hostPort as string)
                #starting: endpointText = "Starting local MCP server..."
                #connecting: endpointText = "Connecting to local MCP server..."
                #reconnecting: endpointText = "Reconnecting to the running MCP server..."
                #restarting: endpointText = "Restarting the verified local MCP server..."
                #error: endpointText = "Please restart the script"
                default: endpointText = "Please restart the script"
            )
            endpointDetails = if (connectionState == #error or connectionState == #disconnected or connectionState == #stopped) then (safeSingleLineUiText connectionError endpointText) else endpointText
            local connectionColor = bridgeStatusTextColor()
            serverStatusDialog.lblConnectionIndicator.ForeColor = connectionColor
            serverStatusDialog.lblConnectionIndicator.AccessibleDescription = connectionStateText()
            serverStatusDialog.lblEndpoint.Text = endpointText
            serverStatusDialog.lblEndpoint.ForeColor = connectionColor
            serverStatusDialog.lblEndpoint.AccessibleDescription = endpointDetails
            local contextText = "PID " + (processId as string) + " | Scene " + currentSceneUiName() + " | Objects " + (objects.count as string) + " | Selection " + (selection.count as string)
            serverStatusDialog.lblContext.Text = contextText
            serverStatusDialog.lblContext.ForeColor = MaxUltraMcpTheme.textColor
            serverStatusDialog.lblContext.AccessibleDescription = contextText
            if (panelToolTip != undefined) do (
                panelToolTip.SetToolTip serverStatusDialog.lblEndpoint endpointDetails
                panelToolTip.SetToolTip serverStatusDialog.lblContext contextText
            )
            MaxUltraMcpUiKit.updateButtonState activityDialog.btnStop (not isStopped)
            MaxUltraMcpUiKit.updateButtonState activityDialog.btnReconnect (connectionState != #reconnecting)
            if (activityLogDirty) do refreshActivityText()
            return true
        ),

        fn showPanel = (
            if (isDisposed) do return false
            if (not (restoreHiddenPanel())) do return false
            attachPanelFormClosing()
            refreshUserInterface()
            return true
        ),

        fn hidePanel = (
            if (isDisposed) do return false
            if (panelIsOpen()) do (
                try (
                    hiddenPanelPosition = capturePanelPosition panelForm
                    persistPanelPosition hiddenPanelPosition
                    if (not (persistPanelHiddenState true)) do (
                        addActivity "error" "Could not save the hidden panel state; the MCP Server panel remains open"
                        return false
                    )
                    if (not (showRestoreBubble())) do (
                        persistPanelHiddenState false
                        addActivity "error" "Could not create the restore mini-panel; the MCP Server panel was shown again"
                        return false
                    )
                    panelFloater.visible = false
                    if (panelIsVisible()) do throw "The Max Ultra MCP floater remained visible"
                    addActivity "info" "Panel hidden; use the lower-left Expand MCP Server mini-panel to restore it"
                ) catch (
                    persistPanelHiddenState false
                    disposeRestoreBubble()
                    try (if (panelIsOpen()) do panelFloater.visible = true) catch ()
                    addActivity "error" ("Could not hide panel: " + (getCurrentException() as string))
                    return false
                )
            )
            return true
        ),

        fn restoreSavedPanelVisibility = (
            if (not (loadPanelHiddenState())) do return showPanel()
            hiddenPanelPosition = loadPanelPosition()
            if (showRestoreBubble()) do return true
            persistPanelHiddenState false
            return showPanel()
        ),

        fn closeForLifecycle reason: "Stopped" = (
            if (isDisposed) do return true
            stopPollTimer()
            addActivity "warning" (reason + ": disconnecting Max and starting the detached single-Max shutdown check")
            connectionState = #stopped
            refreshUserInterface()
            if (panelIsOpen()) then (
                closeRolloutFloater panelFloater
            ) else (
                handlePanelFormClosing panelForm undefined
            )
            return true
        ),

        fn minimizePanel = (
            if (isDisposed) do return false
            if (not (showPanel())) do return false
            try (
                panelFloater.placementName = #minimized
                return true
            ) catch (
                return false
            )
        ),

        fn restorePanel = (
            if (isDisposed) do return false
            if (not (showPanel())) do return false
            try (
                panelFloater.placementName = #normal
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

        fn buildSceneSummaryJson actionName = (
            local versionInfo = maxVersion()
            local currentTimestamp = (dotNetClass "System.DateTime").UtcNow.ToString("o")
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
            local currentTimestamp = (dotNetClass "System.DateTime").UtcNow.ToString("o")
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
            local activityLabel = if (wireFields.count >= 5) then decodeWireField(wireFields[5]) else ""
            if (requestWasCancelled requestId) do (
                addActivity "info" ("Cancelled queued request " + requestId)
                return sendBridgeResponse requestId false "Request was cancelled before main-thread execution"
            )
            case actionName of (
                "logs": return sendBridgeResponse requestId true (buildActivityLogJson())
                "health": (
                    sendSceneStatus()
                    return sendBridgeResponse requestId true (buildSceneSummaryJson actionName)
                )
                "scene_summary": (
                    sendSceneStatus()
                    return sendBridgeResponse requestId true (buildSceneSummaryJson actionName)
                )
                "get_info": (
                    sendSceneStatus()
                    return sendBridgeResponse requestId true (buildGetInfoJson())
                )
                "smoke": (
                    sendSceneStatus()
                    return sendBridgeResponse requestId true (buildSceneSummaryJson actionName)
                )
                "execute": return handleExecuteRequest requestId actionPayload activityLabel
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
                    armSupportReminders()
                    addActivity "success" ("Connected to local MCP server at " + hostAddress + ":" + (hostPort as string))
                )
                "server_ready": addActivity "success" "Local MCP server health check passed"
                "server_restarting": addActivity "warning" "First-step file re-run: stopping the verified previous server before replacement"
                "server_restart_shared": addActivity "warning" "Previous server is shared by another 3ds Max process; reused without interrupting it"
                "legacy_server": addActivity "warning" "Compatible legacy Max Ultra MCP server detected; attached without terminating its process"
                "port_changed": (
                    local portChangeFields = filterString eventMessage "|"
                    if (portChangeFields.count >= 1) do (
                        try (hostPort = portChangeFields[1] as integer) catch ()
                    )
                    local portChangeReason = if (portChangeFields.count >= 2) then portChangeFields[2] else "the configured endpoint is unavailable"
                    addActivity "warning" ("Using safe fallback port " + (hostPort as string) + " because " + portChangeReason)
                    addActivity "system" ("MCP host setting: MAX_ULTRA_MCP_PORT=" + (hostPort as string))
                )
                "server_launching": (
                    connectionState = #starting
                    addActivity "system" ("Starting local MCP server with " + eventMessage)
                )
                "server_waiting": (
                    connectionState = #starting
                    addActivity "warning" "Another Max instance is starting the local server; waiting"
                )
                "server_started": addActivity "success" "Local MCP server started and ownership verified"
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

        fn workerControlRequest workerHost workerPort operationName timeoutMilliseconds requestPayload: "" controlToken: "" = (
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
                if (controlToken != "") do requestLine += "\t" + encodeWireField(controlToken)
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

        fn workerReadControlToken workerTokenFilePath = (
            local environmentClass = dotNetClass "System.Environment"
            local controlToken = environmentClass.GetEnvironmentVariable "MAX_ULTRA_MCP_CONTROL_TOKEN"
            if (controlToken == undefined) do controlToken = ""
            controlToken = trimLeft (trimRight (controlToken as string))
            if (controlToken == "" and workerTokenFilePath != undefined and workerTokenFilePath != "") do (
                try (controlToken = trimLeft (trimRight ((dotNetClass "System.IO.File").ReadAllText workerTokenFilePath))) catch (controlToken = "")
            )
            if (controlToken.count != 64) do return ""
            local hexadecimalCharacters = "0123456789abcdefABCDEF"
            for characterIndex in 1 to controlToken.count do (
                if ((findString hexadecimalCharacters (substring controlToken characterIndex 1)) == undefined) do return ""
            )
            return toLower controlToken
        ),

        fn workerConnectedInstanceCount workerInventoryPayload = (
            if (workerInventoryPayload == undefined or workerInventoryPayload == "") do return -1
            try (
                local countMatch = (dotNetClass "System.Text.RegularExpressions.Regex").Match workerInventoryPayload "\"count\":([0-9]+)"
                if (not countMatch.Success) do return -1
                return countMatch.Groups.Item[1].Value as integer
            ) catch (
                return -1
            )
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

        fn workerWaitForEndpointClose workerHost workerPort timeoutMilliseconds = (
            local closeRetryDelays = #(50, 100, 150, 250, 350, 500, 750, 1000, 1000)
            local closeProbe = workerProbeEndpoint workerHost workerPort timeoutMilliseconds
            if (closeProbe.controlState == #closed) do return closeProbe
            for closeRetryDelay in closeRetryDelays do (
                (dotNetClass "System.Threading.Thread").Sleep closeRetryDelay
                closeProbe = workerProbeEndpoint workerHost workerPort timeoutMilliseconds
                if (closeProbe.controlState == #closed) do return closeProbe
            )
            return closeProbe
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

        fn workerLaunchServer workerLauncherPath workerWorkingDirectory workerPort workerOwnershipDirectory workerOwnerToken workerMaxPid workerServerConsoleVisible = (
            if (workerLauncherPath == undefined or workerLauncherPath == "") do throw "scripts\\start-server.bat was not found below the project root; set MAX_ULTRA_MCP_ROOT if the first-step script was copied"
            local ownershipFilePath = workerOwnershipDirectory + "max-ultra-mcp-owned-" + (workerPort as string) + ".json"
            local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
            startInfo.FileName = "cmd.exe"
            startInfo.Arguments = "/d /c \"\"" + workerLauncherPath + "\" --no-pause --port " + (workerPort as string) + " --owner-file \"" + ownershipFilePath + "\" --owner-token \"" + workerOwnerToken + "\" --owner-max-pid " + (workerMaxPid as string) + "\""
            startInfo.WorkingDirectory = workerWorkingDirectory
            if (workerServerConsoleVisible) then (
                startInfo.UseShellExecute = true
                startInfo.CreateNoWindow = false
                startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Normal
            ) else (
                startInfo.UseShellExecute = false
                startInfo.CreateNoWindow = true
                startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
            )
            local serverProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
            if (serverProcess == undefined) do throw "Windows did not start the Max Ultra MCP launcher"
            return serverProcess
        ),

        fn workerLauncherExitCode launcherProcess = (
            if (launcherProcess == undefined) do return undefined
            try (
                if (launcherProcess.HasExited) do return launcherProcess.ExitCode
            ) catch (
            )
            return undefined
        ),

        fn workerDisposeProcessHandle launcherProcess = (
            if (launcherProcess == undefined) do return true
            try (launcherProcess.Dispose()) catch ()
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
            local workerServerConsoleVisible = workerArguments.Item[11]
            local workerControlTokenFilePath = workerArguments.Item[12]
            local workerRestartExistingServer = workerArguments.Item[13]
            local retryDelays = #(150, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000)
            local probeTimeoutMilliseconds = 500
            local lifecycleMutex = undefined
            local ownsLifecycleMutex = false
            local launchedServer = false
            local launchedServerProcess = undefined
            local workerClient = undefined
            local workerStream = undefined
            local workerReader = undefined
            local workerWriter = undefined

            try (
                local probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                if (workerRestartExistingServer and probeReply.controlState == #healthy) do (
                    if (not workerHostIsLoopback workerHost) do throw "Automatic server restart is allowed only for a configured loopback endpoint"
                    lifecycleMutex = dotNetObject "System.Threading.Mutex" false workerMutexName
                    try (ownsLifecycleMutex = lifecycleMutex.WaitOne 3000 false) catch (ownsLifecycleMutex = false)
                    if (not ownsLifecycleMutex) do throw "Another Max Ultra MCP lifecycle operation is still running; retry after its bounded restart completes"
                    probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                    if (probeReply.controlState == #healthy) do (
                        local inventoryReply = workerControlRequest workerHost workerPort "list" probeTimeoutMilliseconds
                        local connectedInstanceCount = if (inventoryReply.controlState == #verified) then workerConnectedInstanceCount inventoryReply.responsePayload else -1
                        if (connectedInstanceCount < 0) then (
                            throw "The connected 3ds Max count could not be verified; the existing server was left running"
                        ) else if (connectedInstanceCount > 1) then (
                            workerEncodeEvent workerInboundQueue "server_restart_shared" ""
                        ) else (
                            local workerControlToken = workerReadControlToken workerControlTokenFilePath
                            if (workerControlToken == "") do throw "The Max Ultra MCP control token is unavailable; the verified server was left running"
                            workerEncodeEvent workerInboundQueue "server_restarting" ""
                            local shutdownReply = workerControlRequest workerHost workerPort "shutdown_owned" probeTimeoutMilliseconds requestPayload: probeReply.responsePayload controlToken: workerControlToken
                            if (shutdownReply.controlState != #verified) do throw ("Verified server restart was refused: " + shutdownReply.failureMessage)
                            probeReply = workerWaitForEndpointClose workerHost workerPort probeTimeoutMilliseconds
                            if (probeReply.controlState != #closed) do throw "The verified Max Ultra MCP server did not exit within the bounded restart timeout"
                        )
                    )
                )
                local needsFallbackPort = probeReply.controlState == #occupied or (workerRestartExistingServer and probeReply.controlState == #legacy)
                local fallbackReason = ""

                if (needsFallbackPort) do (
                    if (not workerHostIsLoopback workerHost) do throw "Automatic fallback-port selection is allowed only for a configured loopback endpoint"
                    lifecycleMutex = dotNetObject "System.Threading.Mutex" false workerMutexName
                    try (ownsLifecycleMutex = lifecycleMutex.WaitOne 3000 false) catch (ownsLifecycleMutex = false)
                    if (not ownsLifecycleMutex) do throw "Another Max Ultra MCP lifecycle operation is still running; retry after its bounded startup completes"
                    probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                    needsFallbackPort = probeReply.controlState == #occupied or (workerRestartExistingServer and probeReply.controlState == #legacy)
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
                            local launchModeLabel = if (workerServerConsoleVisible) then "a visible console" else "a hidden console"
                            workerEncodeEvent workerInboundQueue "server_launching" launchModeLabel
                            launchedServerProcess = workerLaunchServer workerLauncherPath workerWorkingDirectory workerPort workerOwnershipDirectory workerOwnerToken workerMaxPid workerServerConsoleVisible
                            launchedServer = true
                        )
                    ) else (
                        workerEncodeEvent workerInboundQueue "server_waiting" ""
                    )

                    serverUsable = probeReply.controlState == #healthy or probeReply.controlState == #legacy
                    for retryDelay in retryDelays while not serverUsable do (
                        if (workerSender.CancellationPending) do throw "Server startup cancelled"
                        local launcherExitCode = workerLauncherExitCode launchedServerProcess
                        if (launcherExitCode != undefined) do throw ("Max Ultra MCP launcher exited with code " + (launcherExitCode as string) + ". Enable Show server console when starting in Settings or run scripts\\start-server.bat to view the launcher error.")
                        (dotNetClass "System.Threading.Thread").Sleep retryDelay
                        probeReply = workerProbeEndpoint workerHost workerPort probeTimeoutMilliseconds
                        if (probeReply.controlState == #occupied) do throw "The selected loopback endpoint was taken by an unverified service during startup; no process was terminated"
                        serverUsable = probeReply.controlState == #healthy or probeReply.controlState == #legacy
                    )
                    if (not serverUsable) do throw "Max Ultra MCP server did not become healthy within the bounded startup timeout. Enable Show server console when starting in Settings or run scripts\\start-server.bat to view the launcher error."
                )

                workerDisposeProcessHandle launchedServerProcess
                launchedServerProcess = undefined
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
            workerDisposeProcessHandle launchedServerProcess
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
            bootstrapFilePath = getThisScriptFileName()
            loadProductVersion()
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
            workerArguments.Add (loadServerConsoleVisibleSetting())
            workerArguments.Add controlTokenFilePath
            workerArguments.Add restartExistingServer
            restartExistingServer = false
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
            if (disposeInProgress) do return true
            disposeInProgress = true
            isDisposed = true
            isStopped = true
            pendingConnectOnly = false
            stopPollTimer()
            disposeSettingsDialog()
            disposeOnboardingDialog()
            disposeRestoreBubble()
            releasePanelIconImages()
            try (if (transportWorker != undefined and transportWorker.IsBusy) do transportWorker.CancelAsync()) catch ()
            local integrationProcessFinished = true
            try (if (integrationProcess != undefined) do integrationProcessFinished = integrationProcess.HasExited) catch ()
            try (if (integrationProcess != undefined) do integrationProcess.Dispose()) catch ()
            integrationProcess = undefined
            integrationBusy = false
            integrationAutomaticCheck = false
            integrationAutomaticCheckPending = false
            integrationAutomaticCheckDueAt = undefined
            integrationOperationStartedAt = undefined
            try (
                if (updateProcess != undefined and not updateProcess.HasExited) do updateProcess.Kill()
            ) catch ()
            try (if (updateProcess != undefined) do updateProcess.Dispose()) catch ()
            updateProcess = undefined
            updateBusy = false
            updateAutomaticCheck = false
            try (if (updateResultFilePath != "" and doesFileExist updateResultFilePath) do deleteFile updateResultFilePath) catch ()
            updateResultFilePath = ""
            if (integrationProcessFinished and integrationResultFilePath != "") do try (if (doesFileExist integrationResultFilePath) do deleteFile integrationResultFilePath) catch ()
            try (if (transportWorker != undefined) do dotNet.removeEventHandler transportWorker "DoWork" transportDoWork) catch ()
            pendingRequestLines = #()
            cancelledRequestIds = #()
            try (
                if (panelIsOpen()) do (
                    detachPanelFormEvents panelForm
                    suppressPanelShutdown = true
                    closeRolloutFloater panelFloater
                    suppressPanelShutdown = false
                )
            ) catch (
                suppressPanelShutdown = false
            )
            detachPanelFormEvents panelForm
            disposePanelToolTip()
            panelFloater = undefined
            panelForm = undefined
            transportWorker = undefined
            transportWorkerArguments = undefined
            try (callbacks.removeScripts id: maxShutdownCallbackId) catch ()
            disposeInProgress = false
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
            addActivity "info" "Reconnect requested; a stopped server will not be launched"
            refreshUserInterface()
            return true
        ),

        fn handleTimerTick timerSender eventArgs = (
            if (isDisposed or pollTimer == undefined or timerSender != pollTimer) do return true
            try (
                tickCount += 1
                runPendingAutomaticOnboardingCheck()
                pollIntegrationOperation()
                pollUpdateOperation()
                pollSupportReminder()
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
            supportReminderCount = 0
            supportReminderDueAt = undefined
            shutdownHelperStarted = false
            connectionState = #starting
            connectionError = ""
            if (not (restoreSavedPanelVisibility())) do addActivity "error" "Could not restore the saved panel visibility"
            addActivity "system" "Initializing Max Ultra MCP services"
            if (stagedUpdateStatus != "") do addActivity (if (matchPattern stagedUpdateStatus pattern: "The staged update*" ignoreCase: false) then "error" else "success") stagedUpdateStatus
            if (serverLauncherPath == "") do addActivity "warning" "scripts\\start-server.bat not found below this file; MAX_ULTRA_MCP_ROOT fallback will be required if launch is needed"
            startTransport allowServerLaunch: true
            try (
                pollTimer = dotNetObject "System.Windows.Forms.Timer"
                pollTimer.Interval = 250
                dotNet.addEventHandler pollTimer "Tick" handleTimerTick
                pollTimer.Start()
                beginAutomaticOnboardingCheck()
                if (loadAutomaticUpdateSetting()) do startUpdateCheck automaticCheck: true
            ) catch (
                local timerStartFailure = getCurrentException() as string
                try (format "[3DGROUND | Max Ultra MCP] TIMER START ERROR | %\n" timerStartFailure) catch ()
                try (disposeForReload()) catch ()
                MaxUltraMcpActiveClient = undefined
                return false
            )
            return true
        )
    )

    bridgeClient = MaxUltraMcpBridgeClient statusDialog: MaxUltraMcpAiStatusDialog serverStatusDialog: MaxUltraMcpServerStatusDialog activityDialog: MaxUltraMcpActivityDialog supportDialog: MaxUltraMcpSupportDialog settingsDialog: MaxUltraMcpSettingsDialog onboardingTabsDialog: MaxUltraMcpOnboardingTabsDialog onboardingSetupDialog: MaxUltraMcpOnboardingSetupDialog onboardingTestDialog: MaxUltraMcpOnboardingTestDialog restartExistingServer: restartServerForReload
    MaxUltraMcpActiveClient = bridgeClient
    bridgeClient.startBridge()
    bridgeClient
    )
)
