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
      $ext = $Download.file -match '\.exe$' ? 'exe' : 'zip'

      crawl 'https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm/downloads' |
        Where-Object { $_ -match "-win32\.$ext" } | # There is no 64-bit build for Windows currently
        Select-Object -First 1
    }

    'CMake' {
      $suffix = $Config.bitness -eq 64 ? 'x86_64' : 'i386'
      $ext = $Download.file -match '\.msi$' ? "msi" : "zip"

      # CMake does not mark prereleases as such, so we filter based on the tag
      getGitHubReleaseAssetUrl 'Kitware/CMake' { $_.name -match "windows-$suffix\.$ext`$" } { $_.tag_name -match '^v([0-9]+\.)+[0-9]$' }
    }

    'Ninja' {
      $newName = 'ninja-win.zip'
      getGitHubReleaseAssetUrl 'ninja-build/ninja' { $_.name -eq 'ninja-win.zip' }
    }

    'Python 3.9' {
      $suffix = ''

      if ($Download.file -match '\.exe$') {
        $suffix = $Config.bitness -eq 64 ? '-amd64\.exe' : '\.exe'
      } else {
        $suffix = $Config.bitness -eq 64 ? '-embed-amd64\.zip' : '-embed-win32\.zip'
      }

      crawl 'https://www.python.org/downloads/windows/' |
        Where-Object { $_ -match "python-3\.9\.[0-9]+$suffix`$" } |
        Select-Object -First 1
    }

    'Git for Windows' {
      $prefix = ''
      $ext = 'exe'

      if ($Download.file -match '\.zip$') {
        $prefix = 'Min'
        $ext = 'zip'
      }

      getGitHubReleaseAssetUrl 'git-for-windows/git' { $_.name -match "^${prefix}Git-([0-9]+\.)+[0-9]+-$($Config.bitness)-bit\.$ext`$" }
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

foreach ($arch in @('x86.json', 'x64.json', 'x64-standalone.json')) {
  $config = Get-Content $arch | ConvertFrom-Json

  foreach ($i in $config.downloads) {
    updateDownloadUrl $i $config
  }

  $config | ConvertTo-Json -Depth 3 | Set-Content $arch
}

$tools = Get-Content '.\tools.json' | ConvertFrom-Json

foreach ($i in $tools.tools) {
  updateDownloadUrl $i $tools
}

$tools | ConvertTo-Json -Depth 3 | Set-Content '.\tools.json'
