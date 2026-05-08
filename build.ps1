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

  [switch]
  $SkipDownload,

  [switch]
  $SkipSigning,

  [ValidateSet('zlib', 'bzip2', 'lzma')]
  [string]
  $Compression = 'lzma',

  [ValidateSet('system', 'user')]
  [string]
  $BuildType = 'system'
)

#Requires -Version 7.2

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\common.ps1"

$basename = "pico-setup-windows"
$version = (Get-Content "$PSScriptRoot\version.txt").Trim()
$build = (Get-Date -Format FileDateTimeUniversal)

$tools = (Get-Content '.\config\tools.json' | ConvertFrom-Json).tools
$repositories = (Get-Content '.\config\repositories.json' | ConvertFrom-Json).repositories

$compileOpts = $null
$installerOpts = $null
$bitness = $null
$msysEnv = $null
$downloads = @()
$componentSelection = $false

if ($CompileConfig) {
  Write-Host "Loading compile configuration from $CompileConfig"
  $compileOpts = Get-Content $CompileConfig | ConvertFrom-Json
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

$env:MSYSTEM = $msysEnv
$msysEnv = $msysEnv.ToLowerInvariant()

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
  }
  else {
    $fileVersion = (Get-ChildItem $outfile).VersionInfo.ProductVersion
  }

  if ($fileVersion) {
    Write-Host $fileVersion
  }
  else {
    Write-Host $_.file
  }

  if ($_ | Get-Member dirName) {
    $strip = 0;
    if ($_ | Get-Member extractStrip) { $strip = $_.extractStrip }

    mkdirp "build\$($_.dirName)" -clean
    exec { tar -xf $outfile -C "build\$($_.dirName)" --strip-components $strip }
  }
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
  $env:PATH = $env:PATH + ';' + (Resolve-Path .\build\cmake\bin).Path
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  $env:PATH = $env:PATH + ';' + (Resolve-Path .\build\git\cmd).Path
}

$repositories | ForEach-Object {
  $reponame = [IO.Path]::GetFileNameWithoutExtension($_.href)
  $repodir = Join-Path 'build' $reponame

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
      Write-Output "::group::Cloning submodules for $reponame"
      exec { git -C "$repodir" submodule update --init --depth=1 }
      Write-Output "::endgroup::"
    }
  }
}

# BTstack needs the PyCryptodome module
if (Test-Path .\build\python\python.exe) {
  exec { .\build\python\python.exe .\downloads\pip.pyz install pycryptodome }
  Add-Content -Path .\build\python\python*._pth -Value 'import site'
}

# Clone additional Pico-specific submodules in TinyUSB
# exec { git -C .\build\pico-sdk\lib\tinyusb submodule update --init --depth=1 hw\mcu\raspberry_pi }

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

  if ($SkipSigning) {
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

  exec { & "$MSYS2Path\usr\bin\bash" -leo pipefail -c "$cmd" }
}

# Preserve the current working directory
$env:CHERE_INVOKING = 'yes'
# Use real symlinks
$env:MSYS = "winsymlinks:nativestrict"

if ($null -ne $compileOpts) {
  if (-not (Test-Path $MSYS2Path)) {
    Write-Host 'Extracting MSYS2'
    exec { & .\downloads\msys2.exe -y "-o$(Resolve-Path (Split-Path $MSYS2Path -Parent))" }
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
  Write-Host "No installer configuration file provided. Skipping installer build."
  exit 0
}

$suffix = [io.path]::GetFileNameWithoutExtension($InstallerConfig) + ($BuildType -eq 'user' ? '-user' : '' )
$binfile = "bin\$basename-$suffix.exe"

$downloads | ForEach-Object {

  "Section ``$($_.name)`` Sec$($_.shortName)"
  'ClearErrors'

  if ($_ | Get-Member additionalFiles) {
    $_.additionalFiles | ForEach-Object {
      "File /oname=`$PLUGINSDIR\$(Split-Path -Leaf $_) $_`r`n"
    }
  }

  if (($_ | Get-Member exec) -or ($_ | Get-Member execToLog)) {

    'SetOutPath "$TEMP"'
    "File ``downloads\$($_.file)``"
    "StrCpy `$0 ```$TEMP\$($_.file)``"

    if ($_ | Get-Member exec) {
      "ExecWait ``$($_.exec)`` `$1"
    }

    if ($_ | Get-Member execToLog) {
      "nsExec::ExecToLog ``$($_.execToLog)``"
      "Pop `$1"
    }

    "DetailPrint ``$($_.name) returned `$1``"
    "Delete /REBOOTOK ``$0``"

    '${If} ${Errors}'
    "  Abort ``Installation of $($_.name) failed``"

    if ($_ | Get-Member rebootExitCodes) {
      $_.rebootExitCodes | ForEach-Object {
        "`${ElseIf} `$1 = $_"
        '    SetRebootFlag true'
      }
    }

    '${ElseIf} `$1 <> 0'
    "  Abort ``Installation of $($_.name) failed``"
    '${EndIf}'
  }

  if ($_ | Get-Member dirName) {
    "SetOutPath '`$INSTDIR\$($_.dirName)'`r`n"
    "File /r build\$($_.dirName)\*.*"
  }

  'SectionEnd'
  "LangString DESC_Sec$($_.shortName) `${LANG_ENGLISH} ``$($_.name)``"
} | Out-File -FilePath "build\installer-sections.nsh"

if ($componentSelection) {
  {
    '!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN'

    $($downloads | ForEach-Object {
      "  !insertmacro MUI_DESCRIPTION_TEXT `${Sec$($_.shortName)} `$(DESC_Sec$($_.shortName))"
    })

    '!insertmacro MUI_FUNCTION_DESCRIPTION_END'
  } | Out-File -FilePath "build\installer-sections.nsh" -Append
}

@"
!define COMPANY "$company"
!define PRODUCT "$product"
!define PRODUCT_DIR "$productDir"
!define TITLE "$product"
!define VERSION "$version"
!define BITNESS $bitness
!define OUTPUT_FILE "$binfile"
!define PICO_SDK_VERSION "$sdkVersion"
!define AUMID "$(pascalCase $company).$(pascalCase $basename).$sdkVersion"
!define ARP_DISPLAY_NAME "$($BuildType -eq 'system' ? $product : "$product (User)")"
!define SHELL_VAR_CONTEXT $($BuildType -eq 'system' ? 'all' : 'current')
!define UNINSTALL_KEY_OLD "Software\Microsoft\Windows\CurrentVersion\Uninstall\$basename-$sdkVersion"

$($componentSelection ? '!define ALLOW_COMPONENT_SELECTION' : '')

SetCompressor $Compression
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

@"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "MUI2.nsh"
!include "WinCore.nsh"
!include "WordFunc.nsh"
!include "x64.nsh"

!include "packages\pico-setup-windows\aumi.nsh"
!include "packages\pico-setup-windows\WindowsTerminal.nsh"

!include "build\installer-header.nsh"

!define PICO_INSTALL_DIR PRODUCT_DIR
!define PICO_SHORTCUTS_DIR "`$SMPROGRAMS\`${PRODUCT}"
!define PICO_WINTERM_DIR "`${WINTERMDIR}\`${PRODUCT}"
!define PICO_REG_ROOT SHELL_CONTEXT
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${PRODUCT}"
!define PICO_AppUserModel_ID AUMID

Name "`${TITLE}"
Caption "`${TITLE}"
XPStyle on
ManifestDPIAware true
Unicode true

; Since we're packaging up a bunch of installers, the "Space required" shown is inaccurate
SpaceTexts "none"

; We set the default INSTDIR ourselves in .onInit
InstallDir ""

!ifdef BUILD_UNINSTALLER

OutFile "build\build-uninstaller.exe"

; !define MUI_UNICON "resources\raspberrypi.ico"

!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Function un.onInit

  SetShellVarContext `${SHELL_VAR_CONTEXT}
  SetRegView `${BITNESS}

FunctionEnd

Section "Uninstall"

  RMDir /r /REBOOTOK "`${PICO_SHORTCUTS_DIR}"
  RMDir /r /REBOOTOK "`${PICO_WINTERM_DIR}"

  RMDir /r /REBOOTOK "`$INSTDIR\cmake"
  RMDir /r /REBOOTOK "`$INSTDIR\gcc-arm-none-eabi"
  RMDir /r /REBOOTOK "`$INSTDIR\git"
  RMDir /r /REBOOTOK "`$INSTDIR\ninja"
  RMDir /r /REBOOTOK "`$INSTDIR\openocd"
  RMDir /r /REBOOTOK "`$INSTDIR\python"

  RMDir /r /REBOOTOK "`$INSTDIR\pico-sdk-tools"
  RMDir /r /REBOOTOK "`$INSTDIR\picotool"
  ; RMDir /r /REBOOTOK "`$INSTDIR\resources"

  Delete /REBOOTOK "`$INSTDIR\install.log"
  Delete /REBOOTOK "`$INSTDIR\pico-env.cmd"
  Delete /REBOOTOK "`$INSTDIR\pico-env.ps1"
  Delete /REBOOTOK "`$INSTDIR\pico-setup.cmd"
  Delete /REBOOTOK "`$INSTDIR\pico-setup.lnk"
  Delete /REBOOTOK "`$INSTDIR\README.txt"
  Delete /REBOOTOK "`$INSTDIR\version.ini"

  Delete /REBOOTOK "`$INSTDIR\uninstall.exe"

  RMDir /REBOOTOK "`$INSTDIR"

  DeleteRegKey `${PICO_REG_ROOT} "`${UNINSTALL_KEY}"

SectionEnd

Section

  WriteUninstaller `$INSTDIR\uninstall.exe

SectionEnd

!else

OutFile "`${OUTPUT_FILE}"

; !define MUI_ICON "resources\raspberrypi.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "`${TITLE}"

!insertmacro MUI_PAGE_WELCOME
!ifdef ALLOW_COMPONENT_SELECTION
  !insertmacro MUI_PAGE_COMPONENTS
!endif
!insertmacro MUI_PAGE_DIRECTORY
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE DumpLog
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_SHOWREADME "`$INSTDIR\README.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Show ReadMe"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

!include "packages\pico-setup-windows\DumpLog.nsh"

Function .onInit

  SetShellVarContext `${SHELL_VAR_CONTEXT}
  SetRegView `${BITNESS}

  ; No /D= on the command line
  `${If} `$INSTDIR == ""
    ReadRegStr `$INSTDIR `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "InstallPath"
  `${EndIf}

  ; Nothing in the registry either; use the defaults
  `${If} `$INSTDIR == ""
    `${GetRoot} `$WINDIR `$INSTDIR
    StrCpy `$INSTDIR "`$INSTDIR\`${PICO_INSTALL_DIR}"
  `${EndIf}

FunctionEnd

Section

  SetOutPath `$INSTDIR

  !if `${BITNESS} = 64
  `${IfNot} `${RunningX64}
  `${AndIfNot} `${IsNativeARM64}
    Abort "This installer only supports 64-bit versions of Windows."
  `${EndIf}
  !endif

  ; Uninstall previous version
  ReadRegStr `$R0 HKCU "`${UNINSTALL_KEY_OLD}" "UninstallString"
  `${If} `$R0 == ""
    ReadRegStr `$R0 `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "UninstallString"
  `${EndIf}
  `${If} `$R0 != ""
    `${GetParent} "`$R0" `$R1
    DetailPrint "Uninstalling previous version..."
    ExecWait '"`$R0" /S _?=`$R1' `$1
    DetailPrint "Uninstaller returned `$1"
  `${EndIf}

  InitPluginsDir

  CreateDirectory "`${PICO_SHORTCUTS_DIR}"

  ; SetOutPath `$INSTDIR\resources
  ; File /r resources\*.*

  SetOutPath `$INSTDIR

SectionEnd

!include "build\installer-sections.nsh"

Section "-OpenOCD" SecOpenOCD

  SetOutPath "`$INSTDIR\openocd"
  File "build\openocd-install\$msysEnv\bin\*.*"
  SetOutPath "`$INSTDIR\openocd\scripts"
  File /r "build\openocd-install\$msysEnv\share\openocd\scripts\*.*"

SectionEnd

Section "-riscv-gnu-toolchain" SecRiscV

  SetOutPath "`$INSTDIR\riscv-gnu-toolchain"
  File /r "build\riscv-gnu-toolchain-install\$msysEnv\*.*"

SectionEnd

Section "-Pico environment" SecPico

  SetOutPath "`$INSTDIR\pico-sdk"
  File /r "build\pico-sdk\*.*"

  SetOutPath "`$INSTDIR\pico-sdk-tools"
  File /r "build\pico-sdk-tools\$msysEnv\*.*"

  SetOutPath "`$INSTDIR"
  WriteINIStr "`$INSTDIR\version.ini" "pico-setup-windows" "PICO_SDK_VERSION" "`${PICO_SDK_VERSION}"
  File "packages\pico-setup-windows\pico-env.ps1"
  File "packages\pico-setup-windows\pico-env.cmd"
  File "packages\pico-setup-windows\pico-setup.cmd"
  File "docs\README.txt"

  File "build\uninstall.exe"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "DisplayName" "`${ARP_DISPLAY_NAME}"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "UninstallString" "`$INSTDIR\uninstall.exe"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "InstallPath" "`$INSTDIR"
  ; WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "DisplayIcon" "`$INSTDIR\resources\raspberrypi.ico"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "DisplayVersion" "`${VERSION}"
  WriteRegStr `${PICO_REG_ROOT} "`${UNINSTALL_KEY}" "Publisher" "`${COMPANY}"

  `${CreateShortcutEx} "`${PICO_SHORTCUTS_DIR}\Pico - Developer Command Prompt.lnk" "`${PICO_AppUserModel_ID}!cmd" ``"cmd.exe" '/k "`$INSTDIR\pico-env.cmd"'``
  `${CreateShortcutEx} "`${PICO_SHORTCUTS_DIR}\Pico - Developer PowerShell.lnk" "`${PICO_AppUserModel_ID}!powershell" ``"powershell.exe" '-NoExit -ExecutionPolicy RemoteSigned -File "`$INSTDIR\pico-env.ps1"'``

  SetOutPath "`${PICO_WINTERM_DIR}"
  `${WINTERM_FRAGMENT_BEGIN} "pico-terminals.json"
  `${WINTERM_PROFILE} "Pico - Developer Command Prompt (SDK v`${PICO_SDK_VERSION})" ``cmd.exe /k "`$INSTDIR\pico-env.cmd"`` "`$INSTDIR" ""
  `${WINTERM_PROFILE} "Pico - Developer PowerShell (SDK v`${PICO_SDK_VERSION})" ``powershell.exe -NoExit -ExecutionPolicy RemoteSigned -File "`$INSTDIR\pico-env.ps1"`` "`$INSTDIR" ""
  `${WINTERM_FRAGMENT_END}

  ; Reset working dir
  SetOutPath "`$INSTDIR"

SectionEnd

!endif # BUILD_UNINSTALLER
"@ | Set-Content ".\$basename-$suffix.nsi"

exec { .\build\NSIS\makensis /DBUILD_UNINSTALLER ".\$basename-$suffix.nsi" }

# The 'installer' that just writes the uninstaller asks for admin access, which is not actually needed.
$env:__COMPAT_LAYER = "RunAsInvoker"
exec { Start-Process -FilePath ".\build\build-uninstaller.exe" -ArgumentList "/S /D=$(Join-Path $PSScriptRoot 'build')" -Wait }
$env:__COMPAT_LAYER = ""

# Sign files before packaging up the installer
sign "build\uninstall.exe",
"build\openocd-install\$msysEnv\bin\openocd.exe",
"build\pico-sdk-tools\$msysEnv\elf2uf2\elf2uf2.exe",
"build\pico-sdk-tools\$msysEnv\pioasm\pioasm.exe",
"build\pico-sdk-tools\$msysEnv\picotool\picotool.exe"

exec { .\build\NSIS\makensis ".\$basename-$suffix.nsi" }
Write-Host "Installer saved to $binfile"

# Sign the installer
sign $binfile

# Package OpenOCD separately as well

$version = (cmd /c ".\build\openocd-install\$msysEnv\bin\openocd.exe" --version '2>&1')[0]
if (-not ($version -match 'Open On-Chip Debugger (?<version>[a-zA-Z0-9\.\-+]+) \((?<timestamp>[0-9\-:]+)\)')) {
  Write-Error 'Could not determine openocd version'
}

$filename = 'openocd-{0}-{1}-{2}.zip' -f
($Matches.version -replace '-dirty$', ''),
($Matches.timestamp -replace '[:-]', ''),
$suffix

Write-Host "Saving OpenOCD package to $filename"
exec { tar -a -cf "bin\$filename" -C "build\openocd-install\$msysEnv\bin" '*' -C "..\share\openocd" "scripts" }
