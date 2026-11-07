use std::{
    path::PathBuf,
    sync::Mutex,
};
use rand_core::{OsRng, RngCore};
use zeroize::Zeroizing;

use crate::{
    container::{RecordId, VaultStore},
    model::{
        current_iso_timestamp, RecordKind, RecordPayload, VaultEntryView,
    },
    persistence::{FileMetadataSnapshot, VaultFile},
};

pub struct ActiveSession {
    pub path: PathBuf,
    pub store: VaultStore,
    pub snapshot: FileMetadataSnapshot,
    pub dirty: bool,
}

static SESSION: Mutex<Option<ActiveSession>> = Mutex::new(None);

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct VaultSessionInfo {
    pub is_unlocked: bool,
    pub name: Option<String>,
    pub path: Option<String>,
    pub record_count: usize,
    pub is_dirty: bool,
    pub external_conflict: bool,
}

pub struct SessionManager;

impl SessionManager {
    pub fn is_unlocked() -> bool {
        let guard = SESSION.lock().unwrap();
        guard.is_some()
    }

    pub fn get_info() -> VaultSessionInfo {
        let guard = SESSION.lock().unwrap();
        match guard.as_ref() {
            Some(active) => {
                let external_conflict =
                    VaultFile::check_external_modification(&active.path, &active.snapshot);
                VaultSessionInfo {
                    is_unlocked: true,
                    name: Some(active.store.name().to_string()),
                    path: Some(active.path.to_string_lossy().to_string()),
                    record_count: active.store.record_count(),
                    is_dirty: active.dirty,
                    external_conflict,
                }
            }
            None => VaultSessionInfo {
                is_unlocked: false,
                name: None,
                path: None,
                record_count: 0,
                is_dirty: false,
                external_conflict: false,
            },
        }
    }

    pub fn open(path_str: &str, password: &str) -> Result<VaultSessionInfo, String> {
        let path = PathBuf::from(path_str);
        if !path.exists() {
            return Err("Файл хранилища не найден".to_string());
        }

        let password_bytes = Zeroizing::new(password.as_bytes().to_vec());
        let (store, snapshot) = VaultFile::load(&path, &password_bytes)
            .map_err(|e| format!("Ошибка открытия хранилища: {}", e))?;

        let mut guard = SESSION.lock().unwrap();
        if let Some(old) = guard.take() {
            old.store.lock();
        }

        let info = VaultSessionInfo {
            is_unlocked: true,
            name: Some(store.name().to_string()),
            path: Some(path.to_string_lossy().to_string()),
            record_count: store.record_count(),
            is_dirty: false,
            external_conflict: false,
        };

        *guard = Some(ActiveSession {
            path,
            store,
            snapshot,
            dirty: false,
        });

        Ok(info)
    }

    pub fn create(
        directory: &str,
        name: &str,
        password: &str,
    ) -> Result<VaultSessionInfo, String> {
        let dir = PathBuf::from(directory);
        std::fs::create_dir_all(&dir)
            .map_err(|e| format!("Невозможно создать директорию: {}", e))?;

        let safe_name: String = name
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
            .collect();
        let safe_name = if safe_name.trim().is_empty() {
            "vault".to_string()
        } else {
            safe_name
        };

        let filename = format!("{}.vex", safe_name);
        let mut path = dir.join(&filename);
        let mut counter = 1;
        while path.exists() {
            path = dir.join(format!("{}-{}.vex", safe_name, counter));
            counter += 1;
        }

        let mut store = VaultStore::create_named(name)
            .map_err(|e| format!("Ошибка создания хранилища: {}", e))?;

        let password_bytes = Zeroizing::new(password.as_bytes().to_vec());
        let _snapshot = VaultFile::save(&path, &mut store, &password_bytes)
            .map_err(|e| format!("Ошибка сохранения нового хранилища: {}", e))?;

        // Reopen to get valid wrapped key for commit_unlocked
        let (store, snapshot) = VaultFile::load(&path, &password_bytes)
            .map_err(|e| format!("Ошибка инициализации сессии: {}", e))?;

        let mut guard = SESSION.lock().unwrap();
        if let Some(old) = guard.take() {
            old.store.lock();
        }

        let info = VaultSessionInfo {
            is_unlocked: true,
            name: Some(store.name().to_string()),
            path: Some(path.to_string_lossy().to_string()),
            record_count: store.record_count(),
            is_dirty: false,
            external_conflict: false,
        };

        *guard = Some(ActiveSession {
            path,
            store,
            snapshot,
            dirty: false,
        });

        Ok(info)
    }

    pub fn save() -> Result<(), String> {
        let mut guard = SESSION.lock().unwrap();
        let session = guard.as_mut().ok_or("Хранилище заблокировано")?;
        if session.dirty {
            let snapshot = VaultFile::save_unlocked(&session.path, &session.store)
                .map_err(|e| format!("Ошибка сохранения: {}", e))?;
            session.snapshot = snapshot;
            session.dirty = false;
        }
        Ok(())
    }

    pub fn lock() -> Result<(), String> {
        let mut guard = SESSION.lock().unwrap();
        if let Some(session) = guard.take() {
            if session.dirty {
                let _ = VaultFile::save_unlocked(&session.path, &session.store);
            }
            session.store.lock();
        }
        Ok(())
    }

    pub fn check_conflict() -> bool {
        let guard = SESSION.lock().unwrap();
        if let Some(session) = guard.as_ref() {
            VaultFile::check_external_modification(&session.path, &session.snapshot)
        } else {
            false
        }
    }

    pub fn change_password(new_password: &str) -> Result<(), String> {
        let mut guard = SESSION.lock().unwrap();
        let session = guard.as_mut().ok_or("Хранилище заблокировано")?;
        session
            .store
            .change_password(new_password.as_bytes())
            .map_err(|e| format!("Ошибка смены пароля: {}", e))?;
        session.dirty = true;
        let snapshot = VaultFile::save_unlocked(&session.path, &session.store)
            .map_err(|e| format!("Ошибка сохранения после смены пароля: {}", e))?;
        session.snapshot = snapshot;
        session.dirty = false;
        Ok(())
    }

    pub fn list_entries(
        kind_filter: Option<String>,
        query: Option<String>,
    ) -> Result<Vec<VaultEntryView>, String> {
        let guard = SESSION.lock().unwrap();
        let session = guard.as_ref().ok_or("Хранилище заблокировано")?;

        let query_lower = query.map(|q| q.to_lowercase().trim().to_string());
        let kind_enum = kind_filter.as_deref().and_then(RecordKind::from_str);

        let mut entries = Vec::new();

        for (id, record) in session.store.list() {
            if let Some(filter) = kind_enum {
                if record.kind != filter {
                    continue;
                }
            }

            let payload: RecordPayload = serde_json::from_slice(&record.payload)
                .unwrap_or_else(|_| RecordPayload::Legacy {
                    title: "Запись".to_string(),
                    content: String::from_utf8_lossy(&record.payload).to_string(),
                    updated_at: None,
                });

            let title = payload.title();
            let subtitle = payload.subtitle();
            let tags = payload.tags();

            if let Some(q) = &query_lower {
                if !q.is_empty() {
                    let matches_title = title.to_lowercase().contains(q);
                    let matches_sub = subtitle.to_lowercase().contains(q);
                    let matches_tag = tags.iter().any(|t| t.to_lowercase().contains(q));
                    if !matches_title && !matches_sub && !matches_tag {
                        continue;
                    }
                }
            }

            let payload_json = serde_json::to_string(&payload).unwrap_or_default();

            entries.push(VaultEntryView {
                id: id.to_hex(),
                kind: record.kind.as_str().to_string(),
                title,
                subtitle,
                tags,
                revision: record.revision,
                updated_at: current_iso_timestamp(),
                payload_json,
            });
        }

        // Sort by title
        entries.sort_by(|a, b| a.title.to_lowercase().cmp(&b.title.to_lowercase()));
        Ok(entries)
    }

    pub fn get_entry(id_str: &str) -> Result<VaultEntryView, String> {
        let guard = SESSION.lock().unwrap();
        let session = guard.as_ref().ok_or("Хранилище заблокировано")?;

        let id = RecordId::from_hex(id_str).map_err(|e| format!("Неверный ID: {}", e))?;
        let record = session.store.get(id).ok_or("Запись не найдена")?;

        let payload: RecordPayload = serde_json::from_slice(&record.payload)
            .unwrap_or_else(|_| RecordPayload::Legacy {
                title: "Запись".to_string(),
                content: String::from_utf8_lossy(&record.payload).to_string(),
                updated_at: None,
            });

        let payload_json = serde_json::to_string(&payload).unwrap_or_default();

        Ok(VaultEntryView {
            id: id.to_hex(),
            kind: record.kind.as_str().to_string(),
            title: payload.title(),
            subtitle: payload.subtitle(),
            tags: payload.tags(),
            revision: record.revision,
            updated_at: current_iso_timestamp(),
            payload_json,
        })
    }

    pub fn upsert_payload(
        id_opt: Option<String>,
        kind: RecordKind,
        payload: RecordPayload,
    ) -> Result<String, String> {
        let mut guard = SESSION.lock().unwrap();
        let session = guard.as_mut().ok_or("Хранилище заблокировано")?;

        let serialized = serde_json::to_vec(&payload)
            .map_err(|e| format!("Ошибка сериализации данных: {}", e))?;

        let entry_id = match id_opt {
            Some(id_str) if !id_str.trim().is_empty() => {
                let id = RecordId::from_hex(&id_str)
                    .map_err(|e| format!("Неверный ID: {}", e))?;
                session
                    .store
                    .update(id, serialized)
                    .map_err(|e| format!("Ошибка обновления: {}", e))?;
                id_str
            }
            _ => {
                let id = session
                    .store
                    .insert(kind, serialized)
                    .map_err(|e| format!("Ошибка добавления: {}", e))?;
                id.to_hex()
            }
        };

        session.dirty = true;
        // Auto-save unlocked to keep container fresh
        let snapshot = VaultFile::save_unlocked(&session.path, &session.store)
            .map_err(|e| format!("Ошибка сохранения: {}", e))?;
        session.snapshot = snapshot;
        session.dirty = false;

        Ok(entry_id)
    }

    pub fn delete_entry(id_str: &str) -> Result<(), String> {
        let mut guard = SESSION.lock().unwrap();
        let session = guard.as_mut().ok_or("Хранилище заблокировано")?;

        let id = RecordId::from_hex(id_str).map_err(|e| format!("Неверный ID: {}", e))?;
        session
            .store
            .remove(id)
            .map_err(|e| format!("Ошибка удаления: {}", e))?;

        session.dirty = true;
        let snapshot = VaultFile::save_unlocked(&session.path, &session.store)
            .map_err(|e| format!("Ошибка сохранения: {}", e))?;
        session.snapshot = snapshot;
        session.dirty = false;
        Ok(())
    }

    pub fn export_bytes() -> Result<Vec<u8>, String> {
        let guard = SESSION.lock().unwrap();
        let session = guard.as_ref().ok_or("Хранилище заблокировано")?;
        session
            .store
            .commit_unlocked()
            .map_err(|e| format!("Ошибка экспорта хранилища: {}", e))
    }

    pub fn import_bytes(dest_path_str: &str, bytes: &[u8]) -> Result<(), String> {
        let dest = PathBuf::from(dest_path_str);
        crate::persistence::atomic_replace(&dest, bytes)
            .map_err(|e| format!("Ошибка импорта: {}", e))?;
        Ok(())
    }
}

pub fn generate_password(length: usize, include_symbols: bool, include_numbers: bool) -> String {
    let mut chars = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".to_vec();
    if include_numbers {
        chars.extend_from_slice(b"0123456789");
    }
    if include_symbols {
        chars.extend_from_slice(b"!@#$%^&*()-_=+[]{}|;:,.<>?");
    }

    let mut result = Vec::with_capacity(length);
    let mut random_bytes = vec![0u8; length];
    let _ = OsRng.try_fill_bytes(&mut random_bytes);

    for b in random_bytes {
        let idx = (b as usize) % chars.len();
        result.push(chars[idx]);
    }

    String::from_utf8(result).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_session_lifecycle_and_entities() {
        let dir = tempdir().unwrap();
        let dir_str = dir.path().to_str().unwrap();

        // 1. Create vault
        let info = SessionManager::create(dir_str, "Work Vault", "MasterP@ssw0rd!").unwrap();
        assert!(info.is_unlocked);
        assert_eq!(info.name.as_deref(), Some("Work Vault"));
        assert_eq!(info.record_count, 0);
        assert!(info.path.as_ref().unwrap().ends_with(".vex"));

        // 2. Insert Account
        let acc_id = SessionManager::upsert_payload(
            None,
            RecordKind::Account,
            RecordPayload::Account(crate::model::AccountData {
                service: "GitHub".to_string(),
                username: "octocat".to_string(),
                email: "octo@github.com".to_string(),
                password: "SecretGitHubPassword123".to_string(),
                phone: None,
                two_factor_secret: Some("JBSWY3DPEHPK3PXP".to_string()),
                url: Some("https://github.com".to_string()),
                notes: Some("Main work account".to_string()),
            }),
        )
        .unwrap();

        // 3. Insert Token
        let token_id = SessionManager::upsert_payload(
            None,
            RecordKind::ApiToken,
            RecordPayload::ApiToken(crate::model::ApiTokenData {
                name: "OpenAI Prod".to_string(),
                token: "sk-proj-123456789".to_string(),
                expires_at: Some("2026-12-31".to_string()),
                tags: vec!["ai".to_string(), "prod".to_string()],
                notes: None,
            }),
        )
        .unwrap();

        // 4. Insert SecretRecovery
        let secret_id = SessionManager::upsert_payload(
            None,
            RecordKind::Secret,
            RecordPayload::SecretRecovery(crate::model::SecretRecoveryData {
                name: "Ledger 24 words".to_string(),
                secret_type: "mnemonic".to_string(),
                value: "witch collapse practice feed shame open despair creek road again ice least".to_string(),
                notes: None,
            }),
        )
        .unwrap();

        // 5. Insert Note
        let note_id = SessionManager::upsert_payload(
            None,
            RecordKind::Note,
            RecordPayload::Note(crate::model::NoteData {
                title: "Architecture Roadmap".to_string(),
                content: "# Security Architecture\n\n- Argon2id KDF\n- AES-256-GCM\n- Zeroize".to_string(),
                tags: vec!["dev".to_string(), "security".to_string()],
            }),
        )
        .unwrap();

        // Verify count
        let entries = SessionManager::list_entries(None, None).unwrap();
        assert_eq!(entries.len(), 4);

        // Filter by kind
        let accounts = SessionManager::list_entries(Some("account".to_string()), None).unwrap();
        assert_eq!(accounts.len(), 1);
        assert_eq!(accounts[0].title, "GitHub");

        let notes = SessionManager::list_entries(Some("note".to_string()), None).unwrap();
        assert_eq!(notes.len(), 1);
        assert_eq!(notes[0].title, "Architecture Roadmap");

        // Filter by search query
        let search_res = SessionManager::list_entries(None, Some("OpenAI".to_string())).unwrap();
        assert_eq!(search_res.len(), 1);
        assert_eq!(search_res[0].id, token_id);

        // Get single entry
        let fetched_acc = SessionManager::get_entry(&acc_id).unwrap();
        assert!(fetched_acc.payload_json.contains("octo@github.com"));

        // Update entry
        let _ = SessionManager::upsert_payload(
            Some(note_id.clone()),
            RecordKind::Note,
            RecordPayload::Note(crate::model::NoteData {
                title: "Architecture Roadmap v2".to_string(),
                content: "# Updated Roadmap".to_string(),
                tags: vec!["v2".to_string()],
            }),
        )
        .unwrap();

        let updated_note = SessionManager::get_entry(&note_id).unwrap();
        assert_eq!(updated_note.title, "Architecture Roadmap v2");

        // Lock vault
        let vault_path = SessionManager::get_info().path.unwrap();
        SessionManager::lock().unwrap();
        assert!(!SessionManager::is_unlocked());

        // Reopen vault
        let reopened_info = SessionManager::open(&vault_path, "MasterP@ssw0rd!").unwrap();
        assert!(reopened_info.is_unlocked);
        assert_eq!(reopened_info.record_count, 4);

        // Delete entry
        SessionManager::delete_entry(&secret_id).unwrap();
        let remaining = SessionManager::list_entries(None, None).unwrap();
        assert_eq!(remaining.len(), 3);

        // Lock again
        SessionManager::lock().unwrap();
    }
}
