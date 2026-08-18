# Changelog

All notable changes to the **Vaultex** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added functional Overview, Vault, and Generator sections with separate
  navigation and content.
- Added full vault entry listing, direct navigation from overview cards, and
  password copying from the Generator section.
- Added the first functional UI-to-core integration through Tauri commands.
- Added local vault creation and password-based unlocking.
- Added encrypted persistence for vault entries on the device.
- Added entry creation, deletion, vault locking, and secure password generation.
- Added the initial Vaultex encrypted-vault core library.
- Added the Svelte + Vite user interface and Tauri desktop shell.
- Added versioned vault containers protected by Argon2id and authenticated
  encryption.
- Added AES-256-GCM and XChaCha20-Poly1305 encryption support.
- Added a custom title bar for Linux and Linux Wayland sessions.

### Changed

- Marked Identities, notifications, and identity creation as unavailable until
  their corresponding functionality is implemented.
- Established Linux/Wayland as the first desktop target, with Windows and
  Android planned as additional targets.
- Reworked the title bar and bottom bar layout for the Linux application.

### Fixed

- Fixed custom title bar behavior on Linux.
- Fixed the bottom bar rendering issue on Linux.
