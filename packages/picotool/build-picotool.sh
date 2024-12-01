#!/bin/bash

set -euo pipefail

BUILDDIR="$PWD"
INSTALLDIR="pico-sdk-tools/${MSYSTEM,,}"

export PICO_SDK_PATH="$PWD/pico-sdk"
export LDFLAGS="-static -static-libgcc -static-libstdc++"

build-tool () {
    SRCDIR="$1"
    TOOLDIR="$INSTALLDIR/$(basename "$SRCDIR")"
    shift 1
    pushd "$SRCDIR"
    mkdir -p build
    cd build
    cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release "$@"
    cmake --build .
    popd
    mkdir -p "$TOOLDIR"
    cmake --install "$SRCDIR/build" --prefix "$INSTALLDIR" || cp "$SRCDIR/build/*.exe" "$TOOLDIR"
}

[ -d pico-sdk/tools/elf2uf2 ] && build-tool pico-sdk/tools/elf2uf2 -Wno-dev
build-tool pico-sdk/tools/pioasm -DPIOASM_FLAT_INSTALL=1 -Wno-dev
cp ../packages/pico-sdk-tools/pico-sdk-tools-config.cmake "$INSTALLDIR"

build-tool picotool -DPICOTOOL_FLAT_INSTALL=1
cd "$INSTALLDIR/picotool"
"$BUILDDIR/../packages/common/copy-deps.sh"
