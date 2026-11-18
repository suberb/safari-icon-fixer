#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then echo "macOS is required."; exit 1; fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo 'Command Line Tools are required. Run xcode-select --install, then retry.'
  exit 1
fi
bash Packaging/FetchSparkle.sh
SPARKLE="$PWD/build/vendor/sparkle-2.10.1"
OUT="$PWD/build/Safari Icon Fixer.app"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Frameworks"
if [[ -e "$OUT/Contents/Frameworks/Sparkle.framework" ]]; then rm -rf "$OUT/Contents/Frameworks/Sparkle.framework"; fi
ditto "$SPARKLE/Sparkle.framework" "$OUT/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$OUT/Contents/Resources/Sparkle-LICENSE.txt"
cp Info.plist "$OUT/Contents/Info.plist"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
cp Resources/Translations.json "$OUT/Contents/Resources/Translations.json"
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library -O -target "$(uname -m)-apple-macos13.0" Localization.swift FavoritesIndex.swift PermissionCheck.swift IconSearchModel.swift IconPixels.swift IconArtwork.swift GoogleImageBrowser.swift IconSearch.swift ReleaseModel.swift AppUpdates.swift Personalization.swift IconCollection.swift BackupInventory.swift BackupManagerView.swift DemoModel.swift DemoArtwork.swift CacheRecovery.swift CacheModels.swift IconImageSupport.swift SafariCache.swift SafariIconFixer.swift -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$OUT/Contents/MacOS/SafariIconFixer"
codesign --verify --deep --strict "$OUT/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$OUT"
codesign --verify --deep --strict "$OUT"
otool -L "$OUT/Contents/MacOS/SafariIconFixer" | grep -F '@rpath/Sparkle.framework/'
echo "Built: $OUT"
if [[ "${CI:-}" != true && "${SIF_NO_FINDER:-}" != 1 ]]; then open -R "$OUT"; fi
