#!/usr/bin/env bash
# Fetches the pinned llama.cpp XCFramework (MIT) into app/apple/Vendor (gitignored).
set -euo pipefail
TAG=b11811
SHA=f0dde979e8964d3b54a117efb238f97fe51a3fdb7f2ccaf6d3e6a51ccd0705c3
DEST="$(dirname "$0")/../app/apple/Vendor"
[[ -d "$DEST/llama.xcframework" ]] && { echo "llama.xcframework present"; exit 0; }
tmp=$(mktemp -d)
curl -sSfL -o "$tmp/llama.zip" "https://github.com/ggml-org/llama.cpp/releases/download/$TAG/llama-$TAG-xcframework.zip"
echo "$SHA  $tmp/llama.zip" | shasum -a 256 -c -
mkdir -p "$DEST" && unzip -q "$tmp/llama.zip" -d "$tmp/x"
mv "$(find "$tmp/x" -maxdepth 3 -name llama.xcframework -type d | head -1)" "$DEST/"
rm -rf "$tmp"; echo "Installed $DEST/llama.xcframework ($TAG)"
