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
cp Resources/Translations.json "$OUT/Contents/Resources/Translations.json"
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library -O -target "$(uname -m)-apple-macos13.0" Localization.swift FavoritesIndex.swift PermissionCheck.swift IconSearchModel.swift IconPixels.swift IconArtwork.swift GoogleImageBrowser.swift IconSearch.swift ReleaseModel.swift AppUpdates.swift SafariIconFixer.swift -o "$OUT/Contents/MacOS/SafariIconFixer"
codesign --force --sign - "$OUT"
echo "Zbudowano: $OUT"
if [[ "${CI:-}" != true && "${SIF_NO_FINDER:-}" != 1 ]]; then open -R "$OUT"; fi
