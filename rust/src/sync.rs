use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::Path;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CloudVaultItem {
    pub id: String,
    pub name: String,
    pub size_bytes: u64,
    pub modified_time: String,
}

#[derive(Deserialize)]
struct DriveFileListResponse {
    files: Option<Vec<DriveFileItem>>,
}

#[derive(Deserialize)]
struct DriveFileItem {
    id: Option<String>,
    name: Option<String>,
    size: Option<String>,
    #[serde(rename = "modifiedTime")]
    modified_time: Option<String>,
}

#[derive(Deserialize)]
struct DriveUploadResponse {
    id: Option<String>,
    name: Option<String>,
    #[serde(rename = "modifiedTime")]
    modified_time: Option<String>,
}

const DRIVE_FILES_URL: &str = "https://www.googleapis.com/drive/v3/files";
const DRIVE_UPLOAD_MULTIPART_URL: &str =
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart";

pub fn list_drive_vaults(
    access_token: &str,
    extension: &str,
) -> Result<Vec<CloudVaultItem>, String> {
    let clean_token = access_token.trim();
    if clean_token.is_empty() {
        return Err("Требуется Google Drive Access Token".to_string());
    }

    let ext = extension.trim_start_matches('.');
    let query = format!("name contains '.{ext}' and trashed = false");
    let url = format!(
        "{}?q={}&fields=files(id,name,size,modifiedTime)",
        DRIVE_FILES_URL,
        urlencoding_simple(&query)
    );

    let response = ureq::get(&url)
        .set("Authorization", &format!("Bearer {clean_token}"))
        .call()
        .map_err(|e| format!("Ошибка запроса к Google Drive: {e}"))?;

    let parsed: DriveFileListResponse = response
        .into_json()
        .map_err(|e| format!("Ошибка парсинга ответа Google Drive: {e}"))?;

    let mut result = Vec::new();
    if let Some(files) = parsed.files {
        for f in files {
            result.push(CloudVaultItem {
                id: f.id.unwrap_or_default(),
                name: f.name.unwrap_or_default(),
                size_bytes: f.size.and_then(|s| s.parse::<u64>().ok()).unwrap_or(0),
                modified_time: f.modified_time.unwrap_or_default(),
            });
        }
    }

    Ok(result)
}

pub fn upload_vault_to_drive(
    local_path: &str,
    access_token: &str,
    existing_file_id: Option<&str>,
) -> Result<CloudVaultItem, String> {
    let clean_token = access_token.trim();
    if clean_token.is_empty() {
        return Err("Требуется Google Drive Access Token".to_string());
    }

    let path = Path::new(local_path);
    if !path.exists() {
        return Err(format!("Файл хранилища не существует: {local_path}"));
    }

    let mut file = File::open(path).map_err(|e| format!("Не удалось прочитать файл: {e}"))?;
    let mut file_bytes = Vec::new();
    file.read_to_end(&mut file_bytes)
        .map_err(|e| format!("Ошибка чтения данных: {e}"))?;

    let filename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("vault.vex");

    if let Some(file_id) = existing_file_id {
        if !file_id.trim().is_empty() {
            // Update existing file in Google Drive via media upload
            let url = format!(
                "https://www.googleapis.com/upload/drive/v3/files/{}?uploadType=media",
                file_id.trim()
            );

            let resp = ureq::patch(&url)
                .set("Authorization", &format!("Bearer {clean_token}"))
                .set("Content-Type", "application/octet-stream")
                .send_bytes(&file_bytes)
                .map_err(|e| format!("Ошибка обновления файла в Google Drive: {e}"))?;

            let uploaded: DriveUploadResponse = resp
                .into_json()
                .map_err(|e| format!("Ошибка ответа Google Drive: {e}"))?;

            return Ok(CloudVaultItem {
                id: uploaded.id.unwrap_or_else(|| file_id.to_string()),
                name: uploaded.name.unwrap_or_else(|| filename.to_string()),
                size_bytes: file_bytes.len() as u64,
                modified_time: uploaded.modified_time.unwrap_or_default(),
            });
        }
    }

    // New file: multipart upload (metadata + payload)
    let boundary = "VaultexBoundaryV2MultipartSync";
    let metadata_json = serde_json::json!({
        "name": filename,
        "mimeType": "application/octet-stream"
    })
    .to_string();

    let mut body: Vec<u8> = Vec::new();
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Type: application/json; charset=UTF-8\r\n\r\n");
    body.extend_from_slice(metadata_json.as_bytes());
    body.extend_from_slice(b"\r\n");

    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Type: application/octet-stream\r\n\r\n");
    body.extend_from_slice(&file_bytes);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());

    let content_type = format!("multipart/related; boundary={boundary}");

    let resp = ureq::post(DRIVE_UPLOAD_MULTIPART_URL)
        .set("Authorization", &format!("Bearer {clean_token}"))
        .set("Content-Type", &content_type)
        .send_bytes(&body)
        .map_err(|e| format!("Ошибка создания файла в Google Drive: {e}"))?;

    let uploaded: DriveUploadResponse = resp
        .into_json()
        .map_err(|e| format!("Ошибка парсинга ответа создания Google Drive: {e}"))?;

    Ok(CloudVaultItem {
        id: uploaded.id.unwrap_or_default(),
        name: uploaded.name.unwrap_or_else(|| filename.to_string()),
        size_bytes: file_bytes.len() as u64,
        modified_time: uploaded.modified_time.unwrap_or_default(),
    })
}

pub fn download_vault_from_drive(
    file_id: &str,
    destination_path: &str,
    access_token: &str,
) -> Result<(), String> {
    let clean_token = access_token.trim();
    if clean_token.is_empty() {
        return Err("Требуется Google Drive Access Token".to_string());
    }

    let url = format!("{}/{}?alt=media", DRIVE_FILES_URL, file_id.trim());

    let resp = ureq::get(&url)
        .set("Authorization", &format!("Bearer {clean_token}"))
        .call()
        .map_err(|e| format!("Ошибка скачивания из Google Drive: {e}"))?;

    let mut reader = resp.into_reader();
    let mut downloaded_bytes = Vec::new();
    reader
        .read_to_end(&mut downloaded_bytes)
        .map_err(|e| format!("Ошибка чтения скачанных данных: {e}"))?;

    // Atomic persistence: write to temp, sync, rename (AGENTS.md rule)
    let dest_path = Path::new(destination_path);
    if let Some(parent) = dest_path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Не удалось создать целевую папку: {e}"))?;
    }

    let temp_path = dest_path.with_extension(format!("tmp.{}", std::process::id()));
    {
        let mut tmp_file = File::create(&temp_path)
            .map_err(|e| format!("Не удалось создать временный файл: {e}"))?;
        tmp_file
            .write_all(&downloaded_bytes)
            .map_err(|e| format!("Ошибка записи временного файла: {e}"))?;
        tmp_file
            .sync_all()
            .map_err(|e| format!("Ошибка синхронизации диска: {e}"))?;
    }

    fs::rename(&temp_path, dest_path)
        .map_err(|e| format!("Ошибка атомарной замены файла: {e}"))?;

    Ok(())
}

fn urlencoding_simple(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}
