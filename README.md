# Vaultex

Development version: `0.1.0`. See [CHANGELOG.md](CHANGELOG.md) for the change
history.

Vaultex is a cross-platform privacy vault for encrypted notes, accounts,
passwords, and other sensitive personal data.

The project is built primarily in Rust. Its planned user interface will use web
technologies through a native Tauri shell, with Linux/Wayland as the first
target and Windows and Android as additional targets.

The core library supports versioned vault containers protected by Argon2id and
authenticated encryption. AES-256-GCM is available for Android interoperability;
XChaCha20-Poly1305 is also supported for platforms where its extended nonce is
preferred.
