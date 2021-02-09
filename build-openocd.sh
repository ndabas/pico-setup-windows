#!/bin/bash

set -euo pipefail

BITNESS=$1
ARCH=$2
OPENOCD_BRANCH="picoprobe"

if [ ! -d openocd ]; then
  git clone "https://github.com/raspberrypi/openocd.git" -b $OPENOCD_BRANCH --depth=1
else
  git -C openocd checkout -B $OPENOCD_BRANCH
  git -C openocd pull --ff-only
fi

cd openocd
./bootstrap
./configure --disable-doxygen-pdf --enable-ftdi --enable-picoprobe
make clean
make -j4
export DESTDIR="$PWD/../openocd-install"
make install
for dll in libgcc_s_dw2-1.dll libusb-1.0.dll libwinpthread-1.dll; do
  if [ -f /mingw$BITNESS/bin/$dll ]; then
    cp /mingw$BITNESS/bin/$dll $DESTDIR/mingw$BITNESS/bin
  fi
done
