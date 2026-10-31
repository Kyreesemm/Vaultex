import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
      reason: 'Разблокировка хранилища "${widget.vaultName}"',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: BlocConsumer<VaultBloc, VaultState>(
        listener: (context, state) {
          if (state is VaultUnlocked) {
            // If unlock succeeded and biometrics available but not yet enabled, prompt user
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: AppTheme.primaryColor,
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.vaultName,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.vaultPath,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      autofocus: true,
                      onSubmitted: (_) => _unlockWithPassword(),
                      decoration: InputDecoration(
                        labelText: 'Мастер-пароль',
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: isLoading ? null : _unlockWithPassword,
                        icon: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock_open),
                        label: Text(
                          isLoading ? 'Расшифровка...' : 'Разблокировать',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (_canBiometrics && _biometricEnabled) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: isLoading ? null : _triggerBiometricUnlock,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Войти по биометрии'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 18, color: Colors.grey),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'После открытия ключ DEK защищен в RAM с помощью zeroize и стирается при блокировке.',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
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
        title: const Text('Включить биометрию?'),
        content: const Text(
          'Вы можете использовать сканер отпечатков пальцев / Touch ID для быстрой разблокировки этого хранилища в дальнейшем.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Не сейчас'),
          ),
          FilledButton(
            onPressed: () async {
              await SecurityService().saveBiometricPassword(widget.vaultPath, password);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Включить'),
          ),
        ],
      ),
    );
  }
}
