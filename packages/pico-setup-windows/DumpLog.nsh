; Based on https://nsis.sourceforge.io/Dump_log_to_file
; This should be included after the MUI2 defines.

!include "WinMessages.nsh"

!define /ifndef LOG_PATH "$INSTDIR\install.log"

Function DumpLog
  System::Store "S"

  FileOpen $5 ${LOG_PATH} "w"
  ${If} $5 != ""
    SendMessage $mui.InstFilesPage.Log ${LVM_GETITEMCOUNT} 0 0 $6
    System::Call "*(&t${NSIS_MAX_STRLEN})p.r3"
    System::Call "*(i, i, i, i, i, p, i, i, i) p  (0, 0, 0, 0, 0, r3, ${NSIS_MAX_STRLEN}) .r1"

    StrCpy $2 0
    ${While} $2 < $6
      System::Call "User32::SendMessage(p, i, p, p) p ($mui.InstFilesPage.Log, ${LVM_GETITEMTEXT}, $2, r1)"
      System::Call "*$3(&t${NSIS_MAX_STRLEN} .r4)"
      FileWriteUTF16LE $5 "$4$\r$\n"
      IntOp $2 $2 + 1
    ${EndWhile}

    FileClose $5
    System::Free $1
    System::Free $3
  ${EndIf}

  System::Store "L"
FunctionEnd
