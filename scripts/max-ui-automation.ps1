# Runs process-scoped Windows UI Automation, native window capture, and UI diagnostics for 3ds Max.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

param(
    [Parameter(Mandatory = $true)][int]$TargetProcessId,
    [Parameter(Mandatory = $true)][ValidateSet('listWindows','inspect','diagnose','find','invoke','setValue','select','sendKeys','close','capture')][string]$Operation,
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
using System.Text;
public static class MaxUltraMcpUser32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rectangle);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rectangle);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder value, int maximumCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder value, int maximumCount);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr deviceContext, uint flags);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
    [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hWnd, uint objectId, ref Guid interfaceId, [MarshalAs(UnmanagedType.Interface)] out object accessibleObject);
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

function Get-ComProp($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    try {
        $value = $Object.$Name
        if ($null -eq $value) { return $Default }
        return $value
    } catch {
        return $Default
    }
}

function Assert-OwnedHandle([IntPtr]$Handle) {
    if ($Handle -eq [IntPtr]::Zero -or -not [MaxUltraMcpUser32]::IsWindow($Handle)) { throw 'UI_ELEMENT_NOT_FOUND: the HWND is no longer valid. Re-inspect the Max-owned window and retry with a fresh HWND.' }
    [uint32]$ownerPid = 0
    [void][MaxUltraMcpUser32]::GetWindowThreadProcessId($Handle, [ref]$ownerPid)
    if ([int]$ownerPid -ne $TargetProcessId) { throw 'UI_ELEMENT_NOT_FOUND: the HWND is not owned by the selected 3ds Max process. List or inspect that instance again.' }
    return $Handle
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

function Convert-ToNullableInt32($Value) {
    if ($null -eq $Value) { return $null }
    try {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return $null }
        if ($number -gt [int]::MaxValue -or $number -lt [int]::MinValue) { return $null }
        return [int][Math]::Round($number)
    } catch {
        return $null
    }
}

function Convert-ToNullableDouble($Value) {
    if ($null -eq $Value) { return $null }
    try {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return $null }
        return [Math]::Round($number, 4)
    } catch {
        return $null
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

function Resolve-WindowContext($Selector) {
    $requestedHandle = Get-Prop $Selector 'hwnd'
    if ($null -ne $requestedHandle) {
        $nativeHandle = Assert-OwnedHandle ([IntPtr][int64]$requestedHandle)
        $automationElement = $null
        try {
            $candidate = [System.Windows.Automation.AutomationElement]::FromHandle($nativeHandle)
            if ($null -ne $candidate -and [int]$candidate.Current.ProcessId -eq $TargetProcessId) { $automationElement = $candidate }
        } catch {}
        return [ordered]@{ handle = $nativeHandle; element = $automationElement; source = 'hwnd' }
    }

    $automationElement = Find-Window $Selector
    Assert-OwnedElement $automationElement
    $nativeHandle = [IntPtr][int64]$automationElement.Current.NativeWindowHandle
    if ($nativeHandle -eq [IntPtr]::Zero) { throw 'The selected window has no native handle' }
    [void](Assert-OwnedHandle $nativeHandle)
    return [ordered]@{ handle = $nativeHandle; element = $automationElement; source = 'uia' }
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
    $nativeHandle = [IntPtr][int64]$Element.Current.NativeWindowHandle
    if ($nativeHandle -ne [IntPtr]::Zero) { [void](Assert-OwnedHandle $nativeHandle) }
}

function Get-RootHandle($Element) {
    $cursor = $Element
    $lastHandle = 0
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

function Get-WindowRectangle([IntPtr]$Handle) {
    $rectangle = New-Object MaxUltraMcpUser32+RECT
    if (-not [MaxUltraMcpUser32]::GetWindowRect($Handle, [ref]$rectangle)) { throw 'The selected window rectangle is unavailable' }
    return [ordered]@{
        x = [int]$rectangle.Left
        y = [int]$rectangle.Top
        width = [int]($rectangle.Right - $rectangle.Left)
        height = [int]($rectangle.Bottom - $rectangle.Top)
    }
}

function Get-ClientRectangle([IntPtr]$Handle) {
    $rectangle = New-Object MaxUltraMcpUser32+RECT
    if (-not [MaxUltraMcpUser32]::GetClientRect($Handle, [ref]$rectangle)) { return $null }
    $origin = New-Object MaxUltraMcpUser32+POINT
    if (-not [MaxUltraMcpUser32]::ClientToScreen($Handle, [ref]$origin)) { return $null }
    return [ordered]@{
        x = [int]$origin.X
        y = [int]$origin.Y
        width = [int]($rectangle.Right - $rectangle.Left)
        height = [int]($rectangle.Bottom - $rectangle.Top)
    }
}

function Get-WindowString([IntPtr]$Handle, [bool]$ClassName = $false) {
    if ($ClassName) {
        $builder = New-Object Text.StringBuilder 512
        [void][MaxUltraMcpUser32]::GetClassName($Handle, $builder, $builder.Capacity)
        return $builder.ToString()
    }
    $length = [Math]::Min(512, [Math]::Max(0, [MaxUltraMcpUser32]::GetWindowTextLength($Handle)))
    $builder = New-Object Text.StringBuilder ($length + 1)
    [void][MaxUltraMcpUser32]::GetWindowText($Handle, $builder, $builder.Capacity)
    return $builder.ToString()
}

function Get-WindowDpi([IntPtr]$Handle) {
    try {
        $dpi = [int][MaxUltraMcpUser32]::GetDpiForWindow($Handle)
        if ($dpi -gt 0) { return $dpi }
    } catch {}
    return 96
}

function Get-NativeDepth([IntPtr]$Handle, [IntPtr]$RootHandle) {
    if ($Handle -eq $RootHandle) { return 0 }
    $depth = 0
    $cursor = $Handle
    while ($cursor -ne [IntPtr]::Zero -and $depth -lt 64) {
        $cursor = [MaxUltraMcpUser32]::GetParent($cursor)
        $depth += 1
        if ($cursor -eq $RootHandle) { return $depth }
    }
    return -1
}

function Convert-NativeWindow([IntPtr]$Handle, [IntPtr]$RootHandle) {
    [void](Assert-OwnedHandle $Handle)
    $parentHandle = [MaxUltraMcpUser32]::GetParent($Handle)
    $className = Get-WindowString $Handle $true
    $dpi = Get-WindowDpi $Handle
    return [ordered]@{
        hwnd = [int64]$Handle
        parentHwnd = [int64]$parentHandle
        depth = Get-NativeDepth $Handle $RootHandle
        className = $className
        title = Get-WindowString $Handle
        visible = [bool][MaxUltraMcpUser32]::IsWindowVisible($Handle)
        enabled = [bool][MaxUltraMcpUser32]::IsWindowEnabled($Handle)
        isWinForms = $className.StartsWith('WindowsForms10.', [StringComparison]::OrdinalIgnoreCase)
        isWebBrowserServer = $className -eq 'Internet Explorer_Server'
        rect = Get-WindowRectangle $Handle
        client = Get-ClientRectangle $Handle
        dpi = $dpi
        scalePercent = [int][Math]::Round(($dpi / 96.0) * 100.0)
    }
}

function Get-NativeTree([IntPtr]$RootHandle, [int]$Limit) {
    $nativeHandles = New-Object 'System.Collections.Generic.List[System.IntPtr]'
    $nativeHandles.Add($RootHandle)
    $enumerationState = @{ truncated = $false }
    $callback = [MaxUltraMcpUser32+EnumWindowsProc]{
        param([IntPtr]$childHandle, [IntPtr]$callbackData)
        if ($nativeHandles.Count -ge $Limit) {
            $enumerationState.truncated = $true
            return $false
        }
        $nativeHandles.Add($childHandle)
        return $true
    }
    [void][MaxUltraMcpUser32]::EnumChildWindows($RootHandle, $callback, [IntPtr]::Zero)
    $controls = New-Object System.Collections.Generic.List[object]
    foreach ($nativeHandle in $nativeHandles) {
        try { $controls.Add((Convert-NativeWindow $nativeHandle $RootHandle)) } catch {}
    }
    return [ordered]@{ count = $controls.Count; truncated = $enumerationState.truncated; controls = $controls.ToArray() }
}

function Get-UiaTree($RootElement, [int]$MaxDepth, [int]$Limit) {
    if ($null -eq $RootElement) { return [ordered]@{ available = $false; count = 0; truncated = $false; controls = @() } }
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue(@($RootElement, 0))
    $controls = New-Object System.Collections.Generic.List[object]
    while ($queue.Count -gt 0 -and $controls.Count -lt $Limit) {
        $entry = $queue.Dequeue()
        $element = $entry[0]
        $depth = [int]$entry[1]
        try {
            $controls.Add((Convert-Element $element $depth))
            if ($depth -lt $MaxDepth) {
                $children = $element.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($child in $children) { $queue.Enqueue(@($child, $depth + 1)) }
            }
        } catch {}
    }
    return [ordered]@{ available = $true; count = $controls.Count; truncated = $queue.Count -gt 0; controls = $controls.ToArray() }
}

function Get-DomBoxMetrics($DomElement) {
    if ($null -eq $DomElement) { return $null }
    return [ordered]@{
        clientWidth = Convert-ToNullableInt32 (Get-ComProp $DomElement 'clientWidth')
        clientHeight = Convert-ToNullableInt32 (Get-ComProp $DomElement 'clientHeight')
        offsetWidth = Convert-ToNullableInt32 (Get-ComProp $DomElement 'offsetWidth')
        offsetHeight = Convert-ToNullableInt32 (Get-ComProp $DomElement 'offsetHeight')
        scrollWidth = Convert-ToNullableInt32 (Get-ComProp $DomElement 'scrollWidth')
        scrollHeight = Convert-ToNullableInt32 (Get-ComProp $DomElement 'scrollHeight')
        scrollLeft = Convert-ToNullableInt32 (Get-ComProp $DomElement 'scrollLeft')
        scrollTop = Convert-ToNullableInt32 (Get-ComProp $DomElement 'scrollTop')
    }
}

function Get-WebBrowserMetrics($NativeControl) {
    $browserHandle = [IntPtr][int64]$NativeControl.hwnd
    $browserResult = [ordered]@{
        hwnd = [int64]$browserHandle
        rect = $NativeControl.rect
        client = $NativeControl.client
        available = $false
        document = $null
        body = $null
        layout = $null
        scroll = $null
        zoomDpi = [ordered]@{
            windowDpi = $NativeControl.dpi
            windowScalePercent = $NativeControl.scalePercent
            devicePixelRatio = $null
            screenDeviceDpi = $null
            screenLogicalDpi = $null
            cssZoom = $null
        }
        error = $null
    }
    try {
        $dispatchId = [Guid]'00020400-0000-0000-C000-000000000046'
        $documentObject = $null
        $status = [MaxUltraMcpUser32]::AccessibleObjectFromWindow($browserHandle, [uint32]4294967280, [ref]$dispatchId, [ref]$documentObject)
        if ($status -ne 0 -or $null -eq $documentObject) { throw "MSHTML document interface unavailable (HRESULT $status)" }

        $documentElement = Get-ComProp $documentObject 'documentElement'
        $bodyElement = Get-ComProp $documentObject 'body'
        $parentWindow = Get-ComProp $documentObject 'parentWindow'
        $screenObject = Get-ComProp $parentWindow 'screen'
        $documentMetrics = Get-DomBoxMetrics $documentElement
        $bodyMetrics = Get-DomBoxMetrics $bodyElement
        $scrollWidthValues = @($documentMetrics.scrollWidth, $bodyMetrics.scrollWidth) | Where-Object { $null -ne $_ }
        $scrollHeightValues = @($documentMetrics.scrollHeight, $bodyMetrics.scrollHeight) | Where-Object { $null -ne $_ }
        $scrollLeftValues = @($documentMetrics.scrollLeft, $bodyMetrics.scrollLeft) | Where-Object { $null -ne $_ }
        $scrollTopValues = @($documentMetrics.scrollTop, $bodyMetrics.scrollTop) | Where-Object { $null -ne $_ }
        $currentStyle = Get-ComProp $bodyElement 'currentStyle'

        $browserResult.available = $true
        $browserResult.document = [ordered]@{
            readyState = [string](Get-ComProp $documentObject 'readyState' '')
            compatMode = [string](Get-ComProp $documentObject 'compatMode' '')
            documentMode = Convert-ToNullableInt32 (Get-ComProp $documentObject 'documentMode')
        }
        $browserResult.body = $bodyMetrics
        $browserResult.layout = [ordered]@{
            documentElement = $documentMetrics
            viewportWidth = $documentMetrics.clientWidth
            viewportHeight = $documentMetrics.clientHeight
            documentWidth = if ($scrollWidthValues.Count -gt 0) { [int](($scrollWidthValues | Measure-Object -Maximum).Maximum) } else { $null }
            documentHeight = if ($scrollHeightValues.Count -gt 0) { [int](($scrollHeightValues | Measure-Object -Maximum).Maximum) } else { $null }
        }
        $browserResult.scroll = [ordered]@{
            left = if ($scrollLeftValues.Count -gt 0) { [int](($scrollLeftValues | Measure-Object -Maximum).Maximum) } else { $null }
            top = if ($scrollTopValues.Count -gt 0) { [int](($scrollTopValues | Measure-Object -Maximum).Maximum) } else { $null }
            width = $browserResult.layout.documentWidth
            height = $browserResult.layout.documentHeight
        }
        $browserResult.zoomDpi.devicePixelRatio = Convert-ToNullableDouble (Get-ComProp $parentWindow 'devicePixelRatio')
        $browserResult.zoomDpi.screenDeviceDpi = Convert-ToNullableInt32 (Get-ComProp $screenObject 'deviceXDPI')
        $browserResult.zoomDpi.screenLogicalDpi = Convert-ToNullableInt32 (Get-ComProp $screenObject 'logicalXDPI')
        $browserResult.zoomDpi.cssZoom = Convert-ToNullableDouble (Get-ComProp $currentStyle 'zoom')
    } catch {
        $errorMessage = [string]$_.Exception.Message
        $browserResult.error = $errorMessage.Substring(0, [Math]::Min(240, $errorMessage.Length))
    }
    return $browserResult
}

function Save-WindowCapture([IntPtr]$Handle, [string]$OutputPath) {
    [void](Assert-OwnedHandle $Handle)
    $rectangle = Get-WindowRectangle $Handle
    if ($rectangle.width -le 0 -or $rectangle.height -le 0) { throw 'UI_CAPTURE_FAILED: the selected HWND has empty bounds. Restore the window, re-inspect it, and retry.' }
    if ($rectangle.width -gt 32768 -or $rectangle.height -gt 32768 -or ([int64]$rectangle.width * [int64]$rectangle.height) -gt 100000000) {
        throw 'UI_CAPTURE_FAILED: the selected HWND is too large to capture safely.'
    }

    $bitmap = New-Object System.Drawing.Bitmap($rectangle.width, $rectangle.height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $captureMethod = 'printWindow'
    try {
        $deviceContext = $graphics.GetHdc()
        try {
            [void](Assert-OwnedHandle $Handle)
            $printed = [MaxUltraMcpUser32]::PrintWindow($Handle, $deviceContext, 2)
        } finally {
            $graphics.ReleaseHdc($deviceContext)
        }
        if (-not $printed) {
            [void](Assert-OwnedHandle $Handle)
            $graphics.CopyFromScreen($rectangle.x, $rectangle.y, 0, 0, $bitmap.Size)
            $captureMethod = 'screenCopyFallback'
        }
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } catch {
        $captureError = [string]$_.Exception.Message
        if ($captureError.StartsWith('UI_ELEMENT_NOT_FOUND:') -or $captureError.StartsWith('UI_CAPTURE_FAILED:')) {
            throw $captureError
        }
        throw 'UI_CAPTURE_FAILED: native and screen capture failed. Restore the Max-owned window, obtain a fresh HWND, and retry.'
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    return [ordered]@{ rectangle = $rectangle; captureMethod = $captureMethod }
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
        $context = Resolve-WindowContext $windowSelector
        Assert-OwnedElement $context.element
        $maxDepth = [Math]::Min(10, [Math]::Max(0, [int](Get-Prop $payload 'maxDepth' 5)))
        $limit = [Math]::Min(1000, [Math]::Max(1, [int](Get-Prop $payload 'limit' 200)))
        $uiaTree = Get-UiaTree $context.element $maxDepth $limit
        $result = [ordered]@{ count = $uiaTree.count; truncated = $uiaTree.truncated; controls = $uiaTree.controls }
    }
    'diagnose' {
        $context = Resolve-WindowContext $windowSelector
        $maxDepth = [Math]::Min(10, [Math]::Max(0, [int](Get-Prop $payload 'maxDepth' 5)))
        $limit = [Math]::Min(1000, [Math]::Max(1, [int](Get-Prop $payload 'limit' 200)))
        [void](Assert-OwnedHandle $context.handle)
        $uiaTree = Get-UiaTree $context.element $maxDepth $limit
        $nativeTree = Get-NativeTree $context.handle $limit
        $webBrowsers = New-Object System.Collections.Generic.List[object]
        foreach ($nativeControl in $nativeTree.controls) {
            if ($nativeControl.isWebBrowserServer) { $webBrowsers.Add((Get-WebBrowserMetrics $nativeControl)) }
        }
        $result = [ordered]@{
            window = Convert-NativeWindow $context.handle $context.handle
            selectorSource = $context.source
            uia = $uiaTree
            native = $nativeTree
            webBrowsers = $webBrowsers.ToArray()
            limitations = @(
                'Native WinForms entries represent HWND-backed controls; windowless managed controls may appear only in the UI Automation tree.',
                'WebBrowser DOM metrics require an accessible MSHTML Internet Explorer_Server document and may be unavailable for other browser engines or integrity levels.'
            )
        }
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
            [void](Assert-OwnedHandle $handle)
            [void][MaxUltraMcpUser32]::PostMessage($handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        }
        $result = [ordered]@{ closeRequested = $true; window = Convert-Element $element 0 }
    }
    'capture' {
        $context = Resolve-WindowContext $windowSelector
        $outputPath = [string](Get-Prop $payload 'outputPath' '')
        if (-not $outputPath) { throw 'capture requires outputPath' }
        $capture = Save-WindowCapture $context.handle $outputPath
        $windowSummary = if ($null -ne $context.element) {
            Convert-Element $context.element 0
        } else {
            Convert-NativeWindow $context.handle $context.handle
        }
        $result = [ordered]@{
            filePath = $outputPath
            mimeType = 'image/png'
            width = $capture.rectangle.width
            height = $capture.rectangle.height
            captureMethod = $capture.captureMethod
            selectorSource = $context.source
            window = $windowSummary
        }
    }
}

[ordered]@{ ok = $true; data = $result } | ConvertTo-Json -Depth 16 -Compress
