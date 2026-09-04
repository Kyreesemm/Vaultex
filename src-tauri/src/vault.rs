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

const ARGON2_MEMORY_KIB: u32 = 64 * 1024;
const ARGON2_ITERATIONS: u32 = 3;
const ARGON2_PARALLELISM: u32 = 1;
const AAD_PREFIX: &[u8] = b"vaultex-envelope-v1\0";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct KdfParams {
    pub memory_kib: u32,
    pub iterations: u32,
    pub parallelism: u32,
    pub output_length: usize,
}

impl Default for KdfParams {
    fn default() -> Self {
        Self {
            memory_kib: ARGON2_MEMORY_KIB,
            iterations: ARGON2_ITERATIONS,
            parallelism: ARGON2_PARALLELISM,
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
    #[error("invalid encrypted envelope")]
    InvalidEnvelope,
    #[error("encryption failed")]
    Encryption,
    #[error("decryption failed or authentication failed")]
    Decryption,
    #[error("vault session has not been initialized with a password")]
    MissingWrappedKey,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct EncryptedEnvelope {
    pub version: u8,
    pub salt: [u8; SALT_LENGTH],
    pub nonce: [u8; NONCE_LENGTH],
    pub ciphertext: Vec<u8>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct KeyEnvelope {
    pub nonce: [u8; NONCE_LENGTH],
    pub ciphertext: Vec<u8>,
}

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct VaultKey([u8; KEY_LENGTH]);

impl VaultKey {
    pub(crate) fn generate() -> Result<Self, VaultError> {
        let mut key = [0u8; KEY_LENGTH];
        OsRng.try_fill_bytes(&mut key).map_err(|_| VaultError::Randomness)?;
        Ok(Self(key))
    }

    pub(crate) fn from_bytes(bytes: [u8; KEY_LENGTH]) -> Self {
        Self(bytes)
    }

    pub(crate) fn as_bytes(&self) -> &[u8; KEY_LENGTH] {
        &self.0
    }
}

pub struct VaultCrypto;

impl VaultCrypto {
    pub fn encrypt(
        password: &[u8],
        plaintext: &[u8],
        associated_data: &[u8],
    ) -> Result<EncryptedEnvelope, VaultError> {
        let mut salt = [0u8; SALT_LENGTH];
        let mut nonce = [0u8; NONCE_LENGTH];
        OsRng.try_fill_bytes(&mut salt).map_err(|_| VaultError::Randomness)?;
        OsRng.try_fill_bytes(&mut nonce).map_err(|_| VaultError::Randomness)?;

        let key = derive_key(password, &salt)?;
        let ciphertext = encrypt_with_key(
            &key,
            &nonce,
            plaintext,
            &authenticated_data(ENVELOPE_VERSION, associated_data),
        )?;

        Ok(EncryptedEnvelope {
            version: ENVELOPE_VERSION,
            salt,
            nonce,
            ciphertext,
        })
    }

    pub fn decrypt(
        password: &[u8],
        envelope: &EncryptedEnvelope,
        associated_data: &[u8],
    ) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        validate_envelope(envelope)?;

        let key = derive_key(password, &envelope.salt)?;
        let plaintext = decrypt_with_key(
            &key,
            &envelope.nonce,
            &envelope.ciphertext,
            &authenticated_data(envelope.version, associated_data),
        )?;

        Ok(Zeroizing::new(plaintext))
    }

    pub fn re_encrypt(
        password: &[u8],
        envelope: &EncryptedEnvelope,
        associated_data: &[u8],
    ) -> Result<EncryptedEnvelope, VaultError> {
        let plaintext = Self::decrypt(password, envelope, associated_data)?;
        Self::encrypt(password, &plaintext, associated_data)
    }

    pub(crate) fn encrypt_with_key(
        key: &VaultKey,
        plaintext: &[u8],
        associated_data: &[u8],
    ) -> Result<KeyEnvelope, VaultError> {
        let mut nonce = [0u8; NONCE_LENGTH];
        OsRng.try_fill_bytes(&mut nonce).map_err(|_| VaultError::Randomness)?;
        let ciphertext = encrypt_with_key(key, &nonce, plaintext, associated_data)?;
        Ok(KeyEnvelope { nonce, ciphertext })
    }

    pub(crate) fn decrypt_with_key(
        key: &VaultKey,
        envelope: &KeyEnvelope,
        associated_data: &[u8],
    ) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        if envelope.ciphertext.len() < AUTH_TAG_LENGTH {
            return Err(VaultError::InvalidEnvelope);
        }
        Ok(Zeroizing::new(decrypt_with_key(
            key,
            &envelope.nonce,
            &envelope.ciphertext,
            associated_data,
        )?))
    }
}

fn derive_key(password: &[u8], salt: &[u8; SALT_LENGTH]) -> Result<VaultKey, VaultError> {
    derive_key_with_params(password, salt, KdfParams::default())
}

pub(crate) fn derive_key_with_params(
    password: &[u8],
    salt: &[u8; SALT_LENGTH],
    params: KdfParams,
) -> Result<VaultKey, VaultError> {
    if params.output_length != KEY_LENGTH {
        return Err(VaultError::InvalidKdfParameters);
    }
    let params = Params::new(
        params.memory_kib,
        params.iterations,
        params.parallelism,
        Some(params.output_length),
    )
    .map_err(|_| VaultError::InvalidKdfParameters)?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut key = [0u8; KEY_LENGTH];
    argon2
        .hash_password_into(password, salt, &mut key)
        .map_err(|_| VaultError::InvalidKdfParameters)?;
    Ok(VaultKey(key))
}

fn encrypt_with_key(
    key: &VaultKey,
    nonce: &[u8; NONCE_LENGTH],
    plaintext: &[u8],
    associated_data: &[u8],
) -> Result<Vec<u8>, VaultError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key.as_bytes()));
    cipher
        .encrypt(
            Nonce::from_slice(nonce),
            Payload { msg: plaintext, aad: associated_data },
        )
        .map_err(|_| VaultError::Encryption)
}

fn decrypt_with_key(
    key: &VaultKey,
    nonce: &[u8; NONCE_LENGTH],
    ciphertext: &[u8],
    associated_data: &[u8],
) -> Result<Vec<u8>, VaultError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key.as_bytes()));
    cipher
        .decrypt(
            Nonce::from_slice(nonce),
            Payload { msg: ciphertext, aad: associated_data },
        )
        .map_err(|_| VaultError::Decryption)
}

fn authenticated_data(version: u8, associated_data: &[u8]) -> Vec<u8> {
    let mut data = Vec::with_capacity(AAD_PREFIX.len() + 1 + associated_data.len());
    data.extend_from_slice(AAD_PREFIX);
    data.push(version);
    data.extend_from_slice(associated_data);
    data
}

fn validate_envelope(envelope: &EncryptedEnvelope) -> Result<(), VaultError> {
    if envelope.version != ENVELOPE_VERSION
        || envelope.ciphertext.len() < AUTH_TAG_LENGTH
    {
        return Err(VaultError::InvalidEnvelope);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PASSWORD: &[u8] = b"correct horse battery staple";
    const AAD: &[u8] = b"record:notes:42";

    #[test]
    fn round_trip_preserves_plaintext() {
        let plaintext = b"private markdown content";
        let envelope = VaultCrypto::encrypt(PASSWORD, plaintext, AAD).unwrap();
        let decrypted = VaultCrypto::decrypt(PASSWORD, &envelope, AAD).unwrap();
        assert_eq!(&*decrypted, plaintext);
    }

    #[test]
    fn wrong_password_is_rejected() {
        let envelope = VaultCrypto::encrypt(PASSWORD, b"secret", AAD).unwrap();
        let result = VaultCrypto::decrypt(b"wrong password", &envelope, AAD);
        assert!(matches!(result, Err(VaultError::Decryption)));
    }

    #[test]
    fn modified_ciphertext_is_rejected() {
        let mut envelope = VaultCrypto::encrypt(PASSWORD, b"secret", AAD).unwrap();
        envelope.ciphertext[0] ^= 1;
        let result = VaultCrypto::decrypt(PASSWORD, &envelope, AAD);
        assert!(matches!(result, Err(VaultError::Decryption)));
    }

    #[test]
    fn modified_associated_data_is_rejected() {
        let envelope = VaultCrypto::encrypt(PASSWORD, b"secret", AAD).unwrap();
        let result = VaultCrypto::decrypt(PASSWORD, &envelope, b"record:secrets:42");
        assert!(matches!(result, Err(VaultError::Decryption)));
    }

    #[test]
    fn unsupported_version_is_rejected() {
        let mut envelope = VaultCrypto::encrypt(PASSWORD, b"secret", AAD).unwrap();
        envelope.version = ENVELOPE_VERSION + 1;
        let result = VaultCrypto::decrypt(PASSWORD, &envelope, AAD);
        assert!(matches!(result, Err(VaultError::InvalidEnvelope)));
    }

    #[test]
    fn re_encrypts_with_fresh_nonce_and_salt() {
        let envelope = VaultCrypto::encrypt(PASSWORD, b"secret", AAD).unwrap();
        let rotated = VaultCrypto::re_encrypt(PASSWORD, &envelope, AAD).unwrap();
        assert_ne!(envelope.salt, rotated.salt);
        assert_ne!(envelope.nonce, rotated.nonce);
        let decrypted = VaultCrypto::decrypt(PASSWORD, &rotated, AAD).unwrap();
        assert_eq!(&*decrypted, b"secret");
    }
}
