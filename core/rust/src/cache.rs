//! Translation cache key (README §8.3). Contains NO key material.

use sha2::{Digest, Sha256};

#[derive(Debug, Clone)]
pub struct CacheKeyInput<'a> {
    pub source_language: &'a str,
    pub target_language: &'a str,
    pub model_id: &'a str,
    pub model_version: &'a str,
    pub prompt_template_version: &'a str,
    pub glossary_hash: &'a str,
    pub normalized_text: &'a str,
    pub context_hash: &'a str,
}

pub fn cache_key(i: &CacheKeyInput) -> String {
    let mut h = Sha256::new();
    for part in [
        i.source_language,
        i.target_language,
        i.model_id,
        i.model_version,
        i.prompt_template_version,
        i.glossary_hash,
        i.normalized_text,
        i.context_hash,
    ] {
        h.update((part.len() as u64).to_le_bytes()); // length-prefix: no ambiguity
        h.update(part.as_bytes());
    }
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Whitespace normalization only; Unicode NFKC/JA punctuation is a later OCR task (§6.1 step 6).
pub fn normalize_text(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}
