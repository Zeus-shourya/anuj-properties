<#
  Social share images (Open Graph, 1200x630) - one per page, headline = the page's H1.
  WhatsApp, Facebook and LinkedIn show these when a page link is shared.

      powershell -ExecutionPolicy Bypass -File tools\og.ps1

  Writes src\assets\img\og\<slug>.jpg and default.jpg (= home). Re-run after changing an H1,
  then run tools\build.ps1. Needs internet (the heading font loads from Google Fonts).
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$root  = Split-Path $PSScriptRoot -Parent
$src   = Join-Path $root 'src'
$out   = Join-Path $src 'assets\img\og'
$cache = Join-Path $PSScriptRoot '.cache\og'
New-Item -ItemType Directory -Force $out, $cache | Out-Null

$photo = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $src 'assets\img\photos\office-front-720.jpg')))
$mark  = '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><rect width="64" height="64" rx="15" fill="#0F4C5C"/><path d="M41 0h8a15 15 0 0 1 15 15v8z" fill="#F2A43A"/><path d="M16.5 47 32 17.5 47.5 47" fill="none" stroke="#FFFBF4" stroke-width="5.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M23.6 37h16.8" fill="none" stroke="#FFFBF4" stroke-width="5.4" stroke-linecap="round"/></svg>'
$css = @'
body{margin:0;width:1200px;height:630px;overflow:hidden;font-family:"Segoe UI",system-ui,sans-serif}
.og{position:relative;width:1200px;height:630px;background:#08343D;color:#fff;overflow:hidden}
.grid{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.055) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.055) 1px,transparent 1px);background-size:72px 48px}
.photo{position:absolute;right:0;top:0;width:470px;height:630px;object-fit:cover;object-position:60% 40%}
.shade{position:absolute;right:0;top:0;width:470px;height:630px;background:linear-gradient(90deg,#08343D 0%,rgba(8,52,61,.35) 30%,rgba(8,52,61,0) 70%)}
.corner{position:absolute;right:0;top:0;width:150px;height:150px;background:#F2A43A;clip-path:polygon(38% 0,100% 0,100% 62%)}
.content{position:absolute;left:72px;top:60px;bottom:60px;width:680px;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:16px}
.brand svg{width:64px;height:64px;flex:none}
.brand b{display:block;font-family:"Bricolage Grotesque";font-size:34px;letter-spacing:-.02em;line-height:1.1}
.brand span{display:block;font-size:15px;letter-spacing:.16em;text-transform:uppercase;color:#F9D49E;font-weight:700;margin-top:4px}
h1{font-family:"Bricolage Grotesque";font-weight:700;line-height:1.06;letter-spacing:-.03em;margin:auto 0 0}
.foot{margin-top:30px;display:flex;align-items:center;gap:18px;font-size:21px;color:#D4E6E4}
.pill{background:#25D366;color:#06331C;font-weight:800;padding:11px 20px;border-radius:999px;font-size:21px}
'@

$pages = Get-ChildItem (Join-Path $src 'pages') -Recurse -Filter *.html
foreach ($f in $pages) {
  $raw = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
  $m = [regex]::Match($raw, '(?s)^\s*<!--page\s*(\{.*?\})\s*-->')
  $fm = $m.Groups[1].Value | ConvertFrom-Json
  if ($fm.noindex) { continue }
  $h = [regex]::Match($raw, '(?s)<h1[^>]*>(.*?)</h1>').Groups[1].Value
  $headline = [System.Net.WebUtility]::HtmlDecode(([regex]::Replace($h, '<[^>]+>', '')).Trim())
  $size = if ($headline.Length -gt 62) { 48 } elseif ($headline.Length -gt 44) { 56 } else { 64 }
  $slug = if ($fm.path -eq '/') { 'home' } else { $fm.path.Trim('/') -replace '/', '-' }
  $enc = [System.Net.WebUtility]::HtmlEncode($headline)
  $html = "<!doctype html><html><head><meta charset='utf-8'><link rel='stylesheet' href='https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700&display=block'><style>$css</style></head><body><div class='og'><div class='grid'></div><img class='photo' src='data:image/jpeg;base64,$photo'><div class='shade'></div><div class='corner'></div><div class='content'><div class='brand'>$mark<div><b>Anuj Properties</b><span>Since 1998 &middot; Sonipat</span></div></div><h1 style='font-size:${size}px'>$enc</h1><div class='foot'><span class='pill'>Call / WhatsApp 98134 41130</span><span>A Block, Parsvnath City, Sector 8</span></div></div></div></body></html>"
  $htmlPath = Join-Path $cache "$slug.html"
  [IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding $false))
  $png = Join-Path $cache "$slug.png"
  Invoke-ChromeShot $htmlPath $png 1200 630
  Save-Resized $png (Join-Path $out "$slug.jpg") 1200 630 'jpg' 84
  if ($slug -eq 'home') { Copy-Item (Join-Path $out 'home.jpg') (Join-Path $out 'default.jpg') -Force }
  Write-Host "og: $slug"
}
Get-ChildItem $out | Measure-Object -Property Length -Sum | ForEach-Object { "{0} images, {1:N0} KB" -f $_.Count, ($_.Sum / 1KB) }
