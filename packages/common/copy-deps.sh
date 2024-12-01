#!/bin/bash

set -euo pipefail

find . -name '*.exe' -exec ldd {} ';' | (grep -Po "(?<==> )/${MSYSTEM,,}[^ ]+" || true) | sort -u | xargs -I{} cp -v {} .
