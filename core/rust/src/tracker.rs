//! Subtitle stability tracker (README §6.1 steps 5–9, §6.5). Pure and deterministic:
//! callers feed one OCR sample per analysis tick; no clocks inside.
//!
//! - A text must be seen in `stable_samples` consecutive samples (allowing OCR jitter)
//!   before it is reported `Stable` — so we never translate every flicker.
//! - A stable text that is missing for more than `miss_tolerance` samples is `Vanished`.
//! - A substantially different text replaces the current one (Vanished + new candidate).

use crate::cache::normalize_text;

#[derive(Debug, Clone, PartialEq)]
pub struct TrackerConfig {
    pub stable_samples: u32,
    pub miss_tolerance: u32,
    pub min_confidence: f32,
    /// 0..1, minimum similarity to treat two OCR readings as the same subtitle.
    pub same_text_similarity: f32,
}

impl Default for TrackerConfig {
    fn default() -> Self {
        Self {
            stable_samples: 2,
            miss_tolerance: 1,
            min_confidence: 0.4,
            same_text_similarity: 0.85,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TrackerEvent {
    None,
    /// New stable subtitle; translate this text. `id` is unique per tracker.
    Stable {
        id: u64,
        text: String,
    },
    /// Current stable subtitle gone; clear its overlay.
    Vanished {
        id: u64,
    },
}

#[derive(Debug, Default)]
pub struct StabilityTracker {
    cfg: TrackerConfig,
    candidate: Option<(String, u32)>,
    current: Option<(u64, String)>,
    misses: u32,
    next_id: u64,
}

impl StabilityTracker {
    pub fn new(cfg: TrackerConfig) -> Self {
        Self {
            cfg,
            ..Default::default()
        }
    }

    pub fn current(&self) -> Option<(u64, &str)> {
        self.current.as_ref().map(|(i, t)| (*i, t.as_str()))
    }

    /// Clears all state (seek / source switch). Returns Vanished if something was shown.
    pub fn reset(&mut self) -> TrackerEvent {
        self.candidate = None;
        self.misses = 0;
        match self.current.take() {
            Some((id, _)) => TrackerEvent::Vanished { id },
            None => TrackerEvent::None,
        }
    }

    /// Feed one OCR sample. `None` / empty / low-confidence means "no subtitle visible".
    /// May return up to two events (vanish of old + stable of new) — returned in order.
    pub fn observe(&mut self, text: Option<&str>, confidence: f32) -> Vec<TrackerEvent> {
        let text = text
            .map(normalize_text)
            .filter(|t| !t.is_empty() && confidence >= self.cfg.min_confidence);
        let mut out = Vec::new();
        let Some(text) = text else {
            self.candidate = None;
            if self.current.is_some() {
                self.misses += 1;
                if self.misses > self.cfg.miss_tolerance {
                    let (id, _) = self.current.take().unwrap();
                    self.misses = 0;
                    out.push(TrackerEvent::Vanished { id });
                }
            }
            return out;
        };

        if let Some((_, cur)) = &self.current {
            if similarity(cur, &text) >= self.cfg.same_text_similarity {
                self.misses = 0;
                self.candidate = None;
                return out;
            }
        }

        let count = match &self.candidate {
            Some((c, n)) if similarity(c, &text) >= self.cfg.same_text_similarity => n + 1,
            _ => 1,
        };
        self.candidate = Some((text.clone(), count));
        if count >= self.cfg.stable_samples {
            if let Some((id, _)) = self.current.take() {
                out.push(TrackerEvent::Vanished { id });
            }
            self.next_id += 1;
            self.current = Some((self.next_id, text.clone()));
            self.candidate = None;
            self.misses = 0;
            out.push(TrackerEvent::Stable {
                id: self.next_id,
                text,
            });
        }
        out
    }
}

/// 1 - normalized Levenshtein distance over Unicode scalar values.
pub fn similarity(a: &str, b: &str) -> f32 {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let max = a.len().max(b.len());
    if max == 0 {
        return 1.0;
    }
    1.0 - levenshtein(&a, &b) as f32 / max as f32
}

pub fn levenshtein(a: &[char], b: &[char]) -> usize {
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    let mut cur = vec![0; b.len() + 1];
    for (i, ca) in a.iter().enumerate() {
        cur[0] = i + 1;
        for (j, cb) in b.iter().enumerate() {
            cur[j + 1] = (prev[j] + usize::from(ca != cb))
                .min(prev[j + 1] + 1)
                .min(cur[j] + 1);
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    prev[b.len()]
}

/// Character error rate (README §6.3): edit distance / reference length.
pub fn cer(reference: &str, hypothesis: &str) -> f32 {
    let r: Vec<char> = reference.chars().collect();
    let h: Vec<char> = hypothesis.chars().collect();
    if r.is_empty() {
        return if h.is_empty() { 0.0 } else { 1.0 };
    }
    levenshtein(&r, &h) as f32 / r.len() as f32
}
