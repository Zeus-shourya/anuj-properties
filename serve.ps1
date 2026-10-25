<#
  Tiny static file server for local preview - no Node, no Python needed.

      powershell -ExecutionPolicy Bypass -File serve.ps1
      then open http://localhost:4381/

  Serves the built site in docs\ (run tools\build.ps1 first). Ctrl+C to stop.

  Behaves like GitHub Pages where it matters for testing:
   * /about  -> 301 to /about/  (relative links in the built pages rely on the slash)
   * unknown paths -> docs\404.html with a real 404 status
  Notes:
   * NoDelay - without it, Nagle + delayed ACK adds ~200ms to every response.
   * Poll before reading - browsers open speculative sockets they never use;
     blocking on ReadLine for those would stall every queued request.
#>
param([int]$Port = 4381, [string]$Root = (Join-Path $PSScriptRoot 'docs'))

$Root = (Resolve-Path $Root).Path

$mime = @{
  '.html'='text/html; charset=utf-8'; '.htm'='text/html; charset=utf-8'
  '.css' ='text/css; charset=utf-8';  '.js' ='text/javascript; charset=utf-8'
  '.svg' ='image/svg+xml';            '.json'='application/json; charset=utf-8'
  '.png' ='image/png';                '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'
  '.webp'='image/webp';               '.gif'='image/gif';  '.ico'='image/x-icon'
  '.woff'='font/woff';                '.woff2'='font/woff2'
  '.xml' ='application/xml; charset=utf-8'; '.txt' ='text/plain; charset=utf-8'
  '.webmanifest'='application/manifest+json'
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "Anuj Properties serving $Root" -ForegroundColor DarkGray
Write-Host "  ->  http://localhost:$Port/" -ForegroundColor Yellow

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $client.NoDelay = $true
      if (-not $client.Client.Poll(400000, [System.Net.Sockets.SelectMode]::SelectRead)) { continue }

      $stream = $client.GetStream()
      $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
      $line = $reader.ReadLine()
      if (-not $line) { continue }
      while ($reader.Peek() -ge 0) { if ([string]::IsNullOrEmpty($reader.ReadLine())) { break } }

      $parts   = $line -split ' '
      $rawPath = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
      $rawPath = ($rawPath -split '[?#]')[0]

      $rel = [System.Uri]::UnescapeDataString($rawPath).TrimStart('/')
      $full = Join-Path $Root ($rel -replace '/', '\')
      try { $full = [System.IO.Path]::GetFullPath($full) } catch { $full = '' }

      $body = $null; $status = '200 OK'; $type = 'text/plain; charset=utf-8'; $extra = ''

      if ($full -and $full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path $full -PathType Container) {
          if ($rawPath -notmatch '/$') {
            $status = '301 Moved Permanently'; $extra = "Location: $rawPath/`r`n"; $body = [byte[]]@()
          } else {
            $full = Join-Path $full 'index.html'
          }
        }
        if ($null -eq $body -and (Test-Path $full -PathType Leaf)) {
          $body = [System.IO.File]::ReadAllBytes($full)
          $ext  = [System.IO.Path]::GetExtension($full).ToLower()
          $type = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
        }
      }

      if ($null -eq $body) {
        $status = '404 Not Found'; $type = 'text/html; charset=utf-8'
        $nf = Join-Path $Root '404.html'
        $body = if (Test-Path $nf) { [System.IO.File]::ReadAllBytes($nf) } else { [System.Text.Encoding]::UTF8.GetBytes('<h1>404</h1>') }
      }

      # photos/fonts never change while you work; HTML/CSS/JS must not be cached here
      $cache = if ($rawPath -like '*/assets/img/*') { 'public, max-age=604800' } else { 'no-cache, no-store, must-revalidate' }

      $head = "HTTP/1.1 $status`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: $cache`r`n$($extra)Connection: close`r`n`r`n"
      $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
      $packet = New-Object byte[] ($hb.Length + $body.Length)
      [Array]::Copy($hb, 0, $packet, 0, $hb.Length)
      [Array]::Copy($body, 0, $packet, $hb.Length, $body.Length)
      $stream.Write($packet, 0, $packet.Length)
      $stream.Flush()
      Write-Host ("{0}  {1}" -f $status.Substring(0,3), $rawPath)
    } catch {
      Write-Host "err: $_" -ForegroundColor DarkRed
    } finally {
      try { $client.Close() } catch {}
    }
  }
} finally {
  $listener.Stop()
}
