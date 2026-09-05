#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

pub mod vault;
pub mod storage;
pub mod persistence;
pub mod service;

#[cfg(target_os = "linux")]
fn configure_linux_graphics() {
    // On KDE Plasma under Wayland, GTK native decorations are client-side.
    // Running the GTK window through XWayland lets KWin draw its normal
    // Plasma decoration, matching the rest of the desktop applications.
    if std::env::var_os("WAYLAND_DISPLAY").is_some()
        && std::env::var_os("GDK_BACKEND").is_none()
    {
        std::env::set_var("GDK_BACKEND", "x11");
    }

    // WebKitGTK may still use a GBM/DMA-BUF path through XWayland. Disable it
    // for the Linux build unless the user has explicitly chosen another value.
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }

    if std::env::var_os("WAYLAND_DISPLAY").is_some()
        && std::env::var_os("__NV_DISABLE_EXPLICIT_SYNC").is_none()
    {
        std::env::set_var("__NV_DISABLE_EXPLICIT_SYNC", "1");
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[cfg(target_os = "linux")]
    configure_linux_graphics();

    tauri::Builder::default()
        .manage(service::AppState::default())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            service::vault_status,
            service::vault_create,
            service::vault_open,
            service::vault_lock,
            service::vault_save,
            service::record_list,
            service::record_read,
            service::record_create,
            service::record_update,
            service::record_delete,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Vaultex");
}
