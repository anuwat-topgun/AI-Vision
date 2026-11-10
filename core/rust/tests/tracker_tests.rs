use subtitle_core::tracker::*;

fn t() -> StabilityTracker {
    StabilityTracker::new(TrackerConfig::default())
}

#[test]
fn needs_two_samples_then_vanishes_after_tolerance() {
    let mut k = t();
    assert!(k.observe(Some("Hello there"), 0.9).is_empty());
    assert_eq!(
        k.observe(Some("Hello there"), 0.9),
        vec![TrackerEvent::Stable {
            id: 1,
            text: "Hello there".into()
        }]
    );
    assert!(k.observe(Some("Hello there"), 0.9).is_empty()); // no re-translate
    assert!(k.observe(None, 0.0).is_empty()); // 1 miss tolerated
    assert_eq!(k.observe(None, 0.0), vec![TrackerEvent::Vanished { id: 1 }]);
}

#[test]
fn ocr_jitter_is_same_subtitle() {
    let mut k = t();
    k.observe(Some("We should reach the gate before dawn."), 0.9);
    let ev = k.observe(Some("We should reach the gate before dawn"), 0.9); // missing period
    assert!(matches!(ev.as_slice(), [TrackerEvent::Stable { .. }]));
    assert!(k
        .observe(Some("We shou1d reach the gate before dawn."), 0.9)
        .is_empty());
}

#[test]
fn new_text_replaces_old() {
    let mut k = t();
    k.observe(Some("first line"), 0.9);
    k.observe(Some("first line"), 0.9);
    k.observe(Some("a completely different line"), 0.9);
    let ev = k.observe(Some("a completely different line"), 0.9);
    assert_eq!(
        ev,
        vec![
            TrackerEvent::Vanished { id: 1 },
            TrackerEvent::Stable {
                id: 2,
                text: "a completely different line".into()
            }
        ]
    );
}

#[test]
fn low_confidence_counts_as_absent_and_reset_clears() {
    let mut k = t();
    k.observe(Some("x y z"), 0.1);
    assert!(k.observe(Some("x y z"), 0.1).is_empty());
    k.observe(Some("夜明けまでに門へ行こう。"), 0.9);
    k.observe(Some("夜明けまでに門へ行こう。"), 0.9);
    assert_eq!(k.reset(), TrackerEvent::Vanished { id: 1 });
    assert_eq!(k.current(), None);
}

#[test]
fn cer_metric() {
    assert_eq!(cer("abc", "abc"), 0.0);
    assert!((cer("abcd", "abxd") - 0.25).abs() < 1e-6);
    assert!((cer("夜明け", "夜朋け") - 1.0 / 3.0).abs() < 1e-6);
}
