use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Key, Nonce,
};
use argon2::{Algorithm, Argon2, Params, Version};
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

pub const ENVELOPE_VERSION: u8 = 1;
pub const KEY_LENGTH: usize = 32;
pub const SALT_LENGTH: usize = 16;
pub const NONCE_LENGTH: usize = 12;
pub const AUTH_TAG_LENGTH: usize = 16;

pub const DEFAULT_ARGON2_MEMORY_KIB: u32 = 64 * 1024; // 64 MB
pub const DEFAULT_ARGON2_ITERATIONS: u32 = 3;
pub const DEFAULT_ARGON2_PARALLELISM: u32 = 4;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct KdfParams {
    pub memory_kib: u32,
    pub iterations: u32,
    pub parallelism: u32,
    pub output_length: usize,
}

impl Default for KdfParams {
    fn default() -> Self {
        Self {
            memory_kib: DEFAULT_ARGON2_MEMORY_KIB,
            iterations: DEFAULT_ARGON2_ITERATIONS,
            parallelism: DEFAULT_ARGON2_PARALLELISM,
            output_length: KEY_LENGTH,
        }
    }
}

#[derive(Debug, Error)]
pub enum VaultError {
    #[error("invalid key derivation parameters")]
    InvalidKdfParameters,
    #[error("secure random number generation failed")]
    Randomness,
    #[error("invalid encrypted envelope or corrupted vault file")]
    InvalidEnvelope,
    #[error("encryption failed")]
    Encryption,
    #[error("decryption failed or invalid password")]
    Decryption,
    #[error("vault session has not been initialized with a password")]
    MissingWrappedKey,
    #[error("payload exceeds maximum allowed block size")]
    PayloadTooLarge,
    #[error("serialization error: {0}")]
    Serialization(String),
    #[error("io error: {0}")]
    Io(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct KeyEnvelope {
    pub nonce: [u8; NONCE_LENGTH],
    pub ciphertext: Vec<u8>,
}

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct VaultKey([u8; KEY_LENGTH]);

impl VaultKey {
    pub fn generate() -> Result<Self, VaultError> {
        let mut key = [0u8; KEY_LENGTH];
        OsRng.try_fill_bytes(&mut key).map_err(|_| VaultError::Randomness)?;
        Ok(Self(key))
    }

    pub fn from_bytes(bytes: [u8; KEY_LENGTH]) -> Self {
        Self(bytes)
    }

    pub fn as_bytes(&self) -> &[u8; KEY_LENGTH] {
        &self.0
    }
}

pub struct VaultCrypto;

impl VaultCrypto {
    pub fn encrypt_with_key(
        key: &VaultKey,
        plaintext: &[u8],
        associated_data: &[u8],
    ) -> Result<KeyEnvelope, VaultError> {
        let mut nonce = [0u8; NONCE_LENGTH];
        OsRng.try_fill_bytes(&mut nonce).map_err(|_| VaultError::Randomness)?;
        let ciphertext = encrypt_aes_gcm(key, &nonce, plaintext, associated_data)?;
        Ok(KeyEnvelope { nonce, ciphertext })
    }

    pub fn decrypt_with_key(
        key: &VaultKey,
        envelope: &KeyEnvelope,
        associated_data: &[u8],
    ) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        if envelope.ciphertext.len() < AUTH_TAG_LENGTH {
            return Err(VaultError::InvalidEnvelope);
        }
        let plaintext = decrypt_aes_gcm(
            key,
            &envelope.nonce,
            &envelope.ciphertext,
            associated_data,
        )?;
        Ok(Zeroizing::new(plaintext))
    }
}

pub fn derive_key_with_params(
    password: &[u8],
    salt: &[u8; SALT_LENGTH],
    params: KdfParams,
) -> Result<VaultKey, VaultError> {
    if params.output_length != KEY_LENGTH {
        return Err(VaultError::InvalidKdfParameters);
    }
    let argon_params = Params::new(
        params.memory_kib,
        params.iterations,
        params.parallelism,
        Some(params.output_length),
    )
    .map_err(|_| VaultError::InvalidKdfParameters)?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon_params);
    let mut key = [0u8; KEY_LENGTH];
    argon2
        .hash_password_into(password, salt, &mut key)
        .map_err(|_| VaultError::InvalidKdfParameters)?;
    Ok(VaultKey(key))
}

fn encrypt_aes_gcm(
    key: &VaultKey,
    nonce: &[u8; NONCE_LENGTH],
    plaintext: &[u8],
    associated_data: &[u8],
) -> Result<Vec<u8>, VaultError> {
    let cipher_key = Key::<Aes256Gcm>::from_slice(key.as_bytes());
    let cipher = Aes256Gcm::new(cipher_key);
    let nonce = Nonce::from_slice(nonce);
    cipher
        .encrypt(nonce, Payload { msg: plaintext, aad: associated_data })
        .map_err(|_| VaultError::Encryption)
}

fn decrypt_aes_gcm(
    key: &VaultKey,
    nonce: &[u8; NONCE_LENGTH],
    ciphertext: &[u8],
    associated_data: &[u8],
) -> Result<Vec<u8>, VaultError> {
    let cipher_key = Key::<Aes256Gcm>::from_slice(key.as_bytes());
    let cipher = Aes256Gcm::new(cipher_key);
    let nonce = Nonce::from_slice(nonce);
    cipher
        .decrypt(nonce, Payload { msg: ciphertext, aad: associated_data })
        .map_err(|_| VaultError::Decryption)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encryption_decryption() {
        let key = VaultKey::generate().unwrap();
        let msg = b"Super secret data in RAM";
        let aad = b"test-aad";
        let env = VaultCrypto::encrypt_with_key(&key, msg, aad).unwrap();
        let decrypted = VaultCrypto::decrypt_with_key(&key, &env, aad).unwrap();
        assert_eq!(&*decrypted, msg);
    }

    #[test]
    fn test_argon2id_derivation() {
        let salt = [42u8; SALT_LENGTH];
        let key1 = derive_key_with_params(b"password123", &salt, KdfParams {
            memory_kib: 8192,
            iterations: 1,
            parallelism: 1,
            output_length: 32,
        }).unwrap();
        let key2 = derive_key_with_params(b"password123", &salt, KdfParams {
            memory_kib: 8192,
            iterations: 1,
            parallelism: 1,
            output_length: 32,
        }).unwrap();
        assert_eq!(key1.as_bytes(), key2.as_bytes());
    }
}
