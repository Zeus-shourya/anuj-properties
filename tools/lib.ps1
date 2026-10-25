<#  Shared helpers for tools\*.ps1 (dot-source it). ASCII only. #>
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
Add-Type -AssemblyName System.Drawing

# chrome.exe is a GUI-subsystem binary: run it with Start-Process -Wait, never '& chrome'
function Invoke-ChromeShot([string]$htmlPath, [string]$pngPath, [int]$w, [int]$h, [switch]$Transparent) {
  $prof = Join-Path $env:TEMP ('ap-shot-' + [guid]::NewGuid().ToString('N'))
  $a = @('--headless=new', '--disable-gpu', '--no-first-run', '--hide-scrollbars', '--force-device-scale-factor=1',
         "--user-data-dir=$prof", "--window-size=$w,$h", '--virtual-time-budget=10000', "--screenshot=$pngPath")
  if ($Transparent) { $a += '--default-background-color=00000000' }
  $a += ('file:///' + ($htmlPath -replace '\\', '/'))
  if (Test-Path $pngPath) { [IO.File]::Delete($pngPath) }
  $so = Join-Path $env:TEMP 'ap-shot-out.txt'; $se = Join-Path $env:TEMP 'ap-shot-err.txt'
  Start-Process -FilePath $chrome -ArgumentList $a -RedirectStandardOutput $so -RedirectStandardError $se -Wait -WindowStyle Hidden
  try { [IO.Directory]::Delete($prof, $true) } catch { }
  if (-not (Test-Path $pngPath)) { throw "Chrome screenshot failed for $htmlPath" }
}

function Save-Resized([string]$srcPng, [string]$dst, [int]$w, [int]$h, [string]$format = 'png', [long]$quality = 85) {
  $img = [System.Drawing.Image]::FromFile($srcPng)
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  if ($format -eq 'jpg') { $g.Clear([System.Drawing.Color]::White) }
  $g.DrawImage($img, 0, 0, $w, $h)
  $g.Dispose(); $img.Dispose()
  if ($format -eq 'jpg') {
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $quality
    $bmp.Save($dst, $codec, $ep)
  } else {
    $bmp.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  $bmp.Dispose()
}

function Write-Utf8([string]$p, [string]$s) { [IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding $false)) }
