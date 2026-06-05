$ErrorActionPreference = "Stop"

$sitePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8080
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)

$contentTypes = @{
  ".html" = "text/html; charset=utf-8"
  ".css" = "text/css; charset=utf-8"
  ".js" = "application/javascript; charset=utf-8"
  ".apk" = "application/vnd.android.package-archive"
  ".png" = "image/png"
  ".jpg" = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".webp" = "image/webp"
}

function Get-SafePath($relativePath) {
  $cleanPath = [Uri]::UnescapeDataString($relativePath.TrimStart("/"))
  if ([string]::IsNullOrWhiteSpace($cleanPath)) {
    $cleanPath = "index.html"
  }

  $fullPath = [System.IO.Path]::GetFullPath((Join-Path $sitePath $cleanPath))
  if (-not $fullPath.StartsWith($sitePath, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $null
  }

  return $fullPath
}

function Write-Response($stream, $status, $contentType, $body, $extraHeader) {
  $headers = "HTTP/1.1 $status`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`n"
  if ($extraHeader) {
    $headers += "$extraHeader`r`n"
  }
  $headers += "Connection: close`r`n`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  $stream.Write($body, 0, $body.Length)
}

try {
  $listener.Start()
} catch {
  Write-Host "Cannot start the website. Make sure port 8080 is available." -ForegroundColor Red
  throw
}

Write-Host ""
Write-Host "Tapgo download website is running." -ForegroundColor Green
Write-Host "Local URL:  http://localhost:$port"
Write-Host "LAN URL:    Use this computer's LAN IP with :$port, for example http://192.168.1.20:$port"
Write-Host ""
Write-Host "Keep this window open to keep the website online. Press Ctrl + C to stop."
Write-Host ""

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
      $requestLine = $reader.ReadLine()

      while ($reader.Peek() -ge 0) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($line)) {
          break
        }
      }

      if (-not $requestLine) {
        continue
      }

      $parts = $requestLine.Split(" ")
      $requestPath = "/"
      if ($parts.Length -ge 2) {
        $requestPath = $parts[1].Split("?")[0]
      }

      $filePath = Get-SafePath $requestPath
      if (-not $filePath -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        $body = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
        Write-Response $stream "404 Not Found" "text/plain; charset=utf-8" $body $null
        continue
      }

      $extension = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
      $contentType = $contentTypes[$extension]
      if (-not $contentType) {
        $contentType = "application/octet-stream"
      }

      $extraHeader = $null
      if ($extension -eq ".apk") {
        $extraHeader = "Content-Disposition: attachment; filename=app-debug.apk"
      }

      $body = [System.IO.File]::ReadAllBytes($filePath)
      Write-Response $stream "200 OK" $contentType $body $extraHeader
    } finally {
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
}
