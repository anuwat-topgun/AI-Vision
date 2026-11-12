# HANDOFF — continue AI Vision here

Written 2026-11-12 for a fresh Claude session or account. Read this first, then the docs it points to.
Last updated from branch `exp/typhoon-ab` (PR #12, open).

## 1. What this project is

Offline game/video subtitle translator: OCR English/Japanese subtitles from a video file or a live
capture card, translate to Thai with a local LLM, draw Thai over (or in place of) the original.

- Product spec (source of truth): `../Handoff/README.md` (v2.0) plus the other Handoff docs. Prompt spec:
  `docs/translation/PROMPT_P2_SPEC.md`.
- Architecture: shared Rust core `core/rust` (contracts, epoch, FSM, cache key, tracker, translation
  contract, prompts p1/p2/p3, game profiles), exposed through UniFFI (`core/ffi`). Native UI is
  SwiftUI for iPad and Mac (`app/apple`) and Kotlin/Compose for Android (`app/android`).
- Decisions: `docs/architecture/DECISION_LOG.md` (ADR-0005 … ADR-0011). Known issues:
  `docs/operations/KNOWN_ISSUES.md`. History: `docs/operations/CHANGELOG.md`.

## 2. Rules every PR follows (from the Handoff)

- Either update `docs/windows-handoff/WINDOWS_PORTABILITY_LEDGER.md`, or put
  `Windows impact: NONE — <reason>` (at least 15 characters) in the PR body. CI checks this.
- Architecture change → add an ADR. Always update CHANGELOG and KNOWN_ISSUES. Never claim hardware
  support without evidence (TEST_MATRIX, BENCHMARK_LOG).
- Commits end with `Co-Authored-By: Claude …`. PR bodies end with the Claude Code line.
- CI (`.github/workflows/ci.yml`) has 7 jobs: core ×3 OS (fmt + clippy -D warnings + tests), apple
  (macOS tests + iPadOS build), android assembleDebug, docs-and-schemas, windows-impact.
- Watch for CI's slower Swift type-checker: two big SwiftUI `body` chains (LiveCaptureView) timed out
  on CI but not locally. Keep view bodies split into small pieces.
- Kotlin bindings: never name a UniFFI error field `message` (it clashes with Throwable).

## 3. How the owner likes to work

- Talk to them in Thai. They are hands-on and test on their own Mac with a capture card.
- **"run on macOS" / "run ให้" / "build and run" → build and launch the app yourself.** Don't hand
  them commands. Confirm the window is up with a screenshot, and say which branch or commit you built.
- "Merge when green" → wait for all 7 checks, merge (merge commit), checkout main, pull.
- Ask before downloading anything (give file name, source and size).

## 4. Build and run (macOS)

```bash
cd app/apple
xcodegen generate
xcodebuild -scheme AIVision -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
pkill -x AIVision; open build/Build/Products/Debug/AIVision.app            # add: --args -live YES
```

- Use `open`: launching the binary directly after a pkill came up with no window.
- If the FFI or vendor frameworks are missing, run `scripts/build_apple_core.sh`,
  `scripts/fetch_llama_xcframework.sh` and `scripts/fetch_vlckit.sh` first. Cargo is at
  `/opt/homebrew/opt/rustup/bin`.
- After any Rust or FFI change, run `scripts/build_apple_core.sh` to regenerate the Swift bindings
  and the xcframework.
- Tests: `xcodebuild test …` with the same flags.
  - Model-backed tests run only when `~/Models` has the model.
  - Skip them for speed with `-skip-testing:AIVisionTests/TranslationModelP2Tests -skip-testing:AIVisionTests/TranslationModelP3Tests`.
  - Model comparison: `TEST_RUNNER_AIVISION_COMPARE=1 … -only-testing:AIVisionTests/ModelCompareTests`.
- Debug launch args: `-file <path>`, `-model <gguf>` (file mode only), `-live YES`, `-debugOverlay YES`,
  `-liveReplaceMode YES`.

## 5. Local assets (not in git)

- `~/Models/`:
  - `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` (tested baseline; used for Japanese)
  - `typhoon-translate1.5-4b-q4_k_m.gguf` (sha256 11ab2464…287177; used for English)
  - `typhoon2.5-qwen3-4b-q4_k_m.gguf` (sha256 b3653029…3e511; compared only)
- On macOS, when both are present, the app routes English to Typhoon Translate and Japanese to Qwen
  (`LanguageRouter`). Off switch: UserDefaults `routeByLanguage` = NO.
- Game profiles:
  - bundled in `profiles/*.json` (FF7 Remake/Rebirth, Granblue Fantasy: Relink)
  - the user's own in `~/Library/Application Support/AIVision/Profiles/`
- Vendored, gitignored, fetched by scripts: llama.cpp xcframework b11811, VLCKit 3.7.3 (LGPL).

## 6. What works today (macOS)

- **Inputs**
  - File playback: MP4 via AVFoundation, MKV via VLC.
  - Live UVC capture: OBSBOT webcam; a capture card (VID 21325 / PID 8457, 1080p 25 fps).
- **OCR and zones**
  - OCR with Apple Vision.
  - Multiple subtitle zones. Each zone can be Translate or Speaker name.
  - Small off-center UI text (corner buttons, name tags) is filtered out.
- **Translation**
  - Prompt p3 (default) with a game profile (glossary, style, character voices) and speaker hints.
  - KV-prefix reuse; P50 about 200–230 ms on an M4 Max.
- **Display**
  - Overlay or Mask & Replace.
  - Thai text sized to match the original, plus an Aa size menu.
  - Thai held 0.8 s so it doesn't blink.

## 7. State right now

- **PR #12 (open, branch `exp/typhoon-ab`):**
  - Typhoon Translate prompt adapter
  - three-model comparison (results in `docs/translation/PROMPT_EVALUATION.md`)
  - EN/JA model routing, ADR-0011 (PROPOSED)
  - CI not yet confirmed green; the owner had not yet said "merge".
- **Last live test:** the capture card showed its own color-bar "no signal" screen. The app was fine;
  the console wasn't sending HDMI. Suggested checks: console awake, HDMI IN port, PS5 HDCP off,
  reseat the cable.

## 8. Open work / next steps (owner's priority order as discussed)

1. Merge PR #12 once green, then confirm routing live (the model button should read
   "EN Typhoon Translate · JA Qwen").
2. Glossary fixes found in the comparison:
   - FF7: add "Spiky" → "ไอ้หัวเม่น".
   - Typhoon Translate ignores `thai_name`, so add character names (e.g. Lyria → ลีเรีย) to the glossary,
     or make the adapter add the names automatically.
3. Human evaluation set: 100–200 real lines from play, scored per the Handoff §10.2 (KI-031).
4. Typhoon license review before any bundling (KI-033). Japanese coverage (KI-034).
5. Not yet done or tested:
   - multi-zone and speaker zone on real gameplay
   - unplug/replug (KI-027)
   - iPad device (E06)
   - Android OCR/translation (E08)
   - Cloud BYOK (E09)
   - ROI defaults per game profile (KI-032)

## 9. Claude memory carried by this file

- [feedback] "run on macOS" means build and launch it yourself (see §3). Reason: a `git checkout`
  command given to the owner earlier left the repo on an old branch, and they ran a stale build.
