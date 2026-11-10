#!/usr/bin/env bash
# Fetches pinned VLCKit (macOS, LGPL-2.1) into app/apple/Vendor (gitignored). Used for MKV and
# other containers AVFoundation can't open (ADR-0008). Dynamic framework: keeps LGPL relinkable.
set -euo pipefail
VER=VLCKit-3.7.3-319ed2c0-79128878
SHA=019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d
DEST="$(dirname "$0")/../app/apple/Vendor"
[[ -d "$DEST/VLCKit.xcframework" ]] && { echo "VLCKit.xcframework present"; exit 0; }
tmp=$(mktemp -d)
curl -sSfL -o "$tmp/v.tar.xz" "https://download.videolan.org/pub/cocoapods/prod/$VER.tar.xz"
echo "$SHA  $tmp/v.tar.xz" | shasum -a 256 -c -
tar -xJf "$tmp/v.tar.xz" -C "$tmp"
mkdir -p "$DEST" && mv "$tmp/VLCKit - binary package/VLCKit.xcframework" "$DEST/"
cp "$tmp/VLCKit - binary package/COPYING.txt" "$DEST/VLCKit-COPYING.txt"
rm -rf "$tmp"; echo "Installed $DEST/VLCKit.xcframework ($VER)"
