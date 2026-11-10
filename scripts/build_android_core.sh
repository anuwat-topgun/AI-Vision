#!/usr/bin/env bash
# Builds libsubtitle_ffi.so for Android ABIs and generates Kotlin bindings.
set -euo pipefail
cd "$(dirname "$0")/../core"
APP=../app/android/app
cargo ndk -t arm64-v8a -t x86_64 --platform 31 -o "$APP/src/main/jniLibs" build -p subtitle_ffi --release
cargo build -p subtitle_ffi --release
lib=target/release/libsubtitle_ffi.dylib; [[ -f $lib ]] || lib=target/release/libsubtitle_ffi.so
rm -rf "$APP/build/generated/uniffi"
cargo run -q -p subtitle_ffi --features cli --bin uniffi-bindgen -- generate \
  --library "$lib" --language kotlin --out-dir "$APP/build/generated/uniffi"
echo "Built Android core libs + Kotlin bindings"
