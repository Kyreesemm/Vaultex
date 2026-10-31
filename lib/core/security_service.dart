import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AutoLockTimeout {
  oneMinute(60, '1 минута'),
  fiveMinutes(300, '5 минут'),
  fifteenMinutes(900, '15 минут'),
  never(0, 'Никогда');

  final int seconds;
  final String labelRu;
  const AutoLockTimeout(this.seconds, this.labelRu);

  static AutoLockTimeout fromSeconds(int s) {
    return AutoLockTimeout.values.firstWhere(
      (v) => v.seconds == s,
      orElse: () => AutoLockTimeout.fiveMinutes,
    );
  }
}

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    wOptions: WindowsOptions(useBackwardCompatibility: false),
    lOptions: LinuxOptions(),
  );

  Timer? _clipboardTimer;
  String? _lastCopiedSensitiveText;

  Timer? _inactivityTimer;
  void Function()? _onAutoLockTriggered;

  AutoLockTimeout _currentTimeout = AutoLockTimeout.fiveMinutes;
  AutoLockTimeout get currentTimeout => _currentTimeout;

  Future<void> init(void Function() onAutoLock) async {
    _onAutoLockTriggered = onAutoLock;
    final prefs = await SharedPreferences.getInstance();
    final savedSeconds = prefs.getInt('auto_lock_seconds') ?? 300;
    _currentTimeout = AutoLockTimeout.fromSeconds(savedSeconds);
    resetInactivityTimer();
  }

  void setAutoLockTimeout(AutoLockTimeout timeout) async {
    _currentTimeout = timeout;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_lock_seconds', timeout.seconds);
    resetInactivityTimer();
  }

  void resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_currentTimeout == AutoLockTimeout.never || _currentTimeout.seconds == 0) {
      return;
    }

    _inactivityTimer = Timer(Duration(seconds: _currentTimeout.seconds), () {
      _onAutoLockTriggered?.call();
    });
  }

  void stopInactivityTimer() {
    _inactivityTimer?.cancel();
  }

  /// Secure copy to clipboard with auto-clear after 45 seconds
  Future<void> copySecurely(String secretValue, {int clearAfterSeconds = 45}) async {
    _clipboardTimer?.cancel();
    _lastCopiedSensitiveText = secretValue;

    await Clipboard.setData(ClipboardData(text: secretValue));

    _clipboardTimer = Timer(Duration(seconds: clearAfterSeconds), () async {
      final currentData = await Clipboard.getData(Clipboard.kTextPlain);
      if (currentData?.text == _lastCopiedSensitiveText) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      _lastCopiedSensitiveText = null;
    });
  }

  /// Biometric features
  Future<bool> canUseBiometrics() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      return canAuthenticate;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics({String reason = 'Разблокировка хранилища Vaultex'}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> saveBiometricPassword(String vaultPath, String password) async {
    final key = 'bio_pass_${vaultPath.hashCode}';
    await _secureStorage.write(key: key, value: password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bio_enabled_${vaultPath.hashCode}', true);
  }

  Future<String?> getBiometricPassword(String vaultPath) async {
    final key = 'bio_pass_${vaultPath.hashCode}';
    return await _secureStorage.read(key: key);
  }

  Future<bool> isBiometricEnabled(String vaultPath) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('bio_enabled_${vaultPath.hashCode}') ?? false;
  }

  Future<void> disableBiometric(String vaultPath) async {
    final key = 'bio_pass_${vaultPath.hashCode}';
    await _secureStorage.delete(key: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bio_enabled_${vaultPath.hashCode}', false);
  }
}
