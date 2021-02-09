[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,
               Position=0,
               HelpMessage="Path to a JSON installer configuration file.")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string]
    $ConfigFile,

    [Parameter(HelpMessage="Path to MSYS2 installation. MSYS2 will be downloaded and installed to this path if it doesn't exist.")]
    [ValidatePattern('[\\\/]msys64$')]
    [string]
    $MSYS2Path = '.\build\msys64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host "Building from $ConfigFile"

$suffix = [io.path]::GetFileNameWithoutExtension($ConfigFile)

$tools = (Get-Content '.\tools.json' | ConvertFrom-Json).tools
$config = Get-Content $ConfigFile | ConvertFrom-Json
$bitness = $config.bitness
$mingw_arch = $config.mingw_arch
$installers = $config.installers

($installers + $tools) | ForEach-Object {
  $_ | Add-Member -NotePropertyName 'shortName' -NotePropertyValue ($_.name -replace '[^a-zA-Z0-9]', '')

  Write-Host "Downloading $($_.name)"
  curl.exe --fail --silent --show-error --url "$($_.href)" --location --output "installers/$($_.file)" --create-dirs --remote-time --time-cond "installers/$($_.file)"
}

function mkdirp {
  param ([string] $dir)

  New-Item -Path $dir -Type Directory -Force | Out-Null
}

mkdirp "build"
mkdirp "bin"

if (-not (Test-Path $MSYS2Path)) {
  Write-Host 'Extracting MSYS2'
  & .\installers\msys2.exe -y "-o$(Resolve-Path (Split-Path $MSYS2Path -Parent))"
}

if (-not (Test-Path build\NSIS)) {
  Write-Host 'Extracting NSIS'
  Expand-Archive '.\installers\nsis.zip' -DestinationPath '.\build'
  Rename-Item (Resolve-Path '.\build\nsis-*').Path 'NSIS'
}

function msys {
  param ([string] $cmd)

  & "$MSYS2Path\usr\bin\bash" -lc "$cmd"
}

if (-not (Test-Path ".\build\openocd-install\mingw$bitness")) {
  # First run setup
  msys 'uname -a'
  # Core update
  msys 'pacman --noconfirm -Syuu'
  # Normal update
  msys 'pacman --noconfirm -Suu'

  $openocd_deps = @(
    "autoconf",
    "automake",
    "git",
    "libtool",
    "make",
    "mingw-w64-${mingw_arch}-toolchain",
    "mingw-w64-cross-winpthreads-git",
    "mingw-w64-${mingw_arch}-libusb",
    "pkg-config"
  )
  msys ('pacman -S --noconfirm --needed ' + $openocd_deps -join ' ')

  # Preserve the current working directory
  $env:CHERE_INVOKING = 'yes'
  # Start MINGW32/64 environment
  $env:MSYSTEM = "MINGW$bitness"

  msys "cd build && ../build-openocd.sh $bitness $mingw_arch"
}

@"
!include "MUI2.nsh"

Name "Pico setup for Windows"
Caption "Pico setup for Windows"
OutFile "bin\pico-setup-windows-$suffix.exe"
Unicode True

InstallDir "`$DOCUMENTS\Pico"

;Get installation folder from registry if available
InstallDirRegKey HKCU "Software\pico-setup-windows" ""

!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "Pico setup for Windows"

!define MUI_FINISHPAGE_RUN_TEXT "Clone and build Pico repos"
!define MUI_FINISHPAGE_RUN "cmd.exe"
!define MUI_FINISHPAGE_RUN_PARAMETERS "/k call `$\"`$TEMP\RefreshEnv.cmd`$\" && del `$\"`$TEMP\RefreshEnv.cmd`$\" && call `$\"`$INSTDIR\pico-setup.cmd`$\""

!define MUI_FINISHPAGE_SHOWREADME "`$INSTDIR\ReadMe.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Show ReadMe"

!define MUI_FINISHPAGE_NOAUTOCLOSE

!insertmacro MUI_PAGE_WELCOME
;!insertmacro MUI_PAGE_LICENSE "`${NSISDIR}\Docs\Modern UI\License.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Section

  InitPluginsDir
  File /oname=`$TEMP\RefreshEnv.cmd RefreshEnv.cmd
  File /oname=`$PLUGINSDIR\git.inf git.inf

SectionEnd

$($installers | ForEach-Object {
@"

Section "$($_.name)" Sec$($_.shortName)

  SetOutPath "`$TEMP"
  File "installers\$($_.file)"
  StrCpy `$0 "`$TEMP\$($_.file)"
  ExecWait '$($_.exec)' `$1
  DetailPrint "$($_.name) returned `$1"
  Delete /REBOOTOK "`$0"

SectionEnd

LangString DESC_Sec$($_.shortName) `${LANG_ENGLISH} "$($_.name)"

"@
})

Section "VS Code Extensions" SecCodeExts

  nsExec::ExecToLog 'cmd.exe /c call "`$TEMP\RefreshEnv.cmd" && code --install-extension marus25.cortex-debug'
  Pop `$0
  nsExec::ExecToLog 'cmd.exe /c call "`$TEMP\RefreshEnv.cmd" && code --install-extension ms-vscode.cmake-tools'
  Pop `$0
  nsExec::ExecToLog 'cmd.exe /c call "`$TEMP\RefreshEnv.cmd" && code --install-extension ms-vscode.cpptools'
  Pop `$0

SectionEnd

LangString DESC_SecCodeExts `${LANG_ENGLISH} "Recommended extensions for Visual Studio Code: C/C++, CMake-Tools, and Cortex-Debug"

Section "OpenOCD" SecOpenOCD

  SetOutPath "`$INSTDIR\openocd-picoprobe"
  File "build\openocd-install\mingw$bitness\bin\*.*"
  SetOutPath "`$INSTDIR\openocd-picoprobe\scripts"
  File /r "build\openocd-install\mingw$bitness\share\openocd\scripts\*.*"

SectionEnd

LangString DESC_SecOpenOCD `${LANG_ENGLISH} "Open On-Chip Debugger with picoprobe support"

Section /o "Zadig" SecZadig

  SetOutPath "`$INSTDIR\tools"
  File "installers\zadig.exe"

SectionEnd

LangString DESC_SecZadig `${LANG_ENGLISH} "Zadig is a Windows application that installs generic USB drivers. Used with picoprobe."

Section "Pico environment" SecPico

  SetOutPath "`$INSTDIR"
  File "pico-env.cmd"
  File "pico-setup.cmd"
  File "docs\ReadMe.txt"

  CreateShortcut "`$INSTDIR\Developer Command Prompt for Pico.lnk" "cmd.exe" '/k "`$INSTDIR\pico-env.cmd"'

  ; Unconditionally create a shortcut for VS Code -- in case the user had it
  ; installed already, or if they install it later
  CreateShortcut "`$INSTDIR\Visual Studio Code for Pico.lnk" "cmd.exe" '/c call "`$INSTDIR\pico-env.cmd" && code'

  ; SetOutPath is needed here to set the working directory for the shortcut
  SetOutPath "`$INSTDIR\pico-project-generator"
  CreateShortcut "`$INSTDIR\Pico Project Generator.lnk" "cmd.exe" '/c call "`$INSTDIR\pico-env.cmd" && python "`$INSTDIR\pico-project-generator\pico_project.py" --gui'

  ; Reset working dir for pico-setup.cmd launched from the finish page
  SetOutPath "`$INSTDIR"

SectionEnd

LangString DESC_SecPico `${LANG_ENGLISH} "Scripts for cloning the Pico SDK and tools repos, and for setting up your Pico development environment."

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT `${SecCodeExts} `$(DESC_SecCodeExts)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecOpenOCD} `$(DESC_SecOpenOCD)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecZadig} `$(DESC_SecZadig)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecPico} `$(DESC_SecPico)
$($installers | ForEach-Object {
  "  !insertmacro MUI_DESCRIPTION_TEXT `${Sec$($_.shortName)} `$(DESC_Sec$($_.shortName))`n"
})
!insertmacro MUI_FUNCTION_DESCRIPTION_END
"@ | Set-Content ".\pico-setup-windows-$suffix.nsi"

.\build\NSIS\makensis ".\pico-setup-windows-$suffix.nsi"
