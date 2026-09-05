use std::{path::PathBuf, sync::Mutex};

use serde::{Deserialize, Serialize};
use tauri::State;
use zeroize::Zeroizing;

use crate::{
    persistence::{PersistenceError, VaultFile},
    storage::{RecordId, RecordKind, VaultStore},
    vault::VaultError,
};

const ALGORITHM: &str = "AES-256-GCM";
const MAX_REQUEST_PAYLOAD: usize = 256 * 1024 * 1024 - 16;

#[derive(Default)]
pub struct AppState {
    session: Mutex<Option<ActiveSession>>,
}

struct ActiveSession {
    path: PathBuf,
    store: VaultStore,
    dirty: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct ApiError {
    code: String,
    message: String,
}

impl ApiError {
    fn new(code: &str, message: &str) -> Self {
        Self { code: code.to_owned(), message: message.to_owned() }
    }

    fn locked() -> Self {
        Self::new("vault_locked", "Unlock a vault before using this operation")
    }

    fn invalid_request() -> Self {
        Self::new("invalid_request", "The request contains invalid data")
    }
}

impl From<PersistenceError> for ApiError {
    fn from(error: PersistenceError) -> Self {
        match error {
            PersistenceError::Vault(VaultError::Decryption) =>
                Self::new("unlock_failed", "Unable to unlock the vault"),
            PersistenceError::Io(_) => Self::new("storage_io", "Vault storage I/O failed"),
            PersistenceError::Vault(_) => Self::new("vault_error", "Vault operation failed"),
            PersistenceError::TemporaryPathUnavailable =>
                Self::new("storage_io", "Unable to allocate a safe temporary path"),
        }
    }
}

impl From<VaultError> for ApiError {
    fn from(error: VaultError) -> Self {
        match error {
            VaultError::Decryption => Self::new("unlock_failed", "Unable to unlock the vault"),
            _ => Self::new("vault_error", "Vault operation failed"),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct VaultStatusDto {
    pub locked: bool,
    pub algorithm: &'static str,
    pub path: Option<String>,
    pub dirty: bool,
}

#[derive(Debug, Serialize)]
pub struct RecordSummaryDto {
    pub id: String,
    pub kind: &'static str,
    pub revision: u64,
    pub size: usize,
}

#[derive(Debug, Serialize)]
pub struct RecordDto {
    pub id: String,
    pub kind: &'static str,
    pub revision: u64,
    pub payload: Vec<u8>,
}

#[derive(Debug, Deserialize)]
pub struct CreateRecordRequest {
    pub kind: String,
    pub payload: Vec<u8>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateRecordRequest {
    pub id: String,
    pub payload: Vec<u8>,
}

#[tauri::command]
pub fn vault_status(state: State<'_, AppState>) -> Result<VaultStatusDto, ApiError> {
    let session = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    Ok(match session.as_ref() {
        Some(active) => VaultStatusDto {
            locked: false,
            algorithm: ALGORITHM,
            path: Some(active.path.to_string_lossy().into_owned()),
            dirty: active.dirty,
        },
        None => VaultStatusDto { locked: true, algorithm: ALGORITHM, path: None, dirty: false },
    })
}

#[tauri::command]
pub fn vault_create(state: State<'_, AppState>, path: String, password: String) -> Result<(), ApiError> {
    let path = validate_path(path)?;
    let password = Zeroizing::new(password);
    let mut guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    if guard.is_some() || path.exists() {
        return Err(ApiError::new("vault_exists", "Close the active vault or choose a new path"));
    }

    let store = VaultStore::create()?;
    VaultFile::save(&path, &store, password.as_bytes())?;
    let store = VaultFile::load(&path, password.as_bytes())?;
    *guard = Some(ActiveSession { path, store, dirty: false });
    Ok(())
}

#[tauri::command]
pub fn vault_open(state: State<'_, AppState>, path: String, password: String) -> Result<(), ApiError> {
    let path = validate_path(path)?;
    let password = Zeroizing::new(password);
    let store = VaultFile::load(&path, password.as_bytes())?;
    let mut guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    if guard.is_some() {
        return Err(ApiError::new("vault_already_open", "Close the active vault first"));
    }
    *guard = Some(ActiveSession { path, store, dirty: false });
    Ok(())
}

#[tauri::command]
pub fn vault_lock(state: State<'_, AppState>) -> Result<(), ApiError> {
    let mut guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    guard.take();
    Ok(())
}

#[tauri::command]
pub fn vault_save(state: State<'_, AppState>) -> Result<(), ApiError> {
    let mut guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    let active = guard.as_mut().ok_or_else(ApiError::locked)?;
    if active.dirty {
        VaultFile::save_unlocked(&active.path, &active.store)?;
        active.dirty = false;
    }
    Ok(())
}

#[tauri::command]
pub fn record_list(state: State<'_, AppState>) -> Result<Vec<RecordSummaryDto>, ApiError> {
    let guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    let active = guard.as_ref().ok_or_else(ApiError::locked)?;
    Ok(active.store.list().map(|(id, record)| RecordSummaryDto {
        id: id.to_hex(), kind: kind_name(record.kind), revision: record.revision, size: record.payload.len(),
    }).collect())
}

#[tauri::command]
pub fn record_read(state: State<'_, AppState>, id: String) -> Result<RecordDto, ApiError> {
    let id = parse_id(&id)?;
    let guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    let active = guard.as_ref().ok_or_else(ApiError::locked)?;
    let record = active.store.get(id).ok_or_else(ApiError::invalid_request)?;
    Ok(RecordDto { id: id.to_hex(), kind: kind_name(record.kind), revision: record.revision, payload: record.payload.to_vec() })
}

#[tauri::command]
pub fn record_create(state: State<'_, AppState>, request: CreateRecordRequest) -> Result<String, ApiError> {
    let kind = parse_kind(&request.kind)?;
    validate_payload(&request.payload)?;
    let mut guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    let active = guard.as_mut().ok_or_else(ApiError::locked)?;
    let id = active.store.insert(kind, request.payload)?;
    active.dirty = true;
    Ok(id.to_hex())
}

#[tauri::command]
pub fn record_update(state: State<'_, AppState>, request: UpdateRecordRequest) -> Result<(), ApiError> {
    let id = parse_id(&request.id)?;
    validate_payload(&request.payload)?;
    let mut guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    let active = guard.as_mut().ok_or_else(ApiError::locked)?;
    active.store.update(id, request.payload)?;
    active.dirty = true;
    Ok(())
}

#[tauri::command]
pub fn record_delete(state: State<'_, AppState>, id: String) -> Result<(), ApiError> {
    let id = parse_id(&id)?;
    let mut guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    let active = guard.as_mut().ok_or_else(ApiError::locked)?;
    active.store.remove(id)?;
    active.dirty = true;
    Ok(())
}

fn validate_path(value: String) -> Result<PathBuf, ApiError> {
    if value.trim().is_empty() {
        return Err(ApiError::invalid_request());
    }
    let path = PathBuf::from(value);
    if path.is_dir() || path.parent().is_some_and(|parent| !parent.exists()) {
        return Err(ApiError::new("invalid_path", "The vault path is not usable"));
    }
    Ok(path)
}

fn parse_id(value: &str) -> Result<RecordId, ApiError> {
    RecordId::from_hex(value).map_err(|_| ApiError::invalid_request())
}

fn parse_kind(value: &str) -> Result<RecordKind, ApiError> {
    match value {
        "note" => Ok(RecordKind::Note),
        "secret" => Ok(RecordKind::Secret),
        "attachment" => Ok(RecordKind::Attachment),
        _ => Err(ApiError::invalid_request()),
    }
}

fn kind_name(kind: RecordKind) -> &'static str {
    match kind {
        RecordKind::Note => "note",
        RecordKind::Secret => "secret",
        RecordKind::Attachment => "attachment",
    }
}

fn validate_payload(payload: &[u8]) -> Result<(), ApiError> {
    if payload.len() > MAX_REQUEST_PAYLOAD { Err(ApiError::invalid_request()) } else { Ok(()) }
}
