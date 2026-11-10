#!/usr/bin/env bash
# Builds SubtitleFFI.xcframework (macOS arm64, iPadOS arm64, iOS-simulator arm64)
# and Swift bindings into app/apple/Generated. Re-run after changing core/ffi.
set -euo pipefail
cd "$(dirname "$0")/../core"
OUT=../app/apple/Generated
TARGETS=(aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim)
for t in "${TARGETS[@]}"; do cargo build -p subtitle_ffi --release --target "$t"; done
rm -rf "$OUT" && mkdir -p "$OUT/headers"
cargo run -q -p subtitle_ffi --features cli --bin uniffi-bindgen -- generate \
  --library target/aarch64-apple-darwin/release/libsubtitle_ffi.dylib \
  --language swift --out-dir "$OUT/swift-tmp"
mv "$OUT/swift-tmp/"*.h "$OUT/headers/"
mv "$OUT/swift-tmp/subtitle_ffiFFI.modulemap" "$OUT/headers/module.modulemap"
mv "$OUT/swift-tmp/"*.swift "$OUT/"
rm -rf "$OUT/swift-tmp"
args=()
for t in "${TARGETS[@]}"; do args+=(-library "target/$t/release/libsubtitle_ffi.a" -headers "$OUT/headers"); done
xcodebuild -create-xcframework "${args[@]}" -output "$OUT/SubtitleFFI.xcframework" >/dev/null
echo "Built $OUT/SubtitleFFI.xcframework"
