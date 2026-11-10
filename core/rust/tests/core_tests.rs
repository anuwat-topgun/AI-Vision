use subtitle_core::cache::*;
use subtitle_core::contracts::*;
use subtitle_core::epoch::*;
use subtitle_core::fsm::{step, Effect, SubtitleInput as I, SubtitleState as S};

fn root() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn sample_event() -> SubtitleEvent {
    SubtitleEvent {
        schema_version: 1,
        source_id: "file:abc".into(),
        session_epoch: 0,
        subtitle_id: "s1".into(),
        start_pts_us: 1_200_000,
        end_pts_us: 3_900_000,
        source_language: Language::En,
        text: "We should reach the gate before dawn.".into(),
        bbox: [0.2, 0.82, 0.6, 0.10],
        confidence: 0.9,
        detector_version: None,
        ocr_version: None,
    }
}

#[test]
fn seek_race_drops_stale_translation() {
    // AC-010 / E2E-03 core logic
    let s = Session::new("file:abc");
    let tag = s.tag();
    s.bump(EpochReason::Seek);
    assert!(!s.is_current(&tag));
    let (st, eff) = step(
        S::Pending,
        &I::TranslationReturned {
            epoch_valid: s.is_current(&tag),
            still_visible: true,
        },
    );
    assert_eq!((st, eff), (S::Expired, Effect::DropStale));
}

#[test]
fn other_source_is_stale() {
    // AC-018
    let a = Session::new("file:abc");
    let tag = EpochTag {
        source_id: "uvc:1".into(),
        epoch: a.epoch(),
    };
    assert!(!a.is_current(&tag));
}

#[test]
fn late_response_never_resurrects() {
    for s in [S::Expired, S::Absent, S::Displayed] {
        let (n, e) = step(
            s,
            &I::TranslationReturned {
                epoch_valid: true,
                still_visible: true,
            },
        );
        assert_eq!((n, e), (s, Effect::DropStale));
    }
}

#[test]
fn happy_path_and_vanish_clears() {
    // AC-011
    let mut st = S::Absent;
    for (inp, want) in [
        (I::TextDetected, S::Candidate),
        (I::BecameStable, S::Stable),
        (I::CacheMiss, S::Pending),
        (
            I::TranslationReturned {
                epoch_valid: true,
                still_visible: true,
            },
            S::Displayed,
        ),
        (I::Vanished, S::Expired),
        (I::Cleared, S::Absent),
    ] {
        st = step(st, &inp).0;
        assert_eq!(st, want);
    }
}

#[test]
fn failure_goes_to_fallback() {
    assert_eq!(
        step(S::Pending, &I::TranslationFailed),
        (S::Fallback, Effect::ShowFallback)
    );
}

#[test]
fn event_validation() {
    assert!(sample_event().validate().is_ok());
    let mut e = sample_event();
    e.end_pts_us = e.start_pts_us;
    assert_eq!(e.validate(), Err(ContractError::InvalidPtsRange));
    let mut e = sample_event();
    e.bbox = [0.8, 0.8, 0.5, 0.1];
    assert_eq!(e.validate(), Err(ContractError::InvalidBbox));
}

#[test]
fn serialized_event_matches_json_schema() {
    // README §4.5 cross-platform decoder test
    let schema: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(root().join("schemas/subtitle-event.schema.json")).unwrap(),
    )
    .unwrap();
    let compiled = jsonschema::JSONSchema::compile(&schema).unwrap();
    let v = serde_json::to_value(sample_event()).unwrap();
    assert!(compiled.is_valid(&v));
    let back: SubtitleEvent = serde_json::from_value(v).unwrap();
    assert_eq!(back, sample_event());
}

#[test]
fn translation_request_matches_json_schema() {
    let schema: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(root().join("schemas/translation-request.schema.json")).unwrap(),
    )
    .unwrap();
    let compiled = jsonschema::JSONSchema::compile(&schema).unwrap();
    let r = TranslationRequest {
        schema_version: 1,
        request_id: "r1".into(),
        source_id: "file:abc".into(),
        session_epoch: 2,
        subtitle_id: "s1".into(),
        input_language: Language::Ja,
        output_language: Language::Th,
        text: "夜明けまでに門へ行こう。".into(),
        provider: ProviderKind::Offline,
        context: vec![],
        glossary_hash: None,
        prompt_version: Some("p1".into()),
        model_id: None,
    };
    assert!(compiled.is_valid(&serde_json::to_value(&r).unwrap()));
}

#[test]
fn cache_key_changes_with_model_and_glossary() {
    let base = CacheKeyInput {
        source_language: "en",
        target_language: "th",
        model_id: "m",
        model_version: "1",
        prompt_template_version: "p1",
        glossary_hash: "g",
        normalized_text: "hi",
        context_hash: "c",
    };
    let k = cache_key(&base);
    assert_eq!(k.len(), 64);
    assert_ne!(
        k,
        cache_key(&CacheKeyInput {
            model_version: "2",
            ..base.clone()
        })
    );
    assert_ne!(
        k,
        cache_key(&CacheKeyInput {
            glossary_hash: "g2",
            ..base.clone()
        })
    );
    assert_eq!(normalize_text("  a \n b "), "a b");
}
