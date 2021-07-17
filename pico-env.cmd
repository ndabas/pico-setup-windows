@if not defined _echo echo off

set errors=0
goto main

:AddToPath

  if exist "%~1" (
    set "PATH=%~1;%PATH%"
  )

  goto :EOF

:VerifyExe

  echo Checking %1...
  cmd /c %2 >NUL 2>NUL
  if %ERRORLEVEL% neq 0 (
    echo ERROR: %1 is required but was not found.
    set /a errors += 1
  )

  goto :EOF

:main

for %%i in (sdk examples extras playground) do (
  rem Environment variables in Windows aren't case-sensitive, so we don't need
  rem to bother with uppercasing the env var name.
  if exist "%~dp0pico-%%i" (
    echo PICO_%%i_PATH=%~dp0pico-%%i
    set "PICO_%%i_PATH=%~dp0pico-%%i"
  )
)

if exist "%~dp0tools\openocd-picoprobe" (
  echo OPENOCD_SCRIPTS=%~dp0tools\openocd-picoprobe\scripts
  set "OPENOCD_SCRIPTS=%~dp0tools\openocd-picoprobe\scripts"
  set "PATH=%~dp0tools\openocd-picoprobe;%PATH%"
)

call :AddToPath "%ProgramFiles(x86)%\doxygen\bin"
call :AddToPath "%ProgramFiles%\doxygen\bin"
call :AddToPath "%ProgramW6432%\doxygen\bin"

call :AddToPath "%ProgramFiles(x86)%\Graphviz\bin"
call :AddToPath "%ProgramFiles%\Graphviz\bin"
call :AddToPath "%ProgramW6432%\Graphviz\bin"

call :AddToPath "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer"
call :AddToPath "%ProgramFiles%\Microsoft Visual Studio\Installer"

rem https://github.com/microsoft/vswhere/wiki/Start-Developer-Command-Prompt

for /f "usebackq delims=" %%i in (`vswhere.exe -products * -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" -latest -property installationPath`) do (
  if exist "%%i\Common7\Tools\vsdevcmd.bat" (
    call "%%i\Common7\Tools\vsdevcmd.bat"
  )
)

call :VerifyExe "GNU Arm Embedded Toolchain" "arm-none-eabi-gcc --version"
call :VerifyExe "CMake" "cmake --version"
call :VerifyExe "Visual Studio" "cl"
call :VerifyExe "Python 3" "python --version"
call :VerifyExe "Git" "git --version"

exit /b %errors%
