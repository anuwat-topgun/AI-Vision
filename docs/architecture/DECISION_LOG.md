# Architecture Decision Record index

Do not delete or rewrite adopted decisions silently. For each material change add a new ADR superseding prior one and update Windows Portability Ledger in same PR.

## ADR-0001 — Stage platforms iPadOS/macOS/Android before Windows
- Date: 2026-11-10
- Status: PROPOSED
- Context: Tablet capture and on-device translation require substantial hardware qualification. Windows is desired later, not within initial shipping releases.
- Decision: Build and release iPadOS, macOS, Android tablet first; keep adapters/serialized contracts platform-agnostic and maintain Windows ledger.
- Alternatives: all-four-platform launch; Apple-only launch.
- Consequences: avoids Windows execution workload initially; adds documentation and build-contract maintenance.
- Review gate: R0, architecture owner.

## ADR-0002 — Offline-first AI and opt-in cloud BYOK
- Date: 2026-11-10
- Status: PROPOSED
- Context: Avoid paying recurring cloud tokens centrally; support private/offline use after model installation.
- Decision: local OCR+local MT/LLM by default; cloud disabled unless user explicitly opts in, using secure key storage and approved provider auth path.
- Alternatives: cloud-first; server-mediated paid subscription.
- Consequences: device-specific inference benchmarking, model licensing/download complexity; optional BYOK provider policy review.
- Windows portability: shared TranslationProvider interface and native secret store adapter.

## ADR-0003 — Permanent File Input Mode
- Date: 2026-11-10
- Status: ACCEPTED PRODUCT REQUIREMENT
- Decision: File Input is a permanent top-level input mode on every target, with play/pause/seek, 1080p video where supported, offline translation and native file permissions.
- Consequences: video player timing and decoder tests are production criteria; not developer-only tooling.
- Windows portability: Media Foundation file adapter can implement identical contract.

## ADR-0004 — Flutter UI + Rust shared core + native platform media adapters
- Date: 2026-11-10
- Status: SUPERSEDED by ADR-0006 (was: PROPOSED; FEASIBILITY GATE R0)
- Decision: Cross-platform Flutter app shell and pure portable Rust session/translation state; use Swift/Kotlin/native implementations for media/accelerator/secure key and output.
- Alternatives: fully native Swift+Kotlin; pure Flutter plugins; Tauri desktop plus native tablet apps.
- Validation: benchmark native texture zero-copy properties, FFI calls, memory ownership, file and UVC render throughput across devices.
- Windows portability: Direct3D/Media Foundation platform adapters, no Rust core rewrite.

## ADR-0005 — Monorepo skeleton and minimal core dependency set
- Date: 2026-11-10
- Status: PROPOSED
- Context: README §22.2 Day-1 requires skeleton contracts + Flutter shell + stubbed adapters before R0.
- Decision: Adopt README §18.1 layout. `core/rust` crate `subtitle_core` depends only on serde, serde_json, sha2; epoch-tagged results and the §6.4 FSM live in core. Flutter shell is source-only until runners are generated.
- Alternatives: generate full Flutter runners now (needs Flutter SDK; deferred); add tokio/async runtime in core (deferred until FFI decision D-003).
- Consequences: async/texture plumbing is still open; FSM is pure and deterministic for golden tests.
- Windows impact: WIN-CHANGE-20261110-001; core tested on windows-latest in CI.
- Related FR/AC: FR-007, FR-010, AC-004, AC-010, AC-018, AC-021, AC-022.

## ADR-0006 — Native UI per platform + Rust core via UniFFI
- Date: 2026-11-10
- Status: ACCEPTED (product owner decision); performance validation at R0
- Supersedes: ADR-0004 (Flutter UI). ADR-0005 skeleton otherwise unchanged.
- Context: Product owner asked for native apps. Video, GPU and capture are native anyway; a Flutter layer adds a texture bridge (KI-008, D-003) between the video surface and the UI.
- Decision: SwiftUI single multiplatform target for iPadOS + macOS (`app/apple`); Kotlin + Jetpack Compose for Android (`app/android`); Windows later in WinUI/C#. Shared logic stays in Rust `core/rust`; `core/ffi` exposes it via UniFFI (Swift + Kotlin now, C# bindings at R5).
- Alternatives: Flutter UI (ADR-0004); fully native without Rust (core logic duplicated in Swift/Kotlin/C#, rejected: drift risk, conflicts with §19.1).
- Benefits: direct Metal/SurfaceView video, no Dart bridge, first-class platform accessibility and store review. Drawbacks: 2 UI codebases now (3 at R5); screen behavior must be kept in sync via §11 inventory and shared tests in core.
- Privacy/security/license: uniffi (MPL-2.0, build/runtime glue) and JNA (Apache-2.0/LGPL dual) added — record in SBOM.
- Platform implications: iPadOS 17+/macOS 14+ (SwiftUI), Android minSdk 31 (Android 12).
- Windows impact (ledger record): WIN-CHANGE-20261110-002.
- Migration/rollback: Flutter shell had no features; removed. Revert this ADR + restore `app/flutter_ui` from git history if needed.
- Validation evidence: macOS XCTest 2/2 via FFI; iPadOS generic build OK; Android APK assembles with arm64-v8a + x86_64 `libsubtitle_ffi.so`; not run on a device yet.
- Related FR/AC: FR-010, NFR-004, NFR-008, AC-004, AC-021.

## ADR-0007 — Dev-candidate OCR and local translation runtime on Apple
- Date: 2026-11-10
- Status: PROPOSED (candidate for R0 scorecard; does not close D-001)
- Context: Product owner wants an end-to-end macOS test (file video with EN/JA subtitles → offline Thai) before the full model bake-off.
- Decision: OCR = Apple Vision `VNRecognizeTextRequest` (accurate, ja-JP+en-US, bottom-band ROI) on iPadOS/macOS. Translation = llama.cpp (XCFramework b11811, MIT, Metal offload) running a user-imported GGUF; first tested model Qwen3-4B-Instruct-2507 Q4_K_M (Apache-2.0). Stability/vanish logic and CER live in Rust core (`tracker.rs`) and are shared.
- Alternatives: Apple Translation framework (simpler, no model files; rejected by product owner in favour of LLM); larger Qwen2.5-7B; MT encoder-decoder models (still to benchmark in SPK-02).
- Consequences: model weights not shipped in app/repo; users import a GGUF (FR-017 subset). Greedy decoding for deterministic tests. 4B Q4 needs ~3 GB RAM — tablet tiers need smaller models.
- Privacy/security/license: fully offline; prompt treats OCR text as data with delimiter sanitizing (§7.4). llama.cpp MIT, model Apache-2.0 — add to SBOM.
- Windows impact: WIN-CHANGE-20261110-005.
- Validation evidence: macOS M4 Max: OCR CER 0.000 on 6/6 fixture lines; translation 213–435 ms/line; injection test passes; live app screenshots show Thai overlay on both fixtures.
- Related FR/AC: FR-004, FR-005, FR-006, FR-007, FR-016; AC-005, AC-006, AC-007/008 (partial, macOS only), AC-010, AC-011.

## ADR-0008 — VLC backend for MKV and other containers (macOS)
- Date: 2026-11-10
- Status: ACCEPTED (product owner: "support MKV and MP4; use VLC if needed")
- Context: AVFoundation cannot open Matroska (MKV) at all. Users have MKV files.
- Decision: `PlaybackEngine` abstraction. MP4/MOV → AVFoundation (hardware path, unchanged). MKV/WebM/AVI/TS/… → VLC (VLCKit 3.7.3 macOS, libvlc C API). VLC is also the fallback when AVFoundation rejects a file (but never for DRM-protected files). libvlc decodes into our IOSurface BGRA CVPixelBuffers (vmem callbacks); the same buffer goes to an AVSampleBufferDisplayLayer and to OCR. Audio is played by VLC.
- Alternatives: VLC for everything (rejected: loses AVFoundation path for MP4); remux MKV→MP4 with an own demuxer (limited codecs); FFmpeg libs (no maintained Apple binary; licensing similar).
- Consequences: +~90 MB framework on macOS; vmem path costs a CPU colour-convert per frame (fine on Apple Silicon at 1080p60, to be measured on older Macs). VLC clock read via polling.
- Privacy/security/license: VLCKit/libvlc **LGPL-2.1**: dynamically linked embedded framework (relinkable), license text shipped in app resources; source offer/attribution must be added to Help/Legal before release (KI-021). App Store distribution of LGPL needs legal review (D-005).
- Platform implications: macOS only now. iPadOS needs MobileVLCKit (~264 MB) — not added (KI-020). Android: Media3 MKV extractor already supports Matroska (verify).
- Windows impact: WIN-CHANGE-20261110-006.
- Validation evidence: XCTest 14/14 incl. MKV open/seek/size, OCR on VLC frames paused (CER 0) and during playback (all 3 lines, no wrong reads), MP4 still on AVFoundation; live app screenshot of JA MKV with Thai overlay.
- Related FR/AC: FR-001, FR-002; AC-002, AC-033.

## ADR-0009 — Translation prompt p2 and shared translation contract in core
- Date: 2026-11-10
- Status: ACCEPTED for dev; quality gate (spec §10.2 human review) pending
- Context: `docs/translation/PROMPT_P2_SPEC.md` (product handoff).
- Decision: Canonical prompts live in `core/prompts/*.txt` and are served by Rust (`translation.rs`) together with input sanitizer (NFC, `<>` strip, 500 graphemes), app-built user turn, typed output parser (`Translated`/`Unreadable`/`Invalid`), session history (≤3, deduped) and versioned cache identity. Platforms only run inference. Default `p2`; rollback via `promptVersion` = `p1`.
- Deviation from spec §4.1: the current user turn adds one line restating the task, because the spec format alone let p2 obey an injected command (TR-P2-007). Documented in PROMPT_EVALUATION.md.
- Performance: KV prefix reuse in `LlamaTranslator` (keep shared tokens, decode only the tail) — p2 P50 231 ms / P95 297 ms on M4 Max vs ~600–850 ms without.
- Stability fixes found while testing p2: prompt > n_batch aborted the process (now chunked prefill + context guard); ggml aborted on app quit while Metal residency sets were alive (now model freed on willTerminate, quit-during-load guarded, residency sets disabled).
- Windows impact: WIN-CHANGE-20261110-007.
- Related FR/AC: FR-005, FR-007; AC-007/008 (macOS), AC-010, AC-011.

## ADR-0010 — Prompt p3: game profiles and speaker-aware translation
- Date: 2026-11-11
- Status: ACCEPTED for dev; human evaluation (spec §10.2) pending
- Context: players found p2 output literal and flat for games — the model had no setting, no glossary and no idea who was speaking (wrong ครับ/ค่ะ, transliterated terms).
- Decision: `core/prompts/p3.txt` = p2 + rules for a GAME PROFILE block and a `Speaker:` line (sha256 `a93e8a3e393743218b4436f38ddb6a6d59a54f0e0ef918fbdc994da6da80fa8c`). Profiles are JSON (`profiles/*.json`, user overrides in Application Support) parsed and rendered by Rust `profile.rs` (fields sanitized and capped, reference data only) and appended to the system prompt so KV prefix reuse still covers it. A Live zone can be marked "Speaker name": it is OCR'd but never translated; its text is matched against profile characters (name/aliases/Thai name) and sent with that character's voice note. Cache identity now uses `game_profile_id` = profile id, `glossary_version` = profile content hash, plus a new optional `speaker` component (absent = pre-p3 keys unchanged). Default prompt becomes `p3`; rollback `promptVersion` = `p2`.
- Context size: n_ctx 2048 → 4096 for the profile.
- Evidence: A/B on 9 game lines with Qwen3-4B Q4 — glossary applied (ชินระ/มาโค/แกรนด์ไซเฟอร์, SOLDIER kept), gender particles fixed (Tifa/Lyria), see PROMPT_EVALUATION.md. Remaining: small-model meaning errors ("behind me" → "ข้างๆ").
- Windows impact: WIN-CHANGE-20261111-001.
- Related FR/AC: FR-005, FR-007.

## ADR-0011 — Model-specific prompt adapters; Typhoon Translate 1.5 as the recommended EN→TH model
- Date: 2026-11-11
- Status: PROPOSED (developer A/B only; D-001 model choice still needs the §10.2 human evaluation and legal review)
- Context: KI-031 — Qwen3-4B output stays literal even with p3.
- Decision: `LlamaTranslator` selects a prompt adapter from the model: Typhoon Translate (`*typhoon-translate*`) gets its documented single-user-turn format with the same p3 information as numbered rules (prompt id `tt1.5+p3rules`, kept in the cache key); every other model uses canonical p3 chat. FFI exposes profile setting/style/glossary for adapters. Users pick the model with the existing model picker; auto-load still prefers the tested Qwen file unless a model was chosen before.
- Evidence: PROMPT_EVALUATION.md model comparison — Typhoon Translate most natural, P50 205 ms vs 234 ms (Qwen) on 15 lines.
- Risks: Typhoon Translate model card metadata says Apache-2.0 but the text says Gemma License, plus OpenTyphoon terms (KI-033) — do not bundle or redistribute until legal review. Japanese not officially supported (KI-034).
- Windows impact: WIN-CHANGE-20261111-002.

## New ADR template

```markdown
# ADR-NNNN — Decision title
Date: YYYY-MM-DD
Status: PROPOSED | ACCEPTED | SUPERSEDED
Owners:
Context:
Decision:
Alternatives considered:
Benefits and drawbacks:
Privacy/security/license considerations:
Platform-specific implications:
Windows impact (ledger record):
Migration/rollback:
Validation evidence:
Related FR/AC:
```
