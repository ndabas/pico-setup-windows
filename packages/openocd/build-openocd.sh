#!/bin/bash

set -euo pipefail

BUILDDIR="$PWD"
INSTALLDIR="openocd-install"

. "$BUILDDIR/../packages/common/num-jobs.sh"

cd openocd
./bootstrap
./configure --disable-werror --enable-internal-jimtcl #CFLAGS="-Duint=uint32_t"
make

DESTDIR="$BUILDDIR/$INSTALLDIR" make install-strip

cd "$BUILDDIR/$INSTALLDIR/${MSYSTEM,,}/bin"
"$BUILDDIR/../packages/common/copy-deps.sh"
