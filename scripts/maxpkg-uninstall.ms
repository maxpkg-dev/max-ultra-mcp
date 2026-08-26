-- Focused MaxPkg cleanup hook. Standard MaxPkg handles package files, macros, and icons.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl
(
    local hookFilePath = getThisScriptFileName()
    local hookDirectory = getFilenamePath hookFilePath
    local cleanupScriptPath = hookDirectory + "maxpkg-uninstall.ps1"
    if (not (doesFileExist cleanupScriptPath)) do throw "Max Ultra MCP uninstall helper was not found"

    local packageRoot = (dotNetClass "System.IO.Path").GetFullPath (hookDirectory + "..\\")
    local startInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
    startInfo.FileName = "powershell.exe"
    startInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + cleanupScriptPath + "\" -PackageRoot \"" + packageRoot + "\""
    startInfo.WorkingDirectory = hookDirectory
    startInfo.UseShellExecute = false
    startInfo.CreateNoWindow = true
    startInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden

    local cleanupProcess = (dotNetClass "System.Diagnostics.Process").Start startInfo
    if (cleanupProcess == undefined) do throw "Windows could not start Max Ultra MCP uninstall cleanup"
    if (not (cleanupProcess.WaitForExit 15000)) do (
        try (cleanupProcess.Kill()) catch ()
        throw "Max Ultra MCP uninstall cleanup timed out"
    )
    local cleanupExitCode = cleanupProcess.ExitCode
    cleanupProcess.Dispose()
    if (cleanupExitCode != 0) do throw "Max Ultra MCP uninstall cleanup failed"
    true
)
