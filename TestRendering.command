#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then echo "Wymagany macOS."; exit 1; fi
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
xcrun --sdk macosx swiftc -swift-version 5 Localization.swift IconPixels.swift IconArtwork.swift DemoArtwork.swift Tests/macOS/main.swift -o "$TEMP/test-render"
"$TEMP/test-render"
