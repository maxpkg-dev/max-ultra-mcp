# Runs the local instruction-only skills helper outside the Max main thread.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('list','preview','preview-zip','import','import-zip','read','delete','picker')][string]$Action,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [string]$Source = '',
    [string]$Revision = '',
    [string]$Clients = '',
    [string]$SkillId = '',
    [string]$RelativePath = 'SKILL.md',
    [string]$Background = '',
    [string]$Foreground = '',
    [string]$ButtonBackground = '',
    [string]$ButtonHover = ''
)
$ErrorActionPreference = 'Stop'
if ($Action -eq 'picker') {
    try {
        Add-Type -Path (Join-Path $PSScriptRoot 'SkillsFolderPicker.cs') -OutputAssembly ($ResultPath + '.dll') -OutputType Library
        [IO.File]::WriteAllText($ResultPath, "[result]`nok=true`nmessage=`nhasList=false`ncount=0`n")
        exit 0
    }
    catch {
        $encodedMessage = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.Exception.Message))
        [IO.File]::WriteAllText($ResultPath, "[result]`nok=false`nmessage=$encodedMessage`nhasList=false`ncount=0`n")
        exit 1
    }
}
$runnerPath = Join-Path $PSScriptRoot 'run-node-script.ps1'
$helperArguments = @($Action)
switch ($Action) {
    'preview' { $helperArguments += $Source }
    'preview-zip' { $helperArguments += $Source }
    'import' { $helperArguments += @($Source, $Revision, $Clients) }
    'import-zip' { $helperArguments += @($Source, $Revision, $Clients) }
    'read' { $helperArguments += @($SkillId, $RelativePath) }
    'delete' { $helperArguments += $SkillId }
}
# PowerShell 5.1 may drop an empty native argument. No clients is encoded explicitly.
if ($Action -in @('import','import-zip') -and [string]::IsNullOrEmpty($Clients)) { $helperArguments[3] = 'none' }
$helperArguments += @('--result', $ResultPath)
if ($Background) { $helperArguments += @('--background', $Background) }
if ($Foreground) { $helperArguments += @('--foreground', $Foreground) }
if ($ButtonBackground) { $helperArguments += @('--buttonBackground', $ButtonBackground) }
if ($ButtonHover) { $helperArguments += @('--buttonHover', $ButtonHover) }
& $runnerPath 'core\skills-cli.js' @helperArguments
exit $LASTEXITCODE
