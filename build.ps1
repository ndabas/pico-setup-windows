[CmdletBinding()]
param (
  [Parameter(Mandatory = $true,
    Position = 0,
    HelpMessage = "Path to a JSON installer configuration file.")]
  [Alias("PSPath")]
  [ValidateNotNullOrEmpty()]
  [string]
  $ConfigFile,

  [Parameter(HelpMessage = "Path to MSYS2 installation. MSYS2 will be downloaded and installed to this path if it doesn't exist.")]
  [ValidatePattern('[\\\/]msys64$')]
  [string]
  $MSYS2Path = '.\build\msys64',

  [switch]
  $SkipDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\common.ps1"

Write-Host "Building from $ConfigFile"

$basename = "pico-setup-windows"
$version = (Get-Content "$PSScriptRoot\version.txt").Trim()
$suffix = [io.path]::GetFileNameWithoutExtension($ConfigFile)
$binfile = "bin\$basename-$version-$suffix.exe"

$tools = (Get-Content '.\config\tools.json' | ConvertFrom-Json).tools
$repositories = (Get-Content '.\config\repositories.json' | ConvertFrom-Json).repositories
$config = Get-Content $ConfigFile | ConvertFrom-Json
$bitness = $config.bitness
$mingw_arch = $config.mingw_arch
$downloads = $config.downloads

mkdirp "build"
mkdirp "bin"

($downloads + $tools) | ForEach-Object {
  $_ | Add-Member -NotePropertyName 'shortName' -NotePropertyValue ($_.name -replace '[^a-zA-Z0-9]', '')
  $outfile = "downloads/$($_.file)"

  if ($SkipDownload) {
    Write-Host "Checking $($_.name): " -NoNewline
    if (-not (Test-Path $outfile)) {
      Write-Error "$outfile not found"
    }
  }
  else {
    Write-Host "Downloading $($_.name): " -NoNewline
    exec { curl.exe --fail --silent --show-error --url "$($_.href)" --location --output "$outfile" --create-dirs --remote-time --time-cond "downloads/$($_.file)" }
  }

  # Display versions of packaged installers, for information only. We try to
  # extract it from:
  # 1. The file name
  # 2. The download URL
  # 3. The version metadata in the file
  #
  # This fails for MSYS2, because there is no version number (only a timestamp)
  # and the version that gets reported is 7-zip SFX version.
  $fileVersion = ''
  $versionRegEx = '([0-9]+\.)+[0-9]+'
  if ($_.file -match $versionRegEx -or $_.href -match $versionRegEx) {
    $fileVersion = $Matches[0]
  } else {
    $fileVersion = (Get-ChildItem $outfile).VersionInfo.ProductVersion
  }

  if ($fileVersion) {
    Write-Host $fileVersion
  } else {
    Write-Host $_.file
  }

  if ($_ | Get-Member prebuild) {
    $0 = $outfile
    Invoke-Expression $_.prebuild
  }
}

$repositories | ForEach-Object {
  $repodir = Join-Path 'build' ([IO.Path]::GetFileNameWithoutExtension($_.href))

  if ($SkipDownload) {
    Write-Host "Checking ${repodir}: " -NoNewline
    if (-not (Test-Path $repodir)) {
      Write-Error "$repodir not found"
    }
    exec { git -C "$repodir" describe --all }
  }
  else {
    if (Test-Path $repodir) {
      Remove-Item $repodir -Recurse -Force
    }

    exec { git clone -b "$($_.tree)" --depth=1 -c advice.detachedHead=false "$($_.href)" "$repodir" }

    if ($_ | Get-Member submodules) {
      exec { git -C "$repodir" submodule update --init --depth=1 }
    }
  }
}

$sdkVersion = (.\build\cmake\bin\cmake.exe -P .\packages\pico-setup-windows\pico-sdk-version.cmake -N | Select-String -Pattern 'PICO_SDK_VERSION_STRING=(.*)$').Matches.Groups[1].Value
$product = "Raspberry Pi Pico SDK v$sdkVersion"

Write-Host "SDK version: $sdkVersion"
Write-Host "Installer version: $version"

if (-not (Test-Path $MSYS2Path)) {
  Write-Host 'Extracting MSYS2'
  exec { & .\downloads\msys2.exe -y "-o$(Resolve-Path (Split-Path $MSYS2Path -Parent))" }
}

if (-not (Test-Path build\NSIS)) {
  Write-Host 'Extracting NSIS'
  Expand-Archive '.\downloads\nsis.zip' -DestinationPath '.\build'
  Rename-Item (Resolve-Path '.\build\nsis-*').Path 'NSIS'
  Expand-Archive '.\downloads\nsis-log.zip' -DestinationPath '.\build\NSIS' -Force
}

function msys {
  param ([string] $cmd)

  exec { & "$MSYS2Path\usr\bin\bash" -leo pipefail -c "$cmd" }
}

# Preserve the current working directory
$env:CHERE_INVOKING = 'yes'
# Start MINGW32/64 environment
$env:MSYSTEM = "MINGW$bitness"

if (-not $SkipDownload) {
  # First run setup
  msys 'uname -a'
  # Core update
  msys 'pacman --noconfirm -Syuu'
  # Normal update
  msys 'pacman --noconfirm -Suu'

  msys "pacman -S --noconfirm --needed autoconf automake mingw-w64-${mingw_arch}-cmake git libtool make mingw-w64-${mingw_arch}-ninja mingw-w64-${mingw_arch}-toolchain mingw-w64-${mingw_arch}-libusb mingw-w64-${mingw_arch}-hidapi pkg-config wget"
}

if (-not (Test-Path ".\build\openocd-install\mingw$bitness")) {
  msys "cd build && ../packages/openocd/build-openocd.sh $bitness $mingw_arch"
}

if (-not (Test-Path ".\build\picotool-install\mingw$bitness")) {
  msys "cd build && ../packages/picotool/build-picotool.sh $bitness $mingw_arch"
}

@"
!include "MUI2.nsh"
!include "WordFunc.nsh"

!define TITLE "$product"
!define PICO_INSTALL_DIR "`$PROGRAMFILES$bitness\$product"
; The repos need to be cloned into a dir with a fairly short name, because
; CMake generates build defs with long hashes in the paths. Both CMake and
; Ninja currently have problems working with long paths on Windows.
; !define PICO_REPOS_DIR "`$LOCALAPPDATA\Programs\$product"
!define PICO_REPOS_DIR "`$DOCUMENTS\Pico-v$sdkVersion"
!define PICO_SHORTCUTS_DIR "`$SMPROGRAMS\Raspberry Pi\Pico SDK v$sdkVersion"
!define PICO_REG_ROOT HKCU
!define PICO_REG_KEY "Software\Raspberry Pi\$basename"

Name "`${TITLE}"
Caption "`${TITLE}"

VIAddVersionKey "FileDescription" "`${TITLE}"
VIAddVersionKey "InternalName" "$basename"
VIAddVersionKey "ProductName" "`${TITLE}"
VIAddVersionKey "FileVersion" "$version"
VIAddVersionKey "LegalCopyright" ""
VIFileVersion $version.0
VIProductVersion $version.0

OutFile "$binfile"
Unicode True

; Since we're packaging up a bunch of installers, the "Space required" shown is inaccurate
SpaceTexts "none"

InstallDir "`${PICO_INSTALL_DIR}"

;Get installation folder from registry if available
InstallDirRegKey `${PICO_REG_ROOT} "`${PICO_REG_KEY}" "InstallPath"

!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "`${TITLE}"

!define MUI_COMPONENTSPAGE_SMALLDESC

!define MUI_FINISHPAGE_RUN_TEXT "Clone and build Pico repos"
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_FUNCTION RunBuild

!define MUI_FINISHPAGE_SHOWREADME "`${PICO_REPOS_DIR}\ReadMe.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Show ReadMe"

!define MUI_FINISHPAGE_NOAUTOCLOSE

!insertmacro MUI_PAGE_WELCOME
;!insertmacro MUI_PAGE_LICENSE "`${NSISDIR}\Docs\Modern UI\License.txt"
;!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Section

  ; Make sure that `$INSTDIR exists before enabling logging
  SetOutPath `$INSTDIR
  LogSet on

  InitPluginsDir
  File /oname=`$TEMP\RefreshEnv.cmd "packages\pico-setup-windows\RefreshEnv.cmd"

  WriteRegStr `${PICO_REG_ROOT} "`${PICO_REG_KEY}" "InstallPath" "`$INSTDIR"
  WriteRegStr `${PICO_REG_ROOT} "`${PICO_REG_KEY}\v$version" "InstallPath" "`$INSTDIR"

  CreateDirectory "`${PICO_REPOS_DIR}"
  CreateDirectory "`${PICO_SHORTCUTS_DIR}"

  File /r resources

SectionEnd

$($downloads | ForEach-Object {
@"

Section "$($_.name)" Sec$($_.shortName)

  ClearErrors

  $(if ($_ | Get-Member additionalFiles) {
    $_.additionalFiles | ForEach-Object {
      "File /oname=`$PLUGINSDIR\$(Split-Path -Leaf $_) $_`r`n"
    }
  })

  $(if ($_ | Get-Member exec) {
@"
    SetOutPath "`$TEMP"
    File "downloads\$($_.file)"
    StrCpy `$0 "`$TEMP\$($_.file)"
    ExecWait '$($_.exec)' `$1
    DetailPrint "$($_.name) returned `$1"
    Delete /REBOOTOK "`$0"

    `${If} `${Errors}
      Abort "Installation of $($_.name) failed"
    $(if ($_ | Get-Member rebootExitCodes) {
      $_.rebootExitCodes | ForEach-Object {
        "`${ElseIf} `$1 = $_`r`n    SetRebootFlag true"
      }
    })
    `${ElseIf} `$1 <> 0
      Abort "Installation of $($_.name) failed"
    `${EndIf}
"@
  })

  $(if ($_ | Get-Member copy) {
    "SetOutPath '`$INSTDIR'`r`n"
    "File $($_.copy)"
  })

SectionEnd

LangString DESC_Sec$($_.shortName) `${LANG_ENGLISH} "$($_.name)"

"@
})

Section "VS Code Extensions" SecCodeExts

  ReadEnvStr `$0 COMSPEC
  nsExec::ExecToLog '"`$0" /c call "`$TEMP\RefreshEnv.cmd" && code --install-extension marus25.cortex-debug'
  Pop `$1
  nsExec::ExecToLog '"`$0" /c call "`$TEMP\RefreshEnv.cmd" && code --install-extension ms-vscode.cmake-tools'
  Pop `$1
  nsExec::ExecToLog '"`$0" /c call "`$TEMP\RefreshEnv.cmd" && code --install-extension ms-vscode.cpptools'
  Pop `$1
  nsExec::ExecToLog '"`$0" /c call "`$TEMP\RefreshEnv.cmd" && code --install-extension ms-vscode.cpptools-extension-pack'
  Pop `$1
  nsExec::ExecToLog '"`$0" /c call "`$TEMP\RefreshEnv.cmd" && code --install-extension ms-vscode.vscode-serial-monitor'
  Pop `$1

SectionEnd

LangString DESC_SecCodeExts `${LANG_ENGLISH} "Recommended extensions for Visual Studio Code: C/C++, CMake-Tools, and Cortex-Debug"

Section "OpenOCD" SecOpenOCD

  SetOutPath "`$INSTDIR\openocd"
  File "build\openocd-install\mingw$bitness\bin\*.*"
  SetOutPath "`$INSTDIR\openocd\scripts"
  File /r "build\openocd-install\mingw$bitness\share\openocd\scripts\*.*"

SectionEnd

LangString DESC_SecOpenOCD `${LANG_ENGLISH} "Open On-Chip Debugger with picoprobe support"

Section "Pico environment" SecPico

  SetOutPath "`${PICO_REPOS_DIR}\pico-sdk"
  File /r "build\pico-sdk\*.*"

  SetOutPath "`${PICO_REPOS_DIR}\pico-examples"
  File /r "build\pico-examples\*.*"
  SetOutPath "`${PICO_REPOS_DIR}\pico-examples\.vscode"
  File /oname=launch.json "packages\pico-examples\vscode-launch.json"
  File "build\pico-examples\ide\vscode\settings.json"

  SetOutPath "`$INSTDIR\pico-sdk-tools"
  File "build\pico-sdk-tools\mingw$bitness\*.*"
  WriteRegStr `${PICO_REG_ROOT} "Software\Kitware\CMake\Packages\pico-sdk-tools" "v$version" "`$INSTDIR\pico-sdk-tools"

  SetOutPath "`$INSTDIR\picotool"
  File "build\picotool-install\mingw$bitness\*.*"

  SetOutPath "`${PICO_REPOS_DIR}"
  File "version.txt"
  File "packages\pico-setup-windows\pico-code.ps1"
  File "packages\pico-setup-windows\pico-env.ps1"
  File "packages\pico-setup-windows\pico-env.cmd"
  File "packages\pico-setup-windows\pico-setup.cmd"
  File "packages\pico-setup-windows\ReadMe.txt"

  CreateDirectory "`${PICO_SHORTCUTS_DIR}\Pico - Documentation"

  CreateShortcut "`${PICO_SHORTCUTS_DIR}\Pico - Developer Command Prompt.lnk" "cmd.exe" '/k "`${PICO_REPOS_DIR}\pico-env.cmd"'
  CreateShortcut "`${PICO_SHORTCUTS_DIR}\Pico - Developer PowerShell.lnk" "powershell.exe" '-NoExit -ExecutionPolicy Bypass -File "`${PICO_REPOS_DIR}\pico-env.ps1"'
  CreateShortcut "`${PICO_SHORTCUTS_DIR}\Pico - Visual Studio Code.lnk" "powershell.exe" 'powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "`${PICO_REPOS_DIR}\pico-code.ps1"' "`$INSTDIR\resources\vscode.ico" "" SW_SHOWMINIMIZED

  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Pico - Documentation\Pico Datasheet.url" "InternetShortcut" "URL" "https://datasheets.raspberrypi.com/pico/pico-datasheet.pdf"
  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Pico - Documentation\Pico W Datasheet.url" "InternetShortcut" "URL" "https://datasheets.raspberrypi.com/picow/pico-w-datasheet.pdf"
  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Pico - Documentation\Pico C C++ SDK.url" "InternetShortcut" "URL" "https://datasheets.raspberrypi.com/pico/raspberry-pi-pico-c-sdk.pdf"
  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Pico - Documentation\Pico Python SDK.url" "InternetShortcut" "URL" "https://datasheets.raspberrypi.com/pico/raspberry-pi-pico-python-sdk.pdf"

  ; Reset working dir for pico-setup.cmd launched from the finish page
  SetOutPath "`${PICO_REPOS_DIR}"

SectionEnd

LangString DESC_SecPico `${LANG_ENGLISH} "Scripts for cloning the Pico SDK and tools repos, and for setting up your Pico development environment."

Function RunBuild

  ReadEnvStr `$0 COMSPEC
  Exec '"`$0" /k call "`$TEMP\RefreshEnv.cmd" && del "`$TEMP\RefreshEnv.cmd" && call "`${PICO_REPOS_DIR}\pico-setup.cmd" 1'

FunctionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT `${SecCodeExts} `$(DESC_SecCodeExts)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecOpenOCD} `$(DESC_SecOpenOCD)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecPico} `$(DESC_SecPico)
$($downloads | ForEach-Object {
  "  !insertmacro MUI_DESCRIPTION_TEXT `${Sec$($_.shortName)} `$(DESC_Sec$($_.shortName))`n"
})
!insertmacro MUI_FUNCTION_DESCRIPTION_END
"@ | Set-Content ".\$basename-$suffix.nsi"

exec { .\build\NSIS\makensis ".\$basename-$suffix.nsi" }
Write-Host "Installer saved to $binfile"

# Package OpenOCD separately as well

$version = (cmd /c ".\build\openocd-install\mingw$bitness\bin\openocd.exe" --version '2>&1')[0]
if (-not ($version -match 'Open On-Chip Debugger (?<version>[a-zA-Z0-9\.\-+]+) \((?<timestamp>[0-9\-:]+)\)')) {
  Write-Error 'Could not determine openocd version'
}

$filename = 'openocd-{0}-{1}-{2}.zip' -f
  ($Matches.version -replace '-dirty$', ''),
  ($Matches.timestamp -replace '[:-]', ''),
  $suffix

Write-Host "Saving OpenOCD package to $filename"
exec { tar -a -cf "bin\$filename" -C "build\openocd-install\mingw$bitness\bin" * -C "..\share\openocd" "scripts" }
