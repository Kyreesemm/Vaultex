import 'dart:convert';
import 'package:equatable/equatable.dart';

enum EntryCategory { account, token, secret, note, all }

extension EntryCategoryExt on EntryCategory {
  String get nameStr {
    switch (this) {
      case EntryCategory.account:
        return 'account';
      case EntryCategory.token:
        return 'api_token';
      case EntryCategory.secret:
        return 'secret';
      case EntryCategory.note:
        return 'note';
      case EntryCategory.all:
        return 'all';
    }
  }

  String get labelRu {
    switch (this) {
      case EntryCategory.account:
        return 'Аккаунты';
      case EntryCategory.token:
        return 'API Ключи';
      case EntryCategory.secret:
        return 'Секреты и Сиды';
      case EntryCategory.note:
        return 'Заметки';
      case EntryCategory.all:
        return 'Все записи';
    }
  }
}

class ParsedAccountData {
  final String service;
  final String username;
  final String email;
  final String password;
  final String? phone;
  final String? twoFactorSecret;
  final String? url;
  final String? notes;

  ParsedAccountData({
    required this.service,
    required this.username,
    required this.email,
    required this.password,
    this.phone,
    this.twoFactorSecret,
    this.url,
    this.notes,
  });

  factory ParsedAccountData.fromJson(Map<String, dynamic> json) {
    return ParsedAccountData(
      service: json['service'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      password: json['password'] ?? '',
      phone: json['phone'],
      twoFactorSecret: json['two_factor_secret'],
      url: json['url'],
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() => {
        'service': service,
        'username': username,
        'email': email,
        'password': password,
        'phone': phone,
        'two_factor_secret': twoFactorSecret,
        'url': url,
        'notes': notes,
      };
}

class ParsedApiTokenData {
  final String name;
  final String token;
  final String? expiresAt;
  final List<String> tags;
  final String? notes;

  ParsedApiTokenData({
    required this.name,
    required this.token,
    this.expiresAt,
    this.tags = const [],
    this.notes,
  });

  factory ParsedApiTokenData.fromJson(Map<String, dynamic> json) {
    return ParsedApiTokenData(
      name: json['name'] ?? '',
      token: json['token'] ?? '',
      expiresAt: json['expires_at'],
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'token': token,
        'expires_at': expiresAt,
        'tags': tags,
        'notes': notes,
      };
}

class ParsedSecretRecoveryData {
  final String name;
  final String secretType; // "single", "mnemonic", "recovery_codes"
  final String value;
  final String? notes;

  ParsedSecretRecoveryData({
    required this.name,
    required this.secretType,
    required this.value,
    this.notes,
  });

  factory ParsedSecretRecoveryData.fromJson(Map<String, dynamic> json) {
    return ParsedSecretRecoveryData(
      name: json['name'] ?? '',
      secretType: json['secret_type'] ?? 'single',
      value: json['value'] ?? '',
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'secret_type': secretType,
        'value': value,
        'notes': notes,
      };
}

class ParsedNoteData {
  final String title;
  final String content;
  final List<String> tags;

  ParsedNoteData({
    required this.title,
    required this.content,
    this.tags = const [],
  });

  factory ParsedNoteData.fromJson(Map<String, dynamic> json) {
    return ParsedNoteData(
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'tags': tags,
      };
}

class VaultEntry extends Equatable {
  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final List<String> tags;
  final int revision;
  final String payloadJson;

  const VaultEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.revision,
    required this.payloadJson,
  });

  EntryCategory get category {
    switch (kind) {
      case 'account':
        return EntryCategory.account;
      case 'api_token':
        return EntryCategory.token;
      case 'secret':
        return EntryCategory.secret;
      case 'note':
      default:
        return EntryCategory.note;
    }
  }

  Map<String, dynamic> get rawJson {
    try {
      return jsonDecode(payloadJson) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  ParsedAccountData? get accountData {
    if (kind != 'account') return null;
    return ParsedAccountData.fromJson(rawJson);
  }

  ParsedApiTokenData? get tokenData {
    if (kind != 'api_token') return null;
    return ParsedApiTokenData.fromJson(rawJson);
  }

  ParsedSecretRecoveryData? get secretData {
    if (kind != 'secret') return null;
    return ParsedSecretRecoveryData.fromJson(rawJson);
  }

  ParsedNoteData? get noteData {
    if (kind != 'note') {
      // Check legacy format
      final json = rawJson;
      if (json.containsKey('title') && json.containsKey('content')) {
        return ParsedNoteData.fromJson(json);
      }
      return null;
    }
    return ParsedNoteData.fromJson(rawJson);
  }

  @override
  List<Object?> get props => [id, kind, title, subtitle, tags, revision, payloadJson];
}
