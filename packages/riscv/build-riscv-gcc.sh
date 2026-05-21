#!/bin/bash

# From pico-sdk-tools
# https://github.com/raspberrypi/pico-sdk-tools/blob/63a716bf0c50a37883a740e1526fde65af083493/packages/windows/riscv/build-riscv-gcc.sh

set -euo pipefail

BUILDDIR="$PWD"
INSTALLDIR="riscv-gnu-toolchain-install/${MSYSTEM,,}"
mkdir -p "$INSTALLDIR"

. "$BUILDDIR/../packages/common/num-jobs.sh"

# Currently this results in:
# - GCC is fully static
# - binutils has static libstdc++ and libgcc but needs a few other DLLs
# - GDB is not static at all
export LDFLAGS="-static -static-libgcc -static-libstdc++"
export CXXFLAGS="-fno-char8_t"

cd riscv-gnu-toolchain
./configure \
  --prefix="$BUILDDIR/$INSTALLDIR" \
  --enable-strip \
  --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp \
  --with-abi=ilp32 \
  --with-multilib-generator="rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--"
make

cd "$BUILDDIR/$INSTALLDIR"
"$BUILDDIR/../packages/common/copy-deps.sh"
