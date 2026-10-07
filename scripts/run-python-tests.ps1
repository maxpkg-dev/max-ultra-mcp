# Run scene-free Python contracts with the embedded Max interpreters or an explicit development interpreter.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

$ErrorActionPreference = 'Stop'
$interpreters = @()
if ($env:MAX_ULTRA_PYTHON) {
    $interpreters = @($env:MAX_ULTRA_PYTHON)
} else {
    foreach ($relative in @('Autodesk\3ds Max 2022\Python37\python.exe', 'Autodesk\3ds Max 2027\Python\python.exe')) {
        $candidate = Join-Path $env:ProgramFiles $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $interpreters += $candidate }
    }
}
if ($interpreters.Count -eq 0) { throw 'Set MAX_ULTRA_PYTHON to a Python 3.7+ development interpreter or install a supported 3ds Max. End users do not need a separate Python installation.' }
foreach ($interpreter in $interpreters) {
    & $interpreter -B (Join-Path $PSScriptRoot '..\tests\python-runtime-test.py')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
exit 0
