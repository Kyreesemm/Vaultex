#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;

#[derive(Clone, Serialize)]
struct VaultStatus {
    locked: bool,
    algorithm: &'static str,
}

#[tauri::command]
fn vault_status() -> VaultStatus {
    VaultStatus { locked: false, algorithm: "AES-256-GCM" }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![vault_status])
        .run(tauri::generate_context!())
        .expect("error while running Vaultex");
}

