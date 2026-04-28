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

    'Arm GNU Toolchain' {
      $ext = $Download.file -match '\.zip$' ? 'zip' : 'exe'

      crawl 'https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads' |
        Where-Object { $_ -match "arm-gnu-toolchain-14.*-mingw-w64-x86_64-arm-none-eabi\.$ext" } |
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

    'Python 3.12' {
      $suffix = ''

      if ($Download.file -match '\.exe$') {
        $suffix = $Config.bitness -eq 64 ? '-amd64\.exe' : '\.exe'
      } else {
        $suffix = $Config.bitness -eq 64 ? '-embed-amd64\.zip' : '-embed-win32\.zip'
      }

      crawl 'https://www.python.org/downloads/windows/' |
        Where-Object { $_ -match "python-3\.12\.[0-9]+$suffix`$" } |
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
      $item = Invoke-RestMethod 'https://sourceforge.net/projects/nsis/rss' |
        Where-Object { $_.link -match 'nsis-([0-9]+\.)+[0-9]+\.zip' } |
        Select-Object -First 1
      $newName = $Matches[0]
      $item.link
    }

    'MSYS2' {
      $newName = 'msys2.exe'
      getGitHubReleaseAssetUrl 'msys2/msys2-installer' { $_.name -match "^msys2-base-x86_64-[0-9]+\.sfx\.exe`$" }
    }

    'pandoc' {
      getGitHubReleaseAssetUrl 'jgm/pandoc' { $_.name -match "^pandoc-([0-9]+\.)+[0-9]+-windows-x86_64\.zip`$" }
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

foreach ($arch in @('x64.json', 'x64-standalone.json')) {
  $config = Get-Content ".\config\$arch" | ConvertFrom-Json

  foreach ($i in $config.downloads) {
    updateDownloadUrl $i $config
  }

  $config | ConvertTo-Json -Depth 3 | Set-Content ".\config\$arch"
}

$tools = Get-Content '.\config\tools.json' | ConvertFrom-Json

foreach ($i in $tools.tools) {
  updateDownloadUrl $i $tools
}

$tools | ConvertTo-Json -Depth 3 | Set-Content '.\config\tools.json'
