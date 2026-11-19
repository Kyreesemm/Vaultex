import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/format_utils.dart';
import '../../core/theme.dart';
import '../../logic/blocs/vault_bloc.dart';
import '../widgets/vaultex_wordmark.dart';
import 'unlock_screen.dart';

class VaultPickerScreen extends StatelessWidget {
  const VaultPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<VaultBloc, VaultState>(
          builder: (context, state) {
            if (state is VaultLoading) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppTheme.primaryLight),
                    const SizedBox(height: 16),
                    Text(
                      state.message,
                      style: const TextStyle(fontSize: 14, color: AppTheme.textSecondaryDark),
                    ),
                  ],
                ),
              );
            }

            if (state is VaultLocked) {
              // Canonical path normalization to avoid duplicates
              final localPaths = state.localVaults.map((v) => _normalizePath(v.path)).toSet();
              final filteredRecent = state.recentVaults
                  .where((p) => !localPaths.contains(_normalizePath(p)))
                  .toList();

              final totalDistinctVaults = state.localVaults.length + filteredRecent.length;
              // User requirement: If total vaults <= 1, do not show "Недавние хранилища"
              final shouldShowRecent = totalDistinctVaults > 1 && filteredRecent.isNotEmpty;

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Top Centered Animated "VAULTEX" Wordmark (matching main screen style)
                  const SizedBox(height: 10),
                  const Center(
                    child: VaultexWordmark(
                      fontSize: 24,
                      letterSpacing: 4.5,
                      centered: true,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Action Buttons: "Создать хранилище" & "Выбрать .vex"
                  _buildQuickActions(context, state.defaultDirectory),
                  const SizedBox(height: 24),

                  // Section: Local Vaults
                  if (state.localVaults.isNotEmpty) ...[
                    _buildSectionHeader(
                      title: 'ЛОКАЛЬНЫЕ ХРАНИЛИЩА',
                      trailing: 'Папка Syncthing',
                    ),
                    const SizedBox(height: 8),
                    ...state.localVaults.map(
                      (v) => _buildVaultTile(
                        context,
                        name: formatVaultDisplayName(v.name),
                        path: v.path,
                        sizeBytes: v.sizeBytes,
                        lastModified: v.lastModified,
                      ),
                    ),
                  ] else ...[
                    _buildEmptyState(context, state.defaultDirectory),
                  ],

                  // Section: Recent Vaults (only shown if more than 1 distinct vault)
                  if (shouldShowRecent) ...[
                    const SizedBox(height: 20),
                    _buildSectionHeader(title: 'НЕДАВНИЕ ХРАНИЛИЩА'),
                    const SizedBox(height: 8),
                    ...filteredRecent.map(
                      (path) => _buildVaultTile(
                        context,
                        name: formatVaultDisplayName(path.split(Platform.pathSeparator).last),
                        path: path,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              );
            }

            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight));
          },
        ),
      ),
    );
  }

  static String _normalizePath(String path) {
    try {
      return File(path).resolveSymbolicLinksSync().toLowerCase();
    } catch (_) {
      return path.replaceAll(r'\', '/').toLowerCase();
    }
  }

  Widget _buildSectionHeader({required String title, String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMutedDark,
              letterSpacing: 1.0,
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.textMutedDark,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, String defaultDir) {
    return Row(
      children: [
        // Button 1: "Создать хранилище" (Solid purple, white text/icon, no white border)
        Expanded(
          child: _ActionCardButton(
            title: 'Создать хранилище',
            icon: Icons.add_rounded,
            isPrimary: true,
            onPressed: () => _showCreateVaultDialog(context, defaultDir),
          ),
        ),
        const SizedBox(width: 12),

        // Button 2: "Выбрать .vex" (Dark card style, subtle border, NO white border!)
        Expanded(
          child: _ActionCardButton(
            title: 'Выбрать .vex',
            icon: Icons.file_open_outlined,
            isPrimary: false,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.cardBorderDark,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                // Lock icon badge matching entry cards
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: AppTheme.primaryLight,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimaryDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String defaultDir) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorderDark, width: 1.0),
      ),
      child: Column(
        children: [
          Icon(Icons.shield_outlined, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 12),
          const Text(
            'Локальных хранилищ не найдено',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryDark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Создайте новый контейнер или выберите существующий файл .vex на вашем устройстве.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryDark, height: 1.4),
          ),
        ],
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
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.add_moderator_outlined, color: AppTheme.primaryLight, size: 22),
              SizedBox(width: 10),
              Text('Новое хранилище', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Название хранилища',
                      hintText: 'например, Personal или Work',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dirCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Папка для сохранения',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        onPressed: () async {
                          final dir = await FilePicker.getDirectoryPath();
                          if (dir != null) {
                            setDlgState(() => dirCtrl.text = dir);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Мастер-пароль',
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                        onPressed: () => setDlgState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: obscure,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Подтвердите пароль',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryColor.withOpacity(0.25)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppTheme.primaryLight, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Мастер-пароль защищен Argon2id (64MB RAM, 3 итерации). Данные шифруются AES-256-GCM.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryDark, height: 1.3),
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
              child: const Text('Отмена', style: TextStyle(color: AppTheme.textSecondaryDark)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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
              child: const Text('Создать', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            builder: (_) => UnlockScreen(
              vaultPath: path,
              vaultName: formatVaultDisplayName(name),
            ),
          ),
        );
      }
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _ActionCardButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ActionCardButton({
    required this.title,
    required this.icon,
    required this.isPrimary,
    required this.onPressed,
  });

  @override
  State<_ActionCardButton> createState() => _ActionCardButtonState();
}

class _ActionCardButtonState extends State<_ActionCardButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeInOut,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.isPrimary ? AppTheme.primaryColor : AppTheme.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isPrimary
                  ? Colors.transparent
                  : AppTheme.cardBorderDark,
              width: 1.0,
            ),
            boxShadow: widget.isPrimary
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                color: widget.isPrimary ? Colors.white : AppTheme.primaryLight,
                size: 19,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
