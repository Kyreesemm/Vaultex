use chrono::Utc;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u8)]
pub enum RecordKind {
    Note = 1,
    Secret = 2,
    Attachment = 3,
    Account = 4,
    ApiToken = 5,
}

impl TryFrom<u8> for RecordKind {
    type Error = crate::crypto::VaultError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Self::Note),
            2 => Ok(Self::Secret),
            3 => Ok(Self::Attachment),
            4 => Ok(Self::Account),
            5 => Ok(Self::ApiToken),
            _ => Err(crate::crypto::VaultError::InvalidEnvelope),
        }
    }
}

impl RecordKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            RecordKind::Note => "note",
            RecordKind::Secret => "secret",
            RecordKind::Attachment => "attachment",
            RecordKind::Account => "account",
            RecordKind::ApiToken => "api_token",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "note" => Some(RecordKind::Note),
            "secret" => Some(RecordKind::Secret),
            "attachment" => Some(RecordKind::Attachment),
            "account" => Some(RecordKind::Account),
            "api_token" | "token" => Some(RecordKind::ApiToken),
            _ => None,
        }
    }
}

/// 1. Account (Учетная запись)
#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct AccountData {
    pub service: String,
    pub username: String,
    pub email: String,
    pub password: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phone: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub two_factor_secret: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

/// 2. API Token / Key (Ключ доступа)
#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct ApiTokenData {
    pub name: String,
    pub token: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

/// 3. Secret / Recovery Codes (Секреты и сид-фразы)
#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct SecretRecoveryData {
    pub name: String,
    /// "single", "mnemonic", or "recovery_codes"
    pub secret_type: String,
    pub value: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

/// 4. Markdown Note (Заметка)
#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct NoteData {
    pub title: String,
    pub content: String,
    #[serde(default)]
    pub tags: Vec<String>,
}

/// Generic payload wrapper that is stored inside the encrypted record block
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "entity_type", rename_all = "snake_case")]
pub enum RecordPayload {
    Account(AccountData),
    ApiToken(ApiTokenData),
    SecretRecovery(SecretRecoveryData),
    Note(NoteData),
    /// Fallback for legacy records from earlier versions
    Legacy {
        title: String,
        content: String,
        #[serde(rename = "updatedAt")]
        updated_at: Option<String>,
    },
}

impl RecordPayload {
    pub fn title(&self) -> String {
        match self {
            RecordPayload::Account(a) => {
                if !a.service.is_empty() {
                    a.service.clone()
                } else if !a.username.is_empty() {
                    a.username.clone()
                } else {
                    "Без названия".to_string()
                }
            }
            RecordPayload::ApiToken(t) => {
                if !t.name.is_empty() {
                    t.name.clone()
                } else {
                    "API Ключ".to_string()
                }
            }
            RecordPayload::SecretRecovery(s) => {
                if !s.name.is_empty() {
                    s.name.clone()
                } else {
                    "Секрет".to_string()
                }
            }
            RecordPayload::Note(n) => {
                if !n.title.is_empty() {
                    n.title.clone()
                } else {
                    "Без названия".to_string()
                }
            }
            RecordPayload::Legacy { title, .. } => {
                if !title.is_empty() {
                    title.clone()
                } else {
                    "Без названия".to_string()
                }
            }
        }
    }

    pub fn subtitle(&self) -> String {
        match self {
            RecordPayload::Account(a) => {
                if !a.username.is_empty() && !a.email.is_empty() {
                    format!("{} ({})", a.username, a.email)
                } else if !a.username.is_empty() {
                    a.username.clone()
                } else if !a.email.is_empty() {
                    a.email.clone()
                } else {
                    "Учетная запись".to_string()
                }
            }
            RecordPayload::ApiToken(t) => {
                if let Some(exp) = &t.expires_at {
                    format!("Действует до: {}", exp)
                } else if !t.tags.is_empty() {
                    t.tags.join(", ")
                } else {
                    "Ключ API".to_string()
                }
            }
            RecordPayload::SecretRecovery(s) => match s.secret_type.as_str() {
                "mnemonic" => "Мнемоническая фраза (Seed)".to_string(),
                "recovery_codes" => "Резервные коды".to_string(),
                _ => "Секретное значение".to_string(),
            },
            RecordPayload::Note(n) => {
                let preview: String = n
                    .content
                    .lines()
                    .take(2)
                    .collect::<Vec<_>>()
                    .join(" ")
                    .chars()
                    .take(60)
                    .collect();
                if preview.is_empty() {
                    "Пустая заметка".to_string()
                } else {
                    preview
                }
            }
            RecordPayload::Legacy { content, .. } => {
                let preview: String = content.chars().take(60).collect();
                if preview.is_empty() {
                    "Запись".to_string()
                } else {
                    preview
                }
            }
        }
    }

    pub fn tags(&self) -> Vec<String> {
        match self {
            RecordPayload::Account(_) => vec!["account".to_string()],
            RecordPayload::ApiToken(t) => t.tags.clone(),
            RecordPayload::SecretRecovery(s) => vec![s.secret_type.clone()],
            RecordPayload::Note(n) => n.tags.clone(),
            RecordPayload::Legacy { .. } => vec![],
        }
    }
}

/// Metadata & parsed representation of an entry for Flutter
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct VaultEntryView {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub subtitle: String,
    pub tags: Vec<String>,
    pub revision: u64,
    pub updated_at: String,
    pub payload_json: String,
}

pub fn current_iso_timestamp() -> String {
    Utc::now().to_rfc3339()
}
