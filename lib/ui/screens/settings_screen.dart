import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/security_service.dart';
import '../../core/settings_service.dart';
import '../../core/sync/gdrive_sync_service.dart';
import '../../core/theme.dart';
import '../../data/repositories/vault_repository.dart';
import '../../logic/blocs/vault_bloc.dart';

class SettingsScreen extends StatefulWidget {
  final String currentVaultPath;
  final String currentVaultName;

  const SettingsScreen({
    super.key,
    required this.currentVaultPath,
    required this.currentVaultName,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
  void dispose() {
    _gdriveTokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Назад',
        ),
        title: const Text(
          'Настройки',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // 1. Section: Appearance / Interface
            _buildSectionHeader('ВНЕШНИЙ ВИД И ИНТЕРФЕЙС'),
            _buildCardGroup(
              children: [
                ValueListenableBuilder<StatsDisplayMode>(
                  valueListenable: SettingsService().statsDisplayMode,
                  builder: (context, currentMode, _) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.dashboard_customize_outlined,
                          color: AppTheme.primaryLight,
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Отображение статистики',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        currentMode.labelRu,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryDark),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                      onTap: () => _showStatsModeSelector(context, currentMode),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 2. Section: Security
            _buildSectionHeader('БЕЗОПАСНОСТЬ'),
            _buildCardGroup(
              children: [
                // Auto-lock selector
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.timer_outlined,
                      color: AppTheme.primaryLight,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Таймер автоблокировки',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Блокировать при бездействии: ${_selectedTimeout.labelRu}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryDark),
                  ),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<AutoLockTimeout>(
                      value: _selectedTimeout,
                      icon: const Icon(Icons.unfold_more, size: 18, color: Colors.grey),
                      dropdownColor: AppTheme.cardElevatedDark,
                      borderRadius: BorderRadius.circular(14),
                      items: AutoLockTimeout.values
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.labelRu, style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedTimeout = val);
                          SecurityService().setAutoLockTimeout(val);
                        }
                      },
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56, endIndent: 16),

                // Biometrics Switch
                if (_canBio) ...[
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        color: AppTheme.primaryLight,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Биометрическая разблокировка',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Сканер отпечатков пальцев',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryDark),
                    ),
                    activeColor: AppTheme.primaryLight,
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
                  const Divider(height: 1, indent: 56, endIndent: 16),
                ],

                // Change master password
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.password_outlined,
                      color: AppTheme.primaryLight,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Сменить мастер-пароль',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Перешифровать ключ DEK с новым Argon2id',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryDark),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  onTap: () => _showChangePasswordDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 3. Section: Local-first Sync & Storage
            _buildSectionHeader('СИНХРОНИЗАЦИЯ И ХРАНЕНИЕ (LOCAL-FIRST)'),
            _buildCardGroup(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.sync_alt, color: Color(0xFF38BDF8), size: 20),
                  ),
                  title: const Text(
                    'Папка Syncthing',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _defaultDir.isEmpty ? 'Папка по умолчанию' : _defaultDir,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.folder_open_outlined),
                    tooltip: 'Выбрать папку',
                    onPressed: () async {
                      final dir = await FilePicker.getDirectoryPath();
                      if (dir != null) {
                        await _repository.setCustomVaultDirectory(dir);
                        setState(() => _defaultDir = dir);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 4. Section: Google Drive Cloud Backup
            _buildSectionHeader('ОБЛАЧНАЯ СИНХРОНИЗАЦИЯ GOOGLE DRIVE'),
            _buildCardGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34D399).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.cloud_outlined,
                              color: Color(0xFF34D399),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Резервная копия сейфа',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Передается исключительно зашифрованный контейнер (.vex). Ключи шифрования и пароли никогда не покидают ваше устройство.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryDark, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _gdriveTokenCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Google Drive Access Token',
                          hintText: 'OAuth2 Bearer Token',
                          prefixIcon: const Icon(Icons.key_outlined, size: 18),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: _gdriveSyncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.cloud_upload_outlined, size: 18),
                              label: const Text('Загрузить', style: TextStyle(fontSize: 13)),
                              onPressed: _gdriveSyncing ? null : () => _uploadToDrive(context),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.cloud_download_outlined, size: 18),
                              label: const Text('Файлы в Drive', style: TextStyle(fontSize: 13)),
                              onPressed: () => _listDriveFiles(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 5. Section: About Vault Info
            _buildSectionHeader('О ХРАНИЛИЩЕ'),
            _buildCardGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield_rounded, size: 18, color: AppTheme.primaryLight),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.currentVaultName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'v2.0.0',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Путь: ${widget.currentVaultPath}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryDark),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Шифрование: AES-256-GCM • Argon2id (m=64MB, t=3, p=4) • Zeroize RAM',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMutedDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.textMutedDark,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildCardGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorderDark, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  void _showStatsModeSelector(BuildContext context, StatsDisplayMode currentMode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Отображение статистики',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Выберите вид панели статистики на главном экране',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryDark),
                ),
                const SizedBox(height: 14),

                // 3 Options
                _buildModeTile(
                  ctx,
                  mode: StatsDisplayMode.compact,
                  current: currentMode,
                  icon: Icons.view_column_rounded,
                ),
                const SizedBox(height: 8),
                _buildModeTile(
                  ctx,
                  mode: StatsDisplayMode.progressBar,
                  current: currentMode,
                  icon: Icons.linear_scale_rounded,
                ),
                const SizedBox(height: 8),
                _buildModeTile(
                  ctx,
                  mode: StatsDisplayMode.hidden,
                  current: currentMode,
                  icon: Icons.visibility_off_outlined,
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModeTile(
    BuildContext ctx, {
    required StatsDisplayMode mode,
    required StatsDisplayMode current,
    required IconData icon,
  }) {
    final isSelected = mode == current;

    return InkWell(
      onTap: () {
        SettingsService().setStatsDisplayMode(mode);
        Navigator.pop(ctx);
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withOpacity(0.16) : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primaryLight : AppTheme.cardBorderDark,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withOpacity(0.24)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppTheme.primaryLight : Colors.white70,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.labelRu,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.descriptionRu,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondaryDark,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primaryLight,
                size: 20,
              ),
          ],
        ),
      ),
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
          backgroundColor: AppTheme.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Файлы в Google Drive', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: list.isEmpty
                ? const Text(
                    'Хранилищ не найдено в Google Drive.',
                    style: TextStyle(color: AppTheme.textSecondaryDark),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final item = list[i];
                      return ListTile(
                        leading: const Icon(Icons.shield, color: AppTheme.primaryLight),
                        title: Text(item.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          '${(item.size / 1024).toStringAsFixed(1)} KB',
                          style: const TextStyle(fontSize: 12),
                        ),
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
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Подтвердите мастер-пароль', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Мастер-пароль',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
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
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Сменить мастер-пароль', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Новый мастер-пароль',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Подтвердите пароль',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
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
