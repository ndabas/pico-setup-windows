@if not defined _echo echo off

set interactive=1
set werror=0

:ParseArgs
if "%~1" equ "" goto ParsedArgs
if /I "%~1" equ "-noninteractive" set interactive=0
if /I "%~1" equ "-werror" set werror=1
shift /1
goto ParseArgs
:ParsedArgs

set "PICO_ENV_ARGS="
if "%werror%" equ "1" set "PICO_ENV_ARGS=-werror"
call "%~dp0pico-env.cmd" %PICO_ENV_ARGS% || exit /b 1
setlocal enabledelayedexpansion

rem This is mostly a port of pico-setup
rem https://github.com/raspberrypi/pico-setup/blob/master/pico_setup.sh

set "GITHUB_PREFIX=https://github.com/raspberrypi/"
set "GITHUB_SUFFIX=.git"
set "SDK_BRANCH=sdk-%PICO_SDK_VERSION%"

pushd "%~dp0"
set "PICO_REPOS_PATH=%CD%"

for %%i in (examples extras playground) do (
  set "DEST=%PICO_REPOS_PATH%\pico-%%i"

  if exist "!DEST!\.git" (
    echo !DEST! exists, skipping clone
  ) else (
    set "REPO_URL=%GITHUB_PREFIX%pico-%%i%GITHUB_SUFFIX%"
    echo Cloning !REPO_URL!
    git clone -b %SDK_BRANCH% -c advice.detachedHead=false !REPO_URL! || exit /b 1

    rem Any submodules
    pushd "!DEST!"
    git submodule update --init || exit /b 1
    popd

    set "PICO_%%i_PATH=!DEST!"
  )
)

rem Build a couple of examples
set "BUILD_NAME=pico"
call :Build -DPICO_BOARD=pico || exit /b 1

set "BUILD_NAME=pico2"
call :Build -DPICO_BOARD=pico2 || exit /b 1

if defined PICO_RISCV_TOOLCHAIN_PATH (
  set "BUILD_NAME=pico2-riscv"
  call :Build -DPICO_BOARD=pico2 -DPICO_PLATFORM=rp2350-riscv "-DPICO_RISCV_TOOLCHAIN_PATH=%PICO_RISCV_TOOLCHAIN_PATH%" "-DPICO_ARM_TOOLCHAIN_PATH=%PICO_ARM_TOOLCHAIN_PATH%" || exit /b 1
) else (
  echo RISC-V GNU Toolchain not found, skipping RISC-V build
)

if "%interactive%" equ "1" (
  rem Keep the terminal window open
  pause
)

popd
exit /b 0

:Build

  mkdir "%PICO_REPOS_PATH%\pico-examples\build-%BUILD_NAME%"
  pushd "%PICO_REPOS_PATH%\pico-examples\build-%BUILD_NAME%"
  cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Debug --fresh %* || exit /b 1

  for %%i in (blink "hello_world/all") do (
    echo Building %%~i for %BUILD_NAME%
    ninja "%%~i" || exit /b 1
  )

  popd
  goto :EOF
