Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function crawl {
  param ([string]$url)

  (Invoke-WebRequest $url -UseBasicParsing).Links | Where-Object { $_ | Get-Member href } | ForEach-Object {
    try {
      (New-Object System.Uri([uri]$url, $_.href)).AbsoluteUri
    }
    catch {
      $_.href
    }
  }
}

foreach ($arch in @('x86.json', 'x64.json')) {
  $config = Get-Content $arch | ConvertFrom-Json
  $bitness = $config.bitness

  foreach ($i in $config.installers) {
    [uri]$newUrl = switch ($i.name) {

      'GNU Arm Embedded Toolchain' {
        crawl 'https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm/downloads' |
        Where-Object { $_ -match "-win$bitness\.exe" } |
        Select-Object -First 1
      }

      'Build Tools for Visual Studio 2019' {
        $resp = Invoke-WebRequest 'https://visualstudio.microsoft.com/thank-you-downloading-visual-studio/?sku=BuildTools&rel=16' -UseBasicParsing
        $resp.Content -match "['`"](http[^'`"]+\.exe)[`'`"]" | Out-Null
        $Matches[1]
      }

      'CMake' {
        $rel = (Invoke-RestMethod 'https://api.github.com/repos/Kitware/CMake/releases') |
        Where-Object { $_.tag_name -match '^v([0-9]+\.)+[0-9]$' } |
        Select-Object -First 1
        $asset = $rel.assets |
        Where-Object { $_.name -match "win$bitness-x[0-9]{2}\.msi$" }
        $asset.browser_download_url
      }

      'Python 3.8' {
        $suffix = ''
        if ($config.bitness -eq 64) { $suffix = '-amd64' }

        crawl 'https://www.python.org/downloads/windows/' |
        Where-Object { $_ -match "python-3\.8\.[0-9]+$suffix\.exe$" } |
        Select-Object -First 1
      }

      'Git for Windows' {
        $rel = (Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases') |
        Where-Object { $_.prerelease -eq $false } |
        Select-Object -First 1
        $asset = $rel.assets |
        Where-Object { $_.name -match "^Git-([0-9]+\.)+[0-9]-$bitness-bit\.exe$" }
        $asset.browser_download_url
      }
    }

    if ($newUrl) {
      $i.file = $newUrl.Segments[-1]
      $i.href = $newUrl.AbsoluteUri
    }
  }

  $config | ConvertTo-Json | Set-Content $arch
}
