#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Safari Icon Fixer.app"
[[ -d "$APP" ]] || { echo 'Najpierw uruchom bash Zbuduj.command.'; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$VERSION" == '0.7.0' ]] || { echo 'Zbuduj wersję 0.7.0 przed uruchomieniem demo.'; exit 1; }
open -na "$APP" --args --demo
