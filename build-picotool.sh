#!/bin/bash

set -euo pipefail

BITNESS=$1
ARCH=$2

export PICO_SDK_PATH="$PWD/pico-sdk"
export LIBUSB_ROOT="/mingw$BITNESS"
export LDFLAGS="-static -static-libgcc -static-libstdc++"

cd pico-sdk/tools/elf2uf2
mkdir -p build
cd build
cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release -Wno-dev
cmake --build .

cd ../../pioasm
mkdir -p build
cd build
cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release -Wno-dev
cmake --build .

cd ../../../..
INSTALLDIR="pico-sdk-tools/mingw$BITNESS"
mkdir -p $INSTALLDIR
cp pico-sdk/tools/elf2uf2/build/elf2uf2.exe $INSTALLDIR
cp pico-sdk/tools/pioasm/build/pioasm.exe $INSTALLDIR
cp ../packages/pico-sdk-tools/pico-sdk-tools-config.cmake $INSTALLDIR

cd picotool
mkdir -p build
cd build
cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release
cmake --build .

cd ../..
INSTALLDIR="picotool-install/mingw$BITNESS"
mkdir -p $INSTALLDIR
cp picotool/build/picotool.exe $INSTALLDIR
cp "/mingw$BITNESS/bin/libusb-1.0.dll" $INSTALLDIR
