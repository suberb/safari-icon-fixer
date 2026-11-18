#!/bin/bash
# Run only in the trusted release job. Do not enable shell tracing or print secrets.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SPARKLE_PRIVATE_KEY:?Missing GitHub Actions secret SPARKLE_PRIVATE_KEY}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
PUBKEY=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Info.plist)
DMG="$PWD/dist/SafariIconFixer-$VERSION-macOS-arm64.dmg"
[[ -f "$DMG" ]]
# Pin and check dependency digest, then sign the exact bytes that will be published.
bash Packaging/FetchSparkle.sh
SIGN="$PWD/build/vendor/sparkle-2.10.1/bin/sign_update"
SIGNATURE=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - -p "$DMG")
# Swift's independent Ed25519 verification rejects a mismatched GitHub secret.
xcrun swift Packaging/VerifyUpdate.swift "$DMG" "$PUBKEY" "$SIGNATURE"
python3 Packaging/MakeAppcast.py "$DMG" "$SIGNATURE" "$PWD/dist/appcast.xml"
# Sparkle embeds a signature in the feed itself; never modify the signed XML afterward.
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - "$PWD/dist/appcast.xml"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - --verify "$PWD/dist/appcast.xml"
unset SPARKLE_PRIVATE_KEY
(cd dist && shasum -a 256 *.dmg appcast.xml > SHA256SUMS.txt)
