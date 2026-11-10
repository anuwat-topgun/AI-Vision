# Pull Request Template

## Summary / requirement IDs

## Modified components / platforms
- [ ] Shared Rust core
- [ ] iPadOS
- [ ] macOS
- [ ] Android tablet
- [ ] Flutter UI
- [ ] AI/model/OCR
- [ ] media/TV output
- [ ] security/cloud

## Acceptance tests / evidence

## Windows portability impact (MANDATORY)
- [ ] Impacting Windows: added entry to `docs/windows-handoff/WINDOWS_PORTABILITY_LEDGER.md` (record ID: ____)
- [ ] Windows impact: NONE — explanation: _____________________________

## Architecture change?
- [ ] No
- [ ] Yes — ADR link and migration plan: ________

## Mandatory review
- [ ] Offline-by-default preserved; no unintended network call
- [ ] No API keys or copyrighted assets committed
- [ ] Contract schemas + compatibility tests updated
- [ ] QA matrix / benchmark log updated as needed
- [ ] Documentation, changelog and known issues updated
- [ ] Native video/UI threads never block on OCR/translation
- [ ] Hardware support claims substantiated
