//! Thin FFI surface (README §4.2: opaque handles, API version, error codes).
//! Keep business logic in `subtitle_core`; this crate only adapts types.

use std::sync::Arc;
use subtitle_core::epoch::{EpochReason, EpochTag, Session};

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
