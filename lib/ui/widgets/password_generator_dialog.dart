import 'package:flutter/material.dart';
import '../../core/security_service.dart';
import '../../data/repositories/vault_repository.dart';

class PasswordGeneratorDialog extends StatefulWidget {
  final ValueChanged<String>? onSelectPassword;

  const PasswordGeneratorDialog({super.key, this.onSelectPassword});

  @override
  State<PasswordGeneratorDialog> createState() => _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  final VaultRepository _repository = VaultRepository();
  double _length = 20;
  bool _includeSymbols = true;
  bool _includeNumbers = true;
  String _generated = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() async {
    final pwd = await _repository.generatePassword(
      length: _length.toInt(),
      includeSymbols: _includeSymbols,
      includeNumbers: _includeNumbers,
    );
    if (mounted) {
      setState(() {
        _generated = pwd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.vpn_key_outlined),
          SizedBox(width: 10),
          Text('Генератор паролей'),
        ],
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _generated,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Сгенерировать заново',
                    onPressed: _regenerate,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Скопировать',
                    onPressed: () {
                      SecurityService().copySecurely(_generated);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Пароль скопирован! Автоочистка через 45 сек.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Длина пароля:'),
                Text(
                  '${_length.toInt()} символов',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Slider(
              value: _length,
              min: 8,
              max: 64,
              divisions: 56,
              label: _length.toInt().toString(),
              onChanged: (val) {
                setState(() {
                  _length = val;
                });
                _regenerate();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Спецсимволы (!@#\$)'),
              value: _includeSymbols,
              onChanged: (val) {
                setState(() {
                  _includeSymbols = val;
                });
                _regenerate();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Цифры (0-9)'),
              value: _includeNumbers,
              onChanged: (val) {
                setState(() {
                  _includeNumbers = val;
                });
                _regenerate();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        if (widget.onSelectPassword != null)
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Использовать'),
            onPressed: () {
              widget.onSelectPassword!(_generated);
              Navigator.pop(context);
            },
          ),
      ],
    );
  }
}
