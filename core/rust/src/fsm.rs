//! Subtitle state machine (README §6.4). Pure, deterministic; no clocks inside.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubtitleState {
    Absent,
    Candidate,
    Stable,
    Pending,
    Displayed,
    Fallback,
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubtitleInput {
    TextDetected,
    BecameStable,
    Vanished,
    CacheHit {
        epoch_valid: bool,
    },
    CacheMiss,
    TranslationReturned {
        epoch_valid: bool,
        still_visible: bool,
    },
    TranslationFailed,
    SourceChanged,
    Cleared,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Effect {
    None,
    StartTranslation,
    Show,
    ClearOverlay,
    DropStale,
    ShowFallback,
}

pub fn step(state: SubtitleState, input: &SubtitleInput) -> (SubtitleState, Effect) {
    use Effect as E;
    use SubtitleInput as I;
    use SubtitleState as S;
    match (state, input) {
        // Source change wins from any state with something possibly visible.
        (S::Absent, I::SourceChanged) => (S::Absent, E::None),
        (_, I::SourceChanged) => (S::Expired, E::ClearOverlay),

        (S::Absent, I::TextDetected) => (S::Candidate, E::None),
        (S::Candidate, I::BecameStable) => (S::Stable, E::None),
        (S::Candidate, I::Vanished) => (S::Absent, E::None),

        (S::Stable, I::CacheHit { epoch_valid: true }) => (S::Displayed, E::Show),
        (S::Stable, I::CacheHit { epoch_valid: false }) | (S::Stable, I::CacheMiss) => {
            (S::Pending, E::StartTranslation)
        }
        (S::Stable, I::Vanished) => (S::Expired, E::ClearOverlay),

        (
            S::Pending,
            I::TranslationReturned {
                epoch_valid: true,
                still_visible: true,
            },
        ) => (S::Displayed, E::Show),
        (S::Pending, I::TranslationReturned { .. }) => (S::Expired, E::DropStale),
        (S::Pending, I::Vanished) => (S::Expired, E::ClearOverlay),
        (S::Pending, I::TranslationFailed) => (S::Fallback, E::ShowFallback),

        (S::Displayed, I::Vanished) | (S::Fallback, I::Vanished) => (S::Expired, E::ClearOverlay),
        // A late response must never resurrect an expired/displayed subtitle.
        (S::Displayed, I::TranslationReturned { .. })
        | (S::Expired, I::TranslationReturned { .. })
        | (S::Absent, I::TranslationReturned { .. }) => (state, E::DropStale),

        (S::Expired, I::Cleared) => (S::Absent, E::None),
        (s, _) => (s, E::None),
    }
}
