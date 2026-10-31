import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/security_service.dart';
import '../../core/sync/gdrive_sync_service.dart';
import '../../core/theme.dart';
import '../../data/repositories/vault_repository.dart';
import '../../logic/blocs/vault_bloc.dart';

class SettingsDialog extends StatefulWidget {
  final String currentVaultPath;
  final String currentVaultName;

  const SettingsDialog({
    super.key,
    required this.currentVaultPath,
    required this.currentVaultName,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final VaultRepository _repository = VaultRepository();
  final GDriveSyncService _gdrive = GDriveSyncService();

  late AutoLockTimeout _selectedTimeout;
  bool _canBio = false;
  bool _bioEnabled = false;
  String _defaultDir = '';
  final _gdriveTokenCtrl = TextEditingController();
  bool _gdriveSyncing = false;

  @override
  void initState() {
    super.initState();
    _selectedTimeout = SecurityService().currentTimeout;
    _loadSettings();
  }

  void _loadSettings() async {
    final can = await SecurityService().canUseBiometrics();
    final enabled = await SecurityService().isBiometricEnabled(widget.currentVaultPath);
    final dir = await _repository.getDefaultVaultDirectory();
    if (mounted) {
      setState(() {
        _canBio = can;
        _bioEnabled = enabled;
        _defaultDir = dir;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.settings_outlined, color: AppTheme.primaryColor),
          SizedBox(width: 10),
          Text('Настройки хранилища'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Security Section
              const Text(
                'БЕЗОПАСНОСТЬ',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),

              // Auto-lock selector
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Таймер автоблокировки'),
                subtitle: Text('Блокировать при бездействии: ${_selectedTimeout.labelRu}'),
                trailing: DropdownButton<AutoLockTimeout>(
                  value: _selectedTimeout,
                  underline: const SizedBox.shrink(),
                  items: AutoLockTimeout.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.labelRu)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedTimeout = val);
                      SecurityService().setAutoLockTimeout(val);
                    }
                  },
                ),
              ),

              // Biometrics Toggle
              if (_canBio)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Биометрическая разблокировка'),
                  subtitle: const Text('Touch ID / сканер отпечатков пальцев'),
                  value: _bioEnabled,
                  onChanged: (val) async {
                    if (val) {
                      _promptMasterPasswordForBiometrics(context);
                    } else {
                      await SecurityService().disableBiometric(widget.currentVaultPath);
                      setState(() => _bioEnabled = false);
                    }
                  },
                ),

              // Change Password Button
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.password),
                title: const Text('Сменить мастер-пароль'),
                subtitle: const Text('Перешифровать ключ DEK с новым Argon2id'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showChangePasswordDialog(context),
              ),

              const Divider(height: 32),

              // Syncthing & Storage Section
              const Text(
                'СИНХРОНИЗАЦИЯ И ХРАНЕНИЕ (LOCAL-FIRST)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync_alt, color: Colors.blue),
                title: const Text('Папка Syncthing'),
                subtitle: Text(_defaultDir, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Изменить папку Syncthing',
                  onPressed: () async {
                    final dir = await FilePicker.getDirectoryPath();
                    if (dir != null) {
                      await _repository.setCustomVaultDirectory(dir);
                      setState(() => _defaultDir = dir);
                    }
                  },
                ),
              ),

              const Divider(height: 32),

              // Google Drive Sync Section
              const Text(
                'ОБЛАЧНАЯ СИНХРОНИЗАЦИЯ GOOGLE DRIVE',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              const Text(
                'Передается исключительно зашифрованный контейнер. Ключи и пароли никогда не покидают ваше устройство.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _gdriveTokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Google Drive Access Token',
                  hintText: 'OAuth2 Bearer Token',
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _gdriveSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Загрузить в Drive'),
                      onPressed: _gdriveSyncing ? null : () => _uploadToDrive(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Список файлов'),
                      onPressed: () => _listDriveFiles(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
      ],
    );
  }

  void _uploadToDrive(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final token = _gdriveTokenCtrl.text.trim();
    if (token.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Введите Google Drive Access Token')),
      );
      return;
    }

    setState(() => _gdriveSyncing = true);
    try {
      final file = File(widget.currentVaultPath);
      final result = await _gdrive.uploadVaultFile(
        localFile: file,
        accessToken: token,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Контейнер успешно загружен в Google Drive (ID: ${result.id})')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка Drive: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _gdriveSyncing = false);
    }
  }

  void _listDriveFiles(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final token = _gdriveTokenCtrl.text.trim();
    if (token.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Введите Google Drive Access Token')),
      );
      return;
    }

    try {
      final list = await _gdrive.listVaultFiles(token);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Файлы в Google Drive'),
          content: SizedBox(
            width: 400,
            child: list.isEmpty
                ? const Text('Хранилищ не найдено в Google Drive.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final item = list[i];
                      return ListTile(
                        leading: const Icon(Icons.shield),
                        title: Text(item.name),
                        subtitle: Text('${(item.size / 1024).toStringAsFixed(1)} KB'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _promptMasterPasswordForBiometrics(BuildContext context) {
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтвердите мастер-пароль'),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Мастер-пароль'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (passCtrl.text.isNotEmpty) {
                await SecurityService().saveBiometricPassword(
                  widget.currentVaultPath,
                  passCtrl.text,
                );
                setState(() => _bioEnabled = true);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Сохранить в Keystore'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сменить мастер-пароль'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Новый мастер-пароль'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Подтвердите пароль'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final newP = newPassCtrl.text;
              if (newP.isEmpty || newP != confirmPassCtrl.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Пароли не совпадают или пусты')),
                );
                return;
              }
              Navigator.pop(ctx);
              context.read<VaultBloc>().add(ChangePasswordEvent(newP));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Мастер-пароль успешно изменен!')),
              );
            },
            child: const Text('Сменить'),
          ),
        ],
      ),
    );
  }
}
