import 'dart:io';
import '../../src/rust/api/vault.dart' as ffi;

class GDriveFileInfo {
  final String id;
  final String name;
  final int size;
  final DateTime modifiedTime;

  GDriveFileInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.modifiedTime,
  });

  factory GDriveFileInfo.fromJson(Map<String, dynamic> json) {
    return GDriveFileInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      size: int.tryParse(json['size']?.toString() ?? '0') ?? 0,
      modifiedTime: DateTime.tryParse(json['modifiedTime'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Google Drive Sync Provider:
/// Transfers ONLY encrypted .vex container files (zero-knowledge cloud sync).
/// The sync protocol and network engine are fully executed in native Rust core,
/// ensuring that cryptographic secrets and unencrypted data never touch the network
/// or browser/VM heap storage.
class GDriveSyncService {
  /// Lists all .vex files in Google Drive via native Rust client
  Future<List<GDriveFileInfo>> listVaultFiles(String accessToken) async {
    final rawList = await ffi.syncListDriveVaults(accessToken: accessToken);
    return rawList
        .map((item) => GDriveFileInfo(
              id: item.id,
              name: item.name,
              size: item.sizeBytes.toInt(),
              modifiedTime: DateTime.tryParse(item.modifiedTime) ?? DateTime.now(),
            ))
        .toList();
  }

  /// Uploads an encrypted .vex file to Google Drive (creates or updates) via native Rust client
  Future<GDriveFileInfo> uploadVaultFile({
    required File localFile,
    required String accessToken,
    String? existingFileId,
  }) async {
    final res = await ffi.syncUploadVaultToDrive(
      localPath: localFile.path,
      accessToken: accessToken,
      existingFileId: existingFileId,
    );
    return GDriveFileInfo(
      id: res.id,
      name: res.name,
      size: res.sizeBytes.toInt(),
      modifiedTime: DateTime.tryParse(res.modifiedTime) ?? DateTime.now(),
    );
  }

  /// Downloads an encrypted .vex file from Google Drive to local disk via native Rust client
  Future<File> downloadVaultFile({
    required String fileId,
    required File targetFile,
    required String accessToken,
  }) async {
    await ffi.syncDownloadVaultFromDrive(
      fileId: fileId,
      destinationPath: targetFile.path,
      accessToken: accessToken,
    );
    return targetFile;
  }
}
