# Android tablet app — Kotlin + Jetpack Compose

Rust core linked via UniFFI + JNA (ADR-0006). Requires Android SDK 36, NDK, `cargo install cargo-ndk`.

```bash
scripts/build_android_core.sh        # builds .so into app/src/main/jniLibs + Kotlin bindings
cd app/android && ./gradlew assembleDebug
```

Planned adapters (README §5.3): Camera2 external camera / audited USB Host UVC (D-002), Media3 files, Keystore SecretStore.
