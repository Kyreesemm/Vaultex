# Changelog

All notable changes to the **Vaultex** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
- Reused the visual direction and typography approach from the existing WebFlow Runtime interface example.
- Moved frontend font assets into `webui/fonts` so the application does not depend on ignored `no-public` materials.
- Configured Tauri to load the static interface directly from the `webui` directory without requiring a separate development HTTP server.
- Added project and build artifact exclusions to `.gitignore`.
- Restored the standard native window decorations for desktop environments.
- Configured Linux Wayland sessions to use the Plasma-compatible XWayland path by default.

### Fixed
- Added a Linux Wayland/WebKitGTK graphics workaround for the DMA-BUF and NVIDIA explicit synchronization startup issue.
- Removed the static UI's dependency on an unavailable `localhost:1420` development server that could result in an HTTP 404 page.
- Removed the custom titlebar and returned window rendering to the native Wayland/GTK/Plasma titlebar.
- Added a visible 128×128 application icon for native Linux window decorations.
- Disabled the Linux WebKitGTK DMA-BUF renderer when it prevents the UI webview from rendering.
