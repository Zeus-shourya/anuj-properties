<#
  Static site builder for Anuj Properties - no Node/Python needed.

      powershell -ExecutionPolicy Bypass -File tools\build.ps1

  Reads   src\site.json            business details (NAP, phone, base URL, analytics id...)
          src\partials\*.html      layout, header, footer, enquiry form, icons ...
          src\pages\**\*.html      one file per page: <!--page {json} --> front matter + body
          src\data\*.json          reviews, listings
          src\assets\**            css, js, images (copied as-is, CSS minified)
  Writes  docs\                    the publishable site (GitHub Pages serves /docs)

  Template syntax available in pages and partials:
    {{> name}}                     include src\partials\name.html
    {{name}} {{phone}} {{tel}} ... site tokens (see $tokens below)
    {{wa}} / {{wa:Hello text}}     WhatsApp link, optionally with a pre-filled message
    {{page.title}} ...             any front-matter value
    {{#if flag}} ... {{/if}}       flags: ga4, endpoint, listings, home, form
    {{photo name="x" alt="..." sizes="..." [eager] [class="..."]}}  responsive <picture>
    {{breadcrumbs}} {{faqs}} {{reviews:6}} {{listings}}

  Root-relative URLs (href="/about/") are rewritten to relative ones per page,
  so the same build works on localhost, on github.io/anuj-properties/ and on a
  custom domain. Canonical/OG/sitemap URLs use baseUrl from site.json.

  Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less scripts as ANSI).
#>
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$src   = Join-Path $root 'src'
$out   = Join-Path $root 'docs'
$utf8  = New-Object System.Text.UTF8Encoding $false
$today = (Get-Date).ToString('yyyy-MM-dd')
$year  = (Get-Date).Year

function Read-Text([string]$p) { [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) }
function Write-Text([string]$p, [string]$s) {
  $d = Split-Path $p -Parent
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
  [IO.File]::WriteAllText($p, $s, $utf8)
}
function Enc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function AttrUrl([string]$u) { $u.Replace('&', '&amp;') }
function UrlEnc([string]$s) { [Uri]::EscapeDataString($s) }
function Strip-Tags([string]$s) { ([regex]::Replace($s, '<[^>]+>', '')).Replace('&amp;', '&').Replace('&nbsp;', ' ').Trim() }
function To-Json($o) { $o | ConvertTo-Json -Depth 14 -Compress }

$site = (Read-Text (Join-Path $src 'site.json')) | ConvertFrom-Json
$base = $site.baseUrl.TrimEnd('/') + '/'
$basePath = ([Uri]$base).AbsolutePath
# (PS 5.1's ConvertFrom-Json emits a JSON array as ONE pipeline object - assign first, then enumerate)
$tmp = (Read-Text (Join-Path $src 'data\reviews.json')) | ConvertFrom-Json
$reviews = @($tmp)
$listingsFile = Join-Path $src 'data\listings.json'
$listings = @()
if (Test-Path $listingsFile) {
  $tmp = (Read-Text $listingsFile) | ConvertFrom-Json
  $listings = @(@($tmp) | Where-Object { $_ -and $_.status -ne 'hidden' })
}

$waBase  = "https://wa.me/$($site.whatsapp)"
$placeId = $site.google.placeId
$q       = UrlEnc "$($site.name), Parsvnath City, Sector 8, Sonipat"
$tokens = [ordered]@{
  '{{name}}'          = $site.name
  '{{hindiName}}'     = $site.hindiName
  '{{tagline}}'       = $site.tagline
  '{{since}}'         = [string]$site.since
  '{{years}}'         = [string]($year - [int]$site.since)
  '{{phone}}'         = $site.phone.display
  '{{phoneIntl}}'     = $site.phone.intl
  '{{tel}}'           = "tel:$($site.phone.e164)"
  '{{wa}}'            = $waBase
  '{{street}}'        = $site.address.street
  '{{addressShort}}'  = $site.address.short
  '{{locality}}'      = $site.address.locality
  '{{region}}'        = $site.address.region
  '{{postalCode}}'    = $site.address.postalCode
  '{{plusCode}}'      = $site.plusCode
  '{{hours}}'         = $site.hours.display
  '{{hoursShort}}'    = $site.hours.short
  '{{rating}}'        = $site.google.rating
  '{{reviewCount}}'   = [string]$site.google.reviewCount
  '{{ratingAsOf}}'    = $site.google.ratingAsOf
  '{{mapsUrl}}'       = AttrUrl "https://www.google.com/maps/search/?api=1&query=$q&query_place_id=$placeId"
  '{{directionsUrl}}' = AttrUrl "https://www.google.com/maps/dir/?api=1&destination=$q&destination_place_id=$placeId"
  '{{reviewsUrl}}'    = AttrUrl "https://search.google.com/local/reviews?placeid=$placeId"
  '{{writeReviewUrl}}'= AttrUrl "https://search.google.com/local/writereview?placeid=$placeId"
  '{{mapEmbedUrl}}'   = AttrUrl "https://maps.google.com/maps?q=$q&ll=$($site.geo.lat),$($site.geo.lng)&z=16&output=embed"
  '{{formEndpoint}}'  = AttrUrl ([string]$site.formEndpoint)
  '{{formAccessKey}}' = [string]$site.formAccessKey
  '{{year}}'          = [string]$year
  '{{baseUrl}}'       = $base
}

# ------------------------------------------------------------------ partials
$partials = @{}
Get-ChildItem (Join-Path $src 'partials') -File | ForEach-Object { $partials[$_.BaseName] = Read-Text $_.FullName }
function Expand-Partials([string]$html) {
  for ($i = 0; $i -lt 6; $i++) {
    if ($html -notmatch '\{\{>\s*[\w-]+\s*\}\}') { break }
    $html = [regex]::Replace($html, '\{\{>\s*([\w-]+)\s*\}\}', [Text.RegularExpressions.MatchEvaluator]{
      param($m) $n = $m.Groups[1].Value
      if (-not $partials.ContainsKey($n)) { throw "Unknown partial: $n" }
      $partials[$n]
    })
  }
  $html
}
function Expand-Conditionals([string]$html, [hashtable]$flags) {
  [regex]::Replace($html, '(?s)\{\{#if (!?)([\w-]+)\}\}(.*?)\{\{/if\}\}', [Text.RegularExpressions.MatchEvaluator]{
    param($m) $neg = $m.Groups[1].Value -eq '!'; $on = [bool]$flags[$m.Groups[2].Value]
    if ($on -xor $neg) { $m.Groups[3].Value } else { '' }
  }.GetNewClosure())
}

# ------------------------------------------------------------------ photos
Add-Type -AssemblyName System.Drawing
$photoDir = Join-Path $src 'assets\img\photos'
$photoInfo = @{}
function Get-PhotoInfo([string]$name) {
  if ($photoInfo.ContainsKey($name)) { return $photoInfo[$name] }
  $files = @(Get-ChildItem $photoDir -Filter "$name-*.jpg" | Where-Object { $_.BaseName -match "^$([regex]::Escape($name))-(\d+)$" })
  if (-not $files.Count) { throw "No photo files for '$name' in $photoDir" }
  $widths = @($files | ForEach-Object { [int]($_.BaseName -replace '^.*-(\d+)$', '$1') } | Sort-Object)
  $img = [System.Drawing.Image]::FromFile((Join-Path $photoDir "$name-$($widths[-1]).jpg"))
  $info = @{ widths = $widths; w = $img.Width; h = $img.Height }
  $img.Dispose()
  $photoInfo[$name] = $info
  $info
}
function Render-Photo([string]$attrText) {
  $a = @{}
  foreach ($m in [regex]::Matches($attrText, '([\w-]+)="([^"]*)"')) { $a[$m.Groups[1].Value] = $m.Groups[2].Value }
  $eager = $attrText -match '(^|\s)eager(\s|$)'
  $info = Get-PhotoInfo $a['name']
  $sizes = if ($a['sizes']) { $a['sizes'] } else { '100vw' }
  $p = "/assets/img/photos/$($a['name'])"
  $webp = ($info.widths | ForEach-Object { "$p-$_.webp ${_}w" }) -join ', '
  $jpg  = ($info.widths | ForEach-Object { "$p-$_.jpg ${_}w" }) -join ', '
  $mid  = $info.widths[[Math]::Floor(($info.widths.Count - 1) / 2)]
  $load = if ($eager) { 'loading="eager" fetchpriority="high"' } else { 'loading="lazy"' }
  $cls  = if ($a['class']) { " class=""$($a['class'])""" } else { '' }
  "<picture$cls><source type=""image/webp"" srcset=""$webp"" sizes=""$sizes""><img src=""$p-$mid.jpg"" srcset=""$jpg"" sizes=""$sizes"" width=""$($info.w)"" height=""$($info.h)"" alt=""$($a['alt'])"" $load decoding=""async""></picture>"
}

# ------------------------------------------------------------------ components
function Render-Breadcrumbs($crumbs) {
  $items = @('<li><a href="/">Home</a></li>')
  for ($i = 0; $i -lt $crumbs.Count; $i++) {
    $c = $crumbs[$i]
    if ($i -eq $crumbs.Count - 1) { $items += "<li><span aria-current=""page"">$(Enc $c[0])</span></li>" }
    else { $items += "<li><a href=""$($c[1])"">$(Enc $c[0])</a></li>" }
  }
  "<nav class=""crumbs"" aria-label=""Breadcrumb""><ol>$($items -join '')</ol></nav>"
}
function Render-Faqs($faqs) {
  $h = @()
  foreach ($f in $faqs) {
    $h += "<details class=""faq""><summary><span>$($f[0])</span><svg class=""faq__icon"" aria-hidden=""true""><use href=""#i-plus""/></svg></summary><div class=""faq__a"">$($f[1])</div></details>"
  }
  "<div class=""faqs"">$($h -join '')</div>"
}
function Render-Reviews([int]$n) {
  $stars = '<span class="stars" aria-label="Rated 5 out of 5"><svg aria-hidden="true"><use href="#i-star"/></svg><svg aria-hidden="true"><use href="#i-star"/></svg><svg aria-hidden="true"><use href="#i-star"/></svg><svg aria-hidden="true"><use href="#i-star"/></svg><svg aria-hidden="true"><use href="#i-star"/></svg></span>'
  $h = @()
  foreach ($r in ($reviews | Select-Object -First $n)) {
    $h += "<figure class=""review"">$stars<blockquote><p>$(Enc $r.text)</p></blockquote><figcaption><span class=""review__name"">$(Enc $r.name)</span><span class=""review__src"">Google review</span></figcaption></figure>"
  }
  "<div class=""reviews"">$($h -join '')</div>"
}
function Render-Listings {
  if (-not $listings.Count) { return '' }
  $h = @()
  foreach ($l in $listings) {
    $msg = "Hi Anuj Properties, I'm interested in: $($l.title) ($($l.locality)) [ref $($l.id)]"
    $photo = if ($l.photo) { Render-Photo "name=""$($l.photo)"" alt=""$(Enc $l.title)"" sizes=""(min-width: 960px) 380px, 100vw""" } else { '<div class="listing__ph" aria-hidden="true"><svg><use href="#i-plot"/></svg></div>' }
    $feat = if ($l.features) { '<ul class="listing__feat">' + (($l.features | ForEach-Object { "<li>$(Enc $_)</li>" }) -join '') + '</ul>' } else { '' }
    $badge = if ($l.status -eq 'available') { '' } else { "<span class=""listing__status"">$(Enc $l.status)</span>" }
    $h += "<article class=""listing"" id=""$($l.id)"">$photo<div class=""listing__body""><p class=""listing__meta"">$(Enc $l.purpose) &middot; $(Enc $l.type)</p><h3>$(Enc $l.title)</h3><p class=""listing__loc"">$(Enc $l.locality)</p><dl class=""listing__facts""><div><dt>Size</dt><dd>$(Enc $l.size)</dd></div><div><dt>Price</dt><dd>$(Enc $l.price)</dd></div></dl>$feat$badge<a class=""btn btn--wa btn--block"" href=""$waBase`?text=$(UrlEnc $msg)"" data-track=""whatsapp""><svg aria-hidden=""true""><use href=""#i-whatsapp""/></svg>Ask about this property</a></div></article>"
  }
  "<div class=""listings"">$($h -join '')</div>"
}

# ------------------------------------------------------------------ JSON-LD
$businessId = "$base#business"
$websiteId  = "$base#website"
function Business-Node {
  [ordered]@{
    '@type' = 'RealEstateAgent'; '@id' = $businessId
    name = $site.name; alternateName = $site.hindiName; slogan = $site.tagline
    description = $site.description; url = $base
    telephone = $site.phone.e164
    image = @("$($base)assets/img/photos/office-front-900.jpg", "$($base)assets/img/photos/office-sign-1200.jpg", "$($base)assets/img/photos/office-lounge-1200.jpg")
    logo = "$($base)assets/img/brand/logo-512.png"
    foundingDate = [string]$site.since
    address = [ordered]@{ '@type' = 'PostalAddress'; streetAddress = $site.address.street; addressLocality = $site.address.locality; addressRegion = $site.address.region; postalCode = $site.address.postalCode; addressCountry = $site.address.country }
    geo = [ordered]@{ '@type' = 'GeoCoordinates'; latitude = $site.geo.lat; longitude = $site.geo.lng }
    hasMap = "https://www.google.com/maps?cid=$($site.google.cid)"
    openingHoursSpecification = @([ordered]@{ '@type' = 'OpeningHoursSpecification'; dayOfWeek = @('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'); opens = $site.hours.opens; closes = $site.hours.closes })
    areaServed = @(
      [ordered]@{ '@type' = 'Place'; name = 'Parsvnath City, Sector 8, Sonipat' },
      [ordered]@{ '@type' = 'Place'; name = 'Omaxe City, Sonipat' },
      [ordered]@{ '@type' = 'City'; name = 'Sonipat'; containedInPlace = [ordered]@{ '@type' = 'State'; name = 'Haryana' } })
    knowsAbout = @('Residential plots', 'Independent houses and kothis', 'Builder floors', 'Flats and apartments', 'Farmhouses', 'Shops, showrooms and office space', 'Rental and leasing', 'Property valuation', 'Property documentation')
    contactPoint = [ordered]@{ '@type' = 'ContactPoint'; telephone = $site.phone.e164; contactType = 'sales'; areaServed = 'IN'; availableLanguage = @('English', 'Hindi') }
    sameAs = @($site.sameAs)
  }
}
function Build-JsonLd($fm, [string]$url, [string]$ogImage) {
  $graph = New-Object System.Collections.ArrayList
  $isHome = $fm.path -eq '/'
  if ($fm.noindex) { return '' }
  [void]$graph.Add((Business-Node))
  if ($isHome) {
    [void]$graph.Add([ordered]@{ '@type' = 'WebSite'; '@id' = $websiteId; url = $base; name = $site.name; inLanguage = 'en-IN'; publisher = @{ '@id' = $businessId } })
  }
  $ptype = switch ($fm.pageType) { 'about' { 'AboutPage' } 'contact' { 'ContactPage' } 'collection' { 'CollectionPage' } default { if ($fm.faqs) { 'FAQPage' } else { 'WebPage' } } }
  $page = [ordered]@{ '@type' = $ptype; '@id' = "$url#webpage"; url = $url; name = $fm.title; description = $fm.description; inLanguage = 'en-IN'; isPartOf = @{ '@id' = $websiteId }; about = @{ '@id' = $businessId }; primaryImageOfPage = $ogImage; dateModified = $fm.updated }
  if (-not $isHome) { $page['breadcrumb'] = @{ '@id' = "$url#breadcrumb" } }
  if ($fm.faqs) {
    $page['mainEntity'] = @($fm.faqs | ForEach-Object { [ordered]@{ '@type' = 'Question'; name = (Strip-Tags $_[0]); acceptedAnswer = [ordered]@{ '@type' = 'Answer'; text = (Strip-Tags $_[1]) } } })
  }
  [void]$graph.Add($page)
  if (-not $isHome) {
    $items = New-Object System.Collections.ArrayList
    [void]$items.Add([ordered]@{ '@type' = 'ListItem'; position = 1; name = 'Home'; item = $base })
    $pos = 2
    foreach ($c in $fm.crumbs) {
      $curl = if ($c.Count -gt 1) { $base + $c[1].TrimStart('/') } else { $url }
      [void]$items.Add([ordered]@{ '@type' = 'ListItem'; position = $pos; name = $c[0]; item = $curl }); $pos++
    }
    [void]$graph.Add([ordered]@{ '@type' = 'BreadcrumbList'; '@id' = "$url#breadcrumb"; itemListElement = @($items) })
  }
  if ($fm.service) {
    [void]$graph.Add([ordered]@{ '@type' = 'Service'; '@id' = "$url#service"; name = $fm.service.name; serviceType = $fm.service.type; description = $fm.description; url = $url; provider = @{ '@id' = $businessId }
      areaServed = @(@($fm.service.areas) | ForEach-Object { [ordered]@{ '@type' = 'Place'; name = $_ } }) })
  }
  if ($fm.article) {
    [void]$graph.Add([ordered]@{ '@type' = 'Article'; '@id' = "$url#article"; headline = $fm.article.headline; description = $fm.description; image = $ogImage
      datePublished = $fm.article.published; dateModified = $fm.updated; inLanguage = 'en-IN'
      author = [ordered]@{ '@type' = 'Organization'; name = $site.name; url = $base }; publisher = @{ '@id' = $businessId }; mainEntityOfPage = @{ '@id' = "$url#webpage" } })
  }
  if ($fm.place) {
    $pl = [ordered]@{ '@type' = 'Place'; '@id' = "$url#place"; name = $fm.place.name; description = $fm.place.description
      address = [ordered]@{ '@type' = 'PostalAddress'; addressLocality = 'Sonipat'; addressRegion = 'Haryana'; addressCountry = 'IN' } }
    if ($fm.place.lat) { $pl['geo'] = [ordered]@{ '@type' = 'GeoCoordinates'; latitude = $fm.place.lat; longitude = $fm.place.lng } }
    $page['about'] = @(@{ '@id' = "$url#place" }, @{ '@id' = $businessId })
    [void]$graph.Add($pl)
  }
  $json = To-Json ([ordered]@{ '@context' = 'https://schema.org'; '@graph' = @($graph) })
  "<script type=""application/ld+json"">$json</script>"
}

# ------------------------------------------------------------------ assets
Write-Host 'Copying assets...' -ForegroundColor DarkGray
if (-not (Test-Path $out)) { New-Item -ItemType Directory -Force $out | Out-Null }
$rc = Start-Process robocopy -ArgumentList @("`"$(Join-Path $src 'assets')`"", "`"$(Join-Path $out 'assets')`"", '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') -Wait -PassThru -WindowStyle Hidden
if ($rc.ExitCode -ge 8) { throw "robocopy failed ($($rc.ExitCode))" }
foreach ($f in 'favicon.ico') { if (Test-Path (Join-Path $src "assets\img\brand\$f")) { Copy-Item (Join-Path $src "assets\img\brand\$f") (Join-Path $out $f) -Force } }

$cssRaw = Read-Text (Join-Path $src 'assets\css\site.css')
$css = [regex]::Replace($cssRaw, '(?s)/\*.*?\*/', '')
$css = [regex]::Replace($css, '\s+', ' ')
$css = [regex]::Replace($css, '\s*([{};,])\s*', '$1')
$css = $css.Replace(';}', '}').Trim()
Write-Text (Join-Path $out 'assets\css\site.css') $css
$sha = [System.Security.Cryptography.SHA1]::Create()
function Short-Hash([string]$s) { (($sha.ComputeHash($utf8.GetBytes($s)) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') }) -join '') }
$cssv = Short-Hash $css
$jsv  = Short-Hash (Read-Text (Join-Path $src 'assets\js\site.js'))
$fontHref = 'https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700&amp;display=swap'

# ------------------------------------------------------------------ pages
$pages = @()
foreach ($file in Get-ChildItem (Join-Path $src 'pages') -Recurse -Filter *.html) {
  $raw = Read-Text $file.FullName
  $m = [regex]::Match($raw, '(?s)^\s*<!--page\s*(\{.*?\})\s*-->')
  if (-not $m.Success) { throw "Missing <!--page {...} --> front matter in $($file.FullName)" }
  try { $fm = $m.Groups[1].Value | ConvertFrom-Json } catch { throw "Bad front matter JSON in $($file.Name): $_" }
  if (-not $fm.updated) { $fm | Add-Member -NotePropertyName updated -NotePropertyValue $today -Force }
  $pages += @{ fm = $fm; body = $raw.Substring($m.Length); file = $file.FullName }
}
$pagePaths = @{}
foreach ($p in $pages) {
  if ($pagePaths.ContainsKey($p.fm.path)) { throw "Duplicate path $($p.fm.path)" }
  $pagePaths[$p.fm.path] = $true
}

# clear previously built pages so deleted or renamed pages don't linger in docs\
$assetsDir = Join-Path $out 'assets'
Get-ChildItem $out -Recurse -File -Filter index.html | Where-Object { -not $_.FullName.StartsWith($assetsDir) } | ForEach-Object { $_.Delete() }
Get-ChildItem $out -Recurse -Directory | Where-Object { -not $_.FullName.StartsWith($assetsDir) } |
  Sort-Object { $_.FullName.Length } -Descending | Where-Object { -not (Get-ChildItem $_.FullName -Force) } | ForEach-Object { $_.Delete() }

$report = New-Object System.Collections.ArrayList
$allLinks = New-Object System.Collections.ArrayList
$seenTitles = @{}; $seenDescs = @{}
$sitemap = New-Object System.Collections.ArrayList

foreach ($p in $pages) {
  $fm = $p.fm
  $path = $fm.path
  $is404 = $path -eq '/404.html'
  $url = if ($is404) { $base + '404.html' } else { $base + $path.TrimStart('/') }
  $slug = if ($path -eq '/') { 'home' } else { ($path.Trim('/') -replace '/', '-') -replace '\.html$', '' }
  $ogRel = if (Test-Path (Join-Path $src "assets\img\og\$slug.jpg")) { "assets/img/og/$slug.jpg" } else { 'assets/img/og/default.jpg' }
  $ogImage = $base + $ogRel

  $flags = @{ ga4 = [bool]$site.ga4Id; endpoint = [bool]$site.formEndpoint; listings = ($listings.Count -gt 0); home = ($path -eq '/'); form = [bool]($p.body -match '\{\{>\s*enquiry\s*\}\}') }

  $body = Expand-Partials $p.body
  $html = Expand-Partials $partials['layout']
  $html = $html.Replace('{{content}}', $body)
  $html = Expand-Conditionals $html $flags

  # components
  if ($fm.crumbs) { $html = $html.Replace('{{breadcrumbs}}', (Render-Breadcrumbs $fm.crumbs)) } else { $html = $html.Replace('{{breadcrumbs}}', '') }
  if ($fm.faqs)   { $html = $html.Replace('{{faqs}}', (Render-Faqs $fm.faqs)) }
  $html = [regex]::Replace($html, '\{\{reviews:(\d+)\}\}', [Text.RegularExpressions.MatchEvaluator]{ param($mm) Render-Reviews ([int]$mm.Groups[1].Value) })
  $html = $html.Replace('{{listings}}', (Render-Listings))
  $html = [regex]::Replace($html, '\{\{photo\s+([^}]*)\}\}', [Text.RegularExpressions.MatchEvaluator]{ param($mm) Render-Photo $mm.Groups[1].Value })

  # enquiry-form presets
  $form = $fm.form
  $presets = @{ intent = 'Buy'; type = ''; area = ''; heading = 'Tell us what you need'; sub = 'Share a few details and send them to us on WhatsApp in one tap.'; submit = 'Send on WhatsApp' }
  if ($form) { foreach ($k in @($presets.Keys)) { if ($form.$k) { $presets[$k] = $form.$k } } }
  foreach ($k in $presets.Keys) { $html = $html.Replace("{{form.$k}}", (Enc $presets[$k])) }

  # head
  $robots = if ($fm.noindex) { 'noindex, follow' } else { 'index, follow, max-image-preview:large' }
  $ogType = if ($fm.article) { 'article' } else { 'website' }
  $ogTitle = if ($fm.ogTitle) { $fm.ogTitle } else { $fm.title }
  $cssTag = if ($site.inlineCss) { "<style>$css</style>" } else { "<link rel=""stylesheet"" href=""/assets/css/site.css?v=$cssv"">" }
  $preload = ''
  if ($fm.preloadPhoto) {
    $pi = Get-PhotoInfo $fm.preloadPhoto
    $pre = ($pi.widths | ForEach-Object { "/assets/img/photos/$($fm.preloadPhoto)-$_.webp ${_}w" }) -join ', '
    $preload = "<link rel=""preload"" as=""image"" type=""image/webp"" imagesrcset=""$pre"" imagesizes=""$($fm.preloadSizes)"" fetchpriority=""high"">"
  }
  $canonical = if ($is404) { '' } else { "<link rel=""canonical"" href=""$url"">" }
  $ga = ''
  if ($site.ga4Id) {
    $ga = "<script async src=""https://www.googletagmanager.com/gtag/js?id=$($site.ga4Id)""></script><script>window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments)}gtag('js',new Date());gtag('config','$($site.ga4Id)');</script>"
  }
  $head = @(
    '<meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    "<title>$(Enc $fm.title)</title>"
    "<meta name=""description"" content=""$(Enc $fm.description)"">"
    $canonical
    "<meta name=""robots"" content=""$robots"">"
    '<meta name="theme-color" content="#0F4C5C">'
    '<meta name="format-detection" content="telephone=no">'
    "<meta property=""og:type"" content=""$ogType"">"
    "<meta property=""og:site_name"" content=""$(Enc $site.name)"">"
    '<meta property="og:locale" content="en_IN">'
    "<meta property=""og:title"" content=""$(Enc $ogTitle)"">"
    "<meta property=""og:description"" content=""$(Enc $fm.description)"">"
    "<meta property=""og:url"" content=""$url"">"
    "<meta property=""og:image"" content=""$ogImage"">"
    '<meta property="og:image:width" content="1200">'
    '<meta property="og:image:height" content="630">'
    "<meta property=""og:image:alt"" content=""$(Enc $ogTitle)"">"
    '<meta name="twitter:card" content="summary_large_image">'
    '<link rel="icon" href="/favicon.ico" sizes="32x32">'
    '<link rel="icon" href="/assets/img/brand/favicon.svg" type="image/svg+xml">'
    '<link rel="apple-touch-icon" href="/assets/img/brand/apple-touch-icon.png">'
    '<link rel="manifest" href="/site.webmanifest">'
    '<link rel="preconnect" href="https://fonts.googleapis.com">'
    '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
    "<link rel=""stylesheet"" href=""$fontHref"" media=""print"" onload=""this.media='all'"">"
    "<noscript><link rel=""stylesheet"" href=""$fontHref""></noscript>"
    $preload
    $cssTag
    (Build-JsonLd $fm $url $ogImage)
    $ga
  ) | Where-Object { $_ }
  $html = $html.Replace('{{head}}', ($head -join "`n"))
  $bodyClass = if ($fm.bodyClass) { $fm.bodyClass } else { 'page' }
  $html = $html.Replace('{{bodyClass}}', $bodyClass).Replace('{{jsv}}', $jsv)

  # tokens ({{waPage}} = WhatsApp link with this page's pre-filled message)
  $waText = if ($fm.waText) { $fm.waText } else { 'Hi Anuj Properties, I have a property enquiry.' }
  $html = $html.Replace('{{waPage}}', "{{wa:$waText}}")
  $html = [regex]::Replace($html, '\{\{wa:([^}]+)\}\}', [Text.RegularExpressions.MatchEvaluator]{ param($mm) "$waBase`?text=" + (UrlEnc ([System.Net.WebUtility]::HtmlDecode($mm.Groups[1].Value))) })
  foreach ($k in $tokens.Keys) { $html = $html.Replace($k, $tokens[$k]) }
  # (evaluators below run at script scope, so they see $fm/$navKey/$prefix and the script's functions;
  #  .GetNewClosure() would hide those functions)
  $html = [regex]::Replace($html, '\{\{page\.(\w+)\}\}', [Text.RegularExpressions.MatchEvaluator]{ param($mm) Enc ([string]$fm.($mm.Groups[1].Value)) })
  $navKey = [string]$fm.nav
  $html = [regex]::Replace($html, '\{\{navcur:(\w+)\}\}', [Text.RegularExpressions.MatchEvaluator]{ param($mm) if ($mm.Groups[1].Value -eq $navKey) { ' is-current' } else { '' } })
  $enquireTarget = if ($html -match 'id="enquire"') { '#enquire' } else { '/contact/#enquire' }
  $html = $html.Replace('{{enquireHref}}', $enquireTarget)

  # aria-current on the matching header link
  $hm = [regex]::Match($html, '(?s)<header.*?</header>')
  if ($hm.Success -and -not $is404) {
    $hdr = $hm.Value.Replace("href=""$path""", "href=""$path"" aria-current=""page""")
    $html = $html.Substring(0, $hm.Index) + $hdr + $html.Substring($hm.Index + $hm.Length)
  }

  # ---- audit (on root-relative html, before rewriting)
  $issues = @()
  if ($html -match '\{\{') { $issues += 'unresolved template token: ' + ([regex]::Match($html, '\{\{[^}]{0,40}')).Value }
  $h1 = ([regex]::Matches($html, '<h1[\s>]')).Count
  if ($h1 -ne 1) { $issues += "h1 count = $h1" }
  if ($fm.title.Length -gt 65) { $issues += "title $($fm.title.Length) chars" }
  if ($fm.description.Length -lt 70 -or $fm.description.Length -gt 160) { $issues += "description $($fm.description.Length) chars" }
  if (-not $fm.noindex) {
    if ($seenTitles.ContainsKey($fm.title)) { $issues += 'duplicate title with ' + $seenTitles[$fm.title] }
    if ($seenDescs.ContainsKey($fm.description)) { $issues += 'duplicate description with ' + $seenDescs[$fm.description] }
    $seenTitles[$fm.title] = $path; $seenDescs[$fm.description] = $path
  }
  foreach ($im in [regex]::Matches($html, '<img\b[^>]*>')) {
    $tag = $im.Value
    if ($tag -notmatch '\salt="') { $issues += 'img without alt: ' + $tag.Substring(0, [Math]::Min(80, $tag.Length)) }
    if ($tag -notmatch '\swidth="' -or $tag -notmatch '\sheight="') { $issues += 'img without width/height: ' + $tag.Substring(0, [Math]::Min(80, $tag.Length)) }
  }
  $ids = [regex]::Matches($html, '\sid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
  $dupIds = $ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
  if ($dupIds) { $issues += 'duplicate ids: ' + ($dupIds -join ', ') }
  foreach ($lm in [regex]::Matches($html, '\s(?:href|src)="(/[^"]*)"')) { [void]$allLinks.Add(@{ from = $path; to = $lm.Groups[1].Value }) }
  foreach ($lm in [regex]::Matches($html, 'href="#([^"]+)"')) { if ($ids -notcontains $lm.Groups[1].Value) { $issues += "in-page anchor #$($lm.Groups[1].Value) has no target" } }
  [void]$report.Add(@{ path = $path; issues = $issues; bytes = $utf8.GetByteCount($html) })

  # ---- rewrite root-relative URLs for this page's location
  if ($is404) { $prefix = $basePath }
  else { $depth = ($path.Trim('/').Split('/', [StringSplitOptions]::RemoveEmptyEntries)).Count; $prefix = ('../' * $depth) }
  $html = [regex]::Replace($html, '(\s(?:href|src|action|poster|data-src)=")/(?!/)', [Text.RegularExpressions.MatchEvaluator]{ param($mm) $mm.Groups[1].Value + $prefix })
  $html = [regex]::Replace($html, '(\s(?:srcset|imagesrcset)=")([^"]*)(")', [Text.RegularExpressions.MatchEvaluator]{
    param($mm) $list = [regex]::Replace($mm.Groups[2].Value, '(^|,\s*)/(?!/)', [Text.RegularExpressions.MatchEvaluator]{ param($nn) $nn.Groups[1].Value + $prefix })
    $mm.Groups[1].Value + $list + $mm.Groups[3].Value })
  $html = $html.Replace('href=""', 'href="./"')

  $target = if ($is404) { Join-Path $out '404.html' } else { Join-Path $out (($path.Trim('/') -replace '/', '\') + '\index.html') }
  if ($path -eq '/') { $target = Join-Path $out 'index.html' }
  Write-Text $target $html
  if (-not $fm.noindex -and -not $is404) { [void]$sitemap.Add("<url><loc>$url</loc><lastmod>$($fm.updated)</lastmod></url>") }
}

# ------------------------------------------------------------------ site files
Write-Text (Join-Path $out 'sitemap.xml') ("<?xml version=""1.0"" encoding=""UTF-8""?>`n<urlset xmlns=""http://www.sitemaps.org/schemas/sitemap/0.9"">`n" + ($sitemap -join "`n") + "`n</urlset>`n")
Write-Text (Join-Path $out 'robots.txt') "User-agent: *`nAllow: /`n`nSitemap: $($base)sitemap.xml`n"
Write-Text (Join-Path $out '.nojekyll') ''
$manifest = [ordered]@{ name = $site.name; short_name = 'Anuj Properties'; start_url = './'; scope = './'; display = 'browser'; background_color = '#FFFBF4'; theme_color = '#0F4C5C'
  icons = @([ordered]@{ src = 'assets/img/brand/icon-192.png'; sizes = '192x192'; type = 'image/png' }, [ordered]@{ src = 'assets/img/brand/icon-512.png'; sizes = '512x512'; type = 'image/png' }) }
Write-Text (Join-Path $out 'site.webmanifest') ($manifest | ConvertTo-Json -Depth 5)
$cname = Join-Path $out 'CNAME'
if ($site.customDomain) { Write-Text $cname $site.customDomain } elseif (Test-Path $cname) { Remove-Item $cname }

# ------------------------------------------------------------------ link check
$broken = @()
foreach ($l in $allLinks) {
  $t = ($l.to -split '[?#]')[0]
  if ($t -eq '' ) { continue }
  if ($t.EndsWith('/')) { if (-not $pagePaths.ContainsKey($t)) { $broken += "$($l.from) -> $($l.to)" } }
  else {
    $f = Join-Path $out ($t.TrimStart('/') -replace '/', '\')
    if (-not (Test-Path $f -PathType Leaf)) { $broken += "$($l.from) -> $($l.to)" }
  }
}

# ------------------------------------------------------------------ report
$total = 0
foreach ($r in $report) {
  $total += $r.issues.Count
  $kb = [Math]::Round($r.bytes / 1KB, 1)
  if ($r.issues.Count) { Write-Host ("  {0,-48} {1,6} KB" -f $r.path, $kb) -ForegroundColor Yellow; $r.issues | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow } }
  else { Write-Host ("  {0,-48} {1,6} KB  ok" -f $r.path, $kb) -ForegroundColor DarkGray }
}
if ($broken) { Write-Host "Broken internal links:" -ForegroundColor Red; $broken | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Red } }
Write-Host ("Built {0} pages into {1}  ({2} issues, {3} broken links)" -f $pages.Count, $out, $total, @($broken | Sort-Object -Unique).Count) -ForegroundColor Green
if ($broken -or $total) { exit 1 }
