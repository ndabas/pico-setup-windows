@if not defined _echo echo off

goto main

:test-build

  mkdir "%BUILD_DIR%"
  pushd "%BUILD_DIR%"
  cmake "%SRC_DIR%" -G Ninja -DCMAKE_BUILD_TYPE=Debug --fresh %* || exit /b 1
  ninja --quiet || exit /b 1
  popd
  goto :EOF

:main

call "%PICO_INSTALL_PATH%\pico-env.cmd" || exit /b 1

set "PICO_REPOS_PATH=%PICO_INSTALL_PATH%"
pushd "%PICO_REPOS_PATH%"
if not exist "FreeRTOS-Kernel\.git" (
  git clone --depth=1 -b main "https://github.com/FreeRTOS/FreeRTOS-Kernel.git" || exit /b 1
)
popd

set "SRC_DIR=%PICO_REPOS_PATH%\pico-examples"

set "BUILD_DIR=%PICO_REPOS_PATH%\pico-examples\build-pico"
call :test-build -DPICO_BOARD=pico || exit /b 1

set "BUILD_DIR=%PICO_REPOS_PATH%\pico-examples\build-pico2"
call :test-build -DPICO_BOARD=pico2 || exit /b 1

set "BUILD_DIR=%PICO_REPOS_PATH%\pico-examples\build-pico2-riscv"
call :test-build -DPICO_BOARD=pico2 -DPICO_PLATFORM=rp2350-riscv "-DPICO_RISCV_TOOLCHAIN_PATH=%PICO_RISCV_TOOLCHAIN_PATH%" "-DPICO_ARM_TOOLCHAIN_PATH=%PICO_ARM_TOOLCHAIN_PATH%" || exit /b 1

set "BUILD_DIR=%PICO_REPOS_PATH%\pico-examples\build-pico_w"
call :test-build -DPICO_BOARD=pico_w -DWIFI_SSID=ssid -DWIFI_PASSWORD=pass "-DFREERTOS_KERNEL_PATH=%PICO_REPOS_PATH%\FreeRTOS-Kernel" -DTEST_TCP_SERVER_IP=10.10.10.10 || exit /b 1

set "SRC_DIR=%PICO_SDK_PATH%"
set "BUILD_DIR=%PICO_REPOS_PATH%\pico-sdk-build"
call :test-build -DPICO_SDK_TESTS_ENABLED=1 -DPICO_BOARD=pico_w || exit /b 1
