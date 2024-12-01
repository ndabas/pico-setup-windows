#!/bin/bash

# From pico-sdk-tools
# https://github.com/raspberrypi/pico-sdk-tools/blob/63a716bf0c50a37883a740e1526fde65af083493/packages/windows/riscv/build-riscv-gcc.sh

set -euo pipefail

INSTALLDIR="riscv-gnu-toolchain-install/${MSYSTEM,,}"
mkdir -p "$INSTALLDIR"

BUILDDIR="$(pwd)"

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb --with-abi=ilp32 --with-multilib-generator="rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--"
make -j$(nproc)
