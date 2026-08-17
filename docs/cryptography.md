# Cryptography

Vaultex uses password-based key derivation followed by authenticated encryption.
The password itself is never stored in the vault. Argon2id derives a 256-bit
content-encryption key from the password and a random 128-bit salt.

Supported algorithms:

- `AES-256-GCM`: a widely interoperable AEAD mode available through Android's
  `Cipher` API from Android API 10 onward;
- `XChaCha20-Poly1305`: an AEAD mode with a 192-bit nonce and a Rust-native
  implementation.

Every encryption operation generates a fresh salt and nonce. The algorithm is
encoded in the container header, and authentication failure is intentionally
reported together with wrong-password failure.

Entry passwords remain recoverable secrets because a password manager must be
able to provide them to a login form. Hashing them would make that feature
impossible. Hashes should be used for one-way verification data only.

The Android integration should prefer the platform keystore for protecting
device-bound wrapping keys. The vault password remains the user's knowledge
factor, while the keystore can provide an optional device-unlock factor.

