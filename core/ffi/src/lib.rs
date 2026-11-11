//! Thin FFI surface (README §4.2: opaque handles, API version, error codes).
//! Keep business logic in `subtitle_core`; this crate only adapts types.

use std::sync::Arc;
use std::sync::Mutex;
use subtitle_core::cache::{cache_key, CacheKeyInput};
use subtitle_core::epoch::{EpochReason, EpochTag, Session};
use subtitle_core::tracker::{StabilityTracker, TrackerConfig, TrackerEvent};

uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn core_api_version() -> u32 {
    subtitle_core::CORE_API_VERSION
}

#[derive(uniffi::Enum)]
pub enum FfiEpochReason {
    Seek,
    SourceSwitch,
    Reconnect,
    FormatChange,
    LanguageOrProfileChange,
}

impl From<FfiEpochReason> for EpochReason {
    fn from(r: FfiEpochReason) -> Self {
        match r {
            FfiEpochReason::Seek => EpochReason::Seek,
            FfiEpochReason::SourceSwitch => EpochReason::SourceSwitch,
            FfiEpochReason::Reconnect => EpochReason::Reconnect,
            FfiEpochReason::FormatChange => EpochReason::FormatChange,
            FfiEpochReason::LanguageOrProfileChange => EpochReason::LanguageOrProfileChange,
        }
    }
}

/// Opaque session handle for native UI/adapters.
#[derive(uniffi::Object)]
pub struct CoreSession {
    inner: Session,
}

#[uniffi::export]
impl CoreSession {
    #[uniffi::constructor]
    pub fn new(source_id: String) -> Arc<Self> {
        Arc::new(Self {
            inner: Session::new(source_id),
        })
    }
    pub fn source_id(&self) -> String {
        self.inner.source_id().to_string()
    }
    pub fn epoch(&self) -> u64 {
        self.inner.epoch()
    }
    pub fn bump(&self, reason: FfiEpochReason) -> u64 {
        self.inner.bump(reason.into())
    }
    pub fn is_current(&self, source_id: String, epoch: u64) -> bool {
        self.inner.is_current(&EpochTag { source_id, epoch })
    }
}

#[derive(uniffi::Enum, Debug, PartialEq)]
pub enum FfiTrackerEvent {
    Stable { id: u64, text: String },
    Vanished { id: u64 },
}

fn map_events(v: Vec<TrackerEvent>) -> Vec<FfiTrackerEvent> {
    v.into_iter()
        .filter_map(|e| match e {
            TrackerEvent::Stable { id, text } => Some(FfiTrackerEvent::Stable { id, text }),
            TrackerEvent::Vanished { id } => Some(FfiTrackerEvent::Vanished { id }),
            TrackerEvent::None => None,
        })
        .collect()
}

/// Subtitle stability tracker (core `tracker.rs`) behind an opaque handle.
#[derive(uniffi::Object)]
pub struct SubtitleTracker {
    inner: Mutex<StabilityTracker>,
}

#[uniffi::export]
impl SubtitleTracker {
    #[uniffi::constructor]
    pub fn new(stable_samples: u32, miss_tolerance: u32, min_confidence: f32) -> Arc<Self> {
        let cfg = TrackerConfig {
            stable_samples,
            miss_tolerance,
            min_confidence,
            ..Default::default()
        };
        Arc::new(Self {
            inner: Mutex::new(StabilityTracker::new(cfg)),
        })
    }
    pub fn observe(&self, text: Option<String>, confidence: f32) -> Vec<FfiTrackerEvent> {
        map_events(
            self.inner
                .lock()
                .unwrap()
                .observe(text.as_deref(), confidence),
        )
    }
    pub fn reset(&self) -> Vec<FfiTrackerEvent> {
        map_events(vec![self.inner.lock().unwrap().reset()])
    }
    pub fn current_id(&self) -> Option<u64> {
        self.inner.lock().unwrap().current().map(|(id, _)| id)
    }
}

#[derive(uniffi::Record)]
pub struct FfiCacheKeyInput {
    pub source_language: String,
    pub target_language: String,
    pub model_id: String,
    pub model_version: String,
    pub prompt_template_version: String,
    pub glossary_hash: String,
    pub normalized_text: String,
    pub context_hash: String,
}

#[uniffi::export]
pub fn translation_cache_key(input: FfiCacheKeyInput) -> String {
    cache_key(&CacheKeyInput {
        source_language: &input.source_language,
        target_language: &input.target_language,
        model_id: &input.model_id,
        model_version: &input.model_version,
        prompt_template_version: &input.prompt_template_version,
        glossary_hash: &input.glossary_hash,
        normalized_text: &input.normalized_text,
        context_hash: &input.context_hash,
    })
}

#[uniffi::export]
pub fn character_error_rate(reference: String, hypothesis: String) -> f32 {
    subtitle_core::tracker::cer(&reference, &hypothesis)
}

// ---- Translation contract (Prompt p2 spec) ----
use subtitle_core::translation as tr;

#[derive(uniffi::Enum, Clone, Copy)]
pub enum FfiSourceLanguage {
    English,
    Japanese,
}
impl From<FfiSourceLanguage> for tr::SourceLanguage {
    fn from(l: FfiSourceLanguage) -> Self {
        match l {
            FfiSourceLanguage::English => tr::SourceLanguage::English,
            FfiSourceLanguage::Japanese => tr::SourceLanguage::Japanese,
        }
    }
}

#[derive(uniffi::Enum, Debug, PartialEq)]
pub enum FfiSanitized {
    Ok { text: String, truncated: bool },
    Reject,
}

#[derive(uniffi::Enum, Debug, PartialEq)]
pub enum FfiParsedTranslation {
    Translated { text: String },
    Unreadable,
    Invalid { reason: String },
}

#[uniffi::export]
pub fn prompt_text(version: String) -> Option<String> {
    tr::prompt_text(&version).map(str::to_string)
}
#[uniffi::export]
pub fn prompt_hash(version: String) -> Option<String> {
    tr::prompt_hash(&version)
}
#[uniffi::export]
pub fn default_prompt_version() -> String {
    tr::DEFAULT_PROMPT_VERSION.to_string()
}
#[uniffi::export]
pub fn decoding_id() -> String {
    tr::DECODING_ID.to_string()
}
#[uniffi::export]
pub fn sanitize_subtitle(input: String) -> FfiSanitized {
    match tr::sanitize_subtitle(&input) {
        tr::Sanitized::Ok { text, truncated } => FfiSanitized::Ok { text, truncated },
        tr::Sanitized::Reject => FfiSanitized::Reject,
    }
}
#[uniffi::export]
pub fn build_user_message(language: FfiSourceLanguage, sanitized_text: String) -> String {
    tr::user_message(language.into(), &sanitized_text)
}
#[uniffi::export]
pub fn parse_translation(raw: String, source: String, hit_token_cap: bool) -> FfiParsedTranslation {
    match tr::parse_translation(&raw, &source, hit_token_cap) {
        tr::ParsedTranslation::Translated(text) => FfiParsedTranslation::Translated { text },
        tr::ParsedTranslation::Unreadable => FfiParsedTranslation::Unreadable,
        tr::ParsedTranslation::Invalid(r) => FfiParsedTranslation::Invalid {
            reason: format!("{r:?}"),
        },
    }
}

#[derive(uniffi::Record)]
pub struct FfiHistoryPair {
    pub language: FfiSourceLanguage,
    pub source: String,
    pub thai: String,
}

/// Per-session translation history (§4.2), opaque handle.
#[derive(uniffi::Object)]
pub struct TranslationHistory {
    inner: Mutex<tr::TranslationHistory>,
}

#[uniffi::export]
impl TranslationHistory {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(tr::TranslationHistory::default()),
        })
    }
    pub fn push(&self, language: FfiSourceLanguage, source: String, thai: String) {
        self.inner
            .lock()
            .unwrap()
            .push(language.into(), &source, &thai)
    }
    pub fn clear(&self) {
        self.inner.lock().unwrap().clear()
    }
    pub fn fingerprint(&self) -> String {
        self.inner.lock().unwrap().fingerprint()
    }
    pub fn pairs(&self) -> Vec<FfiHistoryPair> {
        self.inner
            .lock()
            .unwrap()
            .pairs()
            .iter()
            .map(|(l, s, t)| FfiHistoryPair {
                language: match l {
                    tr::SourceLanguage::English => FfiSourceLanguage::English,
                    tr::SourceLanguage::Japanese => FfiSourceLanguage::Japanese,
                },
                source: s.clone(),
                thai: t.clone(),
            })
            .collect()
    }
}

#[derive(uniffi::Record)]
pub struct FfiCacheIdentity {
    pub model_id: String,
    pub model_revision: String,
    pub quantization_id: String,
    pub prompt_version: String,
    pub decoding_id: String,
    pub source_language: FfiSourceLanguage,
    pub normalized_text: String,
    pub history_fingerprint: String,
    pub game_profile_id: Option<String>,
    pub glossary_version: Option<String>,
    pub speaker: Option<String>,
}

#[uniffi::export]
pub fn translation_cache_id(i: FfiCacheIdentity) -> String {
    tr::cache_id(&tr::CacheIdentity {
        model_id: &i.model_id,
        model_revision: &i.model_revision,
        quantization_id: &i.quantization_id,
        prompt_version: &i.prompt_version,
        decoding_id: &i.decoding_id,
        source_language: i.source_language.into(),
        normalized_text: &i.normalized_text,
        history_fingerprint: &i.history_fingerprint,
        game_profile_id: i.game_profile_id.as_deref(),
        glossary_version: i.glossary_version.as_deref(),
        speaker: i.speaker.as_deref(),
    })
}

#[uniffi::export]
pub fn build_user_message_with_speaker(
    language: FfiSourceLanguage,
    sanitized_text: String,
    speaker: Option<String>,
) -> String {
    tr::user_message_with_speaker(language.into(), &sanitized_text, speaker.as_deref())
}

#[derive(Debug, uniffi::Error)]
pub enum FfiProfileError {
    Invalid { message: String },
}

impl std::fmt::Display for FfiProfileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FfiProfileError::Invalid { message } => write!(f, "invalid game profile: {message}"),
        }
    }
}

/// Parsed game profile (prompt p3, ADR-0010).
#[derive(uniffi::Object)]
pub struct GameProfile {
    inner: subtitle_core::profile::GameProfile,
}

#[uniffi::export]
impl GameProfile {
    #[uniffi::constructor]
    pub fn from_json(json: String) -> Result<Arc<Self>, FfiProfileError> {
        subtitle_core::profile::GameProfile::from_json(&json)
            .map(|inner| Arc::new(Self { inner }))
            .map_err(|message| FfiProfileError::Invalid { message })
    }
    pub fn id(&self) -> String {
        self.inner.id.clone()
    }
    pub fn title(&self) -> String {
        self.inner.title.clone()
    }
    pub fn content_hash(&self) -> String {
        self.inner.hash()
    }
    pub fn system_prompt(&self, version: String) -> Option<String> {
        subtitle_core::profile::system_prompt(&version, Some(&self.inner))
    }
    pub fn speaker_hint(&self, speaker: Option<String>) -> Option<String> {
        subtitle_core::profile::speaker_hint(speaker.as_deref(), Some(&self.inner))
    }
}

/// Speaker hint without a profile (name only, cleaned).
#[uniffi::export]
pub fn plain_speaker_hint(speaker: Option<String>) -> Option<String> {
    subtitle_core::profile::speaker_hint(speaker.as_deref(), None)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ffi_session_drops_stale_epoch() {
        let s = CoreSession::new("file:a".into());
        let e = s.epoch();
        s.bump(FfiEpochReason::Seek);
        assert!(!s.is_current("file:a".into(), e));
        assert!(s.is_current("file:a".into(), e + 1));
        assert_eq!(core_api_version(), 1);
    }
}
