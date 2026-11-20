#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
bash scripts/build-local.sh

built_app="$PWD/.build/local/Build/Products/Debug/Codex ThemeWurx.app"
installed_app="/Applications/Codex ThemeWurx.app"

test -f "$built_app/Contents/Resources/default.metallib"
codesign --verify --deep --strict "$built_app"
command -v trash >/dev/null

if pgrep -x "Codex ThemeWurx" >/dev/null; then
    pkill -TERM -x "Codex ThemeWurx"
    for attempt in {1..50}; do
        if ! pgrep -x "Codex ThemeWurx" >/dev/null; then
            break
        fi
        sleep 0.1
    done
    if pgrep -x "Codex ThemeWurx" >/dev/null; then
        echo "Codex ThemeWurx did not exit; installation stopped." >&2
        exit 1
    fi
fi

if [ -e "$installed_app" ]; then
    trash "$installed_app"
fi
ditto "$built_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
open "$installed_app"

for attempt in {1..50}; do
    if pgrep -x "Codex ThemeWurx" >/dev/null; then
        echo "Installed and running: $installed_app"
        exit 0
    fi
    sleep 0.1
done
echo "App installed, but launch could not be confirmed." >&2
exit 1
