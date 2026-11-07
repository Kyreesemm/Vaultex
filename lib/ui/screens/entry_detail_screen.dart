import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/security_service.dart';
import '../../core/theme.dart';
import '../../data/models/vault_entry.dart';
import '../../logic/blocs/entries_bloc.dart';
import '../widgets/secret_field_tile.dart';
import '../widgets/totp_field_tile.dart';
import 'entry_edit_screen.dart';

class EntryDetailScreen extends StatelessWidget {
  final VaultEntry entry;

  const EntryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color categoryColor;
    IconData categoryIcon;
    switch (entry.category) {
      case EntryCategory.account:
        categoryColor = AppTheme.accountColor;
        categoryIcon = Icons.person_outline;
        break;
      case EntryCategory.token:
        categoryColor = AppTheme.tokenColor;
        categoryIcon = Icons.key_outlined;
        break;
      case EntryCategory.secret:
        categoryColor = AppTheme.secretColor;
        categoryIcon = Icons.shield_outlined;
        break;
      case EntryCategory.note:
      default:
        categoryColor = AppTheme.noteColor;
        categoryIcon = Icons.description_outlined;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Редактировать',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EntryEditScreen(entry: entry),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Удалить',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: categoryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(categoryIcon, color: categoryColor, size: 30),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.subtitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: categoryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        entry.category.labelRu,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: categoryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Specific entity content
              if (entry.category == EntryCategory.account) _buildAccountDetails(context),
              if (entry.category == EntryCategory.token) _buildTokenDetails(context),
              if (entry.category == EntryCategory.secret) _buildSecretDetails(context),
              if (entry.category == EntryCategory.note) _buildNoteDetails(context),

              // Tags
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entry.tags
                      .map(
                        (tag) => Chip(
                          label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountDetails(BuildContext context) {
    final data = entry.accountData;
    if (data == null) return const SizedBox.shrink();

    return Column(
      children: [
        if (data.username.isNotEmpty)
          _buildInfoTile(
            context,
            label: 'Логин / Username',
            value: data.username,
            icon: Icons.person,
          ),
        if (data.email.isNotEmpty)
          _buildInfoTile(
            context,
            label: 'Email',
            value: data.email,
            icon: Icons.email_outlined,
          ),
        SecretFieldTile(
          label: 'Пароль',
          value: data.password,
          icon: Icons.lock_outline,
        ),
        if (data.twoFactorSecret != null && data.twoFactorSecret!.isNotEmpty) ...[
          TotpFieldTile(secret: data.twoFactorSecret!),
          SecretFieldTile(
            label: '2FA Секретный Ключ (Base32)',
            value: data.twoFactorSecret!,
            icon: Icons.key_outlined,
          ),
        ],
        if (data.phone != null && data.phone!.isNotEmpty)
          _buildInfoTile(
            context,
            label: 'Телефон',
            value: data.phone!,
            icon: Icons.phone_outlined,
          ),
        if (data.url != null && data.url!.isNotEmpty)
          _buildInfoTile(
            context,
            label: 'Веб-сайт / URL',
            value: data.url!,
            icon: Icons.link,
          ),
        if (data.notes != null && data.notes!.isNotEmpty)
          _buildNotesTile(context, data.notes!),
      ],
    );
  }

  Widget _buildTokenDetails(BuildContext context) {
    final data = entry.tokenData;
    if (data == null) return const SizedBox.shrink();

    return Column(
      children: [
        SecretFieldTile(
          label: 'API Токен / Ключ',
          value: data.token,
          icon: Icons.key,
        ),
        if (data.expiresAt != null && data.expiresAt!.isNotEmpty)
          _buildInfoTile(
            context,
            label: 'Срок действия',
            value: data.expiresAt!,
            icon: Icons.calendar_today_outlined,
          ),
        if (data.notes != null && data.notes!.isNotEmpty)
          _buildNotesTile(context, data.notes!),
      ],
    );
  }

  Widget _buildSecretDetails(BuildContext context) {
    final data = entry.secretData;
    if (data == null) return const SizedBox.shrink();

    String typeLabel;
    switch (data.secretType) {
      case 'mnemonic':
        typeLabel = 'Мнемоническая фраза (12/24 слова)';
        break;
      case 'recovery_codes':
        typeLabel = 'Одноразовые резервные коды';
        break;
      default:
        typeLabel = 'Секретное значение';
    }

    return Column(
      children: [
        _buildInfoTile(
          context,
          label: 'Тип секрета',
          value: typeLabel,
          icon: Icons.category_outlined,
        ),
        SecretFieldTile(
          label: 'Секретные данные',
          value: data.value,
          icon: Icons.security,
        ),
        if (data.notes != null && data.notes!.isNotEmpty)
          _buildNotesTile(context, data.notes!),
      ],
    );
  }

  Widget _buildNoteDetails(BuildContext context) {
    final data = entry.noteData;
    if (data == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: MarkdownBody(
        data: data.content,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: isDark ? Colors.grey[200] : Colors.grey[800],
          ),
          h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          code: TextStyle(
            backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Копировать',
            onPressed: () {
              SecurityService().copySecurely(value);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Скопировано в буфер!'), duration: Duration(seconds: 2)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNotesTile(BuildContext context, String notes) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notes, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Заметки',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            notes,
            style: TextStyle(fontSize: 14, color: isDark ? Colors.grey[300] : Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text('Вы действительно хотите удалить "${entry.title}"? Это действие необратимо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<EntriesBloc>().add(DeleteEntryEvent(entry.id));
              Navigator.pop(context);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}
