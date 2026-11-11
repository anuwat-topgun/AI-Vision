//! Shared portable core. MUST compile for aarch64-apple-*, aarch64-linux-android
//! and x86_64-pc-windows-msvc without platform SDK imports (README §19.1).

pub mod cache;
pub mod contracts;
pub mod epoch;
pub mod fsm;
pub mod profile;
pub mod tracker;
pub mod translation;

/// FFI/ABI version exposed to Dart and native adapters (README §4.2, NFR-008).
pub const CORE_API_VERSION: u32 = 1;
/// Version of serialized contracts in `schemas/` (README §4.5).
pub const SCHEMA_VERSION: u32 = 1;
