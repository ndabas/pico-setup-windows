set interactive=%~1

call "%~dp0pico-env.cmd" || exit /b 1
setlocal enabledelayedexpansion

rem This is mostly a port of pico-setup
rem https://github.com/raspberrypi/pico-setup/blob/master/pico_setup.sh

set "GITHUB_PREFIX=https://github.com/raspberrypi/"
set "GITHUB_SUFFIX=.git"
set "SDK_BRANCH=master"

pushd "%PICO_REPOS_PATH%"

for %%i in (sdk examples extras playground project-generator) do (
  set "DEST=%PICO_REPOS_PATH%\pico-%%i"

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
mkdir "%PICO_REPOS_PATH%\pico-examples\build"
pushd "%PICO_REPOS_PATH%\pico-examples\build"
cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Debug --fresh || exit /b 1

for %%i in (blink "hello_world/all") do (
  echo Building %%i
  ninja "%%i" || exit /b 1
)

popd

if "%interactive%" equ "1" (
  rem Open repo folder in Explorer
  start .

  rem Keep the terminal window open
  pause
)

popd
