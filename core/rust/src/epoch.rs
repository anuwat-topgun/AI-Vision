//! Session epoch / generation (README §1.3, §4.3). Any seek, source switch,
//! reconnect or language/profile change bumps the epoch; results tagged with an
//! older epoch or another source are stale and must be dropped.

use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpochReason {
    Seek,
    SourceSwitch,
    Reconnect,
    FormatChange,
    LanguageOrProfileChange,
}

#[derive(Debug)]
pub struct Session {
    source_id: String,
    epoch: AtomicU64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EpochTag {
    pub source_id: String,
    pub epoch: u64,
}

impl Session {
    pub fn new(source_id: impl Into<String>) -> Self {
        Self {
            source_id: source_id.into(),
            epoch: AtomicU64::new(0),
        }
    }
    pub fn source_id(&self) -> &str {
        &self.source_id
    }
    pub fn epoch(&self) -> u64 {
        self.epoch.load(Ordering::Acquire)
    }
    pub fn tag(&self) -> EpochTag {
        EpochTag {
            source_id: self.source_id.clone(),
            epoch: self.epoch(),
        }
    }
    /// Monotonic bump; returns the new epoch.
    pub fn bump(&self, _reason: EpochReason) -> u64 {
        self.epoch.fetch_add(1, Ordering::AcqRel) + 1
    }
    /// Accept a result only if it belongs to this source and current epoch.
    pub fn is_current(&self, tag: &EpochTag) -> bool {
        tag.source_id == self.source_id && tag.epoch == self.epoch()
    }
}
