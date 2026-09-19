/*
 * Exercises real setup controls against synthetic status and a recording process-launch seam.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
local fixtureGuid = (dotNetClass "System.Guid").NewGuid()
local fixtureResultPath = (getDir #temp) + @"\max-ultra-setup-" + (fixtureGuid.ToString "N") + ".ini"
local fixtureAssertions = 0
local fixturePhase = "controls"
fn assertSetup conditionValue failureMessage = (
    if (not conditionValue) do throw failureMessage
    fixtureAssertions += 1
    return true
)
fn setFixtureClient clientId stateValue availableValue = (
    local availableKey = if (clientId == "antigravity") then "setupAvailable" else "cliAvailable"
    setINISetting fixtureResultPath clientId availableKey availableValue
    setINISetting fixtureResultPath clientId "state" stateValue
    setINISetting fixtureResultPath clientId "configured" (if (stateValue == "configured") then "true" else "false")
    setINISetting fixtureResultPath clientId "detail" "Refresh status and retry."
    return true
)
bridgeClient = MaxUltraMcpBridgeClient onboardingTabsDialog: MaxUltraMcpOnboardingTabsDialog onboardingSetupDialog: MaxUltraMcpOnboardingSetupDialog onboardingTestDialog: MaxUltraMcpOnboardingTestDialog
bridgeClient.bootstrapFilePath = fixtureBootstrapPath
bridgeClient.integrationResultFilePath = fixtureResultPath
bridgeClient.suppressOnboardingDismissal = true
try (
    setINISetting fixtureResultPath "operation" "state" "complete"
    setINISetting fixtureResultPath "runtime" "ready" "true"
    for clientId in #("openai", "claudeCode", "antigravity") do setFixtureClient clientId "not_configured" "true"
    assertSetup (bridgeClient.showOnboardingDialog refreshStatus: false) "Setup did not open"
    assertSetup (not bridgeClient.onboardingManualExpanded and not (bridgeClient.onboardingSetupDialog.txtManual.get_Visible())) "Fresh setup must start collapsed"
    local initialCompactHeight = bridgeClient.onboardingFloater.size.y
    bridgeClient.toggleOnboardingManual()
    local expandedHeight = bridgeClient.onboardingFloater.size.y
    local manualBottom = bridgeClient.onboardingSetupDialog.txtManual.pos.y + bridgeClient.onboardingSetupDialog.txtManual.height
    assertSetup (bridgeClient.onboardingSetupDialog.txtManual.width == 516) "Manual values lost full-width layout"
    assertSetup (manualBottom + 8 <= bridgeClient.onboardingSetupDialog.btnCopyManual.pos.y) "Manual copy overlaps text field"
    assertSetup (bridgeClient.onboardingSetupDialog.btnCopyManual.pos.y + 28 + 6 <= bridgeClient.onboardingSetupDialog.lblOnboardingOperation.pos.y) "Manual copy overlaps operation status"
    assertSetup (bridgeClient.onboardingSetupDialog.lblOnboardingOperation.pos.y + 22 + 6 <= bridgeClient.onboardingSetupDialog.btnRefreshAgents.pos.y) "Operation status overlaps footer"
    local fixtureButtons = #(bridgeClient.onboardingSetupDialog.btnOpenAI, bridgeClient.onboardingSetupDialog.btnClaudeCode, bridgeClient.onboardingSetupDialog.btnAntigravity)
    for clientIndex in 1 to 3 do (
        bridgeClient.integrationBusy = false
        bridgeClient.refreshOnboardingDialog()
        assertSetup (fixtureButtons[clientIndex].Image != undefined) "Client logo did not load"
        assertSetup (fixtureButtons[clientIndex].ImageAlign == (dotNetClass "System.Drawing.ContentAlignment").TopCenter) "Logo is not horizontally centered"
        assertSetup (fixtureButtons[clientIndex].TextAlign == (dotNetClass "System.Drawing.ContentAlignment").BottomCenter) "Client name is not centered below logo"
        fixtureButtons[clientIndex].PerformClick()
        assertSetup (bridgeClient.refreshOnboardingDialog()) "Busy status refresh failed"
        assertSetup (bridgeClient.integrationOperationTimeoutSeconds == #(1,2,4)[clientIndex]) "Button dispatched to the wrong client"
        assertSetup bridgeClient.integrationBusy "Setup must enter the busy state"
        -- Explicit getters avoid the rollout wrapper's shadowed Enabled/Visible properties.
        for fixtureButton in fixtureButtons do assertSetup (not (fixtureButton.get_Enabled())) "Concurrent setup button remained enabled"
        assertSetup (not (bridgeClient.installAgentIntegration "openai")) "Busy guard allowed duplicate setup"
        assertSetup (not (bridgeClient.refreshAgentIntegrationStatus())) "Refresh interrupted setup"
    )
    assertSetup (bridgeClient.onboardingSetupDialog.lblAntigravityStatus.Text == "Setting up...") "Active client lost in-progress status"
    bridgeClient.integrationBusy = false
    bridgeClient.integrationOperationName = #status
    setFixtureClient "claudeCode" "cli_missing" "false"
    setFixtureClient "openai" "configured" "true"
    setFixtureClient "antigravity" "install_failed" "true"
    bridgeClient.refreshOnboardingDialog()
    assertSetup (bridgeClient.onboardingSetupDialog.lblOpenAIStatus.Text == "Configured") "Configured status missing"
    assertSetup (bridgeClient.onboardingSetupDialog.lblClaudeCodeStatus.Text == "Not found") "Absent client status missing"
    assertSetup (not (bridgeClient.onboardingSetupDialog.btnClaudeCode.get_Enabled())) "Absent client button enabled"
    assertSetup (not (bridgeClient.installAgentIntegration "claudeCode")) "Absent client could launch setup"
    assertSetup (bridgeClient.onboardingSetupDialog.lblAntigravityStatus.Text == "Error") "Setup failure was hidden"
    assertSetup (findString bridgeClient.onboardingSetupDialog.lblClientDetail.Text "Refresh status" != undefined) "Error explanation missing"
    bridgeClient.integrationOperationTimeoutSeconds = 0
    bridgeClient.onboardingSetupDialog.btnOpenAI.PerformClick()
    assertSetup (bridgeClient.integrationOperationTimeoutSeconds == 0 and not bridgeClient.integrationBusy) "Configured client was reinstalled"
    for clientId in #("openai", "claudeCode", "antigravity") do (
        setFixtureClient clientId "configured" "true"
        assertSetup (bridgeClient.installAgentIntegration clientId) "Configured client click failed"
        assertSetup (bridgeClient.integrationOperationTimeoutSeconds == 0 and not bridgeClient.integrationBusy) "Repeated click launched an installer"
    )
    assertSetup (not (bridgeClient.installAgentIntegration "unknown")) "Unknown client accepted"
    bridgeClient.integrationLastCheckFailed = true
    bridgeClient.refreshOnboardingDialog()
    assertSetup (bridgeClient.onboardingSetupDialog.lblOpenAIStatus.Text == "Error") "Helper failure was hidden"
    bridgeClient.integrationLastCheckFailed = false
    assertSetup ((bridgeClient.onboardingCardPresentation "not_checked" false false false false)[1] == "Not checked") "Initial state claimed detection"
    assertSetup ((bridgeClient.onboardingCardPresentation "runtime_missing" true false false false)[1] == "Error") "Missing runtime claimed readiness"
    bridgeClient.toggleOnboardingManual()
    assertSetup (not (bridgeClient.onboardingSetupDialog.txtManual.get_Visible()) and not (bridgeClient.onboardingSetupDialog.btnCopyManual.get_Visible())) "Manual section did not collapse"
    assertSetup (bridgeClient.onboardingFloater.size.y < expandedHeight) "Collapsed page retained expanded window height"
    assertSetup (bridgeClient.onboardingSetupDialog.btnRefreshAgents.pos.y == 306) "Collapsed footer did not move up"
    bridgeClient.toggleOnboardingManual()
    assertSetup ((bridgeClient.onboardingSetupDialog.txtManual.get_Visible()) and (bridgeClient.onboardingSetupDialog.btnCopyManual.get_Visible())) "Manual section did not expand"
    assertSetup (bridgeClient.onboardingFloater.size.y == expandedHeight and bridgeClient.onboardingSetupDialog.btnRefreshAgents.pos.y == 442) "Expanded layout was not restored"
    local clipboardClass = dotNetClass "System.Windows.Forms.Clipboard"
    fixturePhase = "save clipboard"
    local savedClipboard = clipboardClass.GetDataObject()
    try (
        fixturePhase = "manual copy"
        bridgeClient.copyManualAgentConfiguration()
        assertSetup (clipboardClass.GetText() == bridgeClient.manualAgentConfigurationText()) "Manual copy changed STDIO values"
        bridgeClient.onboardingTabsDialog.dncPages.SelectedIndex = 1
        fixturePhase = "test tab"
        assertSetup (bridgeClient.onboardingPage == #test) "Test tab did not open"
        assertSetup (bridgeClient.onboardingLogoImages.count == 0) "Setup logo resources survived removal"
        bridgeClient.copyOnboardingTestPrompt()
        assertSetup (clipboardClass.GetText() == bridgeClient.onboardingTestPromptText()) "Test prompt copy changed"
        fixturePhase = "restore clipboard"
        if (savedClipboard != undefined) then clipboardClass.SetDataObject savedClipboard false else clipboardClass.Clear()
    ) catch (
        try (if (savedClipboard != undefined) then clipboardClass.SetDataObject savedClipboard false else clipboardClass.Clear()) catch ()
        throw()
    )
    bridgeClient.onboardingTabsDialog.dncPages.SelectedIndex = 0
    assertSetup (bridgeClient.onboardingPage == #setup and bridgeClient.onboardingLogoImages.count == 3) "Setup reopen failed"
    gc light: true
    assertSetup (bridgeClient.onboardingSetupDialog.btnAntigravity.Image.Width == 48) "Logo lost after garbage collection"
    bridgeClient.closeOnboardingDialog()
    assertSetup (bridgeClient.onboardingLogoImages.count == 0) "Close leaked logo resources"
    bridgeClient.showOnboardingDialog refreshStatus: false
    assertSetup (not bridgeClient.onboardingManualExpanded and not (bridgeClient.onboardingSetupDialog.txtManual.get_Visible())) "Fresh reopen restored expanded manual state"
    assertSetup (bridgeClient.onboardingFloater.size.y == initialCompactHeight) "Fresh reopen did not restore compact height"
    bridgeClient.closeOnboardingDialog()
    deleteFile fixtureResultPath
    #("passed", fixtureAssertions, "no bridge start, no client installs, no scene changes")
) catch (
    local failureText = getCurrentException() as string
    bridgeClient.closeOnboardingDialog()
    if (doesFileExist fixtureResultPath) do deleteFile fixtureResultPath
    #("FAILED", fixturePhase, fixtureAssertions, failureText)
)
