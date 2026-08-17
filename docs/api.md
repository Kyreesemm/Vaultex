# Vaultex Core API

`vaultex-core` is a storage-independent Rust library. It does not read files,
access the network, or manage UI state.

## `Vault`

`Vault::new()` creates an empty vault.

`Vault::insert(id, entry)` inserts or replaces an entry by identifier.

`Vault::entries()` returns a read-only ordered map of entries.

`Vault::remove(id)` removes an entry and returns it when present.

`Vault::seal(password)` encrypts the vault using the default
`XChaCha20Poly1305` algorithm.

`Vault::seal_with(password, algorithm)` encrypts the vault using an explicit
`EncryptionAlgorithm`.

`Vault::open(container, password)` detects the algorithm from the versioned
container header and decrypts it.

## `Entry`

An entry contains a title and optional username, password, and notes. The
current API keeps these values in memory as strings for editing; the storage
container never stores them in plaintext.

## Security boundary

The caller is responsible for protecting the password input, limiting retries,
choosing secure file permissions, and clearing UI clipboard data. Passwords for
vault entries are secrets and must not be replaced with hashes when they need to
be retrieved for login; hashes are appropriate only for values that are verified
but never recovered.

