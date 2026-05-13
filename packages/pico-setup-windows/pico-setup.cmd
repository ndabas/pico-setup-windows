@if not defined _echo echo off

set interactive=1
if /I [%1] equ [-noninteractive] set interactive=0

call "%~dp0pico-env.cmd" || exit /b 1
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
for %%j in (pico pico2) do (
  mkdir "%PICO_REPOS_PATH%\pico-examples\build-%%j"
  pushd "%PICO_REPOS_PATH%\pico-examples\build-%%j"
  cmake -G Ninja .. -DPICO_BOARD=%%j -DCMAKE_BUILD_TYPE=Debug --fresh || exit /b 1

  for %%i in (blink "hello_world/all") do (
    echo Building %%i for %%j
    ninja "%%i" || exit /b 1
  )

  popd
)

if "%interactive%" equ "1" (
  rem Keep the terminal window open
  pause
)

popd
