; The generated build\components.nsh calls these; it's included once per pass (install, description, uninstall).

!macro PICO_COMPONENTS PASS
  !define PICO_PASS ${PASS}
  !include "build\components.nsh"
  !undef PICO_PASS
!macroend

!macro PICO_GROUP_BEGIN NAME
  !if "${PICO_PASS}" == "install"
    SectionGroup /e "${NAME}"
  !endif
!macroend

!macro PICO_GROUP_END
  !if "${PICO_PASS}" == "install"
    SectionGroupEnd
  !endif
!macroend

; LEVEL: 1 = required, 2 = typical, 3 = full, 0 = hidden (always installed)
!macro PICO_COMPONENT_BEGIN NAME ID LEVEL
  !define _PICO_NAME "${NAME}"
  !if "${PICO_PASS}" == "install"
    !if ${LEVEL} = 0
      Section "-${NAME}" Sec${ID}
    !else
      Section "${NAME}" Sec${ID}
      !if ${LEVEL} = 1
        SectionInstType ${IT_MIN} RO ${IT_TYPICAL} ${IT_FULL}
      !else if ${LEVEL} = 2
        SectionInstType ${IT_TYPICAL} ${IT_FULL}
      !else
        SectionInstType ${IT_FULL}
      !endif
    !endif
  !else if "${PICO_PASS}" == "description"
    !if ${LEVEL} <> 0
      !insertmacro MUI_DESCRIPTION_TEXT ${Sec${ID}} "${NAME}"
    !endif
  !endif
!macroend

!macro PICO_COMPONENT_END
  !if "${PICO_PASS}" == "install"
    !ifdef _PICO_EXEC_OPEN
      ${ElseIf} $1 <> 0
        Abort "Installation of ${_PICO_NAME} failed"
      ${EndIf}
      !undef _PICO_EXEC_OPEN
    !endif
    SectionEnd
  !endif
  !undef _PICO_NAME
!macroend

; Extra file needed by an installer, e.g. an answer file
!macro PICO_PLUGIN_FILE SRC NAME
  !if "${PICO_PASS}" == "install"
    File "/oname=$PLUGINSDIR\${NAME}" "${SRC}"
  !endif
!macroend

!macro PICO_FILE SRC NAME
  !if "${PICO_PASS}" == "install"
    SetOutPath "$INSTDIR"
    File "${SRC}"
  !else if "${PICO_PASS}" == "uninstall"
    Delete "$INSTDIR\${NAME}"
  !endif
!macroend

!macro PICO_DIR SRC DEST
  !if "${PICO_PASS}" == "install"
    SetOutPath "$INSTDIR\${DEST}"
    File /r "${SRC}\*.*"
  !else if "${PICO_PASS}" == "uninstall"
    RMDir /r /REBOOTOK "$INSTDIR\${DEST}"
  !endif
!macroend

!macro _PICO_EXEC_PREPARE FILE
  ClearErrors
  SetOutPath "$TEMP"
  File "downloads\${FILE}"
  StrCpy $0 "$TEMP\${FILE}"
!macroend

; Leaves the result check open so PICO_REBOOT_ON can add cases; closed by PICO_COMPONENT_END
!macro _PICO_EXEC_CHECK
  DetailPrint "${_PICO_NAME} returned $1"
  Delete /REBOOTOK "$0"
  ${If} ${Errors}
    Abort "Installation of ${_PICO_NAME} failed"
  !define _PICO_EXEC_OPEN
!macroend

; In CMD, $0 is the path to the extracted FILE
!macro PICO_EXEC FILE CMD
  !if "${PICO_PASS}" == "install"
    !insertmacro _PICO_EXEC_PREPARE "${FILE}"
    ExecWait `${CMD}` $1
    !insertmacro _PICO_EXEC_CHECK
  !endif
!macroend

!macro PICO_EXEC_TO_LOG FILE CMD
  !if "${PICO_PASS}" == "install"
    !insertmacro _PICO_EXEC_PREPARE "${FILE}"
    nsExec::ExecToLog `${CMD}`
    Pop $1
    !insertmacro _PICO_EXEC_CHECK
  !endif
!macroend

!macro PICO_REBOOT_ON CODE
  !if "${PICO_PASS}" == "install"
    ${ElseIf} $1 = ${CODE}
      SetRebootFlag true
  !endif
!macroend
