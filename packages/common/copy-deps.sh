#!/bin/bash

set -euo pipefail

find . -name '*.exe' -exec ldd {} ';' | grep -Po "(?<==> )/${MSYSTEM,,}[^ ]+" | sort -u | xargs -I{} cp -v {} .
