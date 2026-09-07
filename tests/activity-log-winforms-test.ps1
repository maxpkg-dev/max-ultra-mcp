# Verifies read-only Activity trimming against isolated hidden Windows RichTextBox controls.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

param([switch]$VerifyLegacyFailure)

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Normalize-LineEndings([string]$Content) {
    return $Content.Replace("`r`n", "`n").Replace("`r", "`n")
}

# This uses the same nonempty RTF stream as production, avoiding WM_CLEAR.
function Remove-ActivityPrefix($Control, [int]$CharacterCount) {
    if ($CharacterCount -le 0) { return }
    $Control.Select(0, $CharacterCount)
    $Control.SelectedRtf = '{\rtf1\ansi}'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$bootstrapSource = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot '01_START_MAX_ULTRA_MCP_FIRST.ms')
$refreshMatch = [regex]::Match($bootstrapSource, '(?s)fn refreshActivityText\b(?<body>.*?)\r?\n\s*fn ')
Assert-True ($refreshMatch.Success -and $refreshMatch.Groups['body'].Value.Contains('activityDialog.rtbActivity.SelectedRtf = "{\\rtf1\\ansi}"')) 'Rolling Activity updates must remove the oldest entry through the nonempty RTF stream'
Assert-True (-not [regex]::IsMatch($refreshMatch.Groups['body'].Value, '\.SelectedText\s*=\s*""')) 'Rolling Activity updates must not use the rejected WM_CLEAR path'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$logControl = New-Object System.Windows.Forms.RichTextBox
$retainedFont = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$linkFont = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Underline)
$retainedColor = [System.Drawing.Color]::FromArgb(120, 225, 150)
$retainedBackground = [System.Drawing.Color]::FromArgb(40, 45, 50)
$linkColor = [System.Drawing.Color]::FromArgb(90, 170, 240)

try {
    # Force a real RichEdit HWND, but never show a window or attach to 3ds Max.
    $logControl.ReadOnly = $true
    [void]$logControl.Handle
    $logControl.Text = "old entry`nretained badge Donate"
    $logControl.Select(10, 14)
    $logControl.SelectionColor = $retainedColor
    $logControl.SelectionBackColor = $retainedBackground
    $logControl.SelectionFont = $retainedFont
    $logControl.Select(25, 6)
    $logControl.SelectionColor = $linkColor
    $logControl.SelectionBackColor = $logControl.BackColor
    $logControl.SelectionFont = $linkFont

    # Opt in because the old WM_CLEAR path can emit a system beep.
    if ($VerifyLegacyFailure) {
        $logControl.Select(0, 10)
        $logControl.SelectedText = ''
        Assert-True ((Normalize-LineEndings $logControl.Text) -eq "old entry`nretained badge Donate") 'Fixture did not reproduce the rejected read-only deletion'
    }

    Remove-ActivityPrefix $logControl 10
    Assert-True ($logControl.Text -eq 'retained badge Donate') 'RTF trim did not remove only the old entry'
    Assert-True $logControl.ReadOnly 'RTF trim left the log user-editable'
    $logControl.Select(0, 14)
    Assert-True ($logControl.SelectionColor.ToArgb() -eq $retainedColor.ToArgb()) 'Trimming changed the retained entry color'
    Assert-True ($logControl.SelectionBackColor.ToArgb() -eq $retainedBackground.ToArgb()) 'Trimming changed the retained badge background'
    Assert-True ($null -ne $logControl.SelectionFont -and $logControl.SelectionFont.Bold) 'Trimming changed the retained font style'
    $logControl.Select(15, 6)
    Assert-True ($logControl.SelectedText -eq 'Donate') 'Trimming did not retain the shifted donation link'
    Assert-True ($logControl.SelectionColor.ToArgb() -eq $linkColor.ToArgb()) 'Trimming changed the donation link color'
    Assert-True ($logControl.SelectionBackColor.ToArgb() -eq $logControl.BackColor.ToArgb()) 'Trimming spread badge color into the donation link'
    Assert-True ($null -ne $logControl.SelectionFont -and $logControl.SelectionFont.Underline) 'Trimming removed the donation link underline'

    # More than two windows of entries catches alternating trim/rebuild failures.
    $logControl.Clear()
    $expectedEntries = New-Object 'System.Collections.Generic.List[string]'
    for ($entryIndex = 1; $entryIndex -le 95; $entryIndex++) {
        if ($expectedEntries.Count -eq 30) {
            $firstEntryLength = (Normalize-LineEndings $logControl.Text).IndexOf("`n") + 1
            Assert-True ($firstEntryLength -gt 0) 'A full Activity buffer must have a removable first entry'
            Remove-ActivityPrefix $logControl $firstEntryLength
            $expectedEntries.RemoveAt(0)
        }
        $entryText = '00:00:00 [info] Entry ' + $entryIndex
        if ($logControl.TextLength -gt 0) { $logControl.AppendText("`r`n") }
        $logControl.SelectionColor = $retainedColor
        $logControl.AppendText($entryText)
        $expectedEntries.Add($entryText)
        Assert-True ((Normalize-LineEndings $logControl.Text) -eq ($expectedEntries -join "`n")) "Rolling update $entryIndex did not preserve exactly the latest entries"
        Assert-True ($expectedEntries.Count -le 30 -and $logControl.Lines.Count -le 30) 'Rolling Activity display exceeded its 30-entry limit'
        Assert-True $logControl.ReadOnly 'Rolling Activity update left the log user-editable'
    }

    # Do not hardcode read-only=true when a caller supplied an editable control.
    $logControl.ReadOnly = $false
    Remove-ActivityPrefix $logControl 1
    Assert-True (-not $logControl.ReadOnly) 'Trimming did not restore an originally editable control'
    $logControl.ReadOnly = $true

    Write-Output ('Activity log WinForms test passed (.NET ' + [Environment]::Version + ').')
} finally {
    $logControl.Dispose()
    $retainedFont.Dispose()
    $linkFont.Dispose()
}
