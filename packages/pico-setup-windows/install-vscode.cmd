@if not defined _echo echo off

rem We don't want to fail and stop the installer if the Visual Studio Code installation fails.
rem So we use a cmd script instead of a PowerShell one, just in case executing PowerShell fails.

setlocal
set "vscode_exts=(Get-Content '%~dp0extensions.json' | ConvertFrom-Json).recommendations"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%1' -BuildEdition Stable-User -AdditionalExtensions %vscode_exts%"

exit /b 0
