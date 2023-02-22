!include "LogicLib.nsh"
!include "x64.nsh"

!define /ifndef VSCODE_DOWNLOAD_URL https://code.visualstudio.com/sha/download?build=stable&os=win32
!define /ifndef VSCODE_DOWNLOAD_PATH $TEMP\vscode-install.exe

Var VSCodeExePath
Var VSCodeCmdPath

; Find VS Code
; Based on https://github.com/microsoft/vcpkg-tool/blob/main/src/vcpkg/commands.edit.cpp

!macro _ReadUninstallRegStr root_key inno_app_id user_var
  ${If} $VSCodeExePath == ""
    ReadRegStr $VSCodeExePath ${root_key} "Software\Microsoft\Windows\CurrentVersion\Uninstall\{${inno_app_id}}_is1" "InstallLocation"
  ${EndIf}
!macroend

!define FindVSCode '!insertmacro FindVSCode '
!macro FindVSCode
  Push $R1
  Push $R2

  StrCpy $VSCodeExePath ""
  StrCpy $VSCodeCmdPath ""

  StrCpy $R1 "Code.exe"
  StrCpy $R2 "bin\code.cmd"

  ; x64-user
  !insertmacro _ReadUninstallRegStr HKCU 771FD6B0-FA20-440A-A002-3B3BAC16DC50 $VSCodeExePath
  ; x86-user
  !insertmacro _ReadUninstallRegStr HKCU D628A17A-9713-46BF-8D57-E671B46A741E $VSCodeExePath
  ; x86-system
  !insertmacro _ReadUninstallRegStr HKLM32 F8A2A208-72B3-4D61-95FC-8A65D340689B $VSCodeExePath
  ; x64-system
  !insertmacro _ReadUninstallRegStr HKLM64 EA457B21-F73E-494C-ACAB-524FDE069978 $VSCodeExePath

  !ifdef VSCODE_FIND_INSIDERS
  ${If} $VSCodeExePath == ""
    StrCpy $R1 "Code - Insiders.exe"
    StrCpy $R2 "bin\code-insiders.cmd"
  ${EndIf}

  ; x64-user insider
  !insertmacro _ReadUninstallRegStr HKCU 217B4C08-948D-4276-BFBB-BEE930AE5A2C $VSCodeExePath
  ; x86-user insider
  !insertmacro _ReadUninstallRegStr HKCU 26F4A15E-E392-4887-8C09-7BC55712FD5B $VSCodeExePath
  ; x86-system insider
  !insertmacro _ReadUninstallRegStr HKLM32 C26E74D1-022E-4238-8B9D-1E7564A36CC9 $VSCodeExePath
  ; x64-system insider
  !insertmacro _ReadUninstallRegStr HKLM64 1287CAD5-7C8D-410D-88B9-0D1EE4A83FF2 $VSCodeExePath
  !endif

  ${If} $VSCodeExePath != ""
    Push $R0

    StrCpy $R0 $VSCodeExePath "" -1
    ${If} $R0 == "\"
      StrCpy $VSCodeExePath $VSCodeExePath -1
    ${EndIf}

    StrCpy $VSCodeCmdPath "$VSCodeExePath\$R2"
    StrCpy $VSCodeExePath "$VSCodeExePath\$R1"

    Pop $R0
  ${EndIf}

  Pop $R2
  Pop $R1
!macroend

!define InstallVSCode '!insertmacro InstallVSCode '
!macro InstallVSCode

  Push $R0

  StrCpy $R0 ""
  ${If} ${IsNativeAMD64}
    StrCpy $R0 "$R0-x64"
  ${EndIf}
  ${IfNot} ${ShellVarContextAll}
    StrCpy $R0 "$R0-user"
  ${EndIf}

  DetailPrint "Downloading ${VSCODE_DOWNLOAD_URL}$R0"
  nsExec::ExecToLog `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '${VSCODE_DOWNLOAD_URL}$R0' -OutFile '${VSCODE_DOWNLOAD_PATH}'"`
  Pop $R0

  DetailPrint "Installing Visual Studio Code..."
  ExecWait `"${VSCODE_DOWNLOAD_PATH}" /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /MERGETASKS=!runcode` $R0

  Delete /REBOOTOK "${VSCODE_DOWNLOAD_PATH}"

  Pop $R0

!macroend

!define VSCodeCmd '!insertmacro VSCodeCmd '
!macro VSCodeCmd args

  ${If} $VSCodeCmdPath == ""
    ${FindVSCode}
  ${EndIf}

  ${If} $VSCodeCmdPath != ""
    nsExec::ExecToLog `"$VSCodeCmdPath" ${args}`
  ${Else}
    Push "notfound"
  ${EndIf}

!macroend
