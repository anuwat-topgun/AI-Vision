# Apple app (iPadOS + macOS) — SwiftUI

One multiplatform target (iPad-only on iOS, macOS 14+). Rust core is linked through UniFFI (ADR-0006).

```bash
scripts/build_apple_core.sh          # builds Generated/SubtitleFFI.xcframework + Swift bindings
cd app/apple && xcodegen generate    # creates AIVision.xcodeproj (not committed)
xcodebuild -scheme AIVision -destination 'platform=macOS' test
```

Planned adapters (README §5.3): AVFoundation external UVC, AVPlayer files, Metal compositor, Keychain SecretStore.
