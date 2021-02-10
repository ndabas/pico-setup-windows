function crawl {
  param ([string]$url)

  (Invoke-WebRequest $url -UseBasicParsing).Links | ForEach-Object {
    try {
      (New-Object System.Uri([uri]$url, $_.href)).AbsoluteUri
    }
    catch {
      $_.href
    }
  }
}

function mkdirp {
  param ([string] $dir)

  New-Item -Path $dir -Type Directory -Force | Out-Null
}

crawl 'https://www.raspberrypi.org/documentation/pico/getting-started/' |
Sort-Object -Unique |
Where-Object { ([uri]$_).Authority -match '\.raspberrypi.org$' } |
ForEach-Object {
  $dir = $null

  switch -regex ($_) {
    '\.pdf$' { $dir = 'docs' }
    '\.zip$' { $dir = 'design' }
    '\.uf2$' { $dir = 'uf2' }
  }

  if ($dir) {
    Write-Host "Downloading $_"
    mkdirp $dir
    $fileName = ([uri]$_).Segments[-1]
    Invoke-WebRequest $_ -OutFile (Join-Path $dir $fileName)
  }
}
