import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

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
/// Transfers ONLY encrypted .vault container files (zero-knowledge cloud sync).
/// Cloud has NO access to decryption keys, DEK or plaintext contents.
class GDriveSyncService {
  static const String _driveFilesEndpoint = 'https://www.googleapis.com/drive/v3/files';
  static const String _driveUploadEndpoint =
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart';

  /// Lists all .vault files in Google Drive
  Future<List<GDriveFileInfo>> listVaultFiles(String accessToken) async {
    final uri = Uri.parse(
        '$_driveFilesEndpoint?q=name+contains+\'.vault\'+and+trashed=false&fields=files(id,name,size,modifiedTime)');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка загрузки списка из Google Drive: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final files = (data['files'] as List<dynamic>?) ?? [];
    return files.map((f) => GDriveFileInfo.fromJson(f as Map<String, dynamic>)).toList();
  }

  /// Uploads an encrypted .vault file to Google Drive (creates or updates)
  Future<GDriveFileInfo> uploadVaultFile({
    required File localFile,
    required String accessToken,
    String? existingFileId,
  }) async {
    if (!localFile.existsSync()) {
      throw Exception('Локальный файл не найден: ${localFile.path}');
    }

    final bytes = await localFile.readAsBytes();
    final filename = localFile.uri.pathSegments.last;

    if (existingFileId != null) {
      // Update existing file content
      final updateUri = Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files/$existingFileId?uploadType=media');
      final response = await http.patch(
        updateUri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка обновления файла в Google Drive: ${response.body}');
      }
      return GDriveFileInfo.fromJson(jsonDecode(response.body));
    } else {
      // Multipart upload new file
      final metadata = jsonEncode({
        'name': filename,
        'mimeType': 'application/octet-stream',
      });

      const boundary = '-------314159265358979323846';
      const delimiter = '\r\n--$boundary\r\n';
      const closeDelimiter = '\r\n--$boundary--';

      final body = <int>[];
      body.addAll(utf8.encode(
          '${delimiter}Content-Type: application/json; charset=UTF-8\r\n\r\n$metadata'));
      body.addAll(utf8.encode(
          '${delimiter}Content-Type: application/octet-stream\r\n\r\n'));
      body.addAll(bytes);
      body.addAll(utf8.encode(closeDelimiter));

      final response = await http.post(
        Uri.parse(_driveUploadEndpoint),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
          'Content-Length': body.length.toString(),
        },
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки файла в Google Drive: ${response.body}');
      }
      return GDriveFileInfo.fromJson(jsonDecode(response.body));
    }
  }

  /// Downloads an encrypted .vault file from Google Drive to local disk
  Future<File> downloadVaultFile({
    required String fileId,
    required File targetFile,
    required String accessToken,
  }) async {
    final downloadUri = Uri.parse('$_driveFilesEndpoint/$fileId?alt=media');
    final response = await http.get(
      downloadUri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка скачивания файла из Google Drive: ${response.body}');
    }

    await targetFile.writeAsBytes(response.bodyBytes, flush: true);
    return targetFile;
  }
}
