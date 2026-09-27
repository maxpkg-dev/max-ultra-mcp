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
fn assertSetupControlUnclipped controlValue = (
    local visibleBounds = controlValue.RectangleToScreen controlValue.ClientRectangle
    local parentControl = controlValue.Parent
    while (parentControl != undefined) do (
        local parentBounds = parentControl.RectangleToScreen parentControl.ClientRectangle
        assertSetup (parentBounds.Contains visibleBounds) "Setup control is clipped by its parent; record Max version and display scaling"
        parentControl = parentControl.Parent
    )
    return true
)
bridgeClient = MaxUltraMcpBridgeClient onboardingTabsDialog: MaxUltraMcpOnboardingTabsDialog onboardingSetupDialog: MaxUltraMcpOnboardingSetupDialog onboardingTestDialog: MaxUltraMcpOnboardingTestDialog onboardingManualDialog: MaxUltraMcpOnboardingManualDialog
bridgeClient.bootstrapFilePath = fixtureBootstrapPath
bridgeClient.integrationResultFilePath = fixtureResultPath
bridgeClient.suppressOnboardingDismissal = true
try (
    setINISetting fixtureResultPath "operation" "state" "complete"
    setINISetting fixtureResultPath "runtime" "ready" "true"
    for clientId in #("openai", "claudeCode", "antigravity") do setFixtureClient clientId "not_configured" "true"
    assertSetup (bridgeClient.showOnboardingDialog refreshStatus: false) "Setup did not open"
    assertSetup (bridgeClient.onboardingTabsDialog.dncPages.TabPages.Count == 3) "Setup must expose three tabs"
    assertSetup (bridgeClient.onboardingTabsDialog.dncPages.TabPages.Item[2].Text == "Manual setup") "Manual setup must be third"
    local initialSetupHeight = bridgeClient.onboardingFloater.size.y
    assertSetupControlUnclipped bridgeClient.onboardingSetupDialog.txtClientDetail
    assertSetupControlUnclipped bridgeClient.onboardingSetupDialog.btnRefreshAgents
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
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Refresh status" != undefined) "Error explanation missing"
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
    setINISetting fixtureResultPath "runtime" "ready" "false"
    setINISetting fixtureResultPath "runtime" "state" "runtime_timeout"
    setINISetting fixtureResultPath "runtime" "detail" "Node.js check timed out. Refresh status to retry."
    setFixtureClient "openai" "configured" "true"
    setFixtureClient "claudeCode" "not_configured" "true"
    assertSetup (bridgeClient.integrationEffectiveState "openai" == "configured") "Runtime probe failure erased saved registration"
    assertSetup (bridgeClient.integrationEffectiveState "claudeCode" == "runtime_timeout") "Runtime timeout became a missing-file error"
    assertSetup (bridgeClient.refreshOnboardingDialog()) "Runtime error presentation failed"
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "timed out" != undefined) "Runtime reason was not displayed"
    assertSetup (findString (bridgeClient.manualAgentConfigurationText()) "timed out" != undefined) "Copyable diagnostic omitted runtime reason"
    assertSetup (bridgeClient.onboardingSetupDialog.btnRefreshAgents.get_Visible()) "Runtime failure hid refresh"
    local longDiagnostic = "Node.js check timed out. "
    for diagnosticIndex in 1 to 20 do longDiagnostic += "Detailed synthetic diagnostic. "
    longDiagnostic += "End."
    setINISetting fixtureResultPath "runtime" "detail" longDiagnostic
    bridgeClient.refreshOnboardingDialog()
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text longDiagnostic != undefined) "Setup truncated the runtime error"
    bridgeClient.onboardingTabsDialog.dncPages.SelectedIndex = 2
    assertSetup (bridgeClient.onboardingPage == #manual) "Manual tab did not open during runtime failure"
    assertSetup (bridgeClient.onboardingManualDialog.txtInstructions.Text.count > 160) "Manual instructions missing"
    assertSetup (findString bridgeClient.onboardingManualDialog.txtManual.Text longDiagnostic != undefined) "Manual diagnostics were truncated"
    assertSetupControlUnclipped bridgeClient.onboardingManualDialog.txtManual
    assertSetupControlUnclipped bridgeClient.onboardingManualDialog.btnCopyManual
    bridgeClient.integrationBusy = true
    bridgeClient.refreshOnboardingDialog()
    assertSetup (not (bridgeClient.onboardingManualDialog.btnRefreshManual.get_Enabled())) "Manual refresh must not interrupt pending setup"
    bridgeClient.integrationBusy = false
    setINISetting fixtureResultPath "runtime" "ready" "true"
    bridgeClient.refreshOnboardingDialog()
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
    assertSetup (bridgeClient.onboardingPage == #setup) "Fresh reopen must start on Setup"
    assertSetup (bridgeClient.onboardingFloater.size.y == initialSetupHeight) "Fresh reopen changed Setup height"
    bridgeClient.closeOnboardingDialog()
    -- Exercise startup completion without launching a helper or changing client settings.
    struct SetupFinishedProcessFixture (
        HasExited = true,
        ExitCode = 0,
        fn Dispose = (return true)
    )
    bridgeClient.uiStateDirectory = getFilenamePath fixtureResultPath
    bridgeClient.uiStateFilePath = fixtureResultPath
    bridgeClient.persistOnboardingDismissed true
    for clientId in #("openai", "claudeCode", "antigravity") do setFixtureClient clientId "cli_missing" "false"
    bridgeClient.integrationProcess = SetupFinishedProcessFixture()
    bridgeClient.integrationBusy = true
    bridgeClient.integrationAutomaticCheck = true
    assertSetup (bridgeClient.pollIntegrationOperation()) "Automatic setup check failed"
    assertSetup (bridgeClient.onboardingDialogIsOpen()) "No configured clients must open Setup"
    bridgeClient.closeOnboardingDialog()
    bridgeClient.pollIntegrationOperation()
    assertSetup (not (bridgeClient.onboardingDialogIsOpen())) "Closing Setup reopened it during the same run"
    setFixtureClient "openai" "configured" "true"
    bridgeClient.integrationProcess = SetupFinishedProcessFixture()
    bridgeClient.integrationBusy = true
    bridgeClient.integrationAutomaticCheck = true
    bridgeClient.pollIntegrationOperation()
    assertSetup (not (bridgeClient.onboardingDialogIsOpen())) "A configured client must suppress automatic Setup"
    setFixtureClient "openai" "check_failed" "true"
    bridgeClient.integrationProcess = SetupFinishedProcessFixture()
    bridgeClient.integrationBusy = true
    bridgeClient.integrationAutomaticCheck = true
    bridgeClient.pollIntegrationOperation()
    assertSetup (not (bridgeClient.onboardingDialogIsOpen())) "Inconclusive checks must not claim no configured clients"
    deleteFile fixtureResultPath
    #("passed", fixtureAssertions, "no bridge start, no client installs, no scene changes")
) catch (
    local failureText = getCurrentException() as string
    bridgeClient.closeOnboardingDialog()
    if (doesFileExist fixtureResultPath) do deleteFile fixtureResultPath
    #("FAILED", fixturePhase, fixtureAssertions, failureText)
)
