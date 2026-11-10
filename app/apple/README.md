# Apple app (iPadOS + macOS) — SwiftUI

One multiplatform target (iPad-only on iOS, macOS 14+). Rust core is linked through UniFFI (ADR-0006).

```bash
scripts/build_apple_core.sh          # builds Generated/SubtitleFFI.xcframework + Swift bindings
cd app/apple && xcodegen generate    # creates AIVision.xcodeproj (not committed)
xcodebuild -scheme AIVision -destination 'platform=macOS' test
```

## Test subtitle translation on macOS (EN/JA → Thai, offline)

1. One-time setup:
   ```bash
   scripts/build_apple_core.sh && scripts/fetch_llama_xcframework.sh && scripts/fetch_vlckit.sh
   cd app/apple && xcodegen generate && open AIVision.xcodeproj
   ```
2. Get a GGUF model (not in git). Tested: `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` (Apache-2.0, 2.5 GB,
   sha256 `3605803b…c4c67e597`) from huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF → `~/Models/`.
3. Run (⌘R) → **Video File** → pick a video (MP4/MOV via AVFoundation; **MKV**/WebM/AVI via VLC on macOS) with burned-in EN/JA subtitles → toolbar **cpu** button → pick the `.gguf`.
   The model is remembered. Toggle **Debug** to see the OCR region, detected box, timings and model.
   Source = Auto/English/日本語; **ไทย** turns translation on/off. Subtitles are read in the bottom ~36% of the frame.

Shortcut (Debug builds only):
```bash
build/Build/Products/Debug/AIVision.app/Contents/MacOS/AIVision -file /path/video.mp4 -model ~/Models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf -debugOverlay YES
```
Model tests run automatically when the model is at `~/Models/...` or `AIVISION_MODEL` is set; CI skips them.

Planned adapters (README §5.3): AVFoundation external UVC, AVPlayer files, Metal compositor, Keychain SecretStore.
