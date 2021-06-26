set interactive=%~1

call "%~dp0pico-env.cmd" || exit /b 1
setlocal enabledelayedexpansion

rem This is mostly a port of pico-setup
rem https://github.com/raspberrypi/pico-setup/blob/master/pico_setup.sh

set "GITHUB_PREFIX=https://github.com/raspberrypi/"
set "GITHUB_SUFFIX=.git"
set "SDK_BRANCH=master"

pushd "%~dp0"

for %%i in (sdk examples extras playground project-generator) do (
  set "DEST=%~dp0pico-%%i"

  if exist "!DEST!\.git" (
    echo !DEST! exists, skipping clone
  ) else (
    set "REPO_URL=%GITHUB_PREFIX%pico-%%i%GITHUB_SUFFIX%"
    echo Cloning !REPO_URL!
    git clone -b %SDK_BRANCH% !REPO_URL! || exit /b 1

    rem Any submodules
    pushd "!DEST!"
    git submodule update --init || exit /b 1
    popd

    set "PICO_%%i_PATH=!DEST!"
  )
)

rem Build a couple of examples
mkdir "%~dp0pico-examples\build"
pushd "%~dp0pico-examples\build"
cmake -G "NMake Makefiles" .. -DCMAKE_BUILD_TYPE=Debug || exit /b 1

for %%i in (blink hello_world) do (
  echo Building %%i
  pushd %%i
  nmake || exit /b 1
  popd
)

popd

rem Build picoprobe and picotool
rem Not building picotool currently because we need to auto-install and
rem configure libusb
for %%i in (picoprobe) do (
  set "DEST=%~dp0%%i"

  if exist "!DEST!" (
    echo !DEST! exists, skipping clone
  ) else (
    set "REPO_URL=%GITHUB_PREFIX%%%i%GITHUB_SUFFIX%"
    echo Cloning !REPO_URL!
    git clone -b %SDK_BRANCH% !REPO_URL! || exit /b 1
  )

  echo Building %%i
  mkdir %%i\build
  pushd %%i\build

  cmake -G "NMake Makefiles" .. || exit /b 1
  nmake || exit /b 1

  popd
)

if exist "%~dp0pico-docs.ps1" (
  echo Downloading Pico documents and files...
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0pico-docs.ps1" || exit /b 1
)

if "%interactive%" equ "1" (
  rem Open repo folder in Explorer
  start .

  rem Keep the terminal window open
  pause
)

popd
