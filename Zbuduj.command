#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then echo "Wymagany macOS."; exit 1; fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo 'Wymagane Command Line Tools. Zainstaluj je poleceniem xcode-select --install, potem ponów.'
  exit 1
fi
OUT="$PWD/build/Safari Icon Fixer.app"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp Info.plist "$OUT/Contents/Info.plist"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library -O -target "$(uname -m)-apple-macos13.0" FavoritesIndex.swift SafariIconFixer.swift -o "$OUT/Contents/MacOS/SafariIconFixer"
codesign --force --sign - "$OUT"
echo "Zbudowano: $OUT"
open -R "$OUT"
