Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\common.ps1"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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
