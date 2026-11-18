#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Safari Icon Fixer.app"
[[ -d "$APP" ]] || { echo 'Run bash Build.command first.'; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
EXPECTED=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
[[ "$VERSION" == "$EXPECTED" ]] || { echo 'Build the current version before launching the demo.'; exit 1; }
open -na "$APP" --args --demo
