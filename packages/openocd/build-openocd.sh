#!/bin/bash

set -euo pipefail

cd openocd
./bootstrap
./configure --disable-werror CFLAGS="-Duint=uint32_t"
make clean
make -j$(nproc)
DESTDIR="$PWD/../openocd-install" make install
cp "/${MSYSTEM,,}/bin/libhidapi-0.dll" "$PWD/../openocd-install/${MSYSTEM,,}/bin"
cp "/${MSYSTEM,,}/bin/libusb-1.0.dll" "$PWD/../openocd-install/${MSYSTEM,,}/bin"
