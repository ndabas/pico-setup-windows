!ifndef AUMI_NSH
!define AUMI_NSH

!include "LogicLib.nsh"
!include "Win\COM.nsh"
!include "Win\Propkey.nsh"
!include "WinVer.nsh"

# Set the Application User Model ID for a shortcut
# This is needed for shortcuts from multiple installed versions to show up in the Start Menu.
# https://learn.microsoft.com/en-us/windows/win32/shell/appids

!define SetShortcutAUMI '!insertmacro SetShortcutAUMI '
!macro SetShortcutAUMI _ShortcutPath _AUMI
System::Store "S"

# Based on the sample code from Include\Win\COM.nsh

# $0: IShellLink
# $1: IPropertyStore
# $2: SYSSTRUCT_PROPERTYKEY
# $3: SYSSTRUCT_PROPVARIANT
# $4: VT_BSTR
# $5: IPersistFile

!insertmacro ComHlpr_CreateInProcInstance ${CLSID_ShellLink} ${IID_IShellLink} r0 ""
${If} $0 P<> 0
  ${IUnknown::QueryInterface} $0 '("${IID_IPersistFile}", .r5)'
  ${If} $5 P<> 0
    ${IPersistFile::Load} $5 '("${_ShortcutPath}", ${STGM_READWRITE})'
    ${IUnknown::QueryInterface} $0 '("${IID_IPropertyStore}", .r1)'
    ${If} $1 P<> 0
      # Only supported on Windows 7 and later, per:
      # https://github.com/jrsoftware/issrc/blob/844775f56cab742d2a61791859b62e72b63cffb7/Projects/InstFnc2.pas#L243
      ${If} ${AtLeastWin7}
        System::Call 'Oleaut32::SysAllocString(w "${_AUMI}") i.r4'

        System::Call '*${SYSSTRUCT_PROPERTYKEY}(${PKEY_AppUserModel_ID}) p.r2'
        System::Call '*${SYSSTRUCT_PROPVARIANT}(${VT_BSTR},, &i4 $4) p.r3'
        ${IPropertyStore::SetValue} $1 '($2, $3)'

        System::Call 'Oleaut32::SysFreeString(ir4)'
        System::Free $2
        System::Free $3
      ${EndIf}

      ${IPropertyStore::Commit} $1 ""
      ${IUnknown::Release} $1 ""

      ${IPersistFile::Save} $5 '("${_ShortcutPath}", 1)'
    ${EndIf}
    ${IUnknown::Release} $5 ""
  ${EndIf}
  ${IUnknown::Release} $0 ""
${EndIf}

System::Store "L"
!macroend

!define CreateShortcutEx '!insertmacro CreateShortcutEx '
!macro CreateShortcutEx _ShortcutPath _AUMI _args

CreateShortcut `${_ShortcutPath}` ${_args}
${SetShortcutAUMI} `${_ShortcutPath}` `${_AUMI}`

!macroend

!endif
