# Serves relay.html and the files of one staging folder on 127.0.0.1 for the maxpkg.dev browser file relay.
# Read-only: it never writes, never lists folders, and serves only top-level .mzp and image files of the staging folder.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,
    [ValidateRange(1, 240)]
    [int]$IdleMinutes = 30
)

$ErrorActionPreference = 'Stop'
$stagingRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $stagingRoot -PathType Container)) { throw "Staging folder was not found: $Root" }
$relayPage = Join-Path $PSScriptRoot 'relay.html'
if (-not (Test-Path -LiteralPath $relayPage -PathType Leaf)) { throw 'relay.html must be next to serve-relay.ps1.' }
$contentTypes = @{
    '.mzp' = 'application/octet-stream'
    '.png' = 'image/png'
    '.jpg' = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.webp' = 'image/webp'
}
$allowedHosts = @("127.0.0.1:$Port", "localhost:$Port")
$indexText = "Max Ultra MCP file relay is running. Open /relay.html?target=<maxpkg.dev page URL>&files=<file names>."

function Send-Response {
    param($Stream, [int]$Status, [string]$Reason, [string]$ContentType, [byte[]]$Body, [bool]$HeadOnly)
    $header = "HTTP/1.1 $Status $Reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`nConnection: close`r`n`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if (-not $HeadOnly -and $Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}

function Send-Text {
    param($Stream, [int]$Status, [string]$Reason, [string]$Text, [bool]$HeadOnly)
    Send-Response $Stream $Status $Reason 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($Text)) $HeadOnly
}

function Resolve-StagedFile {
    param([string]$EncodedName)
    try { $name = [Uri]::UnescapeDataString($EncodedName) } catch { return $null }
    if (-not $name -or $name.StartsWith('.') -or $name.IndexOfAny([char[]]'\/:*?"<>|') -ge 0) { return $null }
    $extension = [IO.Path]::GetExtension($name).ToLowerInvariant()
    if (-not $contentTypes.ContainsKey($extension)) { return $null }
    $fullPath = [IO.Path]::GetFullPath((Join-Path $stagingRoot $name))
    if ([IO.Path]::GetDirectoryName($fullPath).TrimEnd('\', '/') -ne $stagingRoot) { return $null }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }
    return @{ Path = $fullPath; Type = $contentTypes[$extension] }
}

function Invoke-RelayRequest {
    param($Client)
    $Client.ReceiveTimeout = 5000
    $Client.SendTimeout = 30000
    $stream = $Client.GetStream()
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 4096, $true)
    try {
        $requestLine = $reader.ReadLine()
        if (-not $requestLine) { return }
        $hostHeader = ''
        for ($lineIndex = 0; $lineIndex -lt 100; $lineIndex++) {
            $line = $reader.ReadLine()
            if ($null -eq $line -or $line -eq '') { break }
            if ($line -match '^\s*Host\s*:\s*(.+?)\s*$') { $hostHeader = $Matches[1].ToLowerInvariant() }
        }
        $requestParts = $requestLine.Split(' ')
        if ($requestParts.Count -ne 3) { Send-Text $stream 400 'Bad Request' 'Bad request.' $false; return }
        $method = $requestParts[0]
        $requestPath = $requestParts[1].Split('?')[0]
        $headOnly = $method -eq 'HEAD'
        $status = 404
        if ($allowedHosts -notcontains $hostHeader) {
            $status = 403
            Send-Text $stream 403 'Forbidden' 'Only 127.0.0.1 and localhost are accepted.' $headOnly
        } elseif ($method -ne 'GET' -and -not $headOnly) {
            $status = 405
            Send-Text $stream 405 'Method Not Allowed' 'Only GET and HEAD are supported.' $false
        } elseif ($requestPath -eq '/') {
            $status = 200
            Send-Text $stream 200 'OK' $indexText $headOnly
        } elseif ($requestPath -eq '/relay.html') {
            $status = 200
            Send-Response $stream 200 'OK' 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($relayPage)) $headOnly
        } elseif ($requestPath.StartsWith('/files/')) {
            $stagedFile = Resolve-StagedFile $requestPath.Substring(7)
            if ($stagedFile) {
                $status = 200
                Send-Response $stream 200 'OK' $stagedFile.Type ([IO.File]::ReadAllBytes($stagedFile.Path)) $headOnly
            } else {
                Send-Text $stream 404 'Not Found' 'Not found.' $headOnly
            }
        } else {
            Send-Text $stream 404 'Not Found' 'Not found.' $headOnly
        }
        $loggedPath = $requestPath
        if ($requestPath.StartsWith('/files/')) { $loggedPath = '/files/(file)' }
        Write-Host "$method $loggedPath $status"
    } finally {
        $reader.Dispose()
    }
}

$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } catch { throw "Port $Port on 127.0.0.1 is not available: $($_.Exception.Message)" }
$servableCount = @(Get-ChildItem -LiteralPath $stagingRoot -File | Where-Object { $contentTypes.ContainsKey($_.Extension.ToLowerInvariant()) }).Count
Write-Host "Max Ultra MCP file relay listening on http://127.0.0.1:$Port/ with $servableCount staged files; it stops after $IdleMinutes idle minutes."
$lastActivity = [DateTime]::UtcNow
try {
    while ($true) {
        $acceptTask = $listener.AcceptTcpClientAsync()
        while (-not $acceptTask.Wait(1000)) {
            if (([DateTime]::UtcNow - $lastActivity).TotalMinutes -ge $IdleMinutes) {
                Write-Host 'Idle time limit reached; the file relay stopped.'
                return
            }
        }
        $client = $acceptTask.Result
        $lastActivity = [DateTime]::UtcNow
        try {
            Invoke-RelayRequest $client
        } catch {
            [Console]::Error.WriteLine("Relay request failed: $($_.Exception.Message)")
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
