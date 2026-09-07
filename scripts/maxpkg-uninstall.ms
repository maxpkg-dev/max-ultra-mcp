-- Focused MaxPkg cleanup hook. Standard MaxPkg handles package files, macros, and icons.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl
(
    fn maxUltraMcpQuoteUninstallArgument sourceContent = (
        local quoteCharacter = bit.intAsChar 34
        local argumentContent = sourceContent as string
        if ((findString argumentContent quoteCharacter) != undefined or (findString argumentContent "\r") != undefined or (findString argumentContent "\n") != undefined) do throw "An uninstall process argument contains unsupported characters"

        -- Windows command-line parsing consumes a backslash immediately before
        -- a closing quote. Double every trailing backslash so package folders
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
    )

    -- Resolve the system host independently of the launching process PATH.
    fn maxUltraMcpResolveWindowsExecutable executableRelativePath = (
        local environmentClass = dotNetClass "System.Environment"
        local pathClass = dotNetClass "System.IO.Path"
        local fileClass = dotNetClass "System.IO.File"
        local systemDirectory = environmentClass.SystemDirectory
        local candidateDirectories = #()
        if (environmentClass.Is64BitOperatingSystem and not environmentClass.Is64BitProcess) do (
            local windowsDirectory = pathClass.GetDirectoryName systemDirectory
            append candidateDirectories (pathClass.Combine windowsDirectory "Sysnative")
        )
        append candidateDirectories systemDirectory
        for candidateDirectory in candidateDirectories do (
            local executablePath = pathClass.Combine candidateDirectory executableRelativePath
            if (fileClass.Exists executablePath) do return executablePath
        )
        throw ("WINDOWS_EXECUTABLE_NOT_FOUND: " + executableRelativePath + " was not found in the Windows system directories. Check the Windows installation; PATH is not used.")
    )

    fn maxUltraMcpValidateWorkingDirectory directoryPath = (
        if (directoryPath == undefined or directoryPath == "") do throw "PROCESS_WORKING_DIRECTORY_MISSING: The package helper directory is empty."
        local fullDirectoryPath = (dotNetClass "System.IO.Path").GetFullPath directoryPath
        if (not ((dotNetClass "System.IO.Directory").Exists fullDirectoryPath)) do throw ("PROCESS_WORKING_DIRECTORY_MISSING: The package helper directory no longer exists or cannot be accessed: " + fullDirectoryPath)
        return fullDirectoryPath
    )

    local hookFilePath = getThisScriptFileName()
    local hookDirectory = getFilenamePath hookFilePath
    local cleanupScriptPath = hookDirectory + "maxpkg-uninstall.ps1"
    if (not (doesFileExist cleanupScriptPath)) do throw "Max Ultra MCP uninstall helper was not found"

    local packageRoot = (dotNetClass "System.IO.Path").GetFullPath (hookDirectory + "..\\")
    local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
    startInfo.FileName = maxUltraMcpResolveWindowsExecutable @"WindowsPowerShell\v1.0\powershell.exe"
    startInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + (maxUltraMcpQuoteUninstallArgument cleanupScriptPath) + " -PackageRoot " + (maxUltraMcpQuoteUninstallArgument packageRoot)
    startInfo.WorkingDirectory = maxUltraMcpValidateWorkingDirectory hookDirectory
    startInfo.UseShellExecute = false
    startInfo.CreateNoWindow = true
    startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true

    local cleanupProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
    if (cleanupProcess == undefined) do throw "Windows could not start Max Ultra MCP uninstall cleanup"
    if (not (cleanupProcess.WaitForExit 30000)) do (
        try (cleanupProcess.Kill()) catch ()
        cleanupProcess.Dispose()
        throw "Max Ultra MCP uninstall cleanup timed out"
    )
    local cleanupExitCode = cleanupProcess.ExitCode
    local cleanupError = try (trimString (cleanupProcess.StandardError.ReadToEnd())) catch ("")
    local cleanupOutput = try (trimString (cleanupProcess.StandardOutput.ReadToEnd())) catch ("")
    cleanupProcess.Dispose()
    if (cleanupExitCode != 0) do (
        local cleanupFailure = if cleanupError != "" then cleanupError else cleanupOutput
        if cleanupFailure == "" then cleanupFailure = "The cleanup helper returned exit code " + (cleanupExitCode as string)
        throw ("Max Ultra MCP uninstall cleanup failed: " + cleanupFailure)
    )
    true
)
