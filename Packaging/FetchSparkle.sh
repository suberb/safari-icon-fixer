#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.1
DIGEST=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
DEST="$PWD/build/vendor/sparkle-$VERSION"
mkdir -p "$PWD/build/vendor"
# Always validate the pinned upstream archive before using it. Only selected paths are extracted.
WORK=$(mktemp -d "$PWD/build/vendor/sparkle-fetch.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
ARCHIVE="$WORK/Sparkle.tar.xz"
if [[ -f "$HOME/Downloads/Sparkle-$VERSION.tar.xz" && "${CI:-}" != true ]]; then
  cp "$HOME/Downloads/Sparkle-$VERSION.tar.xz" "$ARCHIVE"
else
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --retry 3 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$DIGEST" "$ARCHIVE" | shasum -a 256 -c -
mkdir "$WORK/extracted"
tar -xf "$ARCHIVE" -C "$WORK/extracted" ./Sparkle.framework ./bin/sign_update ./LICENSE
[[ -f "$WORK/extracted/Sparkle.framework/Sparkle" && -x "$WORK/extracted/bin/sign_update" ]]
rm -rf "$DEST"
mv "$WORK/extracted" "$DEST"
