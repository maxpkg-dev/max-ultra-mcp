# Fetches the current official MaxPkg guidance and optionally prepares a project with its tooling.
# The guidance, prompts, API documentation, and MaxScript contents are downloaded from the exact resolved GitHub commit.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param(
    [ValidateSet('Adaptation', 'FullOnboarding')]
    [string]$Prompt = 'Adaptation',
    [string]$ProjectRoot = '',
    [switch]$PrepareProject,
    [switch]$ConfirmProjectWrite
)

$ErrorActionPreference = 'Stop'
$repositorySlug = 'maxpkg-dev/max-dev-tool'
$repositoryUrl = 'https://github.com/maxpkg-dev/max-dev-tool'
$apiCommitUrl = 'https://api.github.com/repos/maxpkg-dev/max-dev-tool/commits/HEAD'
$httpHeaders = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'Max-Ultra-MCP-MaxPkg-Skill'
    'X-GitHub-Api-Version' = '2022-11-28'
}
$requiredFiles = @(
    'README.md',
    'code-rules.md',
    'maxpkg-api.md',
    'maxpkg-adaptation-prompt.md',
    'maxpkg-full-onboarding-prompt.md',
    'maxpkg-packager.ms',
    '_install.ms',
    '_uninstall.ms'
)
$toolingFiles = @('maxpkg-packager.ms', '_install.ms', '_uninstall.ms')

if ($PrepareProject -and -not $ConfirmProjectWrite) {
    throw 'Preparing a project requires -ConfirmProjectWrite after the user completes the MaxPkg skill preflight.'
}
if ($PrepareProject -and [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    throw 'Preparing a project requires -ProjectRoot.'
}

$commitResponse = Invoke-RestMethod -Uri $apiCommitUrl -Headers $httpHeaders -Method Get
$commitSha = [string]$commitResponse.sha
if ($commitSha -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'GitHub did not return a valid MaxPkg commit SHA.'
}
$commitSha = $commitSha.ToLowerInvariant()

$fetchRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-maxpkg-upstream-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fetchRoot -Force | Out-Null

try {
$fileRecords = New-Object System.Collections.Generic.List[object]
foreach ($fileName in $requiredFiles) {
    $downloadUrl = 'https://raw.githubusercontent.com/' + $repositorySlug + '/' + $commitSha + '/' + $fileName
    $downloadPath = Join-Path $fetchRoot $fileName
    Invoke-WebRequest -Uri $downloadUrl -Headers @{ 'User-Agent' = $httpHeaders['User-Agent'] } -OutFile $downloadPath -UseBasicParsing
    if (-not (Test-Path -LiteralPath $downloadPath -PathType Leaf)) {
        throw "Required upstream file was not downloaded: $fileName"
    }
    if ((Get-Item -LiteralPath $downloadPath).Length -le 0) {
        throw "Required upstream file is empty: $fileName"
    }
    $fileRecords.Add([pscustomobject]@{
        name = $fileName
        path = $downloadPath
        sha256 = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash
    })
}

$projectFileRecords = New-Object System.Collections.Generic.List[object]
$resolvedProjectRoot = ''
if ($PrepareProject) {
    $resolvedProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $resolvedProjectRoot -PathType Container)) {
        throw "Project root does not exist: $resolvedProjectRoot"
    }

    foreach ($fileName in $toolingFiles) {
        $sourcePath = Join-Path $fetchRoot $fileName
        $destinationPath = Join-Path $resolvedProjectRoot $fileName
        if (Test-Path -LiteralPath $destinationPath) {
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
                throw "Conflicting project path requires separate review: $destinationPath"
            }
            $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
            if ($sourceHash -ne $destinationHash) {
                throw "Conflicting project file requires separate review and approval before replacement: $destinationPath"
            }
        }
    }

    foreach ($fileName in $toolingFiles) {
        $sourcePath = Join-Path $fetchRoot $fileName
        $destinationPath = Join-Path $resolvedProjectRoot $fileName
        $status = 'created'

        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            $status = 'current'
        } else {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
        }

        $projectFileRecords.Add([pscustomobject]@{
            name = $fileName
            path = $destinationPath
            status = $status
            sha256 = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
        })
    }
}

$selectedPromptFile = if ($Prompt -eq 'FullOnboarding') {
    'maxpkg-full-onboarding-prompt.md'
} else {
    'maxpkg-adaptation-prompt.md'
}

$result = [ordered]@{
    repository = $repositoryUrl
    commit = $commitSha
    fetchedAtUtc = [DateTime]::UtcNow.ToString('o')
    fetchRoot = $fetchRoot
    readmePath = (Join-Path $fetchRoot 'README.md')
    codingRulesPath = (Join-Path $fetchRoot 'code-rules.md')
    apiDocumentationPath = (Join-Path $fetchRoot 'maxpkg-api.md')
    adaptationPromptPath = (Join-Path $fetchRoot 'maxpkg-adaptation-prompt.md')
    fullOnboardingPromptPath = (Join-Path $fetchRoot 'maxpkg-full-onboarding-prompt.md')
    selectedPrompt = $Prompt
    selectedPromptPath = (Join-Path $fetchRoot $selectedPromptFile)
    files = $fileRecords.ToArray()
    projectRoot = $resolvedProjectRoot
    projectFiles = $projectFileRecords.ToArray()
}
$result | ConvertTo-Json -Depth 6
}
catch {
    $fetchFailure = $_
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolvedFetchRoot = [IO.Path]::GetFullPath($fetchRoot)
    if ($resolvedFetchRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedFetchRoot)) {
        Remove-Item -LiteralPath $resolvedFetchRoot -Recurse -Force
    }
    throw $fetchFailure
}
