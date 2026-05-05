!ifndef WINDOWSTERMINAL_NSH
!define WINDOWSTERMINAL_NSH

!include "LogicLib.nsh"
!include "WordFunc.nsh"

# Write Windows terminal profile JSON files.

!define WINTERMDIR "$LOCALAPPDATA\Microsoft\Windows Terminal\Fragments"

!define WINTERM_FRAGMENT_BEGIN '!insertmacro WINTERM_FRAGMENT_BEGIN '
!macro WINTERM_FRAGMENT_BEGIN _FragmentFileName
  System::Store "S"

  FileOpen $0 `${_FragmentFileName}` w
  FileWrite $0 `{$\r$\n`
  FileWrite $0 `  "profiles": [$\r$\n`
!macroend

!define WINTERM_PROFILE '!insertmacro WINTERM_PROFILE '
!macro WINTERM_PROFILE _ProfileName _CommandLine _StartingDirectory _Icon
  ${WordReplace} `${_CommandLine}` "\" "\\" "+" $1
  ${WordReplace} $1 '"' '\"' "+" $1

  ${WordReplace} `${_StartingDirectory}` "\" "\\" "+" $2

  ${WordReplace} `${_Icon}` "\" "\\" "+" $3

  !ifndef WINTERM_FIRST_PROFILE
  !define WINTERM_FIRST_PROFILE
  !else
    FileWrite $0 `,$\r$\n`
  !endif

  FileWrite $0 `    {$\r$\n`
  FileWrite $0 `      "name": "${_ProfileName}",$\r$\n`
  FileWrite $0 `      "commandline": "$1",$\r$\n`
  FileWrite $0 `      "startingDirectory": "$2"$\r$\n`
  ${If} $3 != ""
    FileWrite $0 `      "icon": "$3"$\r$\n`
  ${EndIf}
  FileWrite $0 `    }`
!macroend

!define WINTERM_FRAGMENT_END '!insertmacro WINTERM_FRAGMENT_END'
!macro WINTERM_FRAGMENT_END
  FileWrite $0 `$\r$\n`
  FileWrite $0 `  ]$\r$\n`
  FileWrite $0 `}$\r$\n`
  FileClose $0
  System::Store "L"
  !undef WINTERM_FIRST_PROFILE
!macroend

!endif
