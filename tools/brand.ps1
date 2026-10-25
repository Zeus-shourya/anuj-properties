<#
  Logo / favicon files from the brand mark (teal tile, "A" gable, marigold corner plot).

      powershell -ExecutionPolicy Bypass -File tools\brand.ps1

  Writes src\assets\img\brand\: favicon.svg, favicon.ico (16/32/48), apple-touch-icon.png (180),
  icon-192.png, icon-512.png, logo-512.png (used as the Organization logo in JSON-LD).
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$root  = Split-Path $PSScriptRoot -Parent
$out   = Join-Path $root 'src\assets\img\brand'
$cache = Join-Path $PSScriptRoot '.cache\brand'
New-Item -ItemType Directory -Force $out, $cache | Out-Null

$mark = '<rect width="64" height="64" rx="15" fill="#0F4C5C"/><path d="M41 0h8a15 15 0 0 1 15 15v8z" fill="#F2A43A"/><path d="M16.5 47 32 17.5 47.5 47" fill="none" stroke="#FFFBF4" stroke-width="5.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M23.6 37h16.8" fill="none" stroke="#FFFBF4" stroke-width="5.4" stroke-linecap="round"/>'
Write-Utf8 (Join-Path $out 'favicon.svg') "<svg xmlns=""http://www.w3.org/2000/svg"" viewBox=""0 0 64 64"">$mark</svg>`n"

# full-bleed square (no rounded corners) for platforms that apply their own mask
$markSquare = $mark.Replace('rx="15"', 'rx="0"')
$html = Join-Path $cache 'mark.html'
Write-Utf8 $html "<!doctype html><html><body style='margin:0;background:transparent'><svg xmlns='http://www.w3.org/2000/svg' width='512' height='512' viewBox='0 0 64 64'>$mark</svg></body></html>"
$png = Join-Path $cache 'mark-512.png'
Invoke-ChromeShot $html $png 512 512 -Transparent
Copy-Item $png (Join-Path $out 'logo-512.png') -Force
Save-Resized $png (Join-Path $out 'icon-192.png') 192 192

$html2 = Join-Path $cache 'mark-square.html'
Write-Utf8 $html2 "<!doctype html><html><body style='margin:0;background:#0F4C5C'><svg xmlns='http://www.w3.org/2000/svg' width='512' height='512' viewBox='0 0 64 64'>$markSquare</svg></body></html>"
$png2 = Join-Path $cache 'mark-square-512.png'
Invoke-ChromeShot $html2 $png2 512 512
Copy-Item $png2 (Join-Path $out 'icon-512.png') -Force
Save-Resized $png2 (Join-Path $out 'apple-touch-icon.png') 180 180

# favicon.ico with PNG-compressed 16/32/48 entries
$sizes = 16, 32, 48
$blobs = @()
foreach ($s in $sizes) {
  $p = Join-Path $cache "fav-$s.png"
  Save-Resized $png $p $s $s
  $blobs += , [IO.File]::ReadAllBytes($p)
}
$ms = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter $ms
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $bw.Write([byte]$sizes[$i]); $bw.Write([byte]$sizes[$i]); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([UInt16]1); $bw.Write([UInt16]32); $bw.Write([UInt32]$blobs[$i].Length); $bw.Write([UInt32]$offset)
  $offset += $blobs[$i].Length
}
foreach ($b in $blobs) { $bw.Write($b) }
$bw.Flush()
[IO.File]::WriteAllBytes((Join-Path $out 'favicon.ico'), $ms.ToArray())
$bw.Dispose()

Get-ChildItem $out | Select-Object Name, @{ n = 'KB'; e = { [Math]::Round($_.Length / 1KB, 1) } } | Format-Table -AutoSize | Out-String
