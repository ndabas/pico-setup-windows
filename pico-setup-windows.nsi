!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "MUI2.nsh"
!include "WinCore.nsh"
!include "WordFunc.nsh"
!include "x64.nsh"

!include "packages\pico-setup-windows\aumi.nsh"
!include "packages\pico-setup-windows\WindowsTerminal.nsh"

!include "build\installer-header.nsh"

!define PICO_INSTALL_DIR "${PRODUCT_DIR}"
!define PICO_SHORTCUTS_DIR "$SMPROGRAMS\${PRODUCT}"
!define PICO_WINTERM_DIR "${WINTERMDIR}\${PRODUCT}"
!define PICO_REG_ROOT SHELL_CONTEXT
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT}"
!define PICO_AppUserModel_ID AUMID

Name "${TITLE}"
Caption "${TITLE}"
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

  SetShellVarContext ${SHELL_VAR_CONTEXT}
  SetRegView ${BITNESS}

FunctionEnd

!include "build\uninstaller-sections.nsh"

Section "Uninstall"

  RMDir /r /REBOOTOK "${PICO_SHORTCUTS_DIR}"
  RMDir /r /REBOOTOK "${PICO_WINTERM_DIR}"
  ; RMDir /r /REBOOTOK "$INSTDIR\resources"

  Delete /REBOOTOK "$INSTDIR\install.log"
  Delete /REBOOTOK "$INSTDIR\pico-env.cmd"
  Delete /REBOOTOK "$INSTDIR\pico-env.ps1"
  Delete /REBOOTOK "$INSTDIR\pico-setup.cmd"
  Delete /REBOOTOK "$INSTDIR\pico-setup.lnk"
  Delete /REBOOTOK "$INSTDIR\README.txt"
  Delete /REBOOTOK "$INSTDIR\version.ini"

  Delete /REBOOTOK "$INSTDIR\uninstall.exe"

  RMDir /REBOOTOK "$INSTDIR"

  DeleteRegKey ${PICO_REG_ROOT} "${UNINSTALL_KEY}"

SectionEnd

Section

  WriteUninstaller $INSTDIR\uninstall.exe

SectionEnd

!else

OutFile "${OUTPUT_FILE}"

; !define MUI_ICON "resources\raspberrypi.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "${TITLE}"

!insertmacro MUI_PAGE_WELCOME
!ifdef ALLOW_COMPONENT_SELECTION
  !insertmacro MUI_PAGE_COMPONENTS
!endif
!insertmacro MUI_PAGE_DIRECTORY
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE DumpLog
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\README.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Show ReadMe"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

!include "packages\pico-setup-windows\DumpLog.nsh"

Function .onInit

  SetShellVarContext ${SHELL_VAR_CONTEXT}
  SetRegView ${BITNESS}

  ; No /D= on the command line
  ${If} $INSTDIR == ""
    ReadRegStr $INSTDIR ${PICO_REG_ROOT} "${UNINSTALL_KEY}" "InstallPath"
  ${EndIf}

  ; Nothing in the registry either; use the defaults
  ${If} $INSTDIR == ""
    ${GetRoot} $WINDIR $INSTDIR
    StrCpy $INSTDIR "$INSTDIR\${PICO_INSTALL_DIR}"
  ${EndIf}

FunctionEnd

Section

  SetOutPath $INSTDIR

  !if ${BITNESS} = 64
  ${IfNot} ${RunningX64}
  ${AndIfNot} ${IsNativeARM64}
    Abort "This installer only supports 64-bit versions of Windows."
  ${EndIf}
  !endif

  ; Uninstall previous version
  ReadRegStr $R0 HKCU "${UNINSTALL_KEY_OLD}" "UninstallString"
  ${If} $R0 == ""
    ReadRegStr $R0 ${PICO_REG_ROOT} "${UNINSTALL_KEY}" "UninstallString"
  ${EndIf}
  ${If} $R0 != ""
    ${GetParent} "$R0" $R1
    DetailPrint "Uninstalling previous version..."
    ExecWait '"$R0" /S _?=$R1' $1
    DetailPrint "Uninstaller returned $1"
  ${EndIf}

  InitPluginsDir

  CreateDirectory "${PICO_SHORTCUTS_DIR}"

  ; SetOutPath $INSTDIR\resources
  ; File /r resources\*.*

  SetOutPath $INSTDIR

SectionEnd

!include "build\installer-sections.nsh"

Section "-Pico environment" SecPico

  SetOutPath "$INSTDIR\pico-sdk"
  File /r "build\pico-sdk\*.*"

  SetOutPath "$INSTDIR"
  WriteINIStr "$INSTDIR\version.ini" "pico-setup-windows" "PICO_SDK_VERSION" "${PICO_SDK_VERSION}"
  File "packages\pico-setup-windows\pico-env.ps1"
  File "packages\pico-setup-windows\pico-env.cmd"
  File "packages\pico-setup-windows\pico-setup.cmd"
  File "docs\README.txt"

  File "build\uninstall.exe"
  WriteRegStr ${PICO_REG_ROOT} "${UNINSTALL_KEY}" "DisplayName" "${ARP_DISPLAY_NAME}"
  WriteRegStr ${PICO_REG_ROOT} "${UNINSTALL_KEY}" "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegStr ${PICO_REG_ROOT} "${UNINSTALL_KEY}" "InstallPath" "$INSTDIR"
  ; WriteRegStr ${PICO_REG_ROOT} "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\resources\raspberrypi.ico"
  WriteRegStr ${PICO_REG_ROOT} "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr ${PICO_REG_ROOT} "${UNINSTALL_KEY}" "Publisher" "${COMPANY}"

  ${CreateShortcutEx} "${PICO_SHORTCUTS_DIR}\Pico - Developer Command Prompt.lnk" "${PICO_AppUserModel_ID}!cmd" `"cmd.exe" '/k "$INSTDIR\pico-env.cmd"'`
  ${CreateShortcutEx} "${PICO_SHORTCUTS_DIR}\Pico - Developer PowerShell.lnk" "${PICO_AppUserModel_ID}!powershell" `"powershell.exe" '-NoExit -ExecutionPolicy RemoteSigned -File "$INSTDIR\pico-env.ps1"'`

  SetOutPath "${PICO_WINTERM_DIR}"
  ${WINTERM_FRAGMENT_BEGIN} "pico-terminals.json"
  ${WINTERM_PROFILE} "Pico - Developer Command Prompt (SDK v${PICO_SDK_VERSION})" `cmd.exe /k "$INSTDIR\pico-env.cmd"` "$INSTDIR" ""
  ${WINTERM_PROFILE} "Pico - Developer PowerShell (SDK v${PICO_SDK_VERSION})" `powershell.exe -NoExit -ExecutionPolicy RemoteSigned -File "$INSTDIR\pico-env.ps1"` "$INSTDIR" ""
  ${WINTERM_FRAGMENT_END}

  ; Reset working dir
  SetOutPath "$INSTDIR"

SectionEnd

!endif # BUILD_UNINSTALLER
