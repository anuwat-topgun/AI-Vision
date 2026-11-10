//! Normative contracts from README §4.2. Platform handles are opaque `u64`s,
//! never CVPixelBuffer/SurfaceTexture/AHardwareBuffer/D3D types (§19.1(3)).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PixelFormat {
    Nv12,
    Yuy2,
    Bgra8,
    Mjpeg,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ColorSpace {
    Bt709,
    Bt601,
    Srgb,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FrameMetadata {
    pub source_id: String,
    pub session_epoch: u64,
    pub frame_seq: u64,
    /// Media/capture-clock presentation time; never wall clock (§4.3).
    pub pts_us: i64,
    pub width: u32,
    pub height: u32,
    pub rotation_degrees: u16,
    pub format: PixelFormat,
    pub color_space: ColorSpace,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Language {
    En,
    Ja,
    Th,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LanguageHint {
    En,
    Ja,
    Auto,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceMode {
    File,
    Uvc,
    Screen,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderKind {
    Offline,
    Cloud,
}

/// Mirrors `schemas/subtitle-event.schema.json` v1.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SubtitleEvent {
    pub schema_version: u32,
    pub source_id: String,
    pub session_epoch: u64,
    pub subtitle_id: String,
    pub start_pts_us: i64,
    pub end_pts_us: i64,
    pub source_language: Language,
    pub text: String,
    /// [left, top, width, height], normalized 0..1.
    pub bbox: [f32; 4],
    pub confidence: f32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detector_version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ocr_version: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContractError {
    UnsupportedSchemaVersion(u32),
    InvalidPtsRange,
    InvalidBbox,
    InvalidConfidence,
    EmptyField(&'static str),
    UnsupportedLanguage,
}

impl SubtitleEvent {
    /// Application-level checks the JSON schema cannot express.
    pub fn validate(&self) -> Result<(), ContractError> {
        if self.schema_version != crate::SCHEMA_VERSION {
            return Err(ContractError::UnsupportedSchemaVersion(self.schema_version));
        }
        if self.source_id.is_empty() {
            return Err(ContractError::EmptyField("source_id"));
        }
        if self.subtitle_id.is_empty() {
            return Err(ContractError::EmptyField("subtitle_id"));
        }
        if self.text.is_empty() {
            return Err(ContractError::EmptyField("text"));
        }
        if self.source_language == Language::Th {
            return Err(ContractError::UnsupportedLanguage);
        }
        if self.start_pts_us < 0 || self.end_pts_us <= self.start_pts_us {
            return Err(ContractError::InvalidPtsRange);
        }
        let [l, t, w, h] = self.bbox;
        let in01 = |v: f32| (0.0..=1.0).contains(&v);
        if !(in01(l) && in01(t) && in01(w) && in01(h)) || l + w > 1.0 + 1e-6 || t + h > 1.0 + 1e-6 {
            return Err(ContractError::InvalidBbox);
        }
        if !(0.0..=1.0).contains(&self.confidence) {
            return Err(ContractError::InvalidConfidence);
        }
        Ok(())
    }
}

/// Mirrors `schemas/translation-request.schema.json` v1.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TranslationRequest {
    pub schema_version: u32,
    pub request_id: String,
    pub source_id: String,
    pub session_epoch: u64,
    pub subtitle_id: String,
    pub input_language: Language,
    pub output_language: Language,
    pub text: String,
    pub provider: ProviderKind,
    pub context: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub glossary_hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_id: Option<String>,
}

/// Cloud error taxonomy (README §8.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum TranslationErrorKind {
    KeyInvalid,
    RateLimit,
    BillingRequired,
    Timeout,
    NetworkOffline,
    PolicyBlocked,
    ProviderUnavailable,
    BudgetSoftLimit,
    ModelUnavailable,
    Cancelled,
}

/// User-facing input error distinctions (NFR-009).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum InputErrorKind {
    UnsupportedDevice,
    PermissionDenied,
    UnsupportedStream,
    ProtectedContent,
    Disconnected,
    UnsupportedCodec,
}

/// Semantic shape of the adapter traits (README §4.2). Async/texture details are
/// implemented by platform adapters; core only sees normalized data.
pub trait TranslationProvider: Send + Sync {
    fn id(&self) -> &str;
    fn kind(&self) -> ProviderKind;
}

pub trait SecretStore: Send + Sync {
    /// Returns an opaque credential reference; raw keys never leave the adapter (§8.2).
    fn has_credential(&self, credential_ref: &str) -> bool;
    fn delete(&self, credential_ref: &str) -> Result<(), String>;
}
