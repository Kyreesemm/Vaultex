import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../logic/blocs/vault_bloc.dart';
import 'unlock_screen.dart';

class VaultPickerScreen extends StatelessWidget {
  const VaultPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
              ),
              child: const Icon(Icons.shield_rounded, color: AppTheme.primaryLight, size: 22),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VAULTEX',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    color: AppTheme.primaryLight,
                  ),
                ),
                Text(
                  'Защищенное хранилище (AES-256-GCM)',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryDark),
                ),
              ],
            ),
          ],
        ),
      ),
      body: BlocBuilder<VaultBloc, VaultState>(
        builder: (context, state) {
          if (state is VaultLoading) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(state.message),
                ],
              ),
            );
          }

          if (state is VaultLocked) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildQuickActions(context, state.defaultDirectory),
                const SizedBox(height: 24),
                if (state.localVaults.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined, size: 20, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Локальные хранилища (${state.localVaults.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        'Syncthing папка',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...state.localVaults.map(
                    (v) => _buildVaultTile(
                      context,
                      name: v.name,
                      path: v.path,
                      sizeBytes: v.sizeBytes,
                      lastModified: v.lastModified,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                if (state.recentVaults.isNotEmpty) ...[
                  const Row(
                    children: [
                      Icon(Icons.history, size: 20, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        'Недавние хранилища',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...state.recentVaults.map(
                    (path) => _buildVaultTile(
                      context,
                      name: path.split(Platform.pathSeparator).last,
                      path: path,
                    ),
                  ),
                ],
              ],
            );
          }

          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, String defaultDir) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Создать хранилище'),
            onPressed: () => _showCreateVaultDialog(context, defaultDir),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Выбрать .vex'),
            onPressed: () => _pickCustomVaultFile(context),
          ),
        ),
      ],
    );
  }

  Widget _buildVaultTile(
    BuildContext context, {
    required String name,
    required String path,
    BigInt? sizeBytes,
    String? lastModified,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UnlockScreen(vaultPath: path, vaultName: name),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppTheme.cardBorderDark : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock, color: AppTheme.primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateVaultDialog(BuildContext context, String defaultDir) {
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final dirCtrl = TextEditingController(text: defaultDir);
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.add_moderator_outlined, color: AppTheme.primaryColor),
              SizedBox(width: 10),
              Text('Новое хранилище'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Название хранилища',
                      hintText: 'например, Personal или Work',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dirCtrl,
                    decoration: InputDecoration(
                      labelText: 'Папка для сохранения',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: () async {
                          final dir = await FilePicker.getDirectoryPath();
                          if (dir != null) {
                            setState(() => dirCtrl.text = dir);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Мастер-пароль',
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: 'Подтвердите пароль',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: Colors.blue, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Мастер-пароль защищен Argon2id (64MB RAM, 3 итерации). Данные шифруются AES-256-GCM.',
                            style: TextStyle(fontSize: 11, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final pass = passCtrl.text;
                final confirm = confirmCtrl.text;
                final dir = dirCtrl.text.trim();

                if (name.isEmpty) {
                  _showSnack(ctx, 'Укажите название хранилища');
                  return;
                }
                if (pass.isEmpty) {
                  _showSnack(ctx, 'Введите мастер-пароль');
                  return;
                }
                if (pass != confirm) {
                  _showSnack(ctx, 'Пароли не совпадают');
                  return;
                }

                Navigator.pop(ctx);
                context.read<VaultBloc>().add(CreateVaultEvent(
                      directory: dir,
                      name: name,
                      password: pass,
                    ));
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  void _pickCustomVaultFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['vex', 'vault'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UnlockScreen(vaultPath: path, vaultName: name),
          ),
        );
      }
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
