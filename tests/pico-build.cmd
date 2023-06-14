@if not defined _echo echo off

call "%PICO_INSTALL_PATH%\pico-env.cmd" || exit /b 1

pushd "%PICO_REPOS_PATH%"
if not exist "FreeRTOS-Kernel\.git" (
  git clone --depth=1 -b main "https://github.com/FreeRTOS/FreeRTOS-Kernel.git" || exit /b 1
)
popd

rem Only for non-standalone installs
where pip3 && pip3 install pycryptodome

subst P: "%PICO_REPOS_PATH%" || exit /b 1

pushd "P:\pico-examples\build"
cmake -G Ninja .. -DPICO_BOARD=pico_w -DWIFI_SSID=ssid -DWIFI_PASSWORD=pass "-DFREERTOS_KERNEL_PATH=P:\FreeRTOS-Kernel" -DTEST_TCP_SERVER_IP=10.10.10.10 -DCMAKE_BUILD_TYPE=Debug --fresh || exit /b 1
ninja --quiet || exit /b 1
popd

mkdir "P:\pico-sdk-build"
pushd "P:\pico-sdk-build"
cmake "%PICO_SDK_PATH%" -G Ninja -DPICO_SDK_TESTS_ENABLED=1 -DCMAKE_BUILD_TYPE=Debug -DPICO_BOARD=pico_w --fresh || exit /b 1
ninja --quiet || exit /b 1
popd

subst P: /d
