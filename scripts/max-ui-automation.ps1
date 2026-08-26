param(
    [Parameter(Mandatory = $true)][int]$TargetProcessId,
    [Parameter(Mandatory = $true)][ValidateSet('listWindows','inspect','find','invoke','setValue','select','sendKeys','close','capture')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$PayloadBase64
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MaxUltraMcpUser32 {
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
}
'@

function Convert-FromPayload {
    $bytes = [Convert]::FromBase64String($PayloadBase64)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{} }
    return $text | ConvertFrom-Json
}

function Get-Prop($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Assert-TargetProcess {
    $process = Get-Process -Id $TargetProcessId -ErrorAction Stop
    if ($process.ProcessName -ne '3dsmax') {
        throw "Target PID $TargetProcessId is '$($process.ProcessName)', not 3dsmax.exe"
    }
    return $process
}

function Get-MaxWindows {
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $TargetProcessId
    )
    $collection = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        $condition
    )
    $windows = New-Object System.Collections.Generic.List[object]
    foreach ($element in $collection) { $windows.Add($element) }
    return $windows
}

function Test-ElementMatch($Element, $Selector) {
    if ($null -eq $Selector) { return $true }
    $handle = [int64]$Element.Current.NativeWindowHandle
    $requestedHandle = Get-Prop $Selector 'hwnd'
    if ($null -ne $requestedHandle -and $handle -ne [int64]$requestedHandle) { return $false }

    $automationId = [string]$Element.Current.AutomationId
    $requestedAutomationId = [string](Get-Prop $Selector 'automationId' '')
    if ($requestedAutomationId -and $automationId -ne $requestedAutomationId) { return $false }

    $name = [string]$Element.Current.Name
    $requestedName = [string](Get-Prop $Selector 'name' '')
    if ($requestedName -and $name -ne $requestedName) { return $false }
    $nameContains = [string](Get-Prop $Selector 'nameContains' '')
    if ($nameContains -and $name.IndexOf($nameContains, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }

    $className = [string]$Element.Current.ClassName
    $requestedClass = [string](Get-Prop $Selector 'className' '')
    if ($requestedClass -and $className -ne $requestedClass) { return $false }

    $controlType = [string]$Element.Current.ControlType.ProgrammaticName
    $requestedType = [string](Get-Prop $Selector 'controlType' '')
    if ($requestedType) {
        $normalizedActual = $controlType.Replace('ControlType.', '')
        if ($normalizedActual -ne $requestedType -and $controlType -ne $requestedType) { return $false }
    }
    return $true
}

function Convert-ToSafeInt32($Value) {
    try {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return 0 }
        if ($number -gt [int]::MaxValue) { return [int]::MaxValue }
        if ($number -lt [int]::MinValue) { return [int]::MinValue }
        return [int][Math]::Round($number)
    } catch {
        return 0
    }
}

function Convert-Element($Element, [int]$Depth = 0) {
    $rectangle = $Element.Current.BoundingRectangle
    return [ordered]@{
        hwnd = [int64]$Element.Current.NativeWindowHandle
        processId = [int]$Element.Current.ProcessId
        automationId = [string]$Element.Current.AutomationId
        name = [string]$Element.Current.Name
        className = [string]$Element.Current.ClassName
        controlType = ([string]$Element.Current.ControlType.ProgrammaticName).Replace('ControlType.', '')
        frameworkId = [string]$Element.Current.FrameworkId
        enabled = [bool]$Element.Current.IsEnabled
        offscreen = [bool]$Element.Current.IsOffscreen
        depth = $Depth
        rect = [ordered]@{
            x = Convert-ToSafeInt32 $rectangle.X
            y = Convert-ToSafeInt32 $rectangle.Y
            width = Convert-ToSafeInt32 $rectangle.Width
            height = Convert-ToSafeInt32 $rectangle.Height
        }
    }
}

function Find-Window($Selector) {
    $matches = @()
    foreach ($window in Get-MaxWindows) {
        if (Test-ElementMatch $window $Selector) { $matches += $window }
    }
    $index = [int](Get-Prop $Selector 'index' 0)
    if ($index -lt 0 -or $index -ge $matches.Count) { return $null }
    return $matches[$index]
}

function Find-Control($WindowSelector, $ControlSelector) {
    $roots = @()
    if ($null -ne $WindowSelector) {
        $window = Find-Window $WindowSelector
        if ($null -eq $window) { return $null }
        $roots = @($window)
    } else {
        $roots = @(Get-MaxWindows)
    }
    $matches = @()
    foreach ($root in $roots) {
        if (Test-ElementMatch $root $ControlSelector) { $matches += $root }
        $descendants = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($element in $descendants) {
            if (Test-ElementMatch $element $ControlSelector) { $matches += $element }
        }
    }
    $index = [int](Get-Prop $ControlSelector 'index' 0)
    if ($index -lt 0 -or $index -ge $matches.Count) { return $null }
    return $matches[$index]
}

function Assert-OwnedElement($Element) {
    if ($null -eq $Element) { throw 'UI element was not found' }
    if ([int]$Element.Current.ProcessId -ne $TargetProcessId) { throw 'UI element is not owned by the selected 3ds Max process' }
    $handle = [IntPtr][int64]$Element.Current.NativeWindowHandle
    if ($handle -ne [IntPtr]::Zero -and [MaxUltraMcpUser32]::IsWindow($handle)) {
        [uint32]$ownerPid = 0
        [void][MaxUltraMcpUser32]::GetWindowThreadProcessId($handle, [ref]$ownerPid)
        if ([int]$ownerPid -ne $TargetProcessId) { throw 'Native UI handle ownership changed before the operation' }
    }
}

function Get-RootHandle($Element) {
    $cursor = $Element
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    while ($null -ne $cursor) {
        $handle = [int64]$cursor.Current.NativeWindowHandle
        if ($handle -ne 0) { $lastHandle = $handle }
        $parent = $walker.GetParent($cursor)
        if ($null -eq $parent -or [int]$parent.Current.ProcessId -ne $TargetProcessId) { break }
        $cursor = $parent
    }
    return [int64]$lastHandle
}

$null = Assert-TargetProcess
$payload = Convert-FromPayload
$windowSelector = Get-Prop $payload 'window'
$controlSelector = Get-Prop $payload 'control'
$result = $null

switch ($Operation) {
    'listWindows' {
        $items = @(Get-MaxWindows | ForEach-Object { Convert-Element $_ 0 })
        $titleContains = [string](Get-Prop $payload 'titleContains' '')
        if ($titleContains) { $items = @($items | Where-Object { $_.name.IndexOf($titleContains, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
        $limit = [Math]::Min(200, [Math]::Max(1, [int](Get-Prop $payload 'limit' 50)))
        $result = [ordered]@{ count = [Math]::Min($items.Count, $limit); truncated = $items.Count -gt $limit; windows = @($items | Select-Object -First $limit) }
    }
    'inspect' {
        $root = Find-Window $windowSelector
        Assert-OwnedElement $root
        $maxDepth = [Math]::Min(10, [Math]::Max(0, [int](Get-Prop $payload 'maxDepth' 5)))
        $limit = [Math]::Min(1000, [Math]::Max(1, [int](Get-Prop $payload 'limit' 200)))
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue(@($root, 0))
        $items = New-Object System.Collections.Generic.List[object]
        while ($queue.Count -gt 0 -and $items.Count -lt $limit) {
            $entry = $queue.Dequeue()
            $element = $entry[0]
            $depth = [int]$entry[1]
            $items.Add((Convert-Element $element $depth))
            if ($depth -lt $maxDepth) {
                $children = $element.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($child in $children) { $queue.Enqueue(@($child, $depth + 1)) }
            }
        }
        $result = [ordered]@{ count = $items.Count; truncated = $queue.Count -gt 0; controls = $items.ToArray() }
    }
    'find' {
        $element = Find-Control $windowSelector $controlSelector
        Assert-OwnedElement $element
        $result = Convert-Element $element 0
    }
    'invoke' {
        $element = Find-Control $windowSelector $controlSelector
        Assert-OwnedElement $element
        $pattern = $null
        if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
            ([System.Windows.Automation.InvokePattern]$pattern).Invoke()
        } elseif ($element.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) {
            ([System.Windows.Automation.TogglePattern]$pattern).Toggle()
        } elseif ($element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
            ([System.Windows.Automation.SelectionItemPattern]$pattern).Select()
        } else {
            throw 'The selected control exposes no Invoke, Toggle, or SelectionItem pattern'
        }
        $result = [ordered]@{ invoked = $true; element = Convert-Element $element 0 }
    }
    'setValue' {
        $element = Find-Control $windowSelector $controlSelector
        Assert-OwnedElement $element
        $pattern = $null
        if (-not $element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) { throw 'The selected control exposes no Value pattern' }
        ([System.Windows.Automation.ValuePattern]$pattern).SetValue([string](Get-Prop $payload 'value' ''))
        $result = [ordered]@{ valueSet = $true; element = Convert-Element $element 0 }
    }
    'select' {
        $container = Find-Control $windowSelector $controlSelector
        Assert-OwnedElement $container
        $items = $container.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        $requestedItem = Get-Prop $payload 'item'
        $selected = $null
        if ($requestedItem -is [int] -or $requestedItem -is [long]) {
            $position = [int]$requestedItem
            if ($position -ge 0 -and $position -lt $items.Count) { $selected = $items[$position] }
        } else {
            foreach ($itemElement in $items) { if ([string]$itemElement.Current.Name -eq [string]$requestedItem) { $selected = $itemElement; break } }
        }
        Assert-OwnedElement $selected
        $pattern = $null
        if ($selected.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
            ([System.Windows.Automation.SelectionItemPattern]$pattern).Select()
        } elseif ($selected.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
            ([System.Windows.Automation.InvokePattern]$pattern).Invoke()
        } else { throw 'The selected item exposes no SelectionItem or Invoke pattern' }
        $result = [ordered]@{ selected = $true; element = Convert-Element $selected 0 }
    }
    'sendKeys' {
        $element = if ($null -ne $controlSelector) { Find-Control $windowSelector $controlSelector } else { Find-Window $windowSelector }
        if ($null -eq $element) { $element = (Get-MaxWindows | Select-Object -First 1) }
        Assert-OwnedElement $element
        $rootHandle = Get-RootHandle $element
        if ($rootHandle -ne 0) { [void][MaxUltraMcpUser32]::SetForegroundWindow([IntPtr]$rootHandle) }
        $element.SetFocus()
        [System.Windows.Forms.SendKeys]::SendWait([string](Get-Prop $payload 'keys' ''))
        $result = [ordered]@{ sent = $true; keys = [string](Get-Prop $payload 'keys' ''); element = Convert-Element $element 0 }
    }
    'close' {
        $element = Find-Window $windowSelector
        Assert-OwnedElement $element
        $pattern = $null
        if ($element.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$pattern)) {
            ([System.Windows.Automation.WindowPattern]$pattern).Close()
        } else {
            $handle = [IntPtr][int64]$element.Current.NativeWindowHandle
            if ($handle -eq [IntPtr]::Zero) { throw 'The selected window has no native handle or Window pattern' }
            [void][MaxUltraMcpUser32]::PostMessage($handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        }
        $result = [ordered]@{ closeRequested = $true; window = Convert-Element $element 0 }
    }
    'capture' {
        $element = Find-Window $windowSelector
        Assert-OwnedElement $element
        $rectangle = $element.Current.BoundingRectangle
        if ($rectangle.Width -le 0 -or $rectangle.Height -le 0) { throw 'The selected window has an empty bounding rectangle' }
        $outputPath = [string](Get-Prop $payload 'outputPath' '')
        if (-not $outputPath) { throw 'capture requires outputPath' }
        $bitmap = New-Object System.Drawing.Bitmap([int]$rectangle.Width, [int]$rectangle.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen([int]$rectangle.X, [int]$rectangle.Y, 0, 0, $bitmap.Size)
            $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
        $result = [ordered]@{ filePath = $outputPath; mimeType = 'image/png'; width = [int]$rectangle.Width; height = [int]$rectangle.Height; window = Convert-Element $element 0 }
    }
}

[ordered]@{ ok = $true; data = $result } | ConvertTo-Json -Depth 12 -Compress
