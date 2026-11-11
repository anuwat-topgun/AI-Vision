# Game profiles (prompt p3)

One JSON file per game. The app appends the profile to the translation system prompt and uses
`characters[].voice` when a speaker-name zone reads that character's name tag.

Add or edit your own in `~/Library/Application Support/AIVision/Profiles/` (Game menu → Open
profiles folder, then Reload profiles). A user file with the same `id` replaces the bundled one.

```json
{
  "id": "unique_id",
  "title": "Game title",
  "setting": "world / era in one sentence",
  "style": "register and atmosphere for the Thai",
  "glossary": [{ "source": "Term", "thai": "คำไทย" }, { "source": "KeepMe", "thai": "" }],
  "characters": [{ "name": "Name", "aliases": ["Full Name"], "thai_name": "ชื่อ", "voice": "gender, personality, pronouns/particles" }]
}
```

An empty `thai` keeps the term unchanged. Fields are capped and stripped of `<` `>`; the profile is
reference data, never instructions. Voice notes in the bundled files are starting points: edit
them to match how you want each character to sound.
