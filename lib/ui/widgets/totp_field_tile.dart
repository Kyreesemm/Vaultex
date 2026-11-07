import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/security_service.dart';
import '../../data/repositories/vault_repository.dart';
import '../../src/rust/totp.dart';

class TotpFieldTile extends StatefulWidget {
  final String secret;

  const TotpFieldTile({
    super.key,
    required this.secret,
  });

  @override
  State<TotpFieldTile> createState() => _TotpFieldTileState();
}

class _TotpFieldTileState extends State<TotpFieldTile> {
  final VaultRepository _repository = VaultRepository();
  Timer? _timer;
  TotpCodeResult? _totp;
  String? _error;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _updateCode();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCode());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateCode() async {
    try {
      final res = await _repository.getTotpCode(widget.secret);
      if (mounted) {
        setState(() {
          _totp = res;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Некорректный ключ Base32';
        });
      }
    }
  }

  void _copyTotp() {
    if (_totp == null) return;
    SecurityService().copySecurely(_totp!.code);
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Одноразовый 2FA код скопирован! Автоочистка через 45 сек.'),
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String displayCode;
    if (_error != null) {
      displayCode = _error!;
    } else if (_totp != null) {
      final c = _totp!.code;
      if (c.length == 6) {
        displayCode = '${c.substring(0, 3)} ${c.substring(3)}';
      } else {
        displayCode = c;
      }
    } else {
      displayCode = '••• •••';
    }

    final double progress =
        _totp != null ? (_totp!.secondsRemaining / _totp!.periodSeconds) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phonelink_lock, color: Colors.teal, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '2FA ОДНОРАЗОВЫЙ КОД (TOTP)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayCode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: _error != null
                        ? Colors.redAccent
                        : (isDark ? Colors.tealAccent : Colors.teal.shade700),
                  ),
                ),
              ],
            ),
          ),
          if (_error == null && _totp != null) ...[
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                    color: _totp!.secondsRemaining <= 5 ? Colors.redAccent : Colors.teal,
                  ),
                ),
                Text(
                  '${_totp!.secondsRemaining}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: Icon(_copied ? Icons.check : Icons.copy, size: 20),
            color: _copied ? Colors.green : Colors.grey,
            tooltip: 'Скопировать 2FA код',
            onPressed: _error == null && _totp != null ? _copyTotp : null,
          ),
        ],
      ),
    );
  }
}
