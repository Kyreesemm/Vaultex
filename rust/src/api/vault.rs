use crate::{
    model::{AccountData, ApiTokenData, NoteData, RecordKind, RecordPayload, SecretRecoveryData},
    session::{generate_password as gen_pwd, SessionManager},
};

#[derive(Clone, Debug)]
pub struct VaultInfo {
    pub is_unlocked: bool,
    pub name: Option<String>,
    pub path: Option<String>,
    pub record_count: u32,
    pub is_dirty: bool,
    pub external_conflict: bool,
}

#[derive(Clone, Debug)]
pub struct VaultEntryItem {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub subtitle: String,
    pub tags: Vec<String>,
    pub revision: u64,
    pub payload_json: String,
}

#[derive(Clone, Debug)]
pub struct LocalVaultItem {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub last_modified: String,
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub fn get_vault_info() -> VaultInfo {
    let info = SessionManager::get_info();
    VaultInfo {
        is_unlocked: info.is_unlocked,
        name: info.name,
        path: info.path,
        record_count: info.record_count as u32,
        is_dirty: info.is_dirty,
        external_conflict: info.external_conflict,
    }
}

pub fn open_vault(path: String, password: String) -> Result<VaultInfo, String> {
    let info = SessionManager::open(&path, &password)?;
    Ok(VaultInfo {
        is_unlocked: info.is_unlocked,
        name: info.name,
        path: info.path,
        record_count: info.record_count as u32,
        is_dirty: info.is_dirty,
        external_conflict: info.external_conflict,
    })
}

pub fn create_vault(directory: String, name: String, password: String) -> Result<VaultInfo, String> {
    let info = SessionManager::create(&directory, &name, &password)?;
    Ok(VaultInfo {
        is_unlocked: info.is_unlocked,
        name: info.name,
        path: info.path,
        record_count: info.record_count as u32,
        is_dirty: info.is_dirty,
        external_conflict: info.external_conflict,
    })
}

pub fn lock_vault() -> Result<(), String> {
    SessionManager::lock()
}

pub fn save_vault() -> Result<(), String> {
    SessionManager::save()
}

pub fn check_sync_conflict() -> bool {
    SessionManager::check_conflict()
}

pub fn change_vault_password(new_password: String) -> Result<(), String> {
    SessionManager::change_password(&new_password)
}

pub fn list_entries(
    kind_filter: Option<String>,
    query: Option<String>,
) -> Result<Vec<VaultEntryItem>, String> {
    let list = SessionManager::list_entries(kind_filter, query)?;
    Ok(list
        .into_iter()
        .map(|v| VaultEntryItem {
            id: v.id,
            kind: v.kind,
            title: v.title,
            subtitle: v.subtitle,
            tags: v.tags,
            revision: v.revision,
            payload_json: v.payload_json,
        })
        .collect())
}

pub fn get_entry(id: String) -> Result<VaultEntryItem, String> {
    let v = SessionManager::get_entry(&id)?;
    Ok(VaultEntryItem {
        id: v.id,
        kind: v.kind,
        title: v.title,
        subtitle: v.subtitle,
        tags: v.tags,
        revision: v.revision,
        payload_json: v.payload_json,
    })
}

pub fn save_account(
    id: Option<String>,
    service: String,
    username: String,
    email: String,
    password: String,
    phone: Option<String>,
    two_factor_secret: Option<String>,
    url: Option<String>,
    notes: Option<String>,
) -> Result<String, String> {
    let account = AccountData {
        service,
        username,
        email,
        password,
        phone,
        two_factor_secret,
        url,
        notes,
    };
    SessionManager::upsert_payload(id, RecordKind::Account, RecordPayload::Account(account))
}

pub fn save_api_token(
    id: Option<String>,
    name: String,
    token: String,
    expires_at: Option<String>,
    tags: Vec<String>,
    notes: Option<String>,
) -> Result<String, String> {
    let api_token = ApiTokenData {
        name,
        token,
        expires_at,
        tags,
        notes,
    };
    SessionManager::upsert_payload(id, RecordKind::ApiToken, RecordPayload::ApiToken(api_token))
}

pub fn save_secret_recovery(
    id: Option<String>,
    name: String,
    secret_type: String,
    value: String,
    notes: Option<String>,
) -> Result<String, String> {
    let secret = SecretRecoveryData {
        name,
        secret_type,
        value,
        notes,
    };
    SessionManager::upsert_payload(
        id,
        RecordKind::Secret,
        RecordPayload::SecretRecovery(secret),
    )
}

pub fn save_note(
    id: Option<String>,
    title: String,
    content: String,
    tags: Vec<String>,
) -> Result<String, String> {
    let note = NoteData {
        title,
        content,
        tags,
    };
    SessionManager::upsert_payload(id, RecordKind::Note, RecordPayload::Note(note))
}

pub fn delete_entry(id: String) -> Result<(), String> {
    SessionManager::delete_entry(&id)
}

pub fn list_vault_files(directory: String) -> Vec<LocalVaultItem> {
    let dir_path = std::path::PathBuf::from(&directory);
    let mut result = Vec::new();

    if let Ok(entries) = std::fs::read_dir(dir_path) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() && path.extension().is_some_and(|ext| ext == "vault") {
                let metadata = entry.metadata().ok();
                let size_bytes = metadata.as_ref().map(|m| m.len()).unwrap_or(0);
                let last_modified = metadata
                    .and_then(|m| m.modified().ok())
                    .map(|t| {
                        let dt: chrono::DateTime<chrono::Utc> = t.into();
                        dt.to_rfc3339()
                    })
                    .unwrap_or_default();

                let file_stem = path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("vault")
                    .to_string();

                result.push(LocalVaultItem {
                    name: file_stem,
                    path: path.to_string_lossy().to_string(),
                    size_bytes,
                    last_modified,
                });
            }
        }
    }

    result.sort_by(|a, b| b.last_modified.cmp(&a.last_modified));
    result
}

pub fn export_vault_bytes() -> Result<Vec<u8>, String> {
    SessionManager::export_bytes()
}

pub fn import_vault_bytes(destination_path: String, bytes: Vec<u8>) -> Result<(), String> {
    SessionManager::import_bytes(&destination_path, &bytes)
}

pub fn generate_secure_password(
    length: u32,
    include_symbols: bool,
    include_numbers: bool,
) -> String {
    gen_pwd(length.max(8) as usize, include_symbols, include_numbers)
}
