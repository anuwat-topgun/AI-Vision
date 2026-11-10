# Benchmark and translation quality log

All numbers require measured evidence. Targets in README §14 are not performance claims until qualified.

## Record template

```markdown
### BENCH-YYYYMMDD-NNN
- Owner / commit / release:
- Device/OS/RAM/thermal state:
- Media source / codec / bitrate / fps:
- Capture path / format / screen output:
- OCR detector/recognizer + version:
- Local MT/LLM id, version, quantization, license:
- Translation prompt/glossary version:
- Fixture set IDs, language pair, sample N:
- Source detection recall / false positives per minute:
- OCR CER, JA script segmentation notes:
- Translation Thai reviewer rubric scores (accuracy, naturalness, names, character voice):
- OCR P50/P95 ms:
- Translation P50/P95 ms:
- First Thai display P50/P95 ms:
- Video optical delay P50/P95 ms:
- Frames drop, audio sync, peak RAM, thermal:
- Test artifacts (logs/JSONL/traces):
- Outcome / decision / Windows impact:
```

### BENCH-20261110-001
- Owner / commit / release: Claude Code dev run / feat/e03-e05-ocr-translate-overlay
- Device/OS/RAM/thermal state: MacBook Pro Apple M4 Max, macOS 26.7.1, plugged in, cool
- Media source / codec / bitrate / fps: synth_en_1080p60_001, synth_ja_1080p60_001 (H.264 High, 1080p60)
- Capture path / format / screen output: file, internal display
- OCR detector/recognizer + version: Apple Vision VNRecognizeTextRequest (accurate, ja-JP+en-US), ROI bottom 36%
- Local MT/LLM id, version, quantization, license: Qwen3-4B-Instruct-2507 Q4_K_M GGUF (Apache-2.0), llama.cpp b11811, Metal, greedy
- Translation prompt/glossary version: p1 / none
- Fixture set IDs, language pair, sample N: 2 fixtures, EN→TH 3, JA→TH 3 (N=6 — far below the §14.2 N≥200 rule; smoke only)
- Source detection recall / false positives per minute: 6/6 detected; 0 false positives at blank frames (2 checked)
- OCR CER, JA script segmentation notes: 0.000 on all 6 lines
- Translation Thai reviewer rubric scores: not reviewed by native Thai evaluator yet. Outputs: "เราควรจะถึงประตูก่อนเช้า", "จงตั้งไฟในระดับต่ำ ทหารอยู่ใกล้ๆ" (awkward), "ถ้าเราแยกกัน พบฉันที่บ่อน้ำเก่า", "ไปถึงประตูก่อนที่จะเช้า", "ลดแสงไฟลง ผู้เฝ้าระวังอยู่ใกล้ๆ", "ถ้าสูญเสียกันไป ให้พบกันที่บ่อน้ำเก่า" (meaning drift)
- OCR P50/P95 ms: ~60 ms per sample (debug overlay, N small)
- Translation P50/P95 ms: 330 / 435 ms (N=6, warm)
- First Thai display P50/P95 ms: not measured (expected ≈ 0.5 s stability window + translation)
- Video optical delay P50/P95 ms: n/a (file)
- Frames drop, audio sync, peak RAM, thermal: not measured
- Test artifacts (logs/JSONL/traces): XCTest log; app screenshots
- Outcome / decision / Windows impact: pipeline works end-to-end; quality needs Thai reviewer + larger fixture set before any claim. WIN-CHANGE-20261110-005.

## Translation reviewer rubric (1–5 each)
- Meaning/plot fidelity; Thai naturalness; character voice; names/glossary consistency; truncation/readability; hallucinations (separate count).
- Score English and Japanese independently, anonymize candidate model to reviewers where practical.
- Define acceptable thresholds in ADR after R0, not before.
