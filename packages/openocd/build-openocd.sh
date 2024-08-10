#!/bin/bash

set -euo pipefail

BITNESS=$1
ARCH=$2

cd openocd
./bootstrap
./configure --disable-werror CFLAGS="-Duint=uint32_t"
make clean
make -j4
DESTDIR="$PWD/../openocd-install" make install
cp "/mingw$BITNESS/bin/libhidapi-0.dll" "$PWD/../openocd-install/mingw$BITNESS/bin"
cp "/mingw$BITNESS/bin/libusb-1.0.dll" "$PWD/../openocd-install/mingw$BITNESS/bin"
