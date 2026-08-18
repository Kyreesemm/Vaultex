use serde::Serialize;
use std::{fs, path::PathBuf, sync::Mutex, time::{SystemTime, UNIX_EPOCH}};
use tauri::{AppHandle, Manager, State};
use vaultex_core::{Entry, Vault};

#[derive(Default)]
struct VaultState {
    vault: Option<Vault>,
    password: Option<String>,
    path: Option<PathBuf>,
}

#[derive(Debug, Serialize)]
struct EntryView {
    id: String,
    title: String,
    username: Option<String>,
    password: Option<String>,
    notes: Option<String>,
}

#[derive(Debug, Serialize)]
struct VaultStatus {
    exists: bool,
    unlocked: bool,
    entries: Vec<EntryView>,
}

#[derive(Debug, serde::Deserialize)]
struct NewEntry {
    title: String,
    username: Option<String>,
    password: Option<String>,
    notes: Option<String>,
}

fn vault_path(app: &AppHandle) -> Result<PathBuf, String> {
    let directory = app.path().app_data_dir().map_err(|error| error.to_string())?;
    fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
    Ok(directory.join("vault.vlt"))
}

fn entries(vault: &Vault) -> Vec<EntryView> {
    vault.entries().iter().map(|(id, entry)| EntryView {
        id: id.clone(),
        title: entry.title.clone(),
        username: entry.username.clone(),
        password: entry.password.clone(),
        notes: entry.notes.clone(),
    }).collect()
}

fn persist(state: &VaultState) -> Result<(), String> {
    let vault = state.vault.as_ref().ok_or("Vault is locked")?;
    let password = state.password.as_deref().ok_or("Vault is locked")?;
    let path = state.path.as_ref().ok_or("Vault path is unavailable")?;
    let container = vault.seal(password).map_err(|error| error.to_string())?;
    fs::write(path, container).map_err(|error| error.to_string())
}

#[tauri::command]
fn vault_status(app: AppHandle, state: State<'_, Mutex<VaultState>>) -> Result<VaultStatus, String> {
    let path = vault_path(&app)?;
    let state = state.lock().map_err(|_| "Vault state is unavailable")?;
    Ok(VaultStatus {
        exists: path.exists(),
        unlocked: state.vault.is_some(),
        entries: state.vault.as_ref().map(entries).unwrap_or_default(),
    })
}

#[tauri::command]
fn create_vault(app: AppHandle, password: String, state: State<'_, Mutex<VaultState>>) -> Result<VaultStatus, String> {
    if password.trim().is_empty() {
        return Err("Master password cannot be empty".into());
    }
    let path = vault_path(&app)?;
    if path.exists() {
        return Err("A vault already exists on this device".into());
    }
    let mut state = state.lock().map_err(|_| "Vault state is unavailable")?;
    state.vault = Some(Vault::new());
    state.password = Some(password);
    state.path = Some(path);
    persist(&state)?;
    Ok(VaultStatus { exists: true, unlocked: true, entries: Vec::new() })
}

#[tauri::command]
fn unlock_vault(app: AppHandle, password: String, state: State<'_, Mutex<VaultState>>) -> Result<VaultStatus, String> {
    let path = vault_path(&app)?;
    let container = fs::read(&path).map_err(|_| "No vault exists on this device".to_string())?;
    let vault = Vault::open(&container, &password).map_err(|error| error.to_string())?;
    let result = VaultStatus { exists: true, unlocked: true, entries: entries(&vault) };
    let mut state = state.lock().map_err(|_| "Vault state is unavailable")?;
    state.vault = Some(vault);
    state.password = Some(password);
    state.path = Some(path);
    Ok(result)
}

#[tauri::command]
fn lock_vault(state: State<'_, Mutex<VaultState>>) -> Result<(), String> {
    let mut state = state.lock().map_err(|_| "Vault state is unavailable")?;
    state.vault = None;
    state.password = None;
    Ok(())
}

#[tauri::command]
fn add_entry(entry: NewEntry, state: State<'_, Mutex<VaultState>>) -> Result<VaultStatus, String> {
    if entry.title.trim().is_empty() {
        return Err("Entry title cannot be empty".into());
    }
    let mut state = state.lock().map_err(|_| "Vault state is unavailable")?;
    let id = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| "System clock is invalid")?.as_nanos().to_string();
    state.vault.as_mut().ok_or("Unlock the vault first")?.insert(id, Entry { title: entry.title, username: entry.username, password: entry.password, notes: entry.notes });
    persist(&state)?;
    let vault = state.vault.as_ref().ok_or("Unlock the vault first")?;
    Ok(VaultStatus { exists: true, unlocked: true, entries: entries(vault) })
}

#[tauri::command]
fn delete_entry(id: String, state: State<'_, Mutex<VaultState>>) -> Result<VaultStatus, String> {
    let mut state = state.lock().map_err(|_| "Vault state is unavailable")?;
    state.vault.as_mut().ok_or("Unlock the vault first")?.remove(&id).ok_or("Entry not found")?;
    persist(&state)?;
    let vault = state.vault.as_ref().ok_or("Unlock the vault first")?;
    Ok(VaultStatus { exists: true, unlocked: true, entries: entries(vault) })
}

#[tauri::command]
fn generate_password(length: Option<usize>) -> Result<String, String> {
    let length = length.unwrap_or(20).clamp(8, 64);
    let alphabet = b"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*";
    let mut bytes = vec![0u8; length];
    getrandom::getrandom(&mut bytes).map_err(|error| error.to_string())?;
    Ok(bytes.into_iter().map(|byte| alphabet[byte as usize % alphabet.len()] as char).collect())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(Mutex::new(VaultState::default()))
        .invoke_handler(tauri::generate_handler![
            vault_status,
            create_vault,
            unlock_vault,
            lock_vault,
            add_entry,
            delete_entry,
            generate_password,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Vaultex");
}
