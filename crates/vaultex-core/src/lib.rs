use aes_gcm::{Aes256Gcm, Nonce as AesNonce};
use argon2::Argon2;
use chacha20poly1305::{aead::{Aead, KeyInit}, Key, XChaCha20Poly1305, XNonce};
use getrandom::getrandom;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use thiserror::Error;
use zeroize::Zeroize;

const MAGIC: &[u8; 8] = b"VAULTEX\0";
const FORMAT_VERSION: u16 = 1;
const ALGORITHM_LEN: usize = 1;
const SALT_LEN: usize = 16;
const AES_NONCE_LEN: usize = 12;
const XCHACHA_NONCE_LEN: usize = 24;
const KEY_LEN: usize = 32;

#[derive(Debug, Error)]
pub enum VaultError {
    #[error("invalid or unsupported vault format")]
    InvalidFormat,
    #[error("wrong password or corrupted vault")]
    DecryptionFailed,
    #[error("vault data is malformed")]
    InvalidData,
    #[error("randomness provider failed")]
    Randomness,
    #[error("serialization failed")]
    Serialization,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum EncryptionAlgorithm {
    Aes256Gcm = 1,
    XChaCha20Poly1305 = 2,
}

impl TryFrom<u8> for EncryptionAlgorithm {
    type Error = VaultError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Self::Aes256Gcm),
            2 => Ok(Self::XChaCha20Poly1305),
            _ => Err(VaultError::InvalidFormat),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Entry {
    pub title: String,
    pub username: Option<String>,
    pub password: Option<String>,
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct Vault {
    entries: BTreeMap<String, Entry>,
}

impl Vault {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn entries(&self) -> &BTreeMap<String, Entry> {
        &self.entries
    }

    pub fn insert(&mut self, id: impl Into<String>, entry: Entry) {
        self.entries.insert(id.into(), entry);
    }

    pub fn remove(&mut self, id: &str) -> Option<Entry> {
        self.entries.remove(id)
    }

    pub fn seal(&self, password: &str) -> Result<Vec<u8>, VaultError> {
        self.seal_with(password, EncryptionAlgorithm::XChaCha20Poly1305)
    }

    pub fn seal_with(
        &self,
        password: &str,
        algorithm: EncryptionAlgorithm,
    ) -> Result<Vec<u8>, VaultError> {
        let mut salt = [0u8; SALT_LEN];
        getrandom(&mut salt).map_err(|_| VaultError::Randomness)?;
        let nonce_len = nonce_len(algorithm);
        let mut nonce = vec![0u8; nonce_len];
        getrandom(&mut nonce).map_err(|_| VaultError::Randomness)?;

        let mut key = derive_key(password, &salt)?;
        let mut plaintext = serde_json::to_vec(self).map_err(|_| VaultError::Serialization)?;
        let ciphertext = encrypt(algorithm, &key, &nonce, &plaintext);
        plaintext.zeroize();
        key.zeroize();
        let ciphertext = ciphertext.map_err(|_| VaultError::DecryptionFailed)?;

        let mut output = Vec::with_capacity(
            MAGIC.len() + 2 + ALGORITHM_LEN + SALT_LEN + nonce_len + ciphertext.len(),
        );
        output.extend_from_slice(MAGIC);
        output.extend_from_slice(&FORMAT_VERSION.to_le_bytes());
        output.push(algorithm as u8);
        output.extend_from_slice(&salt);
        output.extend_from_slice(&nonce);
        output.extend_from_slice(&ciphertext);
        Ok(output)
    }

    pub fn open(container: &[u8], password: &str) -> Result<Self, VaultError> {
        if container.len() < MAGIC.len() + 2 + ALGORITHM_LEN + SALT_LEN {
            return Err(VaultError::InvalidFormat);
        }
        if &container[..MAGIC.len()] != MAGIC
            || u16::from_le_bytes([container[8], container[9]]) != FORMAT_VERSION
        {
            return Err(VaultError::InvalidFormat);
        }

        let algorithm = EncryptionAlgorithm::try_from(container[10])?;
        let salt_start = 11;
        let nonce_start = salt_start + SALT_LEN;
        let nonce_end = nonce_start + nonce_len(algorithm);
        if container.len() < nonce_end + 16 {
            return Err(VaultError::InvalidFormat);
        }

        let mut key = derive_key(password, &container[salt_start..nonce_start])?;
        let plaintext = decrypt(
            algorithm,
            &key,
            &container[nonce_start..nonce_end],
            &container[nonce_end..],
        );
        key.zeroize();
        let mut plaintext = plaintext.map_err(|_| VaultError::DecryptionFailed)?;
        let result = serde_json::from_slice(&plaintext).map_err(|_| VaultError::InvalidData);
        plaintext.zeroize();
        result
    }
}

fn nonce_len(algorithm: EncryptionAlgorithm) -> usize {
    match algorithm {
        EncryptionAlgorithm::Aes256Gcm => AES_NONCE_LEN,
        EncryptionAlgorithm::XChaCha20Poly1305 => XCHACHA_NONCE_LEN,
    }
}

fn derive_key(password: &str, salt: &[u8]) -> Result<[u8; KEY_LEN], VaultError> {
    let mut key = [0u8; KEY_LEN];
    Argon2::default()
        .hash_password_into(password.as_bytes(), salt, &mut key)
        .map_err(|_| VaultError::InvalidData)?;
    Ok(key)
}

fn encrypt(
    algorithm: EncryptionAlgorithm,
    key: &[u8; KEY_LEN],
    nonce: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, ()> {
    match algorithm {
        EncryptionAlgorithm::Aes256Gcm => Aes256Gcm::new_from_slice(key)
            .map_err(|_| ())?
            .encrypt(AesNonce::from_slice(nonce), plaintext)
            .map_err(|_| ()),
        EncryptionAlgorithm::XChaCha20Poly1305 => XChaCha20Poly1305::new(Key::from_slice(key))
            .encrypt(XNonce::from_slice(nonce), plaintext)
            .map_err(|_| ()),
    }
}

fn decrypt(
    algorithm: EncryptionAlgorithm,
    key: &[u8; KEY_LEN],
    nonce: &[u8],
    ciphertext: &[u8],
) -> Result<Vec<u8>, ()> {
    match algorithm {
        EncryptionAlgorithm::Aes256Gcm => Aes256Gcm::new_from_slice(key)
            .map_err(|_| ())?
            .decrypt(AesNonce::from_slice(nonce), ciphertext)
            .map_err(|_| ()),
        EncryptionAlgorithm::XChaCha20Poly1305 => XChaCha20Poly1305::new(Key::from_slice(key))
            .decrypt(XNonce::from_slice(nonce), ciphertext)
            .map_err(|_| ()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Vault {
        let mut vault = Vault::new();
        vault.insert("mail", Entry {
            title: "Mail".into(),
            username: Some("alice@example.com".into()),
            password: Some("correct horse battery staple".into()),
            notes: Some("private".into()),
        });
        vault
    }

    #[test]
    fn round_trip_for_each_algorithm() {
        let original = sample();
        for algorithm in [
            EncryptionAlgorithm::Aes256Gcm,
            EncryptionAlgorithm::XChaCha20Poly1305,
        ] {
            let sealed = original.seal_with("master password", algorithm).unwrap();
            assert_eq!(Vault::open(&sealed, "master password").unwrap(), original);
            assert!(!String::from_utf8_lossy(&sealed).contains("alice@example.com"));
        }
    }

    #[test]
    fn wrong_password_fails() {
        let sealed = sample().seal("master password").unwrap();
        assert!(matches!(
            Vault::open(&sealed, "wrong"),
            Err(VaultError::DecryptionFailed)
        ));
    }

    #[test]
    fn tampering_fails() {
        let mut sealed = sample().seal("master password").unwrap();
        *sealed.last_mut().unwrap() ^= 1;
        assert!(matches!(
            Vault::open(&sealed, "master password"),
            Err(VaultError::DecryptionFailed)
        ));
    }
}
