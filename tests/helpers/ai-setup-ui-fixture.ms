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
struct SetupFinishedProcessFixture (
    HasExited = true,
    ExitCode = 0,
    fn Dispose = (return true)
)
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
    setINISetting fixtureResultPath clientId "desktopState" "installed"
    setINISetting fixtureResultPath clientId "desktopAvailable" "true"
    setINISetting fixtureResultPath clientId "desktopInstallState" ""
    setINISetting fixtureResultPath clientId "desktopInstallDetail" ""
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
bridgeClient.uiStateDirectory = getFilenamePath fixtureResultPath
bridgeClient.uiStateFilePath = fixtureResultPath
bridgeClient.suppressOnboardingDismissal = true
try (
    setINISetting fixtureResultPath "operation" "state" "complete"
    setINISetting fixtureResultPath "runtime" "ready" "true"
    for clientId in #("openai", "claudeCode", "antigravity") do setFixtureClient clientId "not_configured" "true"
    assertSetup (bridgeClient.showOnboardingDialog refreshStatus: false) "Setup did not open"
    bridgeClient.onboardingSetupDialog.txtClientDetail.Select 0 1
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionColor == (bridgeClient.activityEntryColor " [info]")) "Initial Choose a client guidance must be informational blue"
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionColor.B > bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionColor.R) "Information palette is orange/yellow instead of blue"
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
    setFixtureClient "openai" "cli_missing" "false"
    bridgeClient.refreshOnboardingDialog()
    assertSetup (bridgeClient.onboardingSetupDialog.lblOpenAIStatus.Text == "Codex CLI not found") "Missing Codex CLI label is ambiguous"
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "setup CLI" != undefined) "Missing setup CLI guidance"
    assertSetup (bridgeClient.onboardingSetupDialog.btnOpenAI.get_Enabled()) "Missing Codex CLI disabled installation"
    assertSetup (bridgeClient.onboardingSetupDialog.btnOpenAI.Text == "Install Codex") "Missing Codex install caption"
    setFixtureClient "claudeCode" "cli_missing" "false"
    setFixtureClient "openai" "configured" "true"
    setFixtureClient "antigravity" "install_failed" "true"
    bridgeClient.refreshOnboardingDialog()
    assertSetup (bridgeClient.onboardingSetupDialog.lblOpenAIStatus.Text == "Configured") "Configured status missing"
    assertSetup (bridgeClient.onboardingSetupDialog.lblClaudeCodeStatus.Text == "Claude Code CLI not found") "Absent client status missing"
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Claude Code > Local" == undefined) "Generic instructions leaked into another client's action"
    assertSetup (bridgeClient.onboardingSetupDialog.btnClaudeCode.get_Enabled()) "Missing Claude CLI disabled installation"
    assertSetup (bridgeClient.onboardingSetupDialog.btnClaudeCode.Text == "Install Claude Code") "Missing Claude install caption"
    assertSetup (not (bridgeClient.installAgentIntegration "claudeCode")) "Declined confirmation launched installation"
    fixtureConfirmInstall = true
    assertSetup (bridgeClient.installAgentIntegration "claudeCode") "Confirmed installation was not dispatched"
    assertSetup (bridgeClient.integrationOperationName == #installCli) "Install click registered MCP instead of installing the CLI"
    assertSetup (bridgeClient.onboardingSetupDialog.prgCliInstall.get_Visible()) "CLI installation has no visible progress bar"
    assertSetup (bridgeClient.onboardingSetupDialog.prgCliInstall.Style == (dotNetClass "System.Windows.Forms.ProgressBarStyle").Marquee) "Installer progress invents a percentage"
    setINISetting fixtureResultPath "operation" "action" "installcli"
    setINISetting fixtureResultPath "operation" "stages" "Running official installer (download and installation)...|Installer finished. Rediscovering and verifying the CLI..."
    setINISetting fixtureResultPath "operation" "stageKinds" "info|info"
    setINISetting fixtureResultPath "operation" "message" "Installer finished. Rediscovering and verifying the CLI..."
    bridgeClient.refreshOnboardingDialog()
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Running official installer" < findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "verifying the CLI") "Observed CLI stages are not chronological"
    local beforeStageCount = bridgeClient.integrationActionSteps.count
    local firstStageStamp = bridgeClient.integrationActionSteps[1][1]
    bridgeClient.refreshOnboardingDialog()
    assertSetup (bridgeClient.integrationActionSteps.count == beforeStageCount) "Polling duplicated stage history"
    assertSetup (bridgeClient.integrationActionSteps[1][1] == firstStageStamp) "Polling regenerated an event timestamp"
    for stageEntry in bridgeClient.integrationActionSteps do assertSetup ((dotNetClass "System.Text.RegularExpressions.Regex").IsMatch stageEntry[1] "^[0-9]{2}:[0-9]{2}:[0-9]{2} > [^\r\n]+$") "Event lacks local time, spaced chevron or single-line message"
    bridgeClient.onboardingSetupDialog.txtClientDetail.Select ((findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Running official installer") - 1) 1
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionColor == (bridgeClient.activityEntryColor " [info]")) "Running action is not informational blue"
    bridgeClient.appendIntegrationStep "Verified synthetic success." kindValue: #success
    bridgeClient.renderIntegrationDetail "" false
    bridgeClient.onboardingSetupDialog.txtClientDetail.Select ((findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Verified synthetic success.") - 1) 1
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionColor == (bridgeClient.activityEntryColor " [success]")) "Verified success is not green"
    bridgeClient.onboardingSetupDialog.txtClientDetail.Select bridgeClient.onboardingSetupDialog.txtClientDetail.TextLength 0
    assertSetup (bridgeClient.onboardingSetupDialog.prgCliInstall.MarqueeAnimationSpeed > 0) "Active CLI stage stopped its animation"
    assertSetup (bridgeClient.refreshAgentIntegrationStatus()) "Cancel action was not accepted"
    assertSetup (doesFileExist (fixtureResultPath + ".cancel")) "Cancel action did not signal the helper"
    deleteFile (fixtureResultPath + ".cancel")
    setINISetting fixtureResultPath "operation" "action" "status"
    fixtureConfirmInstall = false
    bridgeClient.integrationBusy = false
    setFixtureClient "claudeCode" "not_configured" "true"
    bridgeClient.refreshOnboardingDialog()
    assertSetup (bridgeClient.onboardingSetupDialog.btnClaudeCode.Text == "Connect to Claude Code") "Verified installation did not expose Connect"
    assertSetup (not (bridgeClient.onboardingSetupDialog.prgCliInstall.get_Visible())) "Finished installation kept its progress bar"
    assertSetup (bridgeClient.installAgentIntegration "claudeCode") "Separate Connect was not dispatched"
    assertSetup (bridgeClient.integrationOperationName == #install) "Connect did not register MCP"
    bridgeClient.integrationBusy = false
    setFixtureClient "claudeCode" "check_failed" "true"
    bridgeClient.refreshOnboardingDialog()
    assertSetup (not (bridgeClient.onboardingSetupDialog.btnClaudeCode.get_Enabled())) "Failed CLI check offered installation or connection"
    assertSetup (bridgeClient.onboardingSetupDialog.prgCliInstall.MarqueeAnimationSpeed == 0) "Failed operation kept progress animation running"
    assertSetup (bridgeClient.onboardingSetupDialog.lblAntigravityStatus.Text == "Error") "Setup failure was hidden"
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Refresh status" != undefined) "Error explanation missing"
    -- A stale Claude failure cannot color or contaminate an Antigravity action.
    setFixtureClient "claudeCode" "cli_install_failed" "false"
    setINISetting fixtureResultPath "claudeCode" "detail" "Synthetic Claude failure must remain on its own card."
    setFixtureClient "antigravity" "cli_missing" "false"
    setINISetting fixtureResultPath "antigravity" "desktopState" "missing"
    setINISetting fixtureResultPath "antigravity" "desktopAvailable" "false"
    bridgeClient.integrationBusy = false
    fixtureBrowserSucceeds = false
    bridgeClient.integrationOperationName = #installCli
    setINISetting fixtureResultPath "operation" "action" "installcli"
    setINISetting fixtureResultPath "operation" "stages" "Synthetic stale Claude install stage"
    assertSetup (not (bridgeClient.installAgentIntegration "antigravity")) "Browser failure claimed success"
    assertSetup bridgeClient.integrationActionFailed "Browser failure was not marked"
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Antigravity - open download page" != undefined) "Error did not identify the requested action"
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Claude" == undefined) "Antigravity error includes stale Claude failure"
    bridgeClient.onboardingSetupDialog.txtClientDetail.Select ((findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Antigravity - open download page") - 1) 1
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionColor == (bridgeClient.activityEntryColor " [error]")) "Selected browser failure is not visibly an error"
    bridgeClient.onboardingSetupDialog.txtClientDetail.Select 0 1
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionColor == (bridgeClient.activityEntryColor " [info]")) "Informational guidance is not blue"
    fixtureBrowserSucceeds = true
    assertSetup (bridgeClient.installAgentIntegration "antigravity") "Browser retry did not succeed"
    assertSetup (not bridgeClient.integrationActionFailed and not bridgeClient.integrationBusy) "Browser retry retained failure or launched a CLI"
    assertSetup (fixtureBrowserUrls[fixtureBrowserUrls.count] == "https://antigravity.google/download") "Antigravity opened the wrong vendor page"
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "Claude" == undefined) "Successful Antigravity action includes stale Claude failure"
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.ForeColor == MaxUltraMcpTheme.textColor) "Successful retry retained red error styling"
    assertSetup (not (bridgeClient.onboardingSetupDialog.prgCliInstall.get_Visible())) "Manual desktop handoff claimed an active download"
    -- Both components missing: CLI confirmation and installation must precede browser launch.
    setFixtureClient "claudeCode" "cli_missing" "false"
    setINISetting fixtureResultPath "claudeCode" "desktopState" "missing"
    local beforeBrowserCount = fixtureBrowserUrls.count
    fixtureConfirmInstall = true
    assertSetup (bridgeClient.installAgentIntegration "claudeCode") "Missing CLI was not installed first"
    assertSetup (bridgeClient.integrationOperationName == #installCli and fixtureBrowserUrls.count == beforeBrowserCount) "Desktop page opened before CLI verification"
    bridgeClient.integrationBusy = false
    fixtureConfirmInstall = false
    setFixtureClient "claudeCode" "not_configured" "true"
    setINISetting fixtureResultPath "claudeCode" "desktopState" "missing"
    assertSetup (bridgeClient.installAgentIntegration "claudeCode") "Present CLI and missing desktop did not open the page"
    assertSetup (fixtureBrowserUrls[fixtureBrowserUrls.count] == "https://claude.com/download") "Wrong Claude desktop page"
    -- Exercise the asynchronous CLI completion path, not just a direct browser click.
    bridgeClient.integrationActiveClient = "claudeCode"
    bridgeClient.integrationOperationName = #installCli
    bridgeClient.integrationBusy = true
    bridgeClient.integrationProcess = SetupFinishedProcessFixture()
    setINISetting fixtureResultPath "operation" "action" "installcli"
    setINISetting fixtureResultPath "operation" "stages" "Setup CLI installed and verified."
    bridgeClient.updateIntegrationProgress true
    assertSetup (bridgeClient.onboardingSetupDialog.prgCliInstall.get_Visible()) "Fixture did not start actual native progress control"
    assertSetup (not (bridgeClient.openDesktopDownloadPage "claudeCode")) "Browser handoff interrupted automatic CLI work"
    assertSetup (bridgeClient.pollIntegrationOperation()) "CLI completion polling failed"
    assertSetup (not bridgeClient.integrationBusy and bridgeClient.integrationOperationName == #desktopManualWait) "Browser handoff retained automatic-work state"
    for pollIndex in 1 to 5 do (
        bridgeClient.refreshOnboardingDialog()
        bridgeClient.pollIntegrationOperation()
        assertSetup (not (bridgeClient.onboardingSetupDialog.prgCliInstall.get_Visible())) "Repeated polling restored manual-wait progress"
        assertSetup (bridgeClient.onboardingSetupDialog.prgCliInstall.MarqueeAnimationSpeed == 0) "Browser handoff kept the animation running"
    )
    assertSetup (bridgeClient.onboardingSetupDialog.lblClaudeCodeStatus.Text != "Installing...") "Manual desktop wait still says Installing"
    assertSetup (bridgeClient.integrationActionSteps.count == 1) "Manual wait retained obsolete automatic-work stages"
    assertSetup (findString bridgeClient.onboardingSetupDialog.txtClientDetail.Text "opened browser page" != undefined) "Manual installation next step missing"
    assertSetup (matchPattern bridgeClient.onboardingSetupDialog.txtClientDetail.Text pattern: "*After installation, click Refresh status, then click Connect to Claude Code on the same card to finish setting up the connection.") "Manual wait does not end with both selected-client next actions on the same card"
    setFixtureClient "claudeCode" "not_configured" "true"
    beforeBrowserCount = fixtureBrowserUrls.count
    assertSetup (not (bridgeClient.openDesktopDownloadPage "claudeCode")) "Existing desktop triggered download page"
    assertSetup (fixtureBrowserUrls.count == beforeBrowserCount) "Existing desktop was not preserved"
    bridgeClient.integrationActionMessage = ""
    bridgeClient.integrationActiveClient = ""
    bridgeClient.integrationActionSteps = #()
    for eventIndex in 1 to 25 do bridgeClient.appendIntegrationStep ("Synthetic setup event " + (eventIndex as string)) kindValue: #info
    bridgeClient.renderIntegrationDetail "Newest synthetic setup event." false
    assertSetup (bridgeClient.integrationActionSteps.count == 20) "Setup event history is unbounded"
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionStart == bridgeClient.onboardingSetupDialog.txtClientDetail.TextLength) "New event did not move the caret to the bottom"
    assertSetup (bridgeClient.onboardingSetupDialog.txtClientDetail.SelectionColor == (bridgeClient.activityEntryColor " [info]")) "Latest guidance lost its informational color"
    bridgeClient.integrationActionSteps = #()
    bridgeClient.refreshOnboardingDialog()
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
