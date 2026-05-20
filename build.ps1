[CmdletBinding()]
param (
  [Parameter(HelpMessage = "Path to a compile configuration file.")]
  [string]
  $CompileConfig,

  [Parameter(HelpMessage = "Path to an installer configuration file.")]
  [string]
  $InstallerConfig,

  [Parameter(HelpMessage = "Path to MSYS2 installation. MSYS2 will be downloaded and installed to this path if it doesn't exist.")]
  [ValidatePattern('[\\\/]msys64$')]
  [string]
  $MSYS2Path = '.\build\msys64',

  [Parameter(Mandatory = $True)]
  [ValidateSet('Download', 'Compile', 'Sign', 'Installer', 'Archive')]
  [string[]]$Target,

  [ValidateSet('Default', 'Best')]
  [string]
  $Compression = 'Default',

  [ValidateSet('system', 'user')]
  [string]
  $BuildType = 'system'
)

#Requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$ProgressPreference = 'SilentlyContinue'

$basename = "pico-setup-windows"
$version = (Get-Content "$PSScriptRoot\version.txt").Trim()
$build = (Get-Date -Format FileDateTimeUniversal)

$tools = (Get-Content '.\config\tools.json' | ConvertFrom-Json).tools
$repositories = (Get-Content '.\config\repositories.json' | ConvertFrom-Json).repositories

[Flags()] enum BuildTargets {
  Download = 1
  Compile = 2
  Sign = 4
  Installer = 8
  Archive = 16
}
$buildTargets = [BuildTargets] $Target

$compileOpts = $null
$installerOpts = $null
$bitness = $null
$msysEnv = $null
$downloads = @()
$builds = @()
$componentSelection = $false

$additionalDirs = @()
$additionalFiles = @(
  "packages\pico-setup-windows\pico-env.ps1"
  "packages\pico-setup-windows\pico-env.cmd"
  "packages\pico-setup-windows\pico-setup.cmd"
  "docs\README.txt"
  "build\VERSIONS.txt"
)

if ($CompileConfig) {
  Write-Host "Loading compile configuration from $CompileConfig"
  $compileOpts = Get-Content $CompileConfig | ConvertFrom-Json
  $builds = $compileOpts.builds
  $bitness = $compileOpts.bitness
  $msysEnv = $compileOpts.msysEnv
}

if ($InstallerConfig) {
  Write-Host "Loading installer configuration from $InstallerConfig"
  $installerOpts = Get-Content $InstallerConfig | ConvertFrom-Json
  $bitness = $installerOpts.bitness
  $msysEnv = $installerOpts.msysEnv
  $downloads = $installerOpts.downloads
  $componentSelection = ($installerOpts | Get-Member componentSelection) ? $installerOpts.componentSelection : $false
}

($downloads + $tools + $builds) | ForEach-Object {
  $_ | Add-Member -NotePropertyName 'shortName' -NotePropertyValue ($_.name -replace '[^a-zA-Z0-9]', '')
}

$env:MSYSTEM = $msysEnv
$msysEnv = $msysEnv.ToLowerInvariant()

function mkdirp {
  param ([string] $dir, [switch] $clean)

  New-Item -Path $dir -Type Directory -Force | Out-Null

  if ($clean) {
    Remove-Item -Path "$dir\*" -Recurse -Force
  }
}

mkdirp "build"
mkdirp "bin"

"Included in this release:" | Out-File -FilePath "build\VERSIONS.txt"

$versionRegEx = '([0-9]+\.)+[0-9]+'

function guessVersion {
  param ($downloadInfo)

  # Display versions of packaged installers, for information only. We try to
  # extract it from:
  # 1. The file name
  # 2. The download URL
  # 3. The version metadata in the file
  #
  # This fails for MSYS2, because there is no version number (only a timestamp)
  # and the version that gets reported is 7-zip SFX version.
  $fileVersion = ''
  if ($_.file -match $versionRegEx -or $_.href -match $versionRegEx) {
    $fileVersion = $Matches[0]
  }
  else {
    $fileVersion = (Get-ChildItem $outfile).VersionInfo.ProductVersion
  }

  $fileVersion ? $fileVersion : $_.file
}

($downloads + $tools) | ForEach-Object {
  $outfile = "downloads/$($_.file)"

  if (-not $buildTargets.HasFlag([BuildTargets]::Download)) {
    Write-Host "Checking $($_.name): " -NoNewline
    if (-not (Test-Path $outfile)) {
      Write-Error "$outfile not found"
    }
  }
  else {
    Write-Host "Downloading $($_.name): " -NoNewline
    curl.exe --fail --silent --show-error --url "$($_.href)" --location --output "$outfile" --create-dirs --remote-time --time-cond "downloads/$($_.file)"
  }

  guessVersion $_ | Write-Host

  if ($_ | Get-Member dirName) {
    $strip = 0;
    if ($_ | Get-Member extractStrip) { $strip = $_.extractStrip }

    mkdirp "build\$($_.dirName)" -clean
    tar -xf $outfile -C "build\$($_.dirName)" --strip-components $strip
  }
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
  $env:PATH = $env:PATH + ';' + (Resolve-Path .\build\cmake\bin).Path
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  $env:PATH = $env:PATH + ';' + (Resolve-Path .\build\git\cmd).Path
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  $env:PATH = $env:PATH + ';' + (Resolve-Path .\build\python).Path
}

$repositories | ForEach-Object {
  $reponame = [IO.Path]::GetFileNameWithoutExtension($_.href)
  $repodir = Join-Path 'build' $reponame

  if ($reponame.StartsWith('pico-')) {
    $additionalDirs += [PSCustomObject]@{
      'dirName'   = $reponame
      'name'      = $reponame
      'shortName' = ($reponame -replace '[^a-zA-Z0-9]', '')
    }
  }

  if ($buildTargets.HasFlag([BuildTargets]::Download)) {
    if (Test-Path $repodir) {
      Remove-Item $repodir -Recurse -Force
    }

    git clone -b "$($_.tree)" --depth=1 -c advice.detachedHead=false "$($_.href)" "$repodir"

    if ($_ | Get-Member submodules) {
      Write-Output "::group::Cloning submodules for $reponame"
      git -C "$repodir" submodule update --init --depth=1
      Write-Output "::endgroup::"
    }
  }

  Write-Host "Checking ${repodir}: " -NoNewline
  if (-not (Test-Path $repodir)) {
    Write-Error "$repodir not found"
  }
  $tree = git -C "$repodir" describe --all
  Write-Host $tree

  "- ${reponame}: $tree" | Out-File -FilePath "build\VERSIONS.txt" -Append
}

# BTstack needs the PyCryptodome module
if (Test-Path .\build\python\python.exe) {
  .\build\python\python.exe .\downloads\pip.pyz install pycryptodome
  Add-Content -Path .\build\python\python*._pth -Value 'import site'
}

# Clone additional Pico-specific submodules in TinyUSB
# git -C .\build\pico-sdk\lib\tinyusb submodule update --init --depth=1 hw\mcu\raspberry_pi

$sdkVersion = (cmake -P .\packages\pico-setup-windows\pico-sdk-version.cmake -N | Select-String -Pattern 'PICO_SDK_VERSION_STRING=(.*)$').Matches.Groups[1].Value
if (-not ($sdkVersion -match $versionRegEx)) {
  Write-Error 'Could not determine Pico SDK version.'
}
$sdkVersionClean = $Matches[0]
$env:PICO_SDK_VERSION = $sdkVersionClean
$sdkVersionCommit = (git -C .\build\pico-sdk rev-parse --short HEAD)
$product = "Pico SDK v$sdkVersion"
$productDir = "Pico SDK v$sdkVersion"
$company = "Nikhil Dabas"

Write-Host "SDK version: $sdkVersion ($sdkVersionCommit)"
Write-Host "Installer version: $version"

function sign {
  param ([string[]] $filesToSign)

  if (-not $buildTargets.HasFlag([BuildTargets]::Sign)) {
    Write-Warning "Skipping code signing."
  }
  else {
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like "CN=Raspberry Pi*" }
    if (-not $cert) {
      Write-Error "No suitable code signing certificates found."
    }

    $filesToSign | Set-AuthenticodeSignature -Certificate $cert -TimestampServer "http://timestamp.digicert.com" -HashAlgorithm SHA256 | Tee-Object -Variable signatures
    $signatures | ForEach-Object {
      if ($_.Status -ne 0) {
        Write-Error "Error signing $($_.Path)"
      }
    }
  }
}

function msys {
  param ([string] $cmd)

  & "$MSYS2Path\usr\bin\bash" -leo pipefail -c "$cmd"
}

# Preserve the current working directory
$env:CHERE_INVOKING = 'yes'
# Use real symlinks
$env:MSYS = "winsymlinks:nativestrict"

if ($buildTargets.HasFlag([BuildTargets]::Compile)) {
  if (-not (Test-Path $MSYS2Path)) {
    Write-Host 'Extracting MSYS2'
    & .\downloads\msys2.exe -y "-o$(Resolve-Path (Split-Path $MSYS2Path -Parent))"
  }

  Write-Output "::group::Setting up MSYS2 environment"
  # First run setup
  msys 'uname -a'
  # Core update
  msys 'pacman --noconfirm -Syuu'
  # Normal update
  msys 'pacman --noconfirm -Suu'

  msys "pacman -S --noconfirm --needed autoconf automake base-devel expat git libtool pactoys patchutils pkg-config"

  # pacboy adds MINGW_PACKAGE_PREFIX to package names suffixed with :p
  msys "pacboy -S --noconfirm --needed cmake:p ninja:p toolchain:p libusb:p hidapi:p libslirp:p"
  Write-Output "::endgroup::"

  $compileOpts.builds | ForEach-Object {
    if (-not (Test-Path ".\build\$($_.dirName)\$msysEnv")) {
      Write-Output "::group::Building $($_.name)"
      msys "cd build && ../$($_.buildScript)"
      Write-Output "::endgroup::"
    }
    else {
      Write-Output "Build output for $($_.name) already exists. Skipping build."
    }
  }
}

function pascalCase {
  param ([string] $s)

  -join ($s -split '[-_ ]+' | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1).ToLower() })
}

if ($null -eq $installerOpts) {
  Write-Host "No installer configuration file provided. Skipping archive/installer build."
  exit 0
}

$suffix = [io.path]::GetFileNameWithoutExtension($InstallerConfig) + ($BuildType -eq 'user' ? '-user' : '' )
$exefile = "bin\$basename-$suffix.exe"

$archiveContents = @() + $additionalFiles

$downloads + $additionalDirs | ForEach-Object {
  "Section ``$($_.name)`` Sec$($_.shortName)"
  '  ClearErrors'

  if ($_ | Get-Member additionalFiles) {
    $_.additionalFiles | ForEach-Object {
      "  File /oname=`$PLUGINSDIR\$(Split-Path -Leaf $_) $_"
    }
  }

  if (($_ | Get-Member exec) -or ($_ | Get-Member execToLog)) {

    '  SetOutPath "$TEMP"'
    "  File ``downloads\$($_.file)``"
    "  StrCpy `$0 ```$TEMP\$($_.file)``"

    if ($_ | Get-Member exec) {
      "  ExecWait ``$($_.exec)`` `$1"
    }

    if ($_ | Get-Member execToLog) {
      "  nsExec::ExecToLog ``$($_.execToLog)``"
      "  Pop `$1"
    }

    "  DetailPrint ``$($_.name) returned `$1``"
    "  Delete /REBOOTOK ```$0``"

    '  ${If} ${Errors}'
    "    Abort ``Installation of $($_.name) failed``"

    if ($_ | Get-Member rebootExitCodes) {
      $_.rebootExitCodes | ForEach-Object {
        "  `${ElseIf} `$1 = $_"
        '    SetRebootFlag true'
      }
    }

    '  ${ElseIf} $1 <> 0'
    "    Abort ``Installation of $($_.name) failed``"
    '  ${EndIf}'
  }

  if ($_ | Get-Member dirName) {
    "  SetOutPath '`$INSTDIR\$($_.dirName)'"
    "  File /r build\$($_.dirName)\*.*"

    $archiveContents += "build\$($_.dirName)"
  }

  'SectionEnd'
  "LangString DESC_Sec$($_.shortName) `${LANG_ENGLISH} ``$($_.name)``"
  ''
} | Out-File -FilePath "build\installer-sections.nsh"

$builds | ForEach-Object {
  "Section ``$($_.name)`` Sec$($_.shortName)"

  if ($_ | Get-Member dirName) {
    "  SetOutPath '`$INSTDIR\$($_.installDirName)'"
    "  File /r build\$($_.dirName)\$msysEnv\*.*"

    $archiveContents += "$($_.installDirName): build\$($_.dirName)\$msysEnv"
  }

  'SectionEnd'
  "LangString DESC_Sec$($_.shortName) `${LANG_ENGLISH} ``$($_.name)``"
  ''
} | Out-File -FilePath "build\installer-sections.nsh" -Append

if ($componentSelection) {
  & {
    '!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN'

    $($downloads + $additionalDirs + $builds | ForEach-Object {
        "  !insertmacro MUI_DESCRIPTION_TEXT `${Sec$($_.shortName)} `$(DESC_Sec$($_.shortName))"
      })

    '!insertmacro MUI_FUNCTION_DESCRIPTION_END'
  } | Out-File -FilePath "build\installer-sections.nsh" -Append
}

& {
  'Section "-PicoSetup"'
  '  SetOutPath $INSTDIR'
  $additionalFiles | ForEach-Object {
    "  File ``$_``"
  }
  'SectionEnd'
} | Out-File -FilePath "build\installer-sections.nsh" -Append

$downloads + $additionalDirs + $builds | ForEach-Object {
  if ($_ | Get-Member dirName) {
    "Section un.$($_.shortName)"
    "  RMDir /r /REBOOTOK ```$INSTDIR\$($_.dirName)``"
    'SectionEnd'
    ''
  }
} | Out-File -FilePath "build\uninstaller-sections.nsh"

& {
  'Section un.PicoSetup'
  $additionalFiles | ForEach-Object {
    "  Delete ```$INSTDIR\$(Split-Path -Leaf $_)``"
  }
  'SectionEnd'
} | Out-File -FilePath "build\uninstaller-sections.nsh" -Append

@"
!define COMPANY "$company"
!define PRODUCT "$product"
!define PRODUCT_DIR "$productDir"
!define TITLE "$product"
!define VERSION "$version"
!define BITNESS $bitness
!define OUTPUT_FILE "$exefile"
!define PICO_SDK_VERSION "$sdkVersion"
!define AUMID "$(pascalCase $company).$(pascalCase $basename).$sdkVersion"
!define ARP_DISPLAY_NAME "$($BuildType -eq 'system' ? $product : "$product (User)")"
!define SHELL_VAR_CONTEXT $($BuildType -eq 'system' ? 'all' : 'current')
!define UNINSTALL_KEY_OLD "Software\Microsoft\Windows\CurrentVersion\Uninstall\$basename-$sdkVersion"

$($componentSelection ? '!define ALLOW_COMPONENT_SELECTION' : '')

SetCompressor $($Compression -eq 'Best' ? 'lzma' : 'zlib')
RequestExecutionLevel $($BuildType -eq 'system' ? 'admin' : 'user')

VIAddVersionKey "FileDescription" "`${TITLE}"
VIAddVersionKey "InternalName" "$basename"
VIAddVersionKey "ProductName" "`${TITLE}"
VIAddVersionKey "FileVersion" "$version-$build"
VIAddVersionKey "ProductVersion" "$sdkVersion-$sdkVersionCommit"
VIAddVersionKey "LegalCopyright" "$company"
VIAddVersionKey "CompanyName" "$company"
VIFileVersion $version.0
VIProductVersion $sdkVersionClean.0
"@ | Out-File -FilePath "build\installer-header.nsh"

if ($buildTargets.HasFlag([BuildTargets]::Installer)) {
  .\build\NSIS\makensis /DBUILD_UNINSTALLER ".\$basename.nsi"

  # The 'installer' that just writes the uninstaller asks for admin access, which is not actually needed.
  $env:__COMPAT_LAYER = "RunAsInvoker"
  Start-Process -FilePath ".\build\build-uninstaller.exe" -ArgumentList "/S /D=$(Join-Path $PSScriptRoot 'build')" -Wait
  $env:__COMPAT_LAYER = ""
}

# Sign files before packaging
sign "build\uninstall.exe",
"build\openocd-install\$msysEnv\bin\openocd.exe",
"build\pico-sdk-tools\$msysEnv\elf2uf2\elf2uf2.exe",
"build\pico-sdk-tools\$msysEnv\pioasm\pioasm.exe",
"build\pico-sdk-tools\$msysEnv\picotool\picotool.exe"

$suffix = $compileOpts.architecture

$mkzipArgs = @()
if ($Compression -eq 'Best') {
  $mkzipArgs += '--best'
}
$mkzipArgs += '-f'

$downloads | ForEach-Object {
  "- $($_.name): $(guessVersion $_)"
} | Out-File -FilePath "build\VERSIONS.txt" -Append

$compileOpts.builds | ForEach-Object {
  Write-Host "Checking version for $($_.name): " -NoNewline
  $checkVersionCmd = $_.checkVersion
  $version = (cmd /c cd "build\$($_.dirName)\$msysEnv" '&&' @checkVersionCmd '2>&1' | Select-String -Pattern $versionRegEx).Matches.Value
  Write-Host $version

  "- $($_.name): $version" | Out-File -FilePath "build\VERSIONS.txt" -Append

  if ($buildTargets.HasFlag([BuildTargets]::Archive)) {
    $zipfile = "bin\$($_.installDirName)-$version-$suffix.zip"
    python .\packages\common\mkzip.py @mkzipArgs "$zipfile" "build\$($_.dirName)\$msysEnv\"
    Write-Host "Archive saved to $zipfile"
  }
}

if ($buildTargets.HasFlag([BuildTargets]::Installer)) {
  .\build\NSIS\makensis ".\$basename.nsi"
  Write-Host "Installer saved to $exefile"

  # Sign the installer
  sign $exefile
}

if ($buildTargets.HasFlag([BuildTargets]::Archive)) {
  $archiveContents -join "`n" | Out-File -FilePath "build\archive-contents.txt"
  $zipfile = "bin\$basename-$suffix.zip"
  python .\packages\common\mkzip.py @mkzipArgs "$zipfile" "@build\archive-contents.txt"
  Write-Host "Archive saved to $zipfile"
}
