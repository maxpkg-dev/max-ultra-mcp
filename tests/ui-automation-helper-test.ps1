# Verifies direct HWND capture and bounded UI diagnostics against a synthetic 3dsmax.exe WinForms process.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-UiHelper([int]$ProcessId, [string]$Operation, $Payload, [string]$HelperPath) {
    $payloadJson = $Payload | ConvertTo-Json -Depth 8 -Compress
    $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson))
    $helperOutput = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $HelperPath -TargetProcessId $ProcessId -Operation $Operation -PayloadBase64 $payloadBase64 2>&1
    if ($LASTEXITCODE -ne 0) { throw "UI helper $Operation failed: $($helperOutput -join [Environment]::NewLine)" }
    return ($helperOutput | Select-Object -Last 1) | ConvertFrom-Json
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$helperPath = Join-Path $repositoryRoot 'scripts\max-ui-automation.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-ui-helper-' + [Guid]::NewGuid().ToString('N'))
$fixturePath = Join-Path $testRoot '3dsmax.exe'
$handlePath = Join-Path $testRoot 'window-handle.txt'
$capturePath = Join-Path $testRoot 'fixture-window.png'
$fixtureProcess = $null

try {
    [void](New-Item -ItemType Directory -Path $testRoot)
    $fixtureSource = @'
using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

public static class FixtureProgram {
    [STAThread]
    public static void Main(string[] args) {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Form form = new Form();
        form.Text = "Max Ultra MCP Synthetic UI";
        form.Name = "SyntheticMaxWindow";
        form.Size = new Size(420, 260);
        Panel panel = new Panel();
        panel.Name = "ContentPanel";
        panel.Dock = DockStyle.Fill;
        Button button = new Button();
        button.Name = "ApplyButton";
        button.Text = "Apply";
        button.Location = new Point(24, 24);
        panel.Controls.Add(button);
        form.Controls.Add(panel);
        form.HandleCreated += delegate { File.WriteAllText(args[0], form.Handle.ToInt64().ToString()); };
        Application.Run(form);
    }
}
'@
    Add-Type -TypeDefinition $fixtureSource -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing') -OutputAssembly $fixturePath -OutputType WindowsApplication
    $fixtureProcess = Start-Process -FilePath $fixturePath -ArgumentList @($handlePath) -PassThru -WindowStyle Hidden

    $windowHandle = 0
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and $windowHandle -eq 0) {
        Start-Sleep -Milliseconds 100
        if (Test-Path -LiteralPath $handlePath) {
            $windowHandle = [int64](Get-Content -Raw -LiteralPath $handlePath)
        }
    }
    Assert-True ($windowHandle -gt 0) 'Synthetic WinForms fixture did not create a top-level HWND'

    $captureResponse = Invoke-UiHelper $fixtureProcess.Id 'capture' @{
        window = @{ hwnd = $windowHandle }
        outputPath = $capturePath
    } $helperPath
    Assert-True ([bool]$captureResponse.ok) 'Direct HWND capture did not report success'
    Assert-True ($captureResponse.data.selectorSource -eq 'hwnd') 'Direct capture did not use the HWND path'
    Assert-True (@('printWindow', 'screenCopyFallback') -contains $captureResponse.data.captureMethod) 'Direct capture returned an unknown capture method'
    Assert-True ($captureResponse.data.width -gt 0 -and $captureResponse.data.height -gt 0) 'Direct capture returned invalid dimensions'
    Assert-True (Test-Path -LiteralPath $capturePath -PathType Leaf) 'Direct capture did not create a PNG'
    Assert-True ((Get-Item -LiteralPath $capturePath).Length -gt 0) 'Direct capture created an empty PNG'

    $diagnosticResponse = Invoke-UiHelper $fixtureProcess.Id 'diagnose' @{
        window = @{ hwnd = $windowHandle }
        maxDepth = 4
        limit = 50
    } $helperPath
    Assert-True ([bool]$diagnosticResponse.ok) 'UI diagnostics did not report success'
    Assert-True ($diagnosticResponse.data.selectorSource -eq 'hwnd') 'UI diagnostics did not use the HWND path'
    Assert-True ($diagnosticResponse.data.native.count -ge 1) 'UI diagnostics returned no native controls'
    Assert-True ($diagnosticResponse.data.native.count -le 50) 'UI diagnostics exceeded its requested limit'
    Assert-True (($diagnosticResponse.data.native.controls | Where-Object { $_.isWinForms }).Count -ge 1) 'UI diagnostics did not identify a WinForms HWND'
    Assert-True ($null -ne $diagnosticResponse.data.webBrowsers) 'UI diagnostics omitted the stable webBrowsers array'

    Write-Output 'UI automation helper test passed.'
} finally {
    if ($null -ne $fixtureProcess -and -not $fixtureProcess.HasExited) {
        [void]$fixtureProcess.CloseMainWindow()
        if (-not $fixtureProcess.WaitForExit(2000)) { Stop-Process -Id $fixtureProcess.Id -Force -ErrorAction SilentlyContinue }
    }
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
