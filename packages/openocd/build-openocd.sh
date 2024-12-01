#!/bin/bash

set -euo pipefail

BUILDDIR="$PWD"
INSTALLDIR="openocd-install"

cd openocd
./bootstrap
./configure --disable-werror CFLAGS="-Duint=uint32_t"
make -j$(nproc)

DESTDIR="$BUILDDIR/$INSTALLDIR" make install

cd "$BUILDDIR/$INSTALLDIR/${MSYSTEM,,}/bin"
"$BUILDDIR/../packages/common/copy-deps.sh"
