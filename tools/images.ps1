<#
  Builds the web photos from the business's own Google Business Profile uploads
  (originals live in tools\source\, downloaded 2026-10-13 with the client's OK).

      powershell -ExecutionPolicy Bypass -File tools\images.ps1

  For every entry in $photos it crops (to remove the phone-camera watermark and
  frame the subject), applies a mild contrast/saturation lift, and writes
  src\assets\img\photos\<name>-<width>.jpg and .webp for each width.

  JPEG comes from System.Drawing. WebP comes from headless Chrome (canvas.toDataURL)
  because this machine has no WebP encoder. Keep this file ASCII-only: Windows
  PowerShell 5.1 reads BOM-less scripts as ANSI.
#>
$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$srcDir = Join-Path $PSScriptRoot 'source'
$cache  = Join-Path $PSScriptRoot '.cache\img'
$out    = Join-Path $root 'src\assets\img\photos'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
New-Item -ItemType Directory -Force $cache, $out | Out-Null
Add-Type -AssemblyName System.Drawing

# name, source file, crop x, y, w, h (source pixels), output widths
$photos = @(
  @{ name = 'office-front';   file = 'gbp-0-office-front.jpg'; x = 0; y = 380; w = 900;  h = 1125; widths = @(480, 720, 900) }
  @{ name = 'office-sign';    file = 'gbp-5.jpg';              x = 0; y = 96;  w = 1600; h = 960;  widths = @(480, 800, 1200) }
  @{ name = 'office-lounge';  file = 'gbp-1.jpg';              x = 0; y = 0;   w = 1600; h = 1066; widths = @(480, 800, 1200) }
  @{ name = 'office-meeting'; file = 'gbp-2.jpg';              x = 0; y = 0;   w = 1600; h = 1066; widths = @(480, 800, 1200) }
)

# mild lift: saturation 1.06 then contrast 1.07 (row-vector GDI+ ColorMatrix)
$s = 1.06; $c = 1.07; $t = 0.5 * (1 - $c) - 0.005
$lr = (1 - $s) * 0.2126; $lg = (1 - $s) * 0.7152; $lb = (1 - $s) * 0.0722
$m = New-Object System.Drawing.Imaging.ColorMatrix
$m.Matrix00 = ($lr + $s) * $c; $m.Matrix01 = $lr * $c;        $m.Matrix02 = $lr * $c
$m.Matrix10 = $lg * $c;        $m.Matrix11 = ($lg + $s) * $c; $m.Matrix12 = $lg * $c
$m.Matrix20 = $lb * $c;        $m.Matrix21 = $lb * $c;        $m.Matrix22 = ($lb + $s) * $c
$m.Matrix33 = 1; $m.Matrix44 = 1
$m.Matrix40 = $t; $m.Matrix41 = $t; $m.Matrix42 = $t
$attr = New-Object System.Drawing.Imaging.ImageAttributes
$attr.SetColorMatrix($m)
$attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)   # no dark fringe at the edges

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encParams = New-Object System.Drawing.Imaging.EncoderParameters 1
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]80)

$pngs = @()
foreach ($p in $photos) {
  $img = [System.Drawing.Image]::FromFile((Join-Path $srcDir $p.file))
  foreach ($w in $p.widths) {
    $h = [int][Math]::Round($w * $p.h / $p.w)
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), $p.x, $p.y, $p.w, $p.h, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    $g.Dispose()
    $base = "$($p.name)-$w"
    $bmp.Save((Join-Path $out "$base.jpg"), $jpegCodec, $encParams)
    $png = Join-Path $cache "$base.png"
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $pngs += @{ base = $base; png = $png }
  }
  $img.Dispose()
}

# ---- WebP through headless Chrome: one page per image keeps --dump-dom output small
foreach ($item in $pngs) {
  $b64  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($item.png))
  $html = Join-Path $cache 'webp.html'
  $page = "<!doctype html><html><body><img id='i' src='data:image/png;base64,$b64'><textarea id='o'></textarea>" +
          "<script>window.addEventListener('load',function(){var i=document.getElementById('i');var c=document.createElement('canvas');" +
          "c.width=i.naturalWidth;c.height=i.naturalHeight;c.getContext('2d').drawImage(i,0,0);" +
          "document.getElementById('o').textContent=c.toDataURL('image/webp',0.78);i.remove();});</script></body></html>"
  [IO.File]::WriteAllText($html, $page, (New-Object System.Text.UTF8Encoding $false))
  $prof = Join-Path $env:TEMP ('ap-webp-' + [guid]::NewGuid().ToString('N'))
  $so = Join-Path $cache 'dom.txt'; $se = Join-Path $cache 'chrome-err.txt'
  # chrome.exe is a GUI-subsystem binary: '& chrome' returns before it prints, so wait + redirect instead
  $cargs = @('--headless=new', '--disable-gpu', '--no-first-run', "--user-data-dir=$prof",
            '--virtual-time-budget=5000', '--dump-dom', ('file:///' + ($html -replace '\\', '/')))
  Start-Process -FilePath $chrome -ArgumentList $cargs -RedirectStandardOutput $so -RedirectStandardError $se -Wait -WindowStyle Hidden
  Remove-Item -Recurse -Force $prof -ErrorAction SilentlyContinue
  $dom = [IO.File]::ReadAllText($so)
  $mt = [regex]::Match($dom, 'data:image/webp;base64,([A-Za-z0-9+/=]+)')
  if (-not $mt.Success) { throw "Chrome did not return WebP for $($item.base)" }
  [IO.File]::WriteAllBytes((Join-Path $out "$($item.base).webp"), [Convert]::FromBase64String($mt.Groups[1].Value))
}

Get-ChildItem $out | Sort-Object Name | Select-Object Name, @{ n = 'KB'; e = { [Math]::Round($_.Length / 1KB, 1) } } | Format-Table -AutoSize | Out-String
