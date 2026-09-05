# Changelog

All notable changes to the **Vaultex** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added dynamic vault-directory scanning when the unlock screen path changes.
- Added encrypted vault display names stored inside the authenticated manifest.
- Added platform-aware vault directory discovery and a remembered last-vault selection.
- Added a local configuration for non-secret vault paths and display-name metadata.
- Added vault-name input to the new-vault creation flow.
- Added storage format version 3 for the encrypted manifest name field.
- Added separate unlock and new-vault creation screens with mobile-friendly navigation between them.
- Added the first functional unlock screen with master-password and vault-path inputs.
- Added frontend integration for opening, creating, locking, and checking the active vault session through Rust IPC.
- Added a mobile-friendly unlock layout that keeps vault content unavailable until the session is unlocked.
- Added a Rust-owned Tauri IPC service layer with one active, validated vault session.
- Added vault create, open, lock, save, status, record listing, record reading, record creation, record updates, and record deletion commands.
- Added structured IPC errors that avoid exposing password or decryption implementation details to the frontend.
- Added request validation for vault paths, record identifiers, record kinds, and record payload sizes.
- Added unlocked-session persistence so an already opened vault can be saved without re-entering the master password.
- Added explicit `VaultStore::lock()` lifecycle operation that drops the in-memory vault session.
- Added cross-platform `VaultFile` persistence with atomic encrypted-file replacement.
- Added temporary-file creation with collision resistance, write flushing, and parent-directory syncing on Unix.
- Added Windows atomic replacement using `MoveFileExW` with replace and write-through flags.
- Added persistence tests for disk round-trips, plaintext absence, and failed-password handling.
- Added a versioned binary Vaultex storage container with a clear structural frame and encrypted payload regions.
- Added a password-wrapped random vault data-encryption key so records do not derive independent keys directly from the password.
- Added an encrypted manifest for record identity, type, revision, and block mapping.
- Added the in-memory `VaultStore` session with create, unlock, insert, read, update, remove, and commit operations.
- Added zeroizing in-memory record payloads and bounds checks for malformed or oversized containers.
- Added storage tests for round-trips, wrong-password unlocks, record tampering, updates, and removals.
- Bound the binary header, KDF parameters, vault ID, and storage format version to the wrapped-DEK authentication tag.
- Bound the manifest and record authentication data to the explicit storage format version.
- Advanced the binary container format version after changing its authenticated-data contract.
- Added a format-independent Rust cryptographic core for encrypted vault payloads.
- Added Argon2id key derivation with a 64 MiB memory cost, three iterations, and a 256-bit derived key.
- Added AES-256-GCM encryption with authenticated associated data, random salts, and random nonces.
- Added encrypted envelope validation, authentication failure handling, and zeroizing decrypted buffers.
- Added re-encryption support for rotating an encrypted payload's salt and nonce.
- Added unit tests covering encryption round-trips, wrong passwords, tampering, AAD binding, version validation, and re-encryption.
- Added the initial Vaultex Tauri 2 application shell with a Rust backend.
- Added an adaptive HTML, CSS, and JavaScript interface for Windows, Linux, and Android targets.
- Added navigation pages for the overview, notes, secrets, collections, and settings.
- Added a desktop drawer navigation and a mobile bottom navigation bar.
- Added the initial dark Graffiti Grey visual theme with a softly illuminated animated Vaultex wordmark.
- Added local bundled Roboto and Material Symbols Rounded fonts for offline interface rendering.
- Added the initial Rust `vault_status` command for the application shell.
- Added a fallback application icon for Tauri builds.

### Changed
- Styled the vault selector to match the dark input fields and fixed its height.
- Automatically selects the first discovered vault when no remembered selection is available.
- Removed the decorative background highlight so the main interface and topbar use a uniform deep graphite background.
- Darkened the global interface palette to deep graphite-grey backgrounds.
- Made the unlock screen fully opaque so protected content cannot show through it.
- Switched the bundle identifier to a desktop-specific reverse-DNS identifier.
- Reused the visual direction and typography approach from the existing WebFlow Runtime interface example.
- Moved frontend font assets into `webui/fonts` so the application does not depend on ignored `no-public` materials.
- Configured Tauri to load the static interface directly from the `webui` directory without requiring a separate development HTTP server.
- Added project and build artifact exclusions to `.gitignore`.
- Restored the standard native window decorations for desktop environments.
- Configured Linux Wayland sessions to use the Plasma-compatible XWayland path by default.

### Fixed
- Fixed Linux AppImage bundling by providing a square PNG application icon.
- Fixed production UI loading by enabling the Tauri frontend bridge and using the bundled `webui` assets for release builds.
- Added a Linux Wayland/WebKitGTK graphics workaround for the DMA-BUF and NVIDIA explicit synchronization startup issue.
- Removed the static UI's dependency on an unavailable `localhost:1420` development server that could result in an HTTP 404 page.
- Removed the custom titlebar and returned window rendering to the native Wayland/GTK/Plasma titlebar.
- Added a visible 128×128 application icon for native Linux window decorations.
- Disabled the Linux WebKitGTK DMA-BUF renderer when it prevents the UI webview from rendering.
