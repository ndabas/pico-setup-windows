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

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\common.ps1"

Write-Host "Building from $ConfigFile"

$basename = "pico-setup-windows"
$version = (Get-Content "$PSScriptRoot\version.txt").Trim()
$suffix = [io.path]::GetFileNameWithoutExtension($ConfigFile)
$binfile = "bin\$basename-$suffix.exe"

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

  if ($_ | Get-Member dirName) {
    $strip = 0;
    if ($_ | Get-Member extractStrip) { $strip = $_.extractStrip }

    mkdirp "build\$($_.dirName)" -clean
    exec { tar -xf $outfile -C "build\$($_.dirName)" --strip-components $strip }
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
$productDir = "Raspberry Pi\Pico SDK v$sdkVersion"
$company = "Raspberry Pi Ltd"

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

function sign {
  param ([string[]] $filesToSign)

  $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like "CN=Raspberry Pi*" }
  $filesToSign | Set-AuthenticodeSignature -Certificate $cert -TimestampServer "http://timestamp.digicert.com" -HashAlgorithm SHA256
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

  msys "pacman -S --noconfirm --needed autoconf automake git libtool make pactoys pkg-config wget"
  # pacboy adds MINGW_PACKAGE_PREFIX to package names suffixed with :p
  msys "pacboy -S --noconfirm --needed cmake:p ninja:p toolchain:p libusb:p hidapi:p"
}

if (-not (Test-Path ".\build\openocd-install\mingw$bitness")) {
  msys "cd build && ../packages/openocd/build-openocd.sh $bitness $mingw_arch"
}

if (-not (Test-Path ".\build\picotool-install\mingw$bitness")) {
  msys "cd build && ../packages/picotool/build-picotool.sh $bitness $mingw_arch"
}

$template = Get-Content ".\packages\pico-sdk-tools\pico-sdk-tools-config-version.cmake" -Raw
$ExecutionContext.InvokeCommand.ExpandString($template) | Set-Content ".\build\pico-sdk-tools\mingw$bitness\pico-sdk-tools-config-version.cmake"

@"
!include "MUI2.nsh"
!include "WordFunc.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "packages\pico-setup-windows\aumi.nsh"

!define TITLE "$product"
!define PICO_INSTALL_DIR "`$PROGRAMFILES$bitness\$productDir"
; The repos need to be cloned into a dir with a fairly short name, because
; CMake generates build defs with long hashes in the paths. Both CMake and
; Ninja currently have problems working with long paths on Windows.
!define PICO_REPOS_DIR "`$LOCALAPPDATA\$productDir"
!define PICO_SHORTCUTS_DIR "`$SMPROGRAMS\$product"
!define PICO_REG_ROOT SHELL_CONTEXT
!define PICO_REG_KEY "Software\$productDir"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\$product"
!define PICO_AppUserModel_ID "RaspberryPi.PicoSDK.$sdkVersion"

Name "`${TITLE}"
Caption "`${TITLE}"
XPStyle on
ManifestDPIAware true
Unicode True
SetCompressor lzma
RequestExecutionLevel admin

VIAddVersionKey "FileDescription" "`${TITLE}"
VIAddVersionKey "InternalName" "$basename"
VIAddVersionKey "ProductName" "`${TITLE}"
VIAddVersionKey "FileVersion" "$version"
VIAddVersionKey "LegalCopyright" "$company"
VIAddVersionKey "CompanyName" "$company"
VIFileVersion $version.0
VIProductVersion $version.0

; Since we're packaging up a bunch of installers, the "Space required" shown is inaccurate
SpaceTexts "none"

InstallDir "`${PICO_INSTALL_DIR}"

; Get installation folder from registry if available
; We use a version-specific key here so that multiple versions can be installed side-by-side
InstallDirRegKey HKLM "`${PICO_REG_KEY}" "InstallPath"

!ifdef BUILD_UNINSTALLER

OutFile "build\build-uninstaller-$suffix.exe"

!define MUI_UNICON "resources\raspberrypi.ico"

!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Function un.onInit

  SetShellVarContext all
  SetRegView 32

  ReadRegStr `$R0 `${PICO_REG_ROOT} "`${PICO_REG_KEY}" "InstallPath"
  DetailPrint "Install path: `$R0"
  StrCpy `$INSTDIR `$R0

  ReadRegStr `$R1 `${PICO_REG_ROOT} "`${PICO_REG_KEY}" "ReposPath"
  DetailPrint "Repos path: `$R1"

  SetRegView $bitness

FunctionEnd

Section "Uninstall"

  RMDir /r /REBOOTOK "`${PICO_SHORTCUTS_DIR}"

  RMDir /r /REBOOTOK "`$INSTDIR\cmake"
  RMDir /r /REBOOTOK "`$INSTDIR\gcc-arm-none-eabi"
  RMDir /r /REBOOTOK "`$INSTDIR\git"
  RMDir /r /REBOOTOK "`$INSTDIR\ninja"
  RMDir /r /REBOOTOK "`$INSTDIR\openocd"
  RMDir /r /REBOOTOK "`$INSTDIR\python"

  RMDir /r /REBOOTOK "`$INSTDIR\pico-sdk-tools"
  RMDir /r /REBOOTOK "`$INSTDIR\picotool"
  RMDir /r /REBOOTOK "`$INSTDIR\resources"

  Delete /REBOOTOK "`$INSTDIR\install.log"
  Delete /REBOOTOK "`$INSTDIR\pico-code.ps1"
  Delete /REBOOTOK "`$INSTDIR\pico-env.cmd"
  Delete /REBOOTOK "`$INSTDIR\pico-env.ps1"
  Delete /REBOOTOK "`$INSTDIR\pico-setup.cmd"
  Delete /REBOOTOK "`$INSTDIR\ReadMe.txt"
  Delete /REBOOTOK "`$INSTDIR\version.ini"

  Delete /REBOOTOK "`$INSTDIR\uninstall.exe"

  RMDir /REBOOTOK "`$INSTDIR"
  ; Remove the C:\Program Files\Raspberry Pi directory if it is empty
  `${GetParent} "`$INSTDIR" `$R0
  RMDir `$R0

  RMDir /r /REBOOTOK "`$R1\pico-examples"
  RMDir /r /REBOOTOK "`$R1\pico-extras"
  RMDir /r /REBOOTOK "`$R1\pico-playground"
  RMDir /r /REBOOTOK "`$R1\pico-project-generator"
  RMDir /r /REBOOTOK "`$R1\pico-sdk"

  RMDir /REBOOTOK "`$R1"
  ; Remove the C:\ProgramData\Raspberry Pi directory if it is empty
  `${GetParent} "`$R1" `$R0
  RMDir `$R0

  DeleteRegValue `${PICO_REG_ROOT} "Software\Kitware\CMake\Packages\pico-sdk-tools" "v$sdkVersion"
  DeleteRegKey /ifempty `${PICO_REG_ROOT} "Software\Kitware\CMake\Packages\pico-sdk-tools"

  DeleteRegKey `${PICO_REG_ROOT} "`${UNINSTALL_KEY}"

  DeleteRegKey `${PICO_REG_ROOT} "`${PICO_REG_KEY}"
  SetShellVarContext current
  DeleteRegKey `${PICO_REG_ROOT} "`${PICO_REG_KEY}"

SectionEnd

Section

  WriteUninstaller `$INSTDIR\uninstall-$suffix.exe

SectionEnd

!else

OutFile "$binfile"

!define MUI_ICON "resources\raspberrypi.ico"

!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "`${TITLE}"

;!define MUI_COMPONENTSPAGE_SMALLDESC

!define MUI_FINISHPAGE_RUN_TEXT "Clone and build Pico repos"
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_FUNCTION RunBuild

!define MUI_FINISHPAGE_SHOWREADME "`$INSTDIR\ReadMe.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Show ReadMe"

!define MUI_FINISHPAGE_NOAUTOCLOSE

!insertmacro MUI_PAGE_WELCOME
;!insertmacro MUI_PAGE_LICENSE "`${NSISDIR}\Docs\Modern UI\License.txt"
;!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Function .onInit

  SetShellVarContext all
  SetRegView $bitness

FunctionEnd

Section

  ; Make sure that `$INSTDIR exists before enabling logging
  SetOutPath `$INSTDIR
  LogSet on

  $(if ($bitness -eq '64') {
  '${IfNot} ${IsNativeAMD64}
    Abort "This installer only supports x86-64 versions of Windows."
  ${EndIf}'
  })

  ; Uninstall previous version
  ReadRegStr `$R0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\$basename-$sdkVersion" "UninstallString"
  `${If} `$R0 == ""
    ReadRegStr `$R0 `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "UninstallString"
  `${EndIf}
  `${If} `$R0 != ""
    `${GetParent} "`$R0" `$R1
    DetailPrint "Uninstalling previous version..."
    ExecWait '"`$R0" /S _?=`$R1'
  `${EndIf}

  InitPluginsDir
  File /oname=`$TEMP\RefreshEnv.cmd "packages\pico-setup-windows\RefreshEnv.cmd"

  ; Save install paths in the 32-bit registry for ease of access from NSIS (un)installers
  SetRegView 32
  WriteRegStr `${PICO_REG_ROOT} "`${PICO_REG_KEY}" "InstallPath" "`$INSTDIR"
  WriteRegStr `${PICO_REG_ROOT} "`${PICO_REG_KEY}" "ReposPath" "`${PICO_REPOS_DIR}"
  SetRegView $bitness

  CreateDirectory "`${PICO_REPOS_DIR}"
  CreateDirectory "`${PICO_SHORTCUTS_DIR}"

  SetOutPath `$INSTDIR\resources
  File /r resources\*.*

  SetOutPath `$INSTDIR

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

  $(if (($_ | Get-Member exec) -or ($_ | Get-Member execToLog)) {
@"
    SetOutPath "`$TEMP"
    File "downloads\$($_.file)"
    StrCpy `$0 "`$TEMP\$($_.file)"

    $(if ($_ | Get-Member exec) {
      "ExecWait ``$($_.exec)`` `$1"
    })

    $(if ($_ | Get-Member execToLog) {
      "nsExec::ExecToLog ``$($_.execToLog)```r`n"
      "Pop `$1"
    })

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

  $(if ($_ | Get-Member dirName) {
    "SetOutPath '`$INSTDIR\$($_.dirName)'`r`n"
    "File /r build\$($_.dirName)\*.*"
  })

SectionEnd

LangString DESC_Sec$($_.shortName) `${LANG_ENGLISH} "$($_.name)"

"@
})

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
  WriteRegStr `${PICO_REG_ROOT} "Software\Kitware\CMake\Packages\pico-sdk-tools" "v$sdkVersion" "`$INSTDIR\pico-sdk-tools"

  SetOutPath "`$INSTDIR\picotool"
  File "build\picotool-install\mingw$bitness\*.*"

  SetOutPath "`$INSTDIR"
  WriteINIStr "`$INSTDIR\version.ini" "pico-setup-windows" "PICO_SDK_VERSION" "$sdkVersion"
  WriteINIStr "`$INSTDIR\version.ini" "pico-setup-windows" "PICO_REPOS_PATH" "`${PICO_REPOS_DIR}"
  WriteINIStr "`$INSTDIR\version.ini" "pico-setup-windows" "PICO_INSTALL_PATH" "`$INSTDIR"
  File "packages\pico-setup-windows\pico-code.ps1"
  File "packages\pico-setup-windows\pico-env.ps1"
  File "packages\pico-setup-windows\pico-env.cmd"
  File "packages\pico-setup-windows\pico-setup.cmd"
  File "packages\pico-setup-windows\ReadMe.txt"

  File /oname=uninstall.exe "build\uninstall-$suffix.exe"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "DisplayName" "$product"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "UninstallString" "`$INSTDIR\uninstall.exe"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "DisplayIcon" "`$INSTDIR\resources\raspberrypi.ico"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "DisplayVersion" "$version"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "Publisher" "$company"

  # Find Visual Studio Code, so we can point our shortcut icon to code.exe
  ReadEnvStr `$0 COMSPEC
  nsExec::ExecToStack '"`$0" /c call "`$TEMP\RefreshEnv.cmd" && where code.cmd'
  Pop `$0 # return value/error/timeout
  Pop `$1 # stdout
  # Get the last line of output
  `${WordFind} "`$1" "`$\n" "-1" `$1
  `${GetParent} "`$1" `$1
  `${GetParent} "`$1" `$1
  StrCpy `$1 "`$1\Code.exe"

  `${CreateShortcutEx} "`${PICO_SHORTCUTS_DIR}\Pico - Developer Command Prompt.lnk" "`${PICO_AppUserModel_ID}!cmd" ``"cmd.exe" '/k "`$INSTDIR\pico-env.cmd"'``
  `${CreateShortcutEx} "`${PICO_SHORTCUTS_DIR}\Pico - Developer PowerShell.lnk" "`${PICO_AppUserModel_ID}!powershell" ``"powershell.exe" '-NoExit -ExecutionPolicy Bypass -File "`$INSTDIR\pico-env.ps1"'``
  `${CreateShortcutEx} "`${PICO_SHORTCUTS_DIR}\Pico - Visual Studio Code.lnk" "`${PICO_AppUserModel_ID}!code" ``"powershell.exe" '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "`$INSTDIR\pico-code.ps1"' "`$1" "" SW_SHOWMINIMIZED``

  CreateDirectory "`${PICO_SHORTCUTS_DIR}\Pico - Documentation"
  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Pico - Documentation\Pico Datasheet.url" "InternetShortcut" "URL" "https://datasheets.raspberrypi.com/pico/pico-datasheet.pdf"
  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Pico - Documentation\Pico W Datasheet.url" "InternetShortcut" "URL" "https://datasheets.raspberrypi.com/picow/pico-w-datasheet.pdf"
  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Pico - Documentation\Pico C C++ SDK.url" "InternetShortcut" "URL" "https://datasheets.raspberrypi.com/pico/raspberry-pi-pico-c-sdk.pdf"
  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Pico - Documentation\Pico Python SDK.url" "InternetShortcut" "URL" "https://datasheets.raspberrypi.com/pico/raspberry-pi-pico-python-sdk.pdf"

  ; Reset working dir for pico-setup.cmd launched from the finish page
  SetOutPath "`$INSTDIR"

SectionEnd

LangString DESC_SecPico `${LANG_ENGLISH} "Scripts for cloning the Pico SDK and tools repos, and for setting up your Pico development environment."

Function RunBuild

  ReadEnvStr `$0 COMSPEC
  Exec '"`$0" /k call "`$TEMP\RefreshEnv.cmd" && del "`$TEMP\RefreshEnv.cmd" && call "`$INSTDIR\pico-setup.cmd" 1'

FunctionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT `${SecCodeExts} `$(DESC_SecCodeExts)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecOpenOCD} `$(DESC_SecOpenOCD)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecPico} `$(DESC_SecPico)
$($downloads | ForEach-Object {
  "  !insertmacro MUI_DESCRIPTION_TEXT `${Sec$($_.shortName)} `$(DESC_Sec$($_.shortName))`n"
})
!insertmacro MUI_FUNCTION_DESCRIPTION_END

!endif # BUILD_UNINSTALLER
"@ | Set-Content ".\$basename-$suffix.nsi"

exec { .\build\NSIS\makensis /DBUILD_UNINSTALLER ".\$basename-$suffix.nsi" }

# The 'installer' that just writes the uninstaller asks for admin access, which is not actually needed.
$env:__COMPAT_LAYER = "RunAsInvoker"
exec { Start-Process -FilePath ".\build\build-uninstaller-$suffix.exe" -ArgumentList "/S /D=$PSScriptRoot\build" -Wait }
$env:__COMPAT_LAYER = ""

# Sign files before packaging up the installer
sign "build\uninstall-$suffix.exe",
"build\openocd-install\mingw$bitness\bin\openocd.exe",
"build\pico-sdk-tools\mingw$bitness\elf2uf2.exe",
"build\pico-sdk-tools\mingw$bitness\pioasm.exe",
"build\picotool-install\mingw$bitness\picotool.exe"

exec { .\build\NSIS\makensis ".\$basename-$suffix.nsi" }
Write-Host "Installer saved to $binfile"

# Sign the installer
sign $binfile

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
