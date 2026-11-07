import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/security_service.dart';
import '../../core/theme.dart';

class SecretFieldTile extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isMonospace;

  const SecretFieldTile({
    super.key,
    required this.label,
    required this.value,
    this.icon = Icons.lock_outline,
    this.isMonospace = true,
  });

  @override
  State<SecretFieldTile> createState() => _SecretFieldTileState();
}

class _SecretFieldTileState extends State<SecretFieldTile> {
  bool _revealed = false;
  Timer? _autoHideTimer;
  bool _copied = false;

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _toggleReveal() {
    setState(() {
      _revealed = !_revealed;
    });

    _autoHideTimer?.cancel();
    if (_revealed) {
      // Auto-hide secret after 30 seconds as specified in Master Spec
      _autoHideTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _revealed = false;
          });
        }
      });
    }
  }

  Future<void> _copySecret() async {
    await SecurityService().copySecurely(widget.value);
    if (mounted) {
      setState(() {
        _copied = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Скопировано! Буфер очистится через 45 сек.'),
          duration: Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _copied = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const masked = '••••••••••••••••';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.cardBorderDark : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const Spacer(),
              if (_revealed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Скроется через 30с',
                    style: TextStyle(fontSize: 10, color: Colors.amber),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _revealed ? widget.value : masked,
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: widget.isMonospace ? 'monospace' : null,
                    letterSpacing: _revealed ? 0 : 2,
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: _revealed ? FontWeight.w500 : FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _revealed ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
                tooltip: _revealed ? 'Скрыть' : 'Показать (на 30 сек)',
                onPressed: _toggleReveal,
              ),
              IconButton(
                icon: Icon(
                  _copied ? Icons.check : Icons.copy,
                  size: 20,
                  color: _copied ? Colors.green : (isDark ? Colors.grey[300] : Colors.grey[700]),
                ),
                tooltip: 'Безопасно скопировать',
                onPressed: _copySecret,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
