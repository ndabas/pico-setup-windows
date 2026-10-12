#!/bin/bash

set -euo pipefail

BUILDDIR="$PWD"
INSTALLDIR="openocd-install"
BINDIR="/${MSYSTEM,,}/bin"
# Install scripts next to openocd.exe so they are found relative to the executable
PKGDATADIR="$BINDIR"

. "$BUILDDIR/../packages/common/num-jobs.sh"

cd openocd

# Add the tag/branch we built from and the project that built it to the banner.
# Start from the pristine file so that rebuilding without a fresh clone does not repeat the edit.
OPENOCD_REF="$(git describe --all 2>/dev/null || git rev-parse --short HEAD)"
git checkout -- src/openocd.c
sed -i -e "s|VERSION RELSTR|VERSION RELSTR \"-${OPENOCD_REF#*/} [$PICO_SETUP_PROJECT]\"|" src/openocd.c

./bootstrap
./configure --disable-werror --enable-internal-jimtcl --bindir="$BINDIR" #CFLAGS="-Duint=uint32_t"
make pkgdatadir="$PKGDATADIR"

DESTDIR="$BUILDDIR/$INSTALLDIR" make install-strip pkgdatadir="$PKGDATADIR"

cd "$BUILDDIR/$INSTALLDIR/$BINDIR"
find . -maxdepth 1 ! -name . ! -name .. ! -name openocd.exe ! -name scripts -exec rm -r {} +
"$BUILDDIR/../packages/common/copy-deps.sh"
