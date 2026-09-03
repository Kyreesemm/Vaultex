#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;

#[cfg(target_os = "linux")]
fn configure_linux_graphics() {
    // WebKitGTK's DMA-BUF renderer can emit Wayland protocol errors on
    // current Linux/NVIDIA combinations. This must be set before GTK starts.
    if std::env::var_os("WAYLAND_DISPLAY").is_some()
        && std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none()
    {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
        std::env::set_var("__NV_DISABLE_EXPLICIT_SYNC", "1");
    }
}

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
    #[cfg(target_os = "linux")]
    configure_linux_graphics();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![vault_status])
        .run(tauri::generate_context!())
        .expect("error while running Vaultex");
}
