$installers = Get-Content .\x64.json | ConvertFrom-Json
$installers | ForEach-Object {
  $_ | Add-Member -NotePropertyName 'shortName' -NotePropertyValue ($_.name -replace '[^a-zA-Z0-9]', '')

  Write-Host "Downloading $($_.name)"
  curl.exe --fail --silent --show-error --url "$($_.href)" --location --output "installers/$($_.file)" --create-dirs --remote-time --time-cond "installers/$($_.file)"
}

@"
!include "MUI2.nsh"

Name "Pico setup for Windows"
Caption "Pico setup for Windows"
OutFile "pico-setup-windows.exe"
Unicode True

InstallDir "`$DOCUMENTS\Pico"

;Get installation folder from registry if available
InstallDirRegKey HKCU "Software\pico-setup-windows" ""

!define MUI_ABORTWARNING

!define MUI_FINISHPAGE_RUN_TEXT "Clone and build Pico repos"
!define MUI_FINISHPAGE_RUN "cmd.exe"
!define MUI_FINISHPAGE_RUN_PARAMETERS "/k $\"`$INSTDIR\pico-setup.cmd$\""

!insertmacro MUI_PAGE_WELCOME
;!insertmacro MUI_PAGE_LICENSE "`${NSISDIR}\Docs\Modern UI\License.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

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

Section "Pico environment" SecPico

  SetOutPath "`$INSTDIR"
  File "pico-env.cmd"
  File "pico-setup.cmd"
  CreateShortcut "`$INSTDIR\Developer Command Prompt for Pico.lnk" "cmd.exe" '/k "`$INSTDIR\pico-env.cmd"'

SectionEnd

LangString DESC_SecPico `${LANG_ENGLISH} "Scripts for cloning the Pico SDK and tools repos, and for setting up your Pico development environment."

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT `${SecPico} `$(DESC_SecPico)
$($installers | ForEach-Object {
  "  !insertmacro MUI_DESCRIPTION_TEXT `${Sec$($_.shortName)} `$(DESC_Sec$($_.shortName))`n"
})
!insertmacro MUI_FUNCTION_DESCRIPTION_END
"@ | Set-Content .\pico-setup-windows-x64.nsi
