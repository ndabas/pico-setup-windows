#!/bin/bash
set -euo pipefail

TAG=v$(cat version.txt)
echo "Release tag: ${TAG}"

if DRAFT=$(gh release view "${TAG}" --json isDraft --jq '.isDraft' 2>/dev/null); then
    if [ "${DRAFT}" = "true" ]; then
        echo "Draft release ${TAG} already exists; uploading artifacts to it."
    else
        echo "Error: release ${TAG} already exists and is not a draft." >&2
        exit 1
    fi
else
    echo "Creating draft release ${TAG}..."
    gh release create "${TAG}" \
        --draft \
        --title "${TAG}" \
        --notes ""
fi

ARTIFACTS=( bin/* )
if [ ! -e "${ARTIFACTS[0]}" ]; then
    echo "Error: no artifacts found in bin/." >&2
    exit 1
fi

echo "Updating notes for ${TAG}..."
unzip -q bin/pico-setup-windows-*.zip VERSIONS.txt -d build/
gh release edit "${TAG}" --notes-file build/VERSIONS.txt

echo "Uploading ${#ARTIFACTS[@]} artifact(s)..."
gh release upload "${TAG}" "${ARTIFACTS[@]}" --clobber
