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
# Hazard3 traps on misaligned access; without this newlib compiles out its alignment checks
export CFLAGS_FOR_TARGET_EXTRA="-mstrict-align"

cd riscv-gnu-toolchain

# Backport binutils afa6db16e65: on Windows st_ino is always 0, so binutils 2.47's SAME_INODE treats
# every file on a drive as identical and ld fails with "linker script file ... appears multiple times"
git submodule update --init --depth 1 binutils
sed -i 's/(!((a)\.st_ino == 0 && (a)\.st_dev == 0) \\/((a).st_ino != 0 \\/' binutils/include/same-inode.h
grep -q '(a).st_ino != 0' binutils/include/same-inode.h

./configure \
  --prefix="$BUILDDIR/$INSTALLDIR" \
  --enable-strip \
  --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp \
  --with-abi=ilp32 \
  --with-multilib-generator="rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--"
make

newlib_headers=$(find "$BUILDDIR/$INSTALLDIR" -path '*/include/*' -name newlib.h)
if [ -z "$newlib_headers" ]; then
  echo "No newlib.h found under $INSTALLDIR" >&2
  exit 1
fi
if grep -l "define _HAVE_HW_MISALIGNED_ACCESS" $newlib_headers; then
  echo "newlib was built assuming misaligned access is supported, which is unsafe on Hazard3" >&2
  exit 1
fi

cd "$BUILDDIR/$INSTALLDIR"
"$BUILDDIR/../packages/common/copy-deps.sh"
