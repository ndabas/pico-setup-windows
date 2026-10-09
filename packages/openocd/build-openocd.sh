#!/bin/bash

set -euo pipefail

BUILDDIR="$PWD"
INSTALLDIR="openocd-install"
BINDIR="/${MSYSTEM,,}/bin"
# Install scripts next to openocd.exe so they are found relative to the executable
PKGDATADIR="$BINDIR"

. "$BUILDDIR/../packages/common/num-jobs.sh"

cd openocd
./bootstrap
./configure --disable-werror --enable-internal-jimtcl --bindir="$BINDIR" #CFLAGS="-Duint=uint32_t"
make pkgdatadir="$PKGDATADIR"

DESTDIR="$BUILDDIR/$INSTALLDIR" make install-strip pkgdatadir="$PKGDATADIR"

cd "$BUILDDIR/$INSTALLDIR/$BINDIR"
find . -maxdepth 1 ! -name . ! -name .. ! -name openocd.exe ! -name scripts -exec rm -r {} +
"$BUILDDIR/../packages/common/copy-deps.sh"
