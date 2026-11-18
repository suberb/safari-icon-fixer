#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]]
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
APP="$PWD/build/Safari Icon Fixer.app"
DMG="$PWD/dist/SafariIconFixer-$VERSION-macOS-arm64.dmg"
mkdir -p dist
[[ ! -e "$DMG" ]] || { echo "Remove the previous local DMG before rebuilding."; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"
TEMP=$(mktemp -d)
MOUNT="$TEMP/mount"
mkdir "$MOUNT"
mounted=0
cleanup() { if [[ "$mounted" == 1 ]]; then hdiutil detach "$MOUNT" || true; fi; rm -rf "$TEMP"; }
trap cleanup EXIT
python3 -m venv "$TEMP/venv"
"$TEMP/venv/bin/pip" install --disable-pip-version-check 'dmgbuild==1.6.7'
"$TEMP/venv/bin/dmgbuild" -s Packaging/dmg-settings.py -D "app=$APP" -D "background=$PWD/Packaging/InstallerBackground.png" 'Safari Icon Fixer' "$DMG"
hdiutil verify "$DMG"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
mounted=1
test -f "$MOUNT/.DS_Store"
test -L "$MOUNT/Applications"
test "$(readlink "$MOUNT/Applications")" = /Applications
codesign --verify --deep --strict --verbose=2 "$MOUNT/Safari Icon Fixer.app"
hdiutil detach "$MOUNT"
mounted=0
printf 'Verified DMG: %s\n' "$DMG"
