use std::{collections::BTreeMap, env, fs, io, path::{Path, PathBuf}};

use serde::{Deserialize, Serialize};

#[derive(Debug, Default, Deserialize, Serialize)]
pub struct AppConfig {
    pub vault_directories: Vec<PathBuf>,
    pub vault_names: BTreeMap<PathBuf, String>,
    pub last_vault: Option<PathBuf>,
}

pub fn load() -> AppConfig {
    config_path().and_then(|path| fs::read(path).ok()).and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default()
}

pub fn save(config: &AppConfig) -> io::Result<()> {
    let path = config_path().ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "application path unavailable"))?;
    let directory = path.parent().ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "config directory unavailable"))?;
    fs::create_dir_all(directory)?;
    let temporary = path.with_extension("json.tmp");
    fs::write(&temporary, serde_json::to_vec_pretty(config).map_err(io::Error::other)?)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&temporary, fs::Permissions::from_mode(0o600))?;
    }
    fs::rename(temporary, path)
}

pub fn default_vault_directory() -> Option<PathBuf> {
    #[cfg(target_os = "android")]
    return None;
    #[cfg(target_os = "windows")]
    { env::var_os("LOCALAPPDATA").map(PathBuf::from).or_else(|| env::var_os("USERPROFILE").map(|path| PathBuf::from(path).join("AppData").join("Local"))).map(|path| path.join("Vaultex").join("Vaults")) }
    #[cfg(target_os = "linux")]
    { env::var_os("XDG_DATA_HOME").map(PathBuf::from).or_else(|| env::var_os("HOME").map(|path| PathBuf::from(path).join(".local").join("share"))).map(|path| path.join("Vaultex").join("Vaults")) }
    #[cfg(not(any(target_os = "android", target_os = "windows", target_os = "linux")))]
    None
}

fn config_path() -> Option<PathBuf> {
    env::current_exe().ok()?.parent().map(|directory| directory.join("config").join("vaultex.json"))
}

pub fn normalize_directory(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}
