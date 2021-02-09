@if not defined _echo echo off

set ProgRoot=%ProgramFiles%
if not "%ProgramFiles(x86)%" == "" set ProgRoot=%ProgramFiles(x86)%
set "PATH=%ProgRoot%\Microsoft Visual Studio\Installer;%PATH%"

for %%i in (sdk examples extras playground) do (
  rem Environment variables in Windows aren't case-sensitive, so we don't need
  rem to bother with uppercasing the env var name.
  if exist "%~dp0pico-%%i" (
    echo PICO_%%i_PATH=%~dp0pico-%%i
    set "PICO_%%i_PATH=%~dp0pico-%%i"
  )
)

if exist "%~dp0openocd-picoprobe" (
  echo OPENOCD_SCRIPTS=%~dp0openocd-picoprobe\scripts
  set "OPENOCD_SCRIPTS=%~dp0openocd-picoprobe\scripts"
  set "PATH=%~dp0openocd-picoprobe;%PATH%"
)

rem https://github.com/microsoft/vswhere/wiki/Start-Developer-Command-Prompt

for /f "usebackq delims=" %%i in (`vswhere.exe -products * -requires "Microsoft.VisualStudio.Component.VC.CoreIde" -latest -property installationPath`) do (
  if exist "%%i\Common7\Tools\vsdevcmd.bat" (
    call "%%i\Common7\Tools\vsdevcmd.bat"
  )
)
