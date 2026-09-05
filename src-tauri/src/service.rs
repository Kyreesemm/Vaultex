use std::{fs, path::{Path, PathBuf}, sync::Mutex};

use serde::{Deserialize, Serialize};
use tauri::State;
use zeroize::Zeroizing;

use crate::{
    config,
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
    pub name: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct VaultCatalogDto {
    pub directories: Vec<String>,
    pub vaults: Vec<VaultChoiceDto>,
    pub last_vault: Option<String>,
    pub android: bool,
}

#[derive(Debug, Serialize)]
pub struct VaultChoiceDto {
    pub path: String,
    pub name: String,
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
            name: Some(active.store.name().to_owned()),
        },
        None => VaultStatusDto { locked: true, algorithm: ALGORITHM, path: None, dirty: false, name: None },
    })
}

#[tauri::command]
pub fn vault_create(state: State<'_, AppState>, directory: String, name: String, password: String) -> Result<(), ApiError> {
    let directory = validate_directory(directory)?;
    let filename = format!("vault-{}.vault", RecordId::generate()?.to_hex());
    let path = directory.join(filename);
    let password = Zeroizing::new(password);
    let mut guard = state.session.lock().map_err(|_| ApiError::new("state_error", "Application state is unavailable"))?;
    if guard.is_some() || path.exists() {
        return Err(ApiError::new("vault_exists", "Close the active vault or choose a new path"));
    }

    let store = VaultStore::create_named(&name)?;
    VaultFile::save(&path, &store, password.as_bytes())?;
    let store = VaultFile::load(&path, password.as_bytes())?;
    *guard = Some(ActiveSession { path: path.clone(), store, dirty: false });
    remember_vault(&path, &name)?;
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
    let name = store.name().to_owned();
    *guard = Some(ActiveSession { path: path.clone(), store, dirty: false });
    remember_vault(&path, &name)?;
    Ok(())
}

#[tauri::command]
pub fn vault_catalog() -> Result<VaultCatalogDto, ApiError> {
    let mut app_config = config::load();
    if let Some(directory) = config::default_vault_directory() {
        fs::create_dir_all(&directory).map_err(|_| ApiError::new("storage_io", "Unable to prepare the default vault directory"))?;
        if !app_config.vault_directories.contains(&directory) {
            app_config.vault_directories.insert(0, directory);
        }
    }
    let directories = app_config.vault_directories.iter().filter(|path| path.is_dir()).cloned().collect::<Vec<_>>();
    let mut vaults = Vec::new();
    for directory in &directories {
        let entries = fs::read_dir(directory).map_err(|_| ApiError::new("storage_io", "Unable to read vault directory"))?;
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|extension| extension == "vault") && path.is_file() {
                let name = app_config.vault_names.get(&path).cloned().unwrap_or_else(|| "Unnamed vault".to_owned());
                vaults.push(VaultChoiceDto { path: path.to_string_lossy().into_owned(), name });
            }
        }
    }
    let _ = config::save(&app_config);
    Ok(VaultCatalogDto {
        directories: directories.into_iter().map(|path| path.to_string_lossy().into_owned()).collect(),
        vaults,
        last_vault: app_config.last_vault.map(|path| path.to_string_lossy().into_owned()),
        android: cfg!(target_os = "android"),
    })
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

fn validate_directory(value: String) -> Result<PathBuf, ApiError> {
    if value.trim().is_empty() {
        return Err(ApiError::invalid_request());
    }
    let path = PathBuf::from(value);
    if path.exists() && !path.is_dir() { return Err(ApiError::new("invalid_path", "The vault directory is not usable")); }
    fs::create_dir_all(&path).map_err(|_| ApiError::new("invalid_path", "The vault directory is not usable"))?;
    Ok(config::normalize_directory(&path))
}

fn validate_path(value: String) -> Result<PathBuf, ApiError> {
    let path = PathBuf::from(value);
    if !path.is_file() { return Err(ApiError::new("invalid_path", "The vault file is not usable")); }
    Ok(path)
}

fn remember_vault(path: &Path, name: &str) -> Result<(), ApiError> {
    let mut app_config = config::load();
    let directory = path.parent().ok_or_else(ApiError::invalid_request)?;
    let directory = config::normalize_directory(directory);
    app_config.vault_directories.retain(|candidate| candidate != &directory);
    app_config.vault_directories.insert(0, directory);
    app_config.vault_names.insert(path.to_path_buf(), name.to_owned());
    app_config.last_vault = Some(path.to_path_buf());
    config::save(&app_config).map_err(|_| ApiError::new("config_error", "Unable to save vault preferences"))
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
