use std::collections::BTreeMap;
use rand_core::{OsRng, RngCore};
use zeroize::{Zeroize, Zeroizing};

use crate::crypto::{
    derive_key_with_params, KdfParams, KeyEnvelope, VaultCrypto, VaultError, VaultKey,
    KEY_LENGTH, NONCE_LENGTH, SALT_LENGTH,
};
use crate::model::RecordKind;

pub const MAGIC: &[u8; 8] = b"VAULTEX\0";
pub const RECORD_MAGIC: &[u8; 4] = b"VRB1";
pub const FORMAT_VERSION: u16 = 3;
pub const MAX_RECORDS: usize = 1_000_000;
pub const MAX_BLOCK_SIZE: usize = 256 * 1024 * 1024;
pub const MAX_VAULT_NAME_LENGTH: usize = 256;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct RecordId(pub [u8; 16]);

impl RecordId {
    pub fn generate() -> Result<Self, VaultError> {
        let mut id = [0u8; 16];
        OsRng.try_fill_bytes(&mut id).map_err(|_| VaultError::Randomness)?;
        Ok(Self(id))
    }

    pub fn to_hex(self) -> String {
        self.0.iter().map(|b| format!("{b:02x}")).collect()
    }

    pub fn from_hex(val: &str) -> Result<Self, VaultError> {
        let bytes = val.as_bytes();
        if bytes.len() != 32 {
            return Err(VaultError::InvalidEnvelope);
        }
        let mut id = [0u8; 16];
        for (i, byte) in id.iter_mut().enumerate() {
            let h = hex_digit(bytes[i * 2]).ok_or(VaultError::InvalidEnvelope)?;
            let l = hex_digit(bytes[i * 2 + 1]).ok_or(VaultError::InvalidEnvelope)?;
            *byte = (h << 4) | l;
        }
        Ok(Self(id))
    }
}

fn hex_digit(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

pub struct VaultRecord {
    pub kind: RecordKind,
    pub revision: u64,
    pub payload: Zeroizing<Vec<u8>>,
}

pub struct VaultStore {
    name: String,
    vault_id: [u8; 16],
    data_key: VaultKey,
    wrapped_key: Option<KeyEnvelope>,
    kdf_params: KdfParams,
    salt: [u8; SALT_LENGTH],
    records: BTreeMap<RecordId, VaultRecord>,
}

impl VaultStore {
    pub fn create_named(name: &str) -> Result<Self, VaultError> {
        validate_vault_name(name)?;
        let mut vault_id = [0u8; 16];
        let mut salt = [0u8; SALT_LENGTH];
        OsRng.try_fill_bytes(&mut vault_id).map_err(|_| VaultError::Randomness)?;
        OsRng.try_fill_bytes(&mut salt).map_err(|_| VaultError::Randomness)?;

        Ok(Self {
            name: name.to_owned(),
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
        let version = reader.u16()?;
        if version != FORMAT_VERSION {
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
            &KeyEnvelope {
                nonce: wrapped_nonce,
                ciphertext: wrapped_ciphertext.clone(),
            },
            &header_aad(&vault_id, &salt, kdf_params),
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
            &KeyEnvelope {
                nonce: manifest_nonce,
                ciphertext: manifest_ciphertext,
            },
            &manifest_aad(&vault_id),
        )?;
        let (name, entries) = parse_manifest(&manifest)?;

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
            name,
            vault_id,
            data_key,
            wrapped_key: Some(KeyEnvelope {
                nonce: wrapped_nonce,
                ciphertext: wrapped_ciphertext,
            }),
            kdf_params,
            salt,
            records,
        })
    }

    pub fn insert(&mut self, kind: RecordKind, payload: Vec<u8>) -> Result<RecordId, VaultError> {
        if payload.len() > MAX_BLOCK_SIZE - 16 {
            return Err(VaultError::PayloadTooLarge);
        }
        let id = RecordId::generate()?;
        self.records.insert(
            id,
            VaultRecord {
                kind,
                revision: 1,
                payload: Zeroizing::new(payload),
            },
        );
        Ok(id)
    }

    pub fn get(&self, id: RecordId) -> Option<&VaultRecord> {
        self.records.get(&id)
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn set_name(&mut self, name: &str) -> Result<(), VaultError> {
        validate_vault_name(name)?;
        self.name = name.to_string();
        Ok(())
    }

    pub fn vault_id_hex(&self) -> String {
        self.vault_id.iter().map(|b| format!("{b:02x}")).collect()
    }

    pub fn list(&self) -> impl Iterator<Item = (RecordId, &VaultRecord)> {
        self.records.iter().map(|(id, record)| (*id, record))
    }

    pub fn record_count(&self) -> usize {
        self.records.len()
    }

    pub fn update(&mut self, id: RecordId, payload: Vec<u8>) -> Result<(), VaultError> {
        if payload.len() > MAX_BLOCK_SIZE - 16 {
            return Err(VaultError::PayloadTooLarge);
        }
        let record = self.records.get_mut(&id).ok_or(VaultError::InvalidEnvelope)?;
        record.revision = record.revision.checked_add(1).ok_or(VaultError::InvalidEnvelope)?;
        record.payload = Zeroizing::new(payload);
        Ok(())
    }

    pub fn remove(&mut self, id: RecordId) -> Result<(), VaultError> {
        self.records.remove(&id).map(|_| ()).ok_or(VaultError::InvalidEnvelope)
    }

    pub fn change_password(&mut self, new_password: &[u8]) -> Result<(), VaultError> {
        let mut new_salt = [0u8; SALT_LENGTH];
        OsRng.try_fill_bytes(&mut new_salt).map_err(|_| VaultError::Randomness)?;
        self.salt = new_salt;

        let password_key = derive_key_with_params(new_password, &self.salt, self.kdf_params)?;
        let wrapped_key = VaultCrypto::encrypt_with_key(
            &password_key,
            self.data_key.as_bytes(),
            &header_aad(&self.vault_id, &self.salt, self.kdf_params),
        )?;
        self.wrapped_key = Some(wrapped_key);
        Ok(())
    }

    pub fn commit_with_password(&mut self, password: &[u8]) -> Result<Vec<u8>, VaultError> {
        let password_key = derive_key_with_params(password, &self.salt, self.kdf_params)?;
        let wrapped_key = VaultCrypto::encrypt_with_key(
            &password_key,
            self.data_key.as_bytes(),
            &header_aad(&self.vault_id, &self.salt, self.kdf_params),
        )?;
        self.wrapped_key = Some(wrapped_key.clone());
        self.commit_with_wrapped_key(&wrapped_key)
    }

    pub fn commit_unlocked(&self) -> Result<Vec<u8>, VaultError> {
        let wrapped_key = self.wrapped_key.as_ref().ok_or(VaultError::MissingWrappedKey)?;
        self.commit_with_wrapped_key(wrapped_key)
    }

    pub fn lock(mut self) {
        // Zeroize any plaintext records before dropping
        for (_, record) in self.records.iter_mut() {
            record.payload.zeroize();
        }
        self.records.clear();
        drop(self);
    }

    fn commit_with_wrapped_key(&self, wrapped_key: &KeyEnvelope) -> Result<Vec<u8>, VaultError> {
        if self.records.len() > MAX_RECORDS {
            return Err(VaultError::InvalidEnvelope);
        }

        let mut blocks = Vec::with_capacity(self.records.len());
        let mut manifest = Writer::new();
        manifest.u16(FORMAT_VERSION);
        manifest.string(&self.name, MAX_VAULT_NAME_LENGTH)?;
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

fn header_aad(vault_id: &[u8; 16], salt: &[u8; SALT_LENGTH], params: KdfParams) -> Vec<u8> {
    let mut result = Vec::with_capacity(8 + 2 + 4 + 4 + 4 + 2 + 16 + SALT_LENGTH);
    result.extend_from_slice(MAGIC);
    result.extend_from_slice(&FORMAT_VERSION.to_le_bytes());
    result.extend_from_slice(&params.memory_kib.to_le_bytes());
    result.extend_from_slice(&params.iterations.to_le_bytes());
    result.extend_from_slice(&params.parallelism.to_le_bytes());
    result.extend_from_slice(&(params.output_length as u16).to_le_bytes());
    result.extend_from_slice(vault_id);
    result.extend_from_slice(salt);
    result
}

fn manifest_aad(vault_id: &[u8; 16]) -> Vec<u8> {
    aad(b"manifest", vault_id, FORMAT_VERSION)
}

fn record_aad(vault_id: &[u8; 16], id: RecordId, kind: RecordKind, revision: u64) -> Vec<u8> {
    let mut result = aad(b"record", vault_id, FORMAT_VERSION);
    result.extend_from_slice(&id.0);
    result.push(kind as u8);
    result.extend_from_slice(&revision.to_le_bytes());
    result
}

fn aad(domain: &[u8], vault_id: &[u8; 16], version: u16) -> Vec<u8> {
    let mut result = Vec::with_capacity(domain.len() + vault_id.len() + 3);
    result.extend_from_slice(b"vaultex-storage-v1\0");
    result.extend_from_slice(domain);
    result.push(0);
    result.extend_from_slice(&version.to_le_bytes());
    result.extend_from_slice(vault_id);
    result
}

fn parse_manifest(
    bytes: &[u8],
) -> Result<(String, Vec<(RecordId, RecordKind, u64, usize)>), VaultError> {
    let mut reader = Reader::new(bytes);
    if reader.u16()? != FORMAT_VERSION {
        return Err(VaultError::InvalidEnvelope);
    }
    let name = reader.string(MAX_VAULT_NAME_LENGTH)?;
    validate_vault_name(&name)?;
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
    Ok((name, entries))
}

fn validate_vault_name(name: &str) -> Result<(), VaultError> {
    if name.trim().is_empty()
        || name.len() > MAX_VAULT_NAME_LENGTH
        || name.contains(['/', '\\', '\0'])
    {
        return Err(VaultError::InvalidEnvelope);
    }
    Ok(())
}

struct Writer {
    bytes: Vec<u8>,
}

impl Writer {
    fn new() -> Self {
        Self { bytes: Vec::new() }
    }

    fn array<const N: usize>(&mut self, value: &[u8; N]) {
        self.bytes.extend_from_slice(value);
    }

    fn u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    fn u16(&mut self, value: u16) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn u64(&mut self, value: u64) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn bytes(&mut self, value: &[u8]) -> Result<(), VaultError> {
        if value.len() > MAX_BLOCK_SIZE {
            return Err(VaultError::InvalidEnvelope);
        }
        self.u32(value.len() as u32);
        self.bytes.extend_from_slice(value);
        Ok(())
    }

    fn string(&mut self, value: &str, max_len: usize) -> Result<(), VaultError> {
        let bytes = value.as_bytes();
        if bytes.len() > max_len {
            return Err(VaultError::InvalidEnvelope);
        }
        self.u16(bytes.len() as u16);
        self.bytes.extend_from_slice(bytes);
        Ok(())
    }

    fn finish(self) -> Vec<u8> {
        self.bytes
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn remaining(&self) -> usize {
        self.bytes.len().saturating_sub(self.offset)
    }

    fn take_exact(&mut self, expected: &[u8]) -> Result<(), VaultError> {
        let actual = self.slice(expected.len())?;
        if actual != expected {
            return Err(VaultError::InvalidEnvelope);
        }
        Ok(())
    }

    fn slice(&mut self, length: usize) -> Result<&'a [u8], VaultError> {
        let end = self.offset.checked_add(length).ok_or(VaultError::InvalidEnvelope)?;
        if end > self.bytes.len() {
            return Err(VaultError::InvalidEnvelope);
        }
        let slice = &self.bytes[self.offset..end];
        self.offset = end;
        Ok(slice)
    }

    fn array<const N: usize>(&mut self) -> Result<[u8; N], VaultError> {
        let slice = self.slice(N)?;
        let mut array = [0u8; N];
        array.copy_from_slice(slice);
        Ok(array)
    }

    fn u8(&mut self) -> Result<u8, VaultError> {
        Ok(self.array::<1>()?[0])
    }

    fn u16(&mut self) -> Result<u16, VaultError> {
        Ok(u16::from_le_bytes(self.array::<2>()?))
    }

    fn u32(&mut self) -> Result<u32, VaultError> {
        Ok(u32::from_le_bytes(self.array::<4>()?))
    }

    fn u64(&mut self) -> Result<u64, VaultError> {
        Ok(u64::from_le_bytes(self.array::<8>()?))
    }

    fn bytes(&mut self, max_len: usize) -> Result<Vec<u8>, VaultError> {
        let len = self.u32()? as usize;
        if len > max_len {
            return Err(VaultError::InvalidEnvelope);
        }
        Ok(self.slice(len)?.to_vec())
    }

    fn string(&mut self, max_len: usize) -> Result<String, VaultError> {
        let len = self.u16()? as usize;
        if len > max_len {
            return Err(VaultError::InvalidEnvelope);
        }
        let slice = self.slice(len)?;
        String::from_utf8(slice.to_vec()).map_err(|_| VaultError::InvalidEnvelope)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vault_roundtrip() {
        let mut store = VaultStore::create_named("Personal Vault").unwrap();
        let id1 = store.insert(RecordKind::Note, b"Secret Note Payload".to_vec()).unwrap();
        let id2 = store.insert(RecordKind::Account, b"Account Credentials".to_vec()).unwrap();

        let password = b"StrongPassword_1234!";
        let committed = store.commit_with_password(password).unwrap();

        let opened = VaultStore::unlock(&committed, password).unwrap();
        assert_eq!(opened.name(), "Personal Vault");
        assert_eq!(opened.record_count(), 2);

        let rec1 = opened.get(id1).unwrap();
        assert_eq!(&*rec1.payload, b"Secret Note Payload");

        let rec2 = opened.get(id2).unwrap();
        assert_eq!(&*rec2.payload, b"Account Credentials");
    }

    #[test]
    fn test_change_password() {
        let mut store = VaultStore::create_named("Test").unwrap();
        let id = store.insert(RecordKind::Secret, b"Key123".to_vec()).unwrap();
        let _ = store.commit_with_password(b"old_pass").unwrap();

        store.change_password(b"new_pass").unwrap();
        let committed = store.commit_unlocked().unwrap();

        assert!(VaultStore::unlock(&committed, b"old_pass").is_err());
        let unlocked = VaultStore::unlock(&committed, b"new_pass").unwrap();
        assert_eq!(&*unlocked.get(id).unwrap().payload, b"Key123");
    }
}
