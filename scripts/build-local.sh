#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcrun metal --version >/dev/null 2>&1; then
    shopt -s nullglob
    bundles=(.build/toolchains/MetalToolchain-*.exportedBundle)
    if ((${#bundles[@]})); then
        xcodebuild -importComponent MetalToolchain -importPath "${bundles[${#bundles[@]}-1]}"
    else
        xcodebuild -downloadComponent MetalToolchain -exportPath .build/toolchains
    fi
fi

xcodebuild -project CodexThemeBar.xcodeproj -scheme CodexThemeBar \
    -configuration Debug -derivedDataPath .build/local build "$@"
