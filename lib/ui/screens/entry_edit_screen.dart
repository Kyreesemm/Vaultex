import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/theme.dart';
import '../../data/models/vault_entry.dart';
import '../../logic/blocs/entries_bloc.dart';
import '../widgets/password_generator_dialog.dart';

class EntryEditScreen extends StatefulWidget {
  final VaultEntry? entry;
  final EntryCategory? initialCategory;

  const EntryEditScreen({
    super.key,
    this.entry,
    this.initialCategory,
  });

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> with SingleTickerProviderStateMixin {
  late EntryCategory _category;

  // Account controllers
  final _serviceCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _twoFactorCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _accountNotesCtrl = TextEditingController();

  // API Token controllers
  final _tokenNameCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _tokenExpiresCtrl = TextEditingController();
  final _tokenNotesCtrl = TextEditingController();

  // Secret Recovery controllers
  final _secretNameCtrl = TextEditingController();
  String _secretType = 'single'; // single, mnemonic, recovery_codes
  final _secretValueCtrl = TextEditingController();
  final _secretNotesCtrl = TextEditingController();

  // Note controllers
  final _noteTitleCtrl = TextEditingController();
  final _noteContentCtrl = TextEditingController();
  bool _notePreviewMode = false;

  // Tags
  final _tagInputCtrl = TextEditingController();
  final List<String> _tags = [];

  bool _obscureSecret = true;

  @override
  void initState() {
    super.initState();
    _category = widget.entry?.category ?? widget.initialCategory ?? EntryCategory.account;
    if (_category == EntryCategory.all) _category = EntryCategory.account;

    _populateExistingData();
  }

  void _populateExistingData() {
    final e = widget.entry;
    if (e == null) return;

    _tags.addAll(e.tags);

    final acc = e.accountData;
    if (acc != null) {
      _serviceCtrl.text = acc.service;
      _usernameCtrl.text = acc.username;
      _emailCtrl.text = acc.email;
      _passwordCtrl.text = acc.password;
      _phoneCtrl.text = acc.phone ?? '';
      _twoFactorCtrl.text = acc.twoFactorSecret ?? '';
      _urlCtrl.text = acc.url ?? '';
      _accountNotesCtrl.text = acc.notes ?? '';
    }

    final tok = e.tokenData;
    if (tok != null) {
      _tokenNameCtrl.text = tok.name;
      _tokenCtrl.text = tok.token;
      _tokenExpiresCtrl.text = tok.expiresAt ?? '';
      _tokenNotesCtrl.text = tok.notes ?? '';
    }

    final sec = e.secretData;
    if (sec != null) {
      _secretNameCtrl.text = sec.name;
      _secretType = sec.secretType;
      _secretValueCtrl.text = sec.value;
      _secretNotesCtrl.text = sec.notes ?? '';
    }

    final not = e.noteData;
    if (not != null) {
      _noteTitleCtrl.text = not.title;
      _noteContentCtrl.text = not.content;
    }
  }

  void _save() {
    final bloc = context.read<EntriesBloc>();
    final id = widget.entry?.id;

    switch (_category) {
      case EntryCategory.account:
        if (_serviceCtrl.text.trim().isEmpty && _usernameCtrl.text.trim().isEmpty) {
          _showError('Укажите название сервиса или логин');
          return;
        }
        bloc.add(SaveAccountEvent(
          id: id,
          service: _serviceCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          twoFactorSecret: _twoFactorCtrl.text.trim().isEmpty ? null : _twoFactorCtrl.text.trim(),
          url: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
          notes: _accountNotesCtrl.text.trim().isEmpty ? null : _accountNotesCtrl.text.trim(),
        ));
        break;

      case EntryCategory.token:
        if (_tokenNameCtrl.text.trim().isEmpty) {
          _showError('Укажите название API токена');
          return;
        }
        bloc.add(SaveApiTokenEvent(
          id: id,
          name: _tokenNameCtrl.text.trim(),
          token: _tokenCtrl.text.trim(),
          expiresAt: _tokenExpiresCtrl.text.trim().isEmpty ? null : _tokenExpiresCtrl.text.trim(),
          tags: _tags,
          notes: _tokenNotesCtrl.text.trim().isEmpty ? null : _tokenNotesCtrl.text.trim(),
        ));
        break;

      case EntryCategory.secret:
        if (_secretNameCtrl.text.trim().isEmpty) {
          _showError('Укажите название секрета');
          return;
        }
        bloc.add(SaveSecretRecoveryEvent(
          id: id,
          name: _secretNameCtrl.text.trim(),
          secretType: _secretType,
          value: _secretValueCtrl.text.trim(),
          notes: _secretNotesCtrl.text.trim().isEmpty ? null : _secretNotesCtrl.text.trim(),
        ));
        break;

      case EntryCategory.note:
      default:
        if (_noteTitleCtrl.text.trim().isEmpty) {
          _showError('Укажите заголовок заметки');
          return;
        }
        bloc.add(SaveNoteEvent(
          id: id,
          title: _noteTitleCtrl.text.trim(),
          content: _noteContentCtrl.text,
          tags: _tags,
        ));
        break;
    }

    Navigator.pop(context);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.entry == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Новая запись' : 'Редактировать'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Сохранить'),
              onPressed: _save,
            ),
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
              if (isNew) ...[
                // Category Picker
                const Text('Тип записи:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _categoryChip(EntryCategory.account, 'Аккаунт', Icons.person_outline, AppTheme.accountColor),
                    _categoryChip(EntryCategory.token, 'API Токен', Icons.key_outlined, AppTheme.tokenColor),
                    _categoryChip(EntryCategory.secret, 'Секрет / Сид', Icons.shield_outlined, AppTheme.secretColor),
                    _categoryChip(EntryCategory.note, 'Заметка', Icons.description_outlined, AppTheme.noteColor),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // Fields per category
              if (_category == EntryCategory.account) _buildAccountForm(),
              if (_category == EntryCategory.token) _buildTokenForm(),
              if (_category == EntryCategory.secret) _buildSecretForm(),
              if (_category == EntryCategory.note) _buildNoteForm(),

              const SizedBox(height: 24),
              // Tags Section (for Token and Note)
              if (_category == EntryCategory.token || _category == EntryCategory.note) ...[
                const Text('Теги:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagInputCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Добавить тег...',
                          prefixIcon: Icon(Icons.tag),
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            setState(() {
                              _tags.add(val.trim());
                              _tagInputCtrl.clear();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        if (_tagInputCtrl.text.trim().isNotEmpty) {
                          setState(() {
                            _tags.add(_tagInputCtrl.text.trim());
                            _tagInputCtrl.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag),
                          onDeleted: () {
                            setState(() {
                              _tags.remove(tag);
                            });
                          },
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

  Widget _categoryChip(EntryCategory cat, String label, IconData icon, Color color) {
    final isSelected = _category == cat;
    return ChoiceChip(
      selected: isSelected,
      avatar: Icon(icon, size: 18, color: isSelected ? Colors.white : color),
      label: Text(label),
      selectedColor: color,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.bold : null,
      ),
      onSelected: (val) {
        if (val) setState(() => _category = cat);
      },
    );
  }

  Widget _buildAccountForm() {
    return Column(
      children: [
        TextField(
          controller: _serviceCtrl,
          decoration: const InputDecoration(
            labelText: 'Название сервиса *',
            hintText: 'например, Google, GitHub, Telegram',
            prefixIcon: Icon(Icons.business),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameCtrl,
          decoration: const InputDecoration(
            labelText: 'Логин / Username',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscureSecret,
          decoration: InputDecoration(
            labelText: 'Пароль (секретное поле)',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.vpn_key),
                  tooltip: 'Сгенерировать надежный пароль',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => PasswordGeneratorDialog(
                        onSelectPassword: (pwd) {
                          setState(() {
                            _passwordCtrl.text = pwd;
                          });
                        },
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(_obscureSecret ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _twoFactorCtrl,
          decoration: const InputDecoration(
            labelText: '2FA / TOTP seed (секретное поле)',
            hintText: 'например, JBSWY3DPEHPK3PXP',
            prefixIcon: Icon(Icons.phonelink_lock),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Номер телефона (опционально)',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Веб-сайт / URL',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _accountNotesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Заметки',
            prefixIcon: Icon(Icons.notes),
          ),
        ),
      ],
    );
  }

  Widget _buildTokenForm() {
    return Column(
      children: [
        TextField(
          controller: _tokenNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Название ключа *',
            hintText: 'например, OpenAI Production Key',
            prefixIcon: Icon(Icons.label_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Токен / Секретная строка *',
            prefixIcon: Icon(Icons.key),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenExpiresCtrl,
          decoration: const InputDecoration(
            labelText: 'Срок действия (опционально)',
            hintText: 'например, 2026-12-31',
            prefixIcon: Icon(Icons.calendar_today_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenNotesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Заметки к токену',
            prefixIcon: Icon(Icons.notes),
          ),
        ),
      ],
    );
  }

  Widget _buildSecretForm() {
    return Column(
      children: [
        TextField(
          controller: _secretNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Название секрета *',
            hintText: 'например, Ledger Seed Phrase или GitHub Backup Codes',
            prefixIcon: Icon(Icons.label_outline),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _secretType,
          decoration: const InputDecoration(
            labelText: 'Тип секрета',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: const [
            DropdownMenuItem(value: 'single', child: Text('Одиночный пароль / секрет')),
            DropdownMenuItem(value: 'mnemonic', child: Text('Мнемоническая фраза (12/24 слова)')),
            DropdownMenuItem(value: 'recovery_codes', child: Text('Одноразовые резервные коды')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _secretType = val);
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _secretValueCtrl,
          maxLines: 5,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'Секретное значение (сид / коды) *',
            prefixIcon: Icon(Icons.security),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _secretNotesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Дополнительные заметки',
            prefixIcon: Icon(Icons.notes),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteForm() {
    return Column(
      children: [
        TextField(
          controller: _noteTitleCtrl,
          decoration: const InputDecoration(
            labelText: 'Заголовок заметки *',
            prefixIcon: Icon(Icons.title),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Текст Markdown:', style: TextStyle(fontWeight: FontWeight.bold)),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Редактор'), icon: Icon(Icons.edit, size: 16)),
                ButtonSegment(value: true, label: Text('Просмотр'), icon: Icon(Icons.visibility, size: 16)),
              ],
              selected: {_notePreviewMode},
              onSelectionChanged: (set) => setState(() => _notePreviewMode = set.first),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (!_notePreviewMode)
          TextField(
            controller: _noteContentCtrl,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: '# Заголовок\n\n- Пункт 1\n- Пункт 2\n\n```rust\nfn main() {}\n```',
              alignLabelWithHint: true,
            ),
          )
        else
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 250),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
            ),
            child: MarkdownBody(
              data: _noteContentCtrl.text.isEmpty ? '*Заметка пока пуста*' : _noteContentCtrl.text,
            ),
          ),
      ],
    );
  }
}
