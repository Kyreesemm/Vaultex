import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/format_utils.dart';
import '../../core/security_service.dart';
import '../../core/theme.dart';
import '../../logic/blocs/vault_bloc.dart';

class UnlockScreen extends StatefulWidget {
  final String vaultPath;
  final String vaultName;

  const UnlockScreen({
    super.key,
    required this.vaultPath,
    required this.vaultName,
  });

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _canBiometrics = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _checkBiometrics() async {
    final canBio = await SecurityService().canUseBiometrics();
    final enabled = await SecurityService().isBiometricEnabled(widget.vaultPath);
    if (mounted) {
      setState(() {
        _canBiometrics = canBio;
        _biometricEnabled = enabled;
      });
      if (enabled && canBio) {
        _triggerBiometricUnlock();
      }
    }
  }

  void _triggerBiometricUnlock() async {
    final success = await SecurityService().authenticateWithBiometrics(
      reason: 'Разблокировка хранилища "${formatVaultDisplayName(widget.vaultName)}"',
    );
    if (success && mounted) {
      final savedPass = await SecurityService().getBiometricPassword(widget.vaultPath);
      if (savedPass != null && savedPass.isNotEmpty && mounted) {
        context.read<VaultBloc>().add(OpenVaultEvent(
              path: widget.vaultPath,
              password: savedPass,
            ));
      }
    }
  }

  void _unlockWithPassword() {
    final pass = _passwordController.text;
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите мастер-пароль')),
      );
      return;
    }

    context.read<VaultBloc>().add(OpenVaultEvent(
          path: widget.vaultPath,
          password: pass,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final displayName = formatVaultDisplayName(widget.vaultName);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Назад',
        ),
      ),
      body: BlocConsumer<VaultBloc, VaultState>(
        listener: (context, state) {
          if (state is VaultUnlocked) {
            if (_canBiometrics && !_biometricEnabled && _passwordController.text.isNotEmpty) {
              _promptEnableBiometrics(context, _passwordController.text);
            } else {
              Navigator.pop(context);
            }
          }
          if (state is VaultFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error), backgroundColor: Colors.redAccent),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is VaultLoading;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Circular Lock Icon with Amethyst Glow
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor.withOpacity(0.14),
                        border: Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.35),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withOpacity(0.24),
                            blurRadius: 28,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: AppTheme.primaryLight,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Clean formatted vault name
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryDark,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Master password input field
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      autofocus: true,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      onSubmitted: (_) => _unlockWithPassword(),
                      decoration: InputDecoration(
                        labelText: 'Мастер-пароль',
                        prefixIcon: const Icon(Icons.key_outlined, size: 20, color: AppTheme.primaryLight),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 20,
                            color: Colors.white70,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // "Разблокировать" button (Vibrant purple, white text/icon, no white border)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                        ),
                        onPressed: isLoading ? null : _unlockWithPassword,
                        icon: isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock_open_rounded, size: 20, color: Colors.white),
                        label: Text(
                          isLoading ? 'Расшифровка...' : 'Разблокировать',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Bottom friendly security card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.cardDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.cardBorderDark, width: 1.0),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 18, color: AppTheme.primaryLight),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Сквозное локальное шифрование. Ваши секреты расшифровываются исключительно на этом устройстве.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondaryDark,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _promptEnableBiometrics(BuildContext context, String password) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Включить биометрию?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: const Text(
          'Вы можете использовать сканер отпечатков пальцев для быстрой разблокировки этого хранилища в дальнейшем.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryDark, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Не сейчас', style: TextStyle(color: AppTheme.textSecondaryDark)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              await SecurityService().saveBiometricPassword(widget.vaultPath, password);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Включить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
