# Generates Assets/app.ico (multi-size, PNG-compressed) and docs/logo.png from vector primitives.
param(
    [string]$OutIco = "$PSScriptRoot\..\src\JunkCleanup\Assets\app.ico",
    [string]$OutPng = "$PSScriptRoot\..\docs\logo.png"
)

Add-Type -AssemblyName System.Drawing

function Draw-Logo([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $s = [float]$size
    $radius = $s * 0.28
    $rect = New-Object System.Drawing.RectangleF 0, 0, $s, $s

    # rounded square path
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($s - $d, 0, $d, $d, 270, 90)
    $path.AddArc($s - $d, $s - $d, $d, $d, 0, 90)
    $path.AddArc(0, $s - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(255, 0x8B, 0x7C, 0xFF)), ([System.Drawing.Color]::FromArgb(255, 0x22, 0xD3, 0xEE)), 45
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
    $blend.Colors = @([System.Drawing.Color]::FromArgb(255, 0x8B, 0x7C, 0xFF), [System.Drawing.Color]::FromArgb(255, 0x5B, 0x8C, 0xFF), [System.Drawing.Color]::FromArgb(255, 0x22, 0xD3, 0xEE))
    $blend.Positions = @([float]0, [float]0.55, [float]1)
    $brush.InterpolationColors = $blend
    $g.FillPath($brush, $path)

    # sparkle: four-point star made from bezier curves, scaled from a 64-unit design grid
    function Sparkle([float]$cx, [float]$cy, [float]$r) {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $k = $r * 0.12
        $p.AddBezier($cx, $cy - $r, $cx + $k, $cy - $k, $cx + $k, $cy - $k, $cx + $r, $cy)
        $p.AddBezier($cx + $r, $cy, $cx + $k, $cy + $k, $cx + $k, $cy + $k, $cx, $cy + $r)
        $p.AddBezier($cx, $cy + $r, $cx - $k, $cy + $k, $cx - $k, $cy + $k, $cx - $r, $cy)
        $p.AddBezier($cx - $r, $cy, $cx - $k, $cy - $k, $cx - $k, $cy - $k, $cx, $cy - $r)
        $p.CloseFigure()
        return $p
    }

    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(250, 255, 255, 255))
    $g.FillPath($white, (Sparkle ($s * 0.47) ($s * 0.45) ($s * 0.27)))
    $g.FillPath($white, (Sparkle ($s * 0.70) ($s * 0.69) ($s * 0.095)))

    $g.Dispose()
    return $bmp
}

$sizes = 16, 24, 32, 48, 64, 128, 256
$pngs = @()
foreach ($sz in $sizes) {
    $bmp = Draw-Logo $sz
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += ,@{ Size = $sz; Bytes = $ms.ToArray() }
    $bmp.Dispose()
}

# ICO container with PNG entries
$outDir = Split-Path -Parent $OutIco
New-Item -ItemType Directory -Force $outDir | Out-Null
$fs = [System.IO.File]::Create($OutIco)
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count)
$offset = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
    $dim = if ($p.Size -ge 256) { 0 } else { $p.Size }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$p.Bytes.Length); $bw.Write([uint32]$offset)
    $offset += $p.Bytes.Length
}
foreach ($p in $pngs) { $bw.Write($p.Bytes) }
$bw.Dispose(); $fs.Dispose()

# docs logo (512px)
New-Item -ItemType Directory -Force (Split-Path -Parent $OutPng) | Out-Null
$big = Draw-Logo 512
$big.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
$big.Dispose()

Write-Host "Wrote $OutIco and $OutPng"
