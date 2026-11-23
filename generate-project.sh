#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

cd "${SCRIPT_DIR}"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required to regenerate the project. Install it with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate

echo "Generated ${SCRIPT_DIR}/CodexThemeBar.xcodeproj"
