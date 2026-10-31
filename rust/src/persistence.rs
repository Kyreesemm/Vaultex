use std::{
    fs::{self, File},
    io::{self, Write},
    path::{Path, PathBuf},
    time::SystemTime,
};
use rand_core::{OsRng, RngCore};
use thiserror::Error;

use crate::container::VaultStore;
use crate::crypto::VaultError;

const TEMP_NAME_ATTEMPTS: usize = 16;

#[derive(Debug, Error)]
pub enum PersistenceError {
    #[error("vault file I/O failed: {0}")]
    Io(#[from] io::Error),
    #[error("vault cryptographic operation failed: {0}")]
    Vault(#[from] VaultError),
    #[error("could not allocate a unique temporary vault path")]
    TemporaryPathUnavailable,
}

#[derive(Clone, Debug)]
pub struct FileMetadataSnapshot {
    pub modified: Option<SystemTime>,
    pub size: u64,
}

pub struct VaultFile;

impl VaultFile {
    pub fn load(path: &Path, password: &[u8]) -> Result<(VaultStore, FileMetadataSnapshot), PersistenceError> {
        let bytes = fs::read(path)?;
        let metadata = fs::metadata(path)?;
        let snapshot = FileMetadataSnapshot {
            modified: metadata.modified().ok(),
            size: metadata.len(),
        };
        let store = VaultStore::unlock(&bytes, password)?;
        Ok((store, snapshot))
    }

    pub fn save(
        path: &Path,
        store: &mut VaultStore,
        password: &[u8],
    ) -> Result<FileMetadataSnapshot, PersistenceError> {
        let bytes = store.commit_with_password(password)?;
        atomic_replace(path, &bytes)?;
        let metadata = fs::metadata(path)?;
        Ok(FileMetadataSnapshot {
            modified: metadata.modified().ok(),
            size: metadata.len(),
        })
    }

    pub fn save_unlocked(path: &Path, store: &VaultStore) -> Result<FileMetadataSnapshot, PersistenceError> {
        let bytes = store.commit_unlocked()?;
        atomic_replace(path, &bytes)?;
        let metadata = fs::metadata(path)?;
        Ok(FileMetadataSnapshot {
            modified: metadata.modified().ok(),
            size: metadata.len(),
        })
    }

    pub fn check_external_modification(path: &Path, last_snapshot: &FileMetadataSnapshot) -> bool {
        if let Ok(metadata) = fs::metadata(path) {
            let current_mod = metadata.modified().ok();
            let current_len = metadata.len();
            if current_len != last_snapshot.size {
                return true;
            }
            if let (Some(m1), Some(m2)) = (current_mod, last_snapshot.modified) {
                if m1 != m2 {
                    return true;
                }
            }
        }
        false
    }
}

pub fn atomic_replace(path: &Path, bytes: &[u8]) -> Result<(), PersistenceError> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;
    let temporary_path = temporary_path(parent, path.file_name().unwrap_or_default())?;

    let result = write_temporary_file(&temporary_path, bytes)
        .and_then(|_| replace_file(&temporary_path, path))
        .and_then(|_| sync_parent_directory(parent));

    if result.is_err() {
        let _ = fs::remove_file(&temporary_path);
    }

    result.map_err(PersistenceError::from)
}

fn temporary_path(parent: &Path, filename: &std::ffi::OsStr) -> Result<PathBuf, PersistenceError> {
    let mut random = [0u8; 16];

    for _ in 0..TEMP_NAME_ATTEMPTS {
        OsRng
            .try_fill_bytes(&mut random)
            .map_err(|_| PersistenceError::TemporaryPathUnavailable)?;
        let suffix = random.iter().map(|b| format!("{b:02x}")).collect::<String>();
        let candidate = parent.join(format!(".{}.{}.tmp", filename.to_string_lossy(), suffix));
        if !candidate.exists() {
            return Ok(candidate);
        }
    }

    Err(PersistenceError::TemporaryPathUnavailable)
}

fn write_temporary_file(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);

    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }

    let mut file = options.open(path)?;
    file.write_all(bytes)?;
    file.sync_all()
}

#[cfg(unix)]
fn replace_file(temporary: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(temporary, destination)?;
    let mut permissions = fs::metadata(destination)?.permissions();
    use std::os::unix::fs::PermissionsExt;
    permissions.set_mode(0o600);
    fs::set_permissions(destination, permissions)
}

#[cfg(windows)]
fn replace_file(temporary: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(temporary, destination)
}

#[cfg(not(any(unix, windows)))]
fn replace_file(temporary: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(temporary, destination)
}

fn sync_parent_directory(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    {
        File::open(path)?.sync_all()?;
    }
    let _ = path;
    Ok(())
}
