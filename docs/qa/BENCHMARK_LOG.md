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

## Translation reviewer rubric (1–5 each)
- Meaning/plot fidelity; Thai naturalness; character voice; names/glossary consistency; truncation/readability; hallucinations (separate count).
- Score English and Japanese independently, anonymize candidate model to reviewers where practical.
- Define acceptable thresholds in ADR after R0, not before.
