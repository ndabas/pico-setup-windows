!define MUI_FINISHPAGE_NOREBOOTSUPPORT
!define MUI_PAGE_CUSTOMFUNCTION_SHOW OnFinishPageShow
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE OnFinishPageLeave

Var FinishPage.CloneCheckbox
Var FinishPage.ReposDirTextBox
Var FinishPage.BrowseButton

Function OnFinishPageShow

  ${NSD_CreateCheckbox} 120u 110u 195u 10u "Clone and build examples in this folder:"
  Pop $FinishPage.CloneCheckbox
  SetCtlColors $FinishPage.CloneCheckbox "${MUI_TEXTCOLOR}" "${MUI_BGCOLOR}"
  ${NSD_SetState} $FinishPage.CloneCheckbox ${BST_CHECKED}
  ${NSD_OnClick} $FinishPage.CloneCheckbox OnCloneCheckboxChange

  ${NSD_CreateText} 120u 130u 125u 12u "$ReposDir"
  Pop $FinishPage.ReposDirTextBox
  SetCtlColors $FinishPage.ReposDirTextBox "${MUI_TEXTCOLOR}" "${MUI_BGCOLOR}"

  ${NSD_CreateButton} 255u 128u 60u 15u "Browse..."
  Pop $FinishPage.BrowseButton
  ${NSD_OnClick} $FinishPage.BrowseButton OnBrowseButtonClick

FunctionEnd

Function OnCloneCheckboxChange

  Pop $R0
  ${NSD_GetState} $R0 $R1
  ${If} $R1 == ${BST_CHECKED}
    StrCpy $R2 1
  ${Else}
    StrCpy $R2 0
  ${EndIf}
  EnableWindow $FinishPage.ReposDirTextBox $R2
  EnableWindow $FinishPage.BrowseButton $R2

FunctionEnd

Function OnBrowseButtonClick

  Pop $R0
  ${NSD_GetText} $FinishPage.ReposDirTextBox $R1
  nsDialogs::SelectFolderDialog "Select example code folder" "$R1"
  Pop $R1
  ${If} "$R1" != "error"
      ${NSD_SetText} $FinishPage.ReposDirTextBox "$R1"
  ${EndIf}

FunctionEnd

Function OnFinishPageLeave

  ${NSD_GetState} $FinishPage.CloneCheckbox $R1
  ${If} $R1 == ${BST_CHECKED}
    ${NSD_GetText} $FinishPage.ReposDirTextBox $ReposDir
    Call ${FINISHPAGE_RUN_FUNCTION}
  ${EndIf}

FunctionEnd
