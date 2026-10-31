import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../src/rust/api/vault.dart' as ffi;
import '../models/vault_entry.dart';

class VaultRepository {
  static const String _prefRecentVaults = 'recent_vault_paths';
  static const String _prefCustomVaultDir = 'custom_vault_directory';

  Future<ffi.VaultInfo> getStatus() async {
    return await ffi.getVaultInfo();
  }

  Future<ffi.VaultInfo> open(String path, String password) async {
    final info = await ffi.openVault(path: path, password: password);
    await rememberVault(path);
    return info;
  }

  Future<ffi.VaultInfo> create(String directory, String name, String password) async {
    final info = await ffi.createVault(
      directory: directory,
      name: name,
      password: password,
    );
    if (info.path != null) {
      await rememberVault(info.path!);
    }
    return info;
  }

  Future<void> lock() async {
    await ffi.lockVault();
  }

  Future<void> save() async {
    await ffi.saveVault();
  }

  Future<bool> checkConflict() async {
    return await ffi.checkSyncConflict();
  }

  Future<void> changePassword(String newPassword) async {
    await ffi.changeVaultPassword(newPassword: newPassword);
  }

  Future<List<VaultEntry>> getEntries({String? kindFilter, String? query}) async {
    final rawList = await ffi.listEntries(
      kindFilter: kindFilter,
      query: query,
    );

    return rawList
        .map((item) => VaultEntry(
              id: item.id,
              kind: item.kind,
              title: item.title,
              subtitle: item.subtitle,
              tags: item.tags,
              revision: item.revision.toInt(),
              payloadJson: item.payloadJson,
            ))
        .toList();
  }

  Future<VaultEntry> getEntry(String id) async {
    final item = await ffi.getEntry(id: id);
    return VaultEntry(
      id: item.id,
      kind: item.kind,
      title: item.title,
      subtitle: item.subtitle,
      tags: item.tags,
      revision: item.revision.toInt(),
      payloadJson: item.payloadJson,
    );
  }

  Future<String> saveAccount({
    String? id,
    required String service,
    required String username,
    required String email,
    required String password,
    String? phone,
    String? twoFactorSecret,
    String? url,
    String? notes,
  }) async {
    return await ffi.saveAccount(
      id: id,
      service: service,
      username: username,
      email: email,
      password: password,
      phone: phone,
      twoFactorSecret: twoFactorSecret,
      url: url,
      notes: notes,
    );
  }

  Future<String> saveApiToken({
    String? id,
    required String name,
    required String token,
    String? expiresAt,
    required List<String> tags,
    String? notes,
  }) async {
    return await ffi.saveApiToken(
      id: id,
      name: name,
      token: token,
      expiresAt: expiresAt,
      tags: tags,
      notes: notes,
    );
  }

  Future<String> saveSecretRecovery({
    String? id,
    required String name,
    required String secretType,
    required String value,
    String? notes,
  }) async {
    return await ffi.saveSecretRecovery(
      id: id,
      name: name,
      secretType: secretType,
      value: value,
      notes: notes,
    );
  }

  Future<String> saveNote({
    String? id,
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    return await ffi.saveNote(
      id: id,
      title: title,
      content: content,
      tags: tags,
    );
  }

  Future<void> deleteEntry(String id) async {
    await ffi.deleteEntry(id: id);
  }

  Future<String> generatePassword({
    int length = 20,
    bool includeSymbols = true,
    bool includeNumbers = true,
  }) async {
    return ffi.generateSecurePassword(
      length: length,
      includeSymbols: includeSymbols,
      includeNumbers: includeNumbers,
    );
  }

  /// Syncthing / Local Storage Directory
  Future<String> getDefaultVaultDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_prefCustomVaultDir);
    if (custom != null && Directory(custom).existsSync()) {
      return custom;
    }

    if (Platform.isAndroid) {
      // Standard public Documents folder accessible by Syncthing
      const standardDoc = '/storage/emulated/0/Documents/Vaultex';
      try {
        final dir = Directory(standardDoc);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return standardDoc;
      } catch (_) {
        // Fallback to app directory
        final appDir = await getApplicationDocumentsDirectory();
        final vaultexDir = Directory('${appDir.path}/Vaultex');
        if (!vaultexDir.existsSync()) {
          vaultexDir.createSync(recursive: true);
        }
        return vaultexDir.path;
      }
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      final vaultexDir = Directory('${docDir.path}/Vaultex');
      if (!vaultexDir.existsSync()) {
        vaultexDir.createSync(recursive: true);
      }
      return vaultexDir.path;
    }
  }

  Future<void> setCustomVaultDirectory(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomVaultDir, path);
  }

  Future<List<ffi.LocalVaultItem>> listLocalVaults([String? directory]) async {
    final dir = directory ?? await getDefaultVaultDirectory();
    return ffi.listVaultFiles(directory: dir);
  }

  Future<List<String>> getRecentVaults() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_prefRecentVaults) ?? [];
  }

  Future<void> rememberVault(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final recents = prefs.getStringList(_prefRecentVaults) ?? [];
    recents.remove(path);
    recents.insert(0, path);
    if (recents.length > 10) {
      recents.removeLast();
    }
    await prefs.setStringList(_prefRecentVaults, recents);
  }
}
