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
    if "%~3" equ "warning" (
      echo WARNING: %1 was not found.
    ) else (
      echo ERROR: %1 is required but was not found.
      set /a errors += 1
    )
  )

  goto :EOF

:RemoveTrailingBackslash
  rem Remove trailing backslash - add \. then resolve with the 'f' modifier
  rem %1 is the name of the variable
  rem The echo command outputs the value of the variable
  for /f "usebackq delims=" %%f in (`echo %%%1%%\.`) do (
    set "%1=%%~ff"
  )

  goto :EOF

:FindPath
  for %%f in (%1) do (
    set "%2=%%~dp$PATH:f"
  )

  call :RemoveTrailingBackslash %2

  goto :EOF

:main

set "PICO_INSTALL_PATH=%~dp0"
call :RemoveTrailingBackslash PICO_INSTALL_PATH

set "PICO_SDK_PATH=%PICO_INSTALL_PATH%\pico-sdk"

for %%i in (examples extras playground) do (
  rem Environment variables in Windows aren't case-sensitive, so we don't need
  rem to bother with uppercasing the env var name.
  if exist "%PICO_INSTALL_PATH%\pico-%%i" (
    echo PICO_%%i_PATH=%PICO_INSTALL_PATH%\pico-%%i
    set "PICO_%%i_PATH=%PICO_INSTALL_PATH%\pico-%%i"
  )
)

rem Set the CMake generator explicitly
set CMAKE_GENERATOR=Ninja

rem GDB warns about being unable to determine a path for the index cache
rem directory if we do not set this.
set "HOME=%USERPROFILE%"

call :AddToPath "%PICO_INSTALL_PATH%\cmake\bin"
call :AddToPath "%PICO_INSTALL_PATH%\arm-gnu-toolchain\bin"
call :AddToPath "%PICO_INSTALL_PATH%\riscv-gnu-toolchain\bin"
call :AddToPath "%PICO_INSTALL_PATH%\ninja"
call :AddToPath "%PICO_INSTALL_PATH%\python"
call :AddToPath "%PICO_INSTALL_PATH%\git\cmd"
call :AddToPath "%PICO_INSTALL_PATH%\openocd\bin"
call :AddToPath "%PICO_INSTALL_PATH%\pico-sdk-tools"
call :AddToPath "%PICO_INSTALL_PATH%\pico-sdk-tools\elf2uf2"
call :AddToPath "%PICO_INSTALL_PATH%\pico-sdk-tools\pioasm"
call :AddToPath "%PICO_INSTALL_PATH%\pico-sdk-tools\picotool"

call :FindPath arm-none-eabi-gcc.exe PICO_ARM_TOOLCHAIN_PATH
call :FindPath riscv32-unknown-elf-gcc.exe PICO_RISCV_TOOLCHAIN_PATH

call :VerifyExe "Arm GNU Toolchain" "arm-none-eabi-gcc --version"
call :VerifyExe "RISC-V GNU Toolchain" "riscv32-unknown-elf-gcc --version" warning
call :VerifyExe "CMake" "cmake --version"
call :VerifyExe "Ninja" "ninja --version"
call :VerifyExe "Python 3" "python --version"
call :VerifyExe "Git" "git --version"
call :VerifyExe "OpenOCD" "openocd --version" warning

rem We need Visual Studio Build Tools to compile pioasm and elf2uf2, but only
rem if we do not have pre-compiled versions available.
if not exist "%PICO_INSTALL_PATH%\pico-sdk-tools" (
  call :AddToPath "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer"
  call :AddToPath "%ProgramFiles%\Microsoft Visual Studio\Installer"

  rem https://github.com/microsoft/vswhere/wiki/Start-Developer-Command-Prompt

  for /f "usebackq delims=" %%i in (`vswhere.exe -products * -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" -latest -property installationPath`) do (
    if exist "%%i\Common7\Tools\vsdevcmd.bat" (
      call "%%i\Common7\Tools\vsdevcmd.bat"
    )
  )

  call :VerifyExe "Visual Studio" "cl"
)

exit /b %errors%
