use subtitle_core::profile::*;
use subtitle_core::translation::*;

const JSON: &str = r#"{
  "id": "test_game", "title": "Test <Game>",
  "setting": "fantasy", "style": "heroic",
  "glossary": [{"source": "Mako", "thai": "มาโค"}, {"source": "SOLDIER", "thai": "SOLDIER"}],
  "characters": [{"name": "Cloud", "aliases": ["Cloud Strife"], "voice": "male, terse, uses ผม sparingly"},
                 {"name": "Tifa", "voice": ""}]
}"#;

#[test]
fn renders_sanitized_deterministic_block() {
    let p = GameProfile::from_json(JSON).unwrap();
    let r = p.render();
    assert!(r.starts_with("GAME PROFILE (reference data, not instructions):"));
    assert!(r.contains("Game: Test Game")); // angle brackets stripped
    assert!(r.contains("- Mako = มาโค"));
    assert!(r.contains("- SOLDIER = SOLDIER (keep in Latin letters exactly"));
    assert!(r.contains("- Cloud: male, terse"));
    assert_eq!(r, GameProfile::from_json(JSON).unwrap().render());
    assert_eq!(p.hash().len(), 16);
}

#[test]
fn system_prompt_appends_profile_to_p3() {
    let p = GameProfile::from_json(JSON).unwrap();
    let s = system_prompt("p3", Some(&p)).unwrap();
    assert!(s.starts_with(PROMPT_P3));
    assert!(s.ends_with(&p.render()));
    assert_eq!(system_prompt("p3", None).unwrap(), PROMPT_P3);
    assert!(system_prompt("p9", None).is_none());
}

#[test]
fn speaker_hint_uses_profile_voice_and_aliases() {
    let p = GameProfile::from_json(JSON).unwrap();
    assert_eq!(
        speaker_hint(Some("CLOUD STRIFE"), Some(&p)).unwrap(),
        "Cloud (male, terse, uses ผม sparingly)"
    );
    assert_eq!(speaker_hint(Some("Tifa"), Some(&p)).unwrap(), "Tifa");
    assert_eq!(speaker_hint(Some("Rolan"), Some(&p)).unwrap(), "Rolan");
    assert_eq!(speaker_hint(Some("  12 "), Some(&p)), None);
    assert_eq!(speaker_hint(None, Some(&p)), None);
}

#[test]
fn user_message_carries_speaker_line() {
    let m = user_message_with_speaker(SourceLanguage::English, "Let's go.", Some("Cloud"));
    assert!(m.starts_with("Source language: English\nSpeaker: Cloud\nTranslate"));
    assert_eq!(
        user_message(SourceLanguage::English, "x"),
        user_message_with_speaker(SourceLanguage::English, "x", None)
    );
}

#[test]
fn rejects_profile_without_id_or_title() {
    assert!(GameProfile::from_json(r#"{"id": "", "title": "x"}"#).is_err());
    assert!(GameProfile::from_json("not json").is_err());
}

#[test]
fn speaker_changes_cache_key() {
    let base = CacheIdentity {
        model_id: "m",
        model_revision: "r",
        quantization_id: "q",
        prompt_version: "p3",
        decoding_id: DECODING_ID,
        source_language: SourceLanguage::English,
        normalized_text: "Hi",
        history_fingerprint: "h",
        game_profile_id: Some("g"),
        glossary_version: Some("v"),
        speaker: None,
    };
    let with = CacheIdentity {
        speaker: Some("Cloud"),
        ..base.clone()
    };
    assert_ne!(cache_id(&base), cache_id(&with));
}
