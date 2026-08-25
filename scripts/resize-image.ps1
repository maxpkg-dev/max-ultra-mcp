param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [int]$Width = 0,
    [int]$Height = 0
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$resolved = [IO.Path]::GetFullPath($InputPath)
$source = [Drawing.Image]::FromFile($resolved)
try {
    if ($Width -le 0 -and $Height -le 0) { throw 'Width or Height is required.' }
    if ($Width -le 0) { $Width = [Math]::Max(1, [int][Math]::Round($source.Width * ($Height / $source.Height))) }
    if ($Height -le 0) { $Height = [Math]::Max(1, [int][Math]::Round($source.Height * ($Width / $source.Width))) }
    if ($Width -gt 8192 -or $Height -gt 8192) { throw 'Resized viewport edge must be <= 8192 pixels.' }
    $temporary = "$resolved.resize-$PID.png"
    $bitmap = New-Object Drawing.Bitmap($Width, $Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($source, 0, 0, $Width, $Height)
        $bitmap.Save($temporary, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
} finally {
    $source.Dispose()
}
Move-Item -LiteralPath $temporary -Destination $resolved -Force
[ordered]@{ width = $Width; height = $Height; filePath = $resolved; mimeType = 'image/png' } | ConvertTo-Json -Compress
