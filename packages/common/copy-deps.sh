#!/bin/bash

set -euo pipefail

# Find all directories with exe files
find . -name '*.exe' -printf '%h\n' | sort -u | while read i
do
  echo "Copying DLLs to $i"
  pushd "$i" > /dev/null

  # We need to match just the DLL names, if they are from the MSYS2 libraries.
  # (?<=...) is a positive lookbehind assertion, because we are looking for something like
  # "libusb-1.0.dll => /mingw64/.../libusb-1.0.dll"
  find . -maxdepth 1 -name '*.exe' -exec ldd {} ';' | (grep -Po "(?<==> )/${MSYSTEM,,}[^ ]+" || true) | sort -u | xargs -I{} cp -v {} .

  popd > /dev/null
done
