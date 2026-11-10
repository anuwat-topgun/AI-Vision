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
