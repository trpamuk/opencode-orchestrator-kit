param(
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) {
  $OutputPath = Join-Path $root "launcher\icon.ico"
}
Add-Type -AssemblyName System.Drawing

function New-RoundedRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  return $path
}

$master = New-Object System.Drawing.Bitmap -ArgumentList 256, 256
$graphics = [System.Drawing.Graphics]::FromImage($master)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

$backgroundPath = New-RoundedRect 8 8 240 240 52
$backgroundBrush = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 15, 23, 42))
$graphics.FillPath($backgroundBrush, $backgroundPath)
$borderPen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(255, 30, 41, 59)), 4
$graphics.DrawPath($borderPen, $backgroundPath)

$nodes = @(
  @(70, 70),
  @(186, 70),
  @(70, 186),
  @(186, 186)
)
$linePen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(255, 56, 189, 248)), 9
$linePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$linePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
foreach ($node in $nodes) {
  $graphics.DrawLine($linePen, 128, 128, $node[0], $node[1])
}

$nodeBrush = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 226, 232, 240))
foreach ($node in $nodes) {
  $graphics.FillEllipse($nodeBrush, $node[0] - 16, $node[1] - 16, 32, 32)
}

$centerBrush = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 34, 211, 238))
$graphics.FillEllipse($centerBrush, 102, 102, 52, 52)
$centerInnerBrush = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(255, 8, 47, 73))
$graphics.FillEllipse($centerInnerBrush, 118, 118, 20, 20)

$graphics.Dispose()

function Get-IconDib([System.Drawing.Bitmap]$bitmap) {
  $stream = New-Object System.IO.MemoryStream
  $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Bmp)
  $bytes = $stream.ToArray()
  $stream.Dispose()

  $height = $bitmap.Height * 2
  $bytes[22] = [byte]($height -band 0xFF)
  $bytes[23] = [byte](($height -shr 8) -band 0xFF)
  $bytes[24] = [byte](($height -shr 16) -band 0xFF)
  $bytes[25] = [byte](($height -shr 24) -band 0xFF)

  $dib = New-Object byte[] ($bytes.Length - 14)
  [Array]::Copy($bytes, 14, $dib, 0, $dib.Length)
  $maskRow = [int]([Math]::Ceiling($bitmap.Width / 32.0) * 4)
  $mask = New-Object byte[] ($maskRow * $bitmap.Height)
  $combined = New-Object byte[] ($dib.Length + $mask.Length)
  [Array]::Copy($dib, 0, $combined, 0, $dib.Length)
  [Array]::Copy($mask, 0, $combined, $dib.Length, $mask.Length)
  return $combined
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$images = New-Object System.Collections.ArrayList
foreach ($size in $sizes) {
  $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $resize = [System.Drawing.Graphics]::FromImage($bitmap)
  $resize.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $resize.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $resize.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $resize.DrawImage($master, 0, 0, $size, $size)
  $resize.Dispose()

  if ($size -ge 256) {
    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $data = $stream.ToArray()
    $stream.Dispose()
  } else {
    $data = Get-IconDib $bitmap
  }
  $bitmap.Dispose()
  [void]$images.Add([pscustomobject]@{ Size = $size; Data = [byte[]]$data })
}
$master.Dispose()

$directory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$file = [System.IO.File]::Create($OutputPath)
$writer = New-Object System.IO.BinaryWriter -ArgumentList $file
try {
  $writer.Write([UInt16]0)
  $writer.Write([UInt16]1)
  $writer.Write([UInt16]$images.Count)

  $offset = 6 + (16 * $images.Count)
  foreach ($image in $images) {
    $dimension = if ($image.Size -ge 256) { 0 } else { $image.Size }
    $writer.Write([byte]$dimension)
    $writer.Write([byte]$dimension)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$image.Data.Length)
    $writer.Write([UInt32]$offset)
    $offset += $image.Data.Length
  }
  foreach ($image in $images) {
    $writer.Write([byte[]]$image.Data)
  }
} finally {
  $writer.Close()
  $file.Dispose()
}

Write-Host "Icon: $OutputPath ($($images.Count) sizes)" -ForegroundColor Green
