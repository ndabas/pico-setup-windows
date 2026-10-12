#Requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ArmGccMajorVersion = '15'
$PythonVersion = '3.14'

function crawl {
  param ([string]$url)

  (Invoke-WebRequest $url -UseBasicParsing).Links |
    Where-Object {
      ($_ | Get-Member href) -and
      [uri]::IsWellFormedUriString($_.href, [System.UriKind]::RelativeOrAbsolute)
    } |
    ForEach-Object {
      $href = [System.Net.WebUtility]::HtmlDecode($_.href)

      try {
        (New-Object System.Uri([uri]$url, $href)).AbsoluteUri
      }
      catch {
        $href
      }
    }
}

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

function getGitLabGenericPackageUrl {
  param (
    [string] $Server,
    [string] $Project,
    [string] $PackageName,
    [scriptblock] $VersionFilter,
    [scriptblock] $FileFilter
  )

  $projectApi = "$Server/api/v4/projects/$([uri]::EscapeDataString($Project))"

  # gitlab.arm.com blocks the default PowerShell user agent, but allows curl
  $params = @{ UserAgent = 'curl/8.18.0'; FollowRelLink = $true }

  # With -FollowRelLink, each page is emitted as an array, so flatten them
  $pkg = Invoke-RestMethod "$projectApi/packages?package_type=generic&package_name=$PackageName&per_page=100" @params |
    ForEach-Object { $_ } |
    Where-Object { $_.name -eq $PackageName -and $_.status -eq 'default' } |
    Where-Object $VersionFilter |
    Sort-Object { [version](($_.version -replace '[^0-9]+', '.').Trim('.')) } -Descending |
    Select-Object -First 1

  if (-not $pkg) {
    return
  }

  $file = Invoke-RestMethod "$projectApi/packages/$($pkg.id)/package_files?per_page=100" @params |
    ForEach-Object { $_ } |
    Where-Object $FileFilter |
    Select-Object -First 1

  if ($file) {
    "$projectApi/packages/generic/$PackageName/$($pkg.version)/$($file.file_name)"
  }
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

      $armGcc = [regex]::Escape($ArmGccMajorVersion)

      getGitLabGenericPackageUrl 'https://gitlab.arm.com' 'tooling/gnu-toolchains-for-arm' 'gnu-toolchain' `
        { $_.version -match "^$armGcc\.[0-9]+\.rel[0-9]+`$" } `
        { $_.file_name -match "^arm-gnu-toolchain-$armGcc\..*-mingw-w64-x86_64-arm-none-eabi\.$ext`$" }
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

    { $_ -like 'Python *' } {
      $suffix = ''

      if ($Download.file -match '\.exe$') {
        $suffix = $Config.bitness -eq 64 ? '-amd64\.exe' : '\.exe'
      } else {
        $suffix = $Config.bitness -eq 64 ? '-embed-amd64\.zip' : '-embed-win32\.zip'
      }

      $url = crawl 'https://www.python.org/downloads/windows/' |
        Where-Object { $_ -match "python-$([regex]::Escape($PythonVersion))\.[0-9]+$suffix`$" } |
        Select-Object -First 1

      if ($url) {
        $Download.name = "Python $PythonVersion"
      }

      $url
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
