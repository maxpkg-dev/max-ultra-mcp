/*
 * Isolated updater path regression checks; does not install packages or touch scenes.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
(
    local testsDirectory = getFilenamePath (getThisScriptFileName())
    local bootstrapSource = (dotNetClass "System.IO.File").ReadAllText (testsDirectory + @"..\01_START_MAX_ULTRA_MCP_FIRST.ms")
    local validationLines = #()
    for sourceLine in (filterString bootstrapSource "\n") do (
        if ((findString sourceLine "pendingPackageIsValid = normalizedPackagePath.count") != undefined or (findString sourceLine "local packageIsInsideUpdatesRoot =") != undefined) do append validationLines sourceLine
    )
    if (validationLines.count != 2) do throw "Updater validation boundaries changed"
    local fixtureRoot = @"C:\UpdateFixture\updates\"
    local fixtureCases = #(
        #(@"C:\UpdateFixture\updates\package.mzp", true),
        #(@"c:\updatefixture\UPDATES\nested\package.mzp", true),
        #(@"C:\UpdateFixture\updates-other\package.mzp", false),
        #(@"C:\UpdateFixture\updates\..\package.mzp", false),
        #(@"C:\UpdateFixture\package.mzp", false),
        #(@"D:\UpdateFixture\updates\package.mzp", false),
        #(@"C:\", false)
    )
    local assertionCount = 0
    for validationIndex in 1 to validationLines.count do (
        for fixtureCase in fixtureCases do (
            local testSource = "(local normalizedPackagePath = (dotNetClass \"System.IO.Path\").GetFullPath @\"" + fixtureCase[1] + "\"\n"
            testSource += "local normalizedUpdateRoot = @\"" + fixtureRoot + "\"\nlocal normalizedUpdatesRoot = normalizedUpdateRoot\n"
            testSource += "local comparisonClass = dotNetClass \"System.StringComparison\"\nlocal stringComparisonClass = comparisonClass\nlocal pendingPackageIsValid = false\n"
            testSource += validationLines[validationIndex] + "\n"
            testSource += (if (validationIndex == 1) then "pendingPackageIsValid)" else "packageIsInsideUpdatesRoot)")
            local actualValidation = execute testSource
            if (actualValidation != fixtureCase[2]) do throw ("Updater containment case failed: " + (validationIndex as string) + "/" + ((assertionCount + 1) as string))
            assertionCount += 1
        )
    )
    #("passed", assertionCount, "no installs, no bridge start, no scene changes")
)
