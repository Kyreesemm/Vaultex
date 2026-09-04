use std::collections::BTreeMap;

use rand_core::{OsRng, RngCore};
use zeroize::Zeroizing;

use crate::vault::{
    derive_key_with_params, KdfParams, KeyEnvelope, VaultCrypto, VaultError, VaultKey,
    AUTH_TAG_LENGTH, KEY_LENGTH, NONCE_LENGTH, SALT_LENGTH,
};

const MAGIC: &[u8; 8] = b"VAULTEX\0";
const RECORD_MAGIC: &[u8; 4] = b"VRB1";
const FORMAT_VERSION: u16 = 1;
const MAX_RECORDS: usize = 1_000_000;
const MAX_BLOCK_SIZE: usize = 256 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct RecordId([u8; 16]);

impl RecordId {
    pub fn generate() -> Result<Self, VaultError> {
        let mut id = [0u8; 16];
        OsRng.try_fill_bytes(&mut id).map_err(|_| VaultError::Randomness)?;
        Ok(Self(id))
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum RecordKind {
    Note = 1,
    Secret = 2,
    Attachment = 3,
}

impl TryFrom<u8> for RecordKind {
    type Error = VaultError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Self::Note),
            2 => Ok(Self::Secret),
            3 => Ok(Self::Attachment),
            _ => Err(VaultError::InvalidEnvelope),
        }
    }
}

pub struct VaultRecord {
    pub kind: RecordKind,
    pub revision: u64,
    pub payload: Zeroizing<Vec<u8>>,
}

pub struct VaultStore {
    vault_id: [u8; 16],
    data_key: VaultKey,
    wrapped_key: Option<KeyEnvelope>,
    kdf_params: KdfParams,
    salt: [u8; SALT_LENGTH],
    records: BTreeMap<RecordId, VaultRecord>,
}

impl VaultStore {
    pub fn create() -> Result<Self, VaultError> {
        let mut vault_id = [0u8; 16];
        let mut salt = [0u8; SALT_LENGTH];
        OsRng.try_fill_bytes(&mut vault_id).map_err(|_| VaultError::Randomness)?;
        OsRng.try_fill_bytes(&mut salt).map_err(|_| VaultError::Randomness)?;

        Ok(Self {
            vault_id,
            data_key: VaultKey::generate()?,
            wrapped_key: None,
            kdf_params: KdfParams::default(),
            salt,
            records: BTreeMap::new(),
        })
    }

    pub fn unlock(bytes: &[u8], password: &[u8]) -> Result<Self, VaultError> {
        let mut reader = Reader::new(bytes);
        reader.take_exact(MAGIC)?;
        if reader.u16()? != FORMAT_VERSION {
            return Err(VaultError::InvalidEnvelope);
        }

        let kdf_params = KdfParams {
            memory_kib: reader.u32()?,
            iterations: reader.u32()?,
            parallelism: reader.u32()?,
            output_length: reader.u16()? as usize,
        };
        if kdf_params.output_length != KEY_LENGTH
            || kdf_params.memory_kib < 8 * 1024
            || kdf_params.iterations == 0
            || kdf_params.parallelism == 0
        {
            return Err(VaultError::InvalidEnvelope);
        }

        let vault_id = reader.array::<16>()?;
        let salt = reader.array::<SALT_LENGTH>()?;
        let wrapped_nonce = reader.array::<NONCE_LENGTH>()?;
        let wrapped_ciphertext = reader.bytes(MAX_BLOCK_SIZE)?;

        let password_key = derive_key_with_params(password, &salt, kdf_params)?;
        let data_key_bytes = VaultCrypto::decrypt_with_key(
            &password_key,
            &KeyEnvelope { nonce: wrapped_nonce, ciphertext: wrapped_ciphertext.clone() },
            &wrap_aad(&vault_id),
        )?;
        if data_key_bytes.len() != KEY_LENGTH {
            return Err(VaultError::InvalidEnvelope);
        }
        let mut raw_data_key = [0u8; KEY_LENGTH];
        raw_data_key.copy_from_slice(&data_key_bytes);
        let data_key = VaultKey::from_bytes(raw_data_key);

        let manifest_nonce = reader.array::<NONCE_LENGTH>()?;
        let manifest_ciphertext = reader.bytes(MAX_BLOCK_SIZE)?;
        let manifest = VaultCrypto::decrypt_with_key(
            &data_key,
            &KeyEnvelope { nonce: manifest_nonce, ciphertext: manifest_ciphertext },
            &manifest_aad(&vault_id),
        )?;
        let entries = parse_manifest(&manifest)?;

        let mut blocks = Vec::new();
        while reader.remaining() > 0 {
            reader.take_exact(RECORD_MAGIC)?;
            let nonce = reader.array::<NONCE_LENGTH>()?;
            let ciphertext = reader.bytes(MAX_BLOCK_SIZE)?;
            blocks.push(KeyEnvelope { nonce, ciphertext });
        }

        let mut records = BTreeMap::new();
        for (id, kind, revision, block_index) in entries {
            let block = blocks.get(block_index).ok_or(VaultError::InvalidEnvelope)?;
            let payload = VaultCrypto::decrypt_with_key(
                &data_key,
                block,
                &record_aad(&vault_id, id, kind, revision),
            )?;
            records.insert(id, VaultRecord { kind, revision, payload });
        }

        Ok(Self {
            vault_id,
            data_key,
            wrapped_key: Some(KeyEnvelope { nonce: wrapped_nonce, ciphertext: wrapped_ciphertext }),
            kdf_params,
            salt,
            records,
        })
    }

    pub fn insert(
        &mut self,
        kind: RecordKind,
        payload: Vec<u8>,
    ) -> Result<RecordId, VaultError> {
        if payload.len() > MAX_BLOCK_SIZE - AUTH_TAG_LENGTH {
            return Err(VaultError::InvalidEnvelope);
        }
        let id = RecordId::generate()?;
        self.records.insert(
            id,
            VaultRecord { kind, revision: 1, payload: Zeroizing::new(payload) },
        );
        Ok(id)
    }

    pub fn get(&self, id: RecordId) -> Option<&VaultRecord> {
        self.records.get(&id)
    }

    pub fn update(&mut self, id: RecordId, payload: Vec<u8>) -> Result<(), VaultError> {
        if payload.len() > MAX_BLOCK_SIZE - AUTH_TAG_LENGTH {
            return Err(VaultError::InvalidEnvelope);
        }
        let record = self.records.get_mut(&id).ok_or(VaultError::InvalidEnvelope)?;
        record.revision = record.revision.checked_add(1).ok_or(VaultError::InvalidEnvelope)?;
        record.payload = Zeroizing::new(payload);
        Ok(())
    }

    pub fn remove(&mut self, id: RecordId) -> Result<(), VaultError> {
        self.records.remove(&id).map(|_| ()).ok_or(VaultError::InvalidEnvelope)
    }

    pub fn commit_with_password(&self, password: &[u8]) -> Result<Vec<u8>, VaultError> {
        let password_key = derive_key_with_params(password, &self.salt, self.kdf_params)?;
        let wrapped_key = VaultCrypto::encrypt_with_key(
            &password_key,
            self.data_key.as_bytes(),
            &wrap_aad(&self.vault_id),
        )?;
        self.commit_with_wrapped_key(&wrapped_key)
    }

    pub fn commit(&self, password: &[u8]) -> Result<Vec<u8>, VaultError> {
        self.commit_with_password(password)
    }

    pub fn commit_unlocked(&self) -> Result<Vec<u8>, VaultError> {
        let wrapped_key = self.wrapped_key.as_ref().ok_or(VaultError::MissingWrappedKey)?;
        self.commit_with_wrapped_key(wrapped_key)
    }

    pub fn lock(self) {
        drop(self);
    }

    fn commit_with_wrapped_key(&self, wrapped_key: &KeyEnvelope) -> Result<Vec<u8>, VaultError> {
        if self.records.len() > MAX_RECORDS {
            return Err(VaultError::InvalidEnvelope);
        }

        let mut blocks = Vec::with_capacity(self.records.len());
        let mut manifest = Writer::new();
        manifest.u16(FORMAT_VERSION);
        manifest.u32(self.records.len() as u32);

        for (block_index, (id, record)) in self.records.iter().enumerate() {
            let block = VaultCrypto::encrypt_with_key(
                &self.data_key,
                &record.payload,
                &record_aad(&self.vault_id, *id, record.kind, record.revision),
            )?;
            manifest.array(&id.0);
            manifest.u8(record.kind as u8);
            manifest.u64(record.revision);
            manifest.u32(block_index as u32);
            blocks.push(block);
        }

        let manifest_block = VaultCrypto::encrypt_with_key(
            &self.data_key,
            &manifest.finish(),
            &manifest_aad(&self.vault_id),
        )?;

        let mut output = Writer::new();
        output.array(MAGIC);
        output.u16(FORMAT_VERSION);
        output.u32(self.kdf_params.memory_kib);
        output.u32(self.kdf_params.iterations);
        output.u32(self.kdf_params.parallelism);
        output.u16(self.kdf_params.output_length as u16);
        output.array(&self.vault_id);
        output.array(&self.salt);
        output.array(&wrapped_key.nonce);
        output.bytes(&wrapped_key.ciphertext)?;
        output.array(&manifest_block.nonce);
        output.bytes(&manifest_block.ciphertext)?;

        for block in blocks {
            output.array(RECORD_MAGIC);
            output.array(&block.nonce);
            output.bytes(&block.ciphertext)?;
        }

        Ok(output.finish())
    }
}

fn wrap_aad(vault_id: &[u8; 16]) -> Vec<u8> {
    aad(b"wrap", vault_id)
}

fn manifest_aad(vault_id: &[u8; 16]) -> Vec<u8> {
    aad(b"manifest", vault_id)
}

fn record_aad(vault_id: &[u8; 16], id: RecordId, kind: RecordKind, revision: u64) -> Vec<u8> {
    let mut result = aad(b"record", vault_id);
    result.extend_from_slice(&id.0);
    result.push(kind as u8);
    result.extend_from_slice(&revision.to_le_bytes());
    result
}

fn aad(domain: &[u8], vault_id: &[u8; 16]) -> Vec<u8> {
    let mut result = Vec::with_capacity(domain.len() + vault_id.len() + 1);
    result.extend_from_slice(b"vaultex-storage-v1\0");
    result.extend_from_slice(domain);
    result.push(0);
    result.extend_from_slice(vault_id);
    result
}

fn parse_manifest(bytes: &[u8]) -> Result<Vec<(RecordId, RecordKind, u64, usize)>, VaultError> {
    let mut reader = Reader::new(bytes);
    if reader.u16()? != FORMAT_VERSION {
        return Err(VaultError::InvalidEnvelope);
    }
    let count = reader.u32()? as usize;
    if count > MAX_RECORDS {
        return Err(VaultError::InvalidEnvelope);
    }
    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        let id = RecordId(reader.array::<16>()?);
        let kind = RecordKind::try_from(reader.u8()?)?;
        let revision = reader.u64()?;
        let block_index = reader.u32()? as usize;
        entries.push((id, kind, revision, block_index));
    }
    if reader.remaining() != 0 {
        return Err(VaultError::InvalidEnvelope);
    }
    Ok(entries)
}

struct Writer {
    bytes: Vec<u8>,
}

impl Writer {
    fn new() -> Self { Self { bytes: Vec::new() } }
    fn array<const N: usize>(&mut self, value: &[u8; N]) { self.bytes.extend_from_slice(value); }
    fn u8(&mut self, value: u8) { self.bytes.push(value); }
    fn u16(&mut self, value: u16) { self.bytes.extend_from_slice(&value.to_le_bytes()); }
    fn u32(&mut self, value: u32) { self.bytes.extend_from_slice(&value.to_le_bytes()); }
    fn u64(&mut self, value: u64) { self.bytes.extend_from_slice(&value.to_le_bytes()); }
    fn bytes(&mut self, value: &[u8]) -> Result<(), VaultError> {
        if value.len() > MAX_BLOCK_SIZE { return Err(VaultError::InvalidEnvelope); }
        self.u32(value.len() as u32);
        self.bytes.extend_from_slice(value);
        Ok(())
    }
    fn finish(self) -> Vec<u8> { self.bytes }
}

struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self { Self { bytes, offset: 0 } }
    fn take(&mut self, length: usize) -> Result<&'a [u8], VaultError> {
        let end = self.offset.checked_add(length).ok_or(VaultError::InvalidEnvelope)?;
        let value = self.bytes.get(self.offset..end).ok_or(VaultError::InvalidEnvelope)?;
        self.offset = end;
        Ok(value)
    }
    fn take_exact(&mut self, expected: &[u8]) -> Result<(), VaultError> {
        if self.take(expected.len())? != expected { return Err(VaultError::InvalidEnvelope); }
        Ok(())
    }
    fn array<const N: usize>(&mut self) -> Result<[u8; N], VaultError> {
        self.take(N)?.try_into().map_err(|_| VaultError::InvalidEnvelope)
    }
    fn u8(&mut self) -> Result<u8, VaultError> { Ok(*self.take(1)?.first().unwrap()) }
    fn u16(&mut self) -> Result<u16, VaultError> {
        Ok(u16::from_le_bytes(self.array::<2>()?))
    }
    fn u32(&mut self) -> Result<u32, VaultError> {
        Ok(u32::from_le_bytes(self.array::<4>()?))
    }
    fn u64(&mut self) -> Result<u64, VaultError> {
        Ok(u64::from_le_bytes(self.array::<8>()?))
    }
    fn bytes(&mut self, maximum: usize) -> Result<Vec<u8>, VaultError> {
        let length = self.u32()? as usize;
        if length > maximum { return Err(VaultError::InvalidEnvelope); }
        Ok(self.take(length)?.to_vec())
    }
    fn remaining(&self) -> usize { self.bytes.len() - self.offset }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PASSWORD: &[u8] = b"vault password with enough entropy";

    #[test]
    fn binary_store_round_trip_preserves_records() {
        let mut store = VaultStore::create().unwrap();
        let note_id = store.insert(RecordKind::Note, b"private note".to_vec()).unwrap();
        let secret_id = store.insert(RecordKind::Secret, b"token-value".to_vec()).unwrap();
        let bytes = store.commit(PASSWORD).unwrap();

        let restored = VaultStore::unlock(&bytes, PASSWORD).unwrap();
        assert_eq!(&*restored.get(note_id).unwrap().payload, b"private note");
        assert_eq!(restored.get(secret_id).unwrap().kind, RecordKind::Secret);
    }

    #[test]
    fn wrong_password_cannot_unlock_store() {
        let store = VaultStore::create().unwrap();
        let bytes = store.commit(PASSWORD).unwrap();
        assert!(matches!(
            VaultStore::unlock(&bytes, b"wrong"),
            Err(VaultError::Decryption)
        ));
    }

    #[test]
    fn tampered_record_is_rejected() {
        let mut store = VaultStore::create().unwrap();
        store.insert(RecordKind::Note, b"private note".to_vec()).unwrap();
        let mut bytes = store.commit(PASSWORD).unwrap();
        *bytes.last_mut().unwrap() ^= 1;
        assert!(matches!(
            VaultStore::unlock(&bytes, PASSWORD),
            Err(VaultError::Decryption)
        ));
    }

    #[test]
    fn update_and_remove_are_persisted() {
        let mut store = VaultStore::create().unwrap();
        let id = store.insert(RecordKind::Note, b"old".to_vec()).unwrap();
        store.update(id, b"new".to_vec()).unwrap();
        let removed = store.insert(RecordKind::Secret, b"remove me".to_vec()).unwrap();
        store.remove(removed).unwrap();
        let restored = VaultStore::unlock(&store.commit(PASSWORD).unwrap(), PASSWORD).unwrap();
        assert_eq!(&*restored.get(id).unwrap().payload, b"new");
        assert!(restored.get(removed).is_none());
    }
}
