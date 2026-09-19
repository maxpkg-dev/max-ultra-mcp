/*
 * Runs isolated setup UI fixtures inside Max without starting a bridge or installing clients.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
(
    local testsDirectory = getFilenamePath (getThisScriptFileName())
    local projectDirectory = (dotNetClass "System.IO.Path").GetFullPath (testsDirectory + "..")
    local bootstrapPath = projectDirectory + @"\01_START_MAX_ULTRA_MCP_FIRST.ms"
    local bootstrapSource = (dotNetClass "System.IO.File").ReadAllText bootstrapPath
    local definitionsStart = findString bootstrapSource "    struct MaxUltraMcpControlReply ("
    local definitionsEnd = findString bootstrapSource "    bridgeClient = MaxUltraMcpBridgeClient sessionLaunchCount:"
    if (definitionsStart == undefined or definitionsEnd == undefined) do throw "Bootstrap definition boundary changed"
    local definitionsSource = substring bootstrapSource definitionsStart (definitionsEnd - definitionsStart)
    local launchStart = findString definitionsSource "        fn startIntegrationOperation "
    local launchEnd = findString definitionsSource "        fn refreshAgentIntegrationStatus "
    if (launchStart == undefined or launchEnd == undefined) do throw "Integration launch boundary changed"
    -- Replace only the process-launch seam. Real button events, routing, guards, and presentation run unchanged.
    local fakeLauncher = "fn startIntegrationOperation actionName installOpenAI: false installClaudeCode: false installAntigravity: false automaticCheck: false = (integrationOperationTimeoutSeconds = (if (installOpenAI) then 1 else 0) + (if (installClaudeCode) then 2 else 0) + (if (installAntigravity) then 4 else 0); integrationOperationName = actionName; integrationBusy = true; refreshOnboardingDialog(); return true),\n"
    definitionsSource = (substring definitionsSource 1 (launchStart - 1)) + fakeLauncher + (substring definitionsSource launchEnd -1)
    definitionsSource = substituteString definitionsSource "format \"[3DGROUND | Max Ultra MCP] SETUP STATUS ERROR | %\\n\" (getCurrentException() as string)" "throw()"
    local fixtureSource = (dotNetClass "System.IO.File").ReadAllText (testsDirectory + @"helpers\ai-setup-ui-fixture.ms")
    local quotedBootstrap = "@\"" + bootstrapPath + "\""
    local fixtureOutcome = execute ("(local bridgeClient\nlocal stagedUpdateStatus = \"\"\nlocal fixtureBootstrapPath = " + quotedBootstrap + "\n" + definitionsSource + "\n" + fixtureSource + "\n)")
    if (fixtureOutcome[1] != "passed") do throw (fixtureOutcome as string)
    fixtureOutcome
)
