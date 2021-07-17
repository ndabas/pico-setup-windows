#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\common.ps1"

function getGitHubReleaseAssetUrl {
  param (
    [string] $Repo,
    [scriptblock] $AssetFilter,
    [scriptblock] $ReleaseFilter = { $_.prerelease -eq $false }
  )

  $rel = (Invoke-RestMethod "https://api.github.com/repos/$Repo/releases") |
    Where-Object $ReleaseFilter |
    Select-Object -First 1
  $asset = $rel.assets |
    Where-Object $AssetFilter
  $asset.browser_download_url
}

function updateDownloadUrl {
  param (
    $Download,
    $Config
  )

  Write-Host "Updating $($Download.name): " -NoNewline

  $newName = $null # Override local filename if needed

  [uri]$newUrl = switch ($Download.name) {

    'GNU Arm Embedded Toolchain' {
      crawl 'https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm/downloads' |
        Where-Object { $_ -match "-win32\.exe" } | # There is no 64-bit build for Windows currently
        Select-Object -First 1
    }

    'CMake' {
      $suffix = $Config.bitness -eq 64 ? 'x86_64' : 'i386'

      # CMake does not mark prereleases as such, so we filter based on the tag
      getGitHubReleaseAssetUrl 'Kitware/CMake' { $_.name -match "windows-$suffix\.msi`$" } { $_.tag_name -match '^v([0-9]+\.)+[0-9]$' }
    }

    'Python 3.9' {
      $suffix = $Config.bitness -eq 64 ? '-amd64' : ''

      crawl 'https://www.python.org/downloads/windows/' |
        Where-Object { $_ -match "python-3\.9\.[0-9]+$suffix\.exe`$" } |
        Select-Object -First 1
    }

    'Git for Windows' {
      getGitHubReleaseAssetUrl 'git-for-windows/git' { $_.name -match "^Git-([0-9]+\.)+[0-9]+-$($Config.bitness)-bit\.exe`$" }
    }

    'Doxygen' {
      crawl 'https://www.doxygen.nl/download.html' |
        Where-Object { $_ -match "-setup\.exe" } |
        Select-Object -First 1
    }

    'Graphviz' {
      $link = (Invoke-WebRequest 'https://graphviz.org/download/' -UseBasicParsing).Links |
        Where-Object { $_.outerHTML -match "-win$($Config.bitness)\.exe" } |
        Select-Object -First 1
      if ($link.outerHTML -match '[a-zA-Z0-9_\-\.]+\.exe') {
        $newName = $Matches[0]
        $link.href
      }
    }

    'NSIS' {
      $newName = 'nsis.zip'
      $item = Invoke-RestMethod 'https://sourceforge.net/projects/nsis/rss' |
        Where-Object { $_.link -match 'nsis-([0-9]+\.)+[0-9]+\.zip' } |
        Select-Object -First 1
      $item.link
    }

    'NSIS with logging'  {
      $newName = 'nsis-log.zip'
      $item = Invoke-RestMethod 'https://sourceforge.net/projects/nsis/rss' |
        Where-Object { $_.link -match 'nsis-([0-9]+\.)+[0-9]+\-log.zip' } |
        Select-Object -First 1
      $item.link
    }

    'MSYS2' {
      $newName = 'msys2.exe'
      getGitHubReleaseAssetUrl 'msys2/msys2-installer' { $_.name -match "^msys2-base-x86_64-[0-9]+\.sfx\.exe`$" }
    }

    'Zadig' {
      $newName = 'zadig.exe'
      $assetFilter = { $_.name -match "^zadig-([0-9]+\.)+[0-9]+\.exe`$" }
      getGitHubReleaseAssetUrl 'pbatard/libwdi' $assetFilter { $_.assets | Where-Object $assetFilter }
    }

    'libusb' {
      $newName = 'libusb.7z'
      # Do not update libusb currently - 1.0.23 works but 1.0.24 crashes OpenOCD with picoprobe
      # getGitHubReleaseAssetUrl 'libusb/libusb' { $_.name -match "^libusb-([0-9]+\.)+[0-9]+\.7z`$" }
    }

    'vswhere' {
      $newName = 'vswhere.exe'
      getGitHubReleaseAssetUrl 'microsoft/vswhere' { $_.name -eq 'vswhere.exe' }
    }
  }

  if ($newUrl) {
    $newName ??= $newUrl.Segments[-1]

    Write-Host $newName

    $Download.file = $newName
    $Download.href = $newUrl.AbsoluteUri
  } else {
    Write-Host "No update"
  }
}

foreach ($arch in @('x86.json', 'x64.json')) {
  $config = Get-Content $arch | ConvertFrom-Json

  foreach ($i in $config.installers) {
    updateDownloadUrl $i $config
  }

  $config | ConvertTo-Json -Depth 3 | Set-Content $arch
}

$tools = Get-Content '.\tools.json' | ConvertFrom-Json

foreach ($i in $tools.tools) {
  updateDownloadUrl $i $tools
}

$tools | ConvertTo-Json -Depth 3 | Set-Content '.\tools.json'
