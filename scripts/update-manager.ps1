# Checks and stages a verified MaxPkg update from the official GitHub Releases feed.
# Network work uses curl.exe inside this already detached helper process.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CheckAndStage')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$ResultFile,

    [string]$ReleaseMetadataFile = ''
)

$ErrorActionPreference = 'Stop'
function Get-MaxUltraSha256Hash {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $stream = [IO.File]::OpenRead([IO.Path]::GetFullPath($LiteralPath))
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $stream.Dispose()
        $algorithm.Dispose()
    }
}
$expectedRepository = 'maxpkg-dev/max-ultra-mcp'
$packageGuid = 'c6977570-25a6-41b0-b9bb-b3be8101123c'
$normalizedRoot = [IO.Path]::GetFullPath($ProjectRoot)
$versionIniPath = Join-Path $normalizedRoot 'version.ini'
$stateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($ResultFile))
$stagingDirectory = Join-Path $stateDirectory 'updates'
$utf8WithoutBom = New-Object Text.UTF8Encoding($false)
$temporaryFiles = New-Object Collections.Generic.List[string]
$temporarySuffix = ".tmp-$PID-$([Guid]::NewGuid().ToString('N'))"

. (Join-Path $normalizedRoot 'scripts\project-version.ps1')

function Write-UpdateResult {
    param(
        [string]$State,
        [string]$CurrentVersion,
        [string]$LatestVersion,
        [string]$PackagePath,
        [string]$Message
    )

    foreach ($value in @($State, $CurrentVersion, $LatestVersion, $PackagePath, $Message)) {
        if ($value -match '[\r\n]') { throw 'Update result values must be single-line text.' }
    }
    $lines = @(
        '[update]',
        "state=$State",
        "currentVersion=$CurrentVersion",
        "latestVersion=$LatestVersion",
        "packagePath=$PackagePath",
        "message=$Message"
    )
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    [IO.File]::WriteAllLines($ResultFile, $lines, $utf8WithoutBom)
}

function Get-CurlExecutable {
    $windowsDirectory = [Environment]::GetFolderPath('Windows')
    if (-not [string]::IsNullOrWhiteSpace($windowsDirectory)) {
        $systemCurl = Join-Path $windowsDirectory 'System32\curl.exe'
        if (Test-Path -LiteralPath $systemCurl -PathType Leaf) { return $systemCurl }
    }

    $curlCommand = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $curlCommand) { return $curlCommand.Source }
    throw 'Windows curl.exe is unavailable.'
}

function ConvertTo-CurlArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '[\r\n"]') { throw 'A curl argument contains unsupported characters.' }
    return '"' + $Value + '"'
}

function Invoke-CurlDownload {
    param(
        [Parameter(Mandatory = $true)][string]$CurlExecutable,
        [Parameter(Mandatory = $true)][Uri]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [ValidateRange(10, 300)][int]$TimeoutSeconds = 90,
        [string]$Accept = '*/*'
    )

    if ($Uri.Scheme -ne 'https') { throw 'Update downloads require HTTPS.' }
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
    Remove-Item -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue

    $arguments = @(
        '--silent', '--show-error', '--location', '--fail',
        '--connect-timeout', '12', '--max-time', [string]$TimeoutSeconds,
        '--retry', '2', '--retry-delay', '1',
        '--user-agent', (ConvertTo-CurlArgument 'Max-Ultra-MCP-Updater/1.0'),
        '--header', (ConvertTo-CurlArgument "Accept: $Accept"),
        '--header', (ConvertTo-CurlArgument 'Cache-Control: no-cache, no-store, max-age=0'),
        '--output', (ConvertTo-CurlArgument $destinationPath),
        '--write-out', (ConvertTo-CurlArgument '%{http_code}'),
        (ConvertTo-CurlArgument $Uri.AbsoluteUri)
    ) -join ' '

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $CurlExecutable
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'curl.exe could not be started.' }
        if (-not $process.WaitForExit(($TimeoutSeconds + 10) * 1000)) {
            try { $process.Kill() } catch {}
            throw 'curl.exe exceeded the bounded update timeout.'
        }
        $statusText = $process.StandardOutput.ReadToEnd().Trim()
        $errorText = $process.StandardError.ReadToEnd().Trim()
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    $statusCode = 0
    [void][int]::TryParse($statusText, [ref]$statusCode)
    if ($exitCode -ne 0) {
        Remove-Item -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue
        $detail = if ([string]::IsNullOrWhiteSpace($errorText)) { "curl.exe failed with exit code $exitCode." } else { $errorText }
        $exception = New-Object InvalidOperationException($detail)
        $exception.Data['HttpStatusCode'] = $statusCode
        throw $exception
    }
    if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
        throw 'curl.exe completed without creating the requested file.'
    }
    return $statusCode
}

function Remove-TemporaryUpdateFiles {
    foreach ($temporaryFile in $temporaryFiles) {
        if ([string]::IsNullOrWhiteSpace($temporaryFile)) { continue }
        Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
    }
}

function Remove-StaleUpdateTemporaryFiles {
    $cutoff = [DateTime]::UtcNow.AddHours(-6)
    foreach ($temporaryDirectory in @($stateDirectory, $stagingDirectory)) {
        if (-not (Test-Path -LiteralPath $temporaryDirectory -PathType Container)) { continue }
        foreach ($staleFile in Get-ChildItem -LiteralPath $temporaryDirectory -File -ErrorAction SilentlyContinue) {
            if ($staleFile.Name -match '\.tmp-[0-9]+-[0-9a-fA-F]{32}(?:\.json)?$' -and $staleFile.LastWriteTimeUtc -lt $cutoff) {
                Remove-Item -LiteralPath $staleFile.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

$currentVersion = ''
Remove-StaleUpdateTemporaryFiles
try {
    $currentInfo = Get-MaxUltraProjectVersionInfo -VersionIniPath $versionIniPath
    $currentVersion = $currentInfo.Version
    $curlExecutable = ''

    $release = if ([string]::IsNullOrWhiteSpace($ReleaseMetadataFile)) {
        $curlExecutable = Get-CurlExecutable
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        $releaseMetadataPath = Join-Path $stateDirectory ("release-metadata$temporarySuffix.json")
        $temporaryFiles.Add($releaseMetadataPath)
        [void](Invoke-CurlDownload -CurlExecutable $curlExecutable -Uri ([Uri]"https://api.github.com/repos/$expectedRepository/releases/latest") -Destination $releaseMetadataPath -TimeoutSeconds 30 -Accept 'application/vnd.github+json')
        Get-Content -LiteralPath $releaseMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        Get-Content -LiteralPath $ReleaseMetadataFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    if ($release.draft -or $release.prerelease) { throw 'The latest GitHub Release is not stable.' }
    $latestInfo = ConvertTo-MaxUltraReleaseVersion -Text ([string]$release.tag_name) -AllowTagPrefix
    if ($latestInfo.Value.CompareTo($currentInfo.VersionValue) -le 0) {
        Remove-TemporaryUpdateFiles
        Write-UpdateResult -State 'current' -CurrentVersion $currentVersion -LatestVersion $latestInfo.Text -PackagePath '' -Message 'Max Ultra MCP is current.'
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($curlExecutable)) { $curlExecutable = Get-CurlExecutable }
    $expectedPackageName = "max-ultra-mcp@$($latestInfo.Text)@$packageGuid.mzp"
    $expectedChecksumName = "$expectedPackageName.sha256"
    $packageAssets = @($release.assets | Where-Object { $_.name -ceq $expectedPackageName })
    $checksumAssets = @($release.assets | Where-Object { $_.name -ceq $expectedChecksumName })
    if ($packageAssets.Count -ne 1 -or $checksumAssets.Count -ne 1) {
        throw 'The GitHub Release does not contain exactly one expected MZP and checksum asset.'
    }
    foreach ($assetUrl in @([string]$packageAssets[0].browser_download_url, [string]$checksumAssets[0].browser_download_url)) {
        $assetUri = [Uri]$assetUrl
        if ($assetUri.Scheme -ne 'https' -or $assetUri.Host -ne 'github.com') {
            throw 'A release asset URL is outside the expected GitHub HTTPS host.'
        }
    }

    New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
    $packagePath = Join-Path $stagingDirectory $expectedPackageName
    $checksumPath = Join-Path $stagingDirectory $expectedChecksumName
    $temporaryPackagePath = $packagePath + $temporarySuffix
    $temporaryChecksumPath = $checksumPath + $temporarySuffix
    $temporaryFiles.Add($temporaryPackagePath)
    $temporaryFiles.Add($temporaryChecksumPath)
    Remove-Item -LiteralPath $temporaryPackagePath,$temporaryChecksumPath -Force -ErrorAction SilentlyContinue
    [void](Invoke-CurlDownload -CurlExecutable $curlExecutable -Uri ([Uri]$packageAssets[0].browser_download_url) -Destination $temporaryPackagePath -TimeoutSeconds 120)
    [void](Invoke-CurlDownload -CurlExecutable $curlExecutable -Uri ([Uri]$checksumAssets[0].browser_download_url) -Destination $temporaryChecksumPath -TimeoutSeconds 30)

    $checksumLine = ([IO.File]::ReadAllText($temporaryChecksumPath)).Trim()
    $checksumMatch = [regex]::Match($checksumLine, '^(?<hash>[0-9a-fA-F]{64})\s+\*?(?<file>[^\r\n]+)$')
    if (-not $checksumMatch.Success -or $checksumMatch.Groups['file'].Value -cne $expectedPackageName) {
        throw 'The release checksum file has an invalid format or filename.'
    }
    $actualHash = (Get-MaxUltraSha256Hash -LiteralPath $temporaryPackagePath)
    if (-not [string]::Equals($actualHash, $checksumMatch.Groups['hash'].Value, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The staged MZP SHA-256 does not match the published checksum.'
    }

    Move-Item -LiteralPath $temporaryPackagePath -Destination $packagePath -Force
    Move-Item -LiteralPath $temporaryChecksumPath -Destination $checksumPath -Force
    Remove-TemporaryUpdateFiles
    Write-UpdateResult -State 'ready' -CurrentVersion $currentVersion -LatestVersion $latestInfo.Text -PackagePath $packagePath -Message "Version $($latestInfo.Text) is staged. It will be installed and Max Ultra MCP will restart automatically."
}
catch {
    Remove-TemporaryUpdateFiles
    $httpStatusCode = 0
    try { $httpStatusCode = [int]$_.Exception.Data['HttpStatusCode'] } catch {}
    if ($httpStatusCode -eq 404) {
        Write-UpdateResult -State 'current' -CurrentVersion $currentVersion -LatestVersion '' -PackagePath '' -Message 'No stable GitHub Release is published yet.'
        exit 0
    }

    $safeMessage = ($_.Exception.Message -replace '[\r\n]+', ' ').Trim()
    Write-UpdateResult -State 'error' -CurrentVersion $currentVersion -LatestVersion '' -PackagePath '' -Message $safeMessage
    exit 1
}
