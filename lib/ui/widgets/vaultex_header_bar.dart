import 'package:flutter/material.dart';
import 'vaultex_wordmark.dart';

class VaultexHeaderBar extends StatelessWidget {
  final String vaultName;
  final String? vaultPath;
  final VoidCallback onOpenGenerator;
  final VoidCallback onOpenSettings;
  final VoidCallback onLockVault;

  const VaultexHeaderBar({
    super.key,
    required this.vaultName,
    this.vaultPath,
    required this.onOpenGenerator,
    required this.onOpenSettings,
    required this.onLockVault,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 500;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 20,
        vertical: isCompact ? 4 : 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Wordmark "VAULTEX"
          VaultexWordmark(
            fontSize: isCompact ? 20 : 22,
            letterSpacing: isCompact ? 3.5 : 4.5,
          ),

          const Spacer(),

          // Right: Action buttons (Generator, Settings, Manual lock)
          _buildActionButtons(context, isCompact),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, bool isCompact) {
    final iconSize = isCompact ? 21.0 : 22.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Password Generator
        _HeaderIconButton(
          icon: Icons.vpn_key_outlined,
          size: iconSize,
          tooltip: 'Генератор паролей',
          color: Colors.white,
          onPressed: onOpenGenerator,
        ),
        const SizedBox(width: 4),

        // 2. Settings
        _HeaderIconButton(
          icon: Icons.settings_outlined,
          size: iconSize,
          tooltip: 'Настройки',
          color: Colors.white,
          onPressed: onOpenSettings,
        ),
        const SizedBox(width: 4),

        // 3. Manual Lock (White color, not yellow)
        _HeaderIconButton(
          icon: Icons.lock_outline,
          size: iconSize,
          tooltip: 'Ручная блокировка хранилища',
          color: Colors.white,
          onPressed: onLockVault,
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.icon,
    required this.size,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _isPressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeInOut,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
