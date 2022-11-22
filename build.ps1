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

$tools = (Get-Content '.\tools.json' | ConvertFrom-Json).tools
$repositories = (Get-Content '.\repositories.json' | ConvertFrom-Json).repositories
$config = Get-Content $ConfigFile | ConvertFrom-Json
$bitness = $config.bitness
$mingw_arch = $config.mingw_arch
$downloads = $config.downloads

$product = "Raspberry Pi Pico SDK $version"

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
  msys "cd build && ../build-openocd.sh $bitness $mingw_arch"
}

if (-not (Test-Path ".\build\picotool-install\mingw$bitness")) {
  msys "cd build && ../build-picotool.sh $bitness $mingw_arch"
}

@"
!include "MUI2.nsh"
!include "WordFunc.nsh"

!define TITLE "$product"
!define PICO_INSTALL_DIR "`$PROGRAMFILES64\$product"
; The repos need to be cloned into a dir with a fairly short name, because
; CMake generates build defs with long hashes in the paths. Both CMake and
; Ninja currently have problems working with long paths on Windows.
; !define PICO_REPOS_DIR "`$LOCALAPPDATA\Programs\$product"
!define PICO_REPOS_DIR "`$DOCUMENTS\Pico"
!define PICO_SHORTCUTS_DIR "`$SMPROGRAMS\$product"

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
InstallDirRegKey HKCU "Software\$basename" "InstallPath"

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

  ReadRegStr `$R0 HKLM "SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine" "PowerShellVersion"
  DetailPrint "Detected PowerShell version: `$R0"
  `${VersionCompare} "5.1.0.0" `$R0 `$R1
  `${If} `$R1 < 2
    Abort "Windows PowerShell 5.1 is required for this installation. Please install WMF 5.1 and re-run setup."
  `${EndIf}
  ClearErrors

  ; https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed
  ; Check for .NET Framework 4.6.2, required for Visual Studio 2019 Build Tools
  ReadRegDWORD `$R0 HKLM "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" "Release"
  DetailPrint "Detected .NET Framework 4 release: `$R0"
  `${If} `$R0 < 394802
    Abort ".NET Framework 4.6.2 or later is required for this installation. Please install the latest .NET Framework 4.x and re-run setup."
  `${EndIf}
  ClearErrors

  InitPluginsDir
  File /oname=`$TEMP\RefreshEnv.cmd RefreshEnv.cmd

  WriteRegStr HKCU "Software\$basename" "InstallPath" "`$INSTDIR"
  WriteRegStr HKCU "Software\$basename\v$version" "InstallPath" "`$INSTDIR"

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

  SetOutPath "`$INSTDIR\pico-sdk-tools"
  File "build\pico-sdk-tools\mingw$bitness\*.*"
  WriteRegStr HKCU "Software\Kitware\CMake\Packages\pico-sdk-tools" "v$version" "`$INSTDIR\pico-sdk-tools"

  SetOutPath "`$INSTDIR\picotool"
  File "build\picotool-install\mingw$bitness\*.*"

  SetOutPath "`${PICO_REPOS_DIR}"
  File "version.txt"
  File "pico-env.cmd"
  File "pico-setup.cmd"
  File "docs\ReadMe.txt"

  CreateShortcut "`${PICO_SHORTCUTS_DIR}\Developer Command Prompt for Pico.lnk" "cmd.exe" '/k "`${PICO_REPOS_DIR}\pico-env.cmd"'

  CreateShortcut "`${PICO_SHORTCUTS_DIR}\Open pico-examples in Visual Studio Code.lnk" "cmd.exe" '/c (call "`${PICO_REPOS_DIR}\pico-env.cmd" && code --disable-workspace-trust "`${PICO_REPOS_DIR}\pico-examples") || pause' "`$INSTDIR\resources\vscode.ico"

  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Raspberry Pi microcontrollers documentation.url" "InternetShortcut" "URL" "https://www.raspberrypi.com/documentation/microcontrollers/"

  WriteINIStr "`${PICO_SHORTCUTS_DIR}\Raspberry Pi Pico C-C++ SDK documentation.url" "InternetShortcut" "URL" "https://www.raspberrypi.com/documentation/microcontrollers/c_sdk.html"

  ; Unconditionally create a shortcut for VS Code -- in case the user had it
  ; installed already, or if they install it later
  CreateShortcut "`${PICO_SHORTCUTS_DIR}\Visual Studio Code for Pico.lnk" "cmd.exe" '/c (call "`${PICO_REPOS_DIR}\pico-env.cmd" && code) || pause' "`$INSTDIR\resources\vscode.ico"

  ; SetOutPath is needed here to set the working directory for the shortcut
  SetOutPath "`$INSTDIR\pico-project-generator"
  CreateShortcut "`${PICO_SHORTCUTS_DIR}\Pico Project Generator.lnk" "cmd.exe" '/c (call "`${PICO_REPOS_DIR}\pico-env.cmd" && python "`${PICO_REPOS_DIR}\pico-project-generator\pico_project.py" --gui) || pause'

  ; Reset working dir for pico-setup.cmd launched from the finish page
  SetOutPath "`${PICO_REPOS_DIR}"

SectionEnd

LangString DESC_SecPico `${LANG_ENGLISH} "Scripts for cloning the Pico SDK and tools repos, and for setting up your Pico development environment."

Section "Download documents and files" SecDocs

  SetOutPath "`$INSTDIR"
  File "common.ps1"
  File "pico-docs.ps1"

SectionEnd

Function RunBuild

  ReadEnvStr `$0 COMSPEC
  Exec '"`$0" /k call "`$TEMP\RefreshEnv.cmd" && del "`$TEMP\RefreshEnv.cmd" && call "`${PICO_REPOS_DIR}\pico-setup.cmd" 1'

FunctionEnd

LangString DESC_SecDocs `${LANG_ENGLISH} "Adds a script to download the latest Pico documents, design files, and UF2 files."

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT `${SecCodeExts} `$(DESC_SecCodeExts)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecOpenOCD} `$(DESC_SecOpenOCD)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecPico} `$(DESC_SecPico)
  !insertmacro MUI_DESCRIPTION_TEXT `${SecDocs} `$(DESC_SecDocs)
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
