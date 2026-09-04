use std::{fs, fs::File, io, io::Write, path::{Path, PathBuf}};

use rand_core::{OsRng, RngCore};
use thiserror::Error;

use crate::{storage::VaultStore, vault::VaultError};

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

pub struct VaultFile;

impl VaultFile {
    pub fn load(path: &Path, password: &[u8]) -> Result<VaultStore, PersistenceError> {
        let bytes = fs::read(path)?;
        Ok(VaultStore::unlock(&bytes, password)?)
    }

    pub fn save(
        path: &Path,
        store: &VaultStore,
        password: &[u8],
    ) -> Result<(), PersistenceError> {
        let bytes = store.commit(password)?;
        atomic_replace(path, &bytes)
    }

    pub fn save_unlocked(path: &Path, store: &VaultStore) -> Result<(), PersistenceError> {
        let bytes = store.commit_unlocked()?;
        atomic_replace(path, &bytes)
    }
}

fn atomic_replace(path: &Path, bytes: &[u8]) -> Result<(), PersistenceError> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
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
        let suffix = random.iter().map(|byte| format!("{byte:02x}")).collect::<String>();
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
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
    };

    let source = temporary.as_os_str().encode_wide().chain(Some(0)).collect::<Vec<_>>();
    let target = destination.as_os_str().encode_wide().chain(Some(0)).collect::<Vec<_>>();
    let flags = MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH;
    let moved = unsafe { MoveFileExW(source.as_ptr(), target.as_ptr(), flags) };
    if moved == 0 { Err(io::Error::last_os_error()) } else { Ok(()) }
}

#[cfg(unix)]
fn sync_parent_directory(parent: &Path) -> io::Result<()> {
    File::open(parent)?.sync_all()
}

#[cfg(not(unix))]
fn sync_parent_directory(_parent: &Path) -> io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::RecordKind;

    const PASSWORD: &[u8] = b"persistent vault password";

    #[test]
    fn save_and_load_round_trip() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("personal.vault");
        let mut store = VaultStore::create().unwrap();
        let id = store.insert(RecordKind::Note, b"disk-backed secret".to_vec()).unwrap();

        VaultFile::save(&path, &store, PASSWORD).unwrap();
        let restored = VaultFile::load(&path, PASSWORD).unwrap();

        assert_eq!(&*restored.get(id).unwrap().payload, b"disk-backed secret");
        assert!(!fs::read(&path).unwrap().windows(18).any(|part| part == b"disk-backed secret"));
    }

    #[test]
    fn failed_password_does_not_load_file() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("personal.vault");
        let store = VaultStore::create().unwrap();
        VaultFile::save(&path, &store, PASSWORD).unwrap();

        assert!(matches!(
            VaultFile::load(&path, b"wrong password"),
            Err(PersistenceError::Vault(VaultError::Decryption))
        ));
    }

    #[test]
    fn unlocked_session_can_save_without_password() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("personal.vault");
        let second_path = directory.path().join("personal-2.vault");
        let mut store = VaultStore::create().unwrap();
        store.insert(RecordKind::Secret, b"session secret".to_vec()).unwrap();
        VaultFile::save(&path, &store, PASSWORD).unwrap();

        let restored = VaultFile::load(&path, PASSWORD).unwrap();
        VaultFile::save_unlocked(&second_path, &restored).unwrap();
        assert!(VaultFile::load(&second_path, PASSWORD).is_ok());
    }

    #[test]
    fn new_session_requires_password_for_first_save() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("new.vault");
        let store = VaultStore::create().unwrap();
        assert!(matches!(
            VaultFile::save_unlocked(&path, &store),
            Err(PersistenceError::Vault(VaultError::MissingWrappedKey))
        ));
    }
}
