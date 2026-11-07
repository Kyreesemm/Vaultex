import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class VaultexHeaderBar extends StatefulWidget {
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
  State<VaultexHeaderBar> createState() => _VaultexHeaderBarState();
}

class _VaultexHeaderBarState extends State<VaultexHeaderBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    // Slow, smooth ambient shimmer across purple gradients
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 500;

    return Container(
      margin: EdgeInsets.fromLTRB(
        isCompact ? 12 : 16,
        isCompact ? 4 : 8,
        isCompact ? 12 : 16,
        8,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 14,
        vertical: isCompact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(isCompact ? 18 : 22),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.10),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left: Vault indicator pill / badge
          _buildVaultBadge(context, isCompact),

          // Center: Glowing & Slowly Shimmering "VAULTEX"
          Expanded(
            child: Center(
              child: _buildGlowingWordmark(isCompact),
            ),
          ),

          // Right: Action buttons (Generator, Settings, Lock)
          _buildActionButtons(isCompact),
        ],
      ),
    );
  }

  Widget _buildVaultBadge(BuildContext context, bool isCompact) {
    if (isCompact) {
      return Tooltip(
        message: '${widget.vaultName}\nAES-256-GCM • Argon2id',
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.cardElevatedDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.primaryColor.withOpacity(0.18),
            ),
          ),
          child: const Icon(
            Icons.shield_rounded,
            color: AppTheme.primaryLight,
            size: 18,
          ),
        ),
      );
    }

    return Tooltip(
      message: widget.vaultPath != null
          ? 'Хранилище: ${widget.vaultPath}\nШифрование: AES-256-GCM'
          : 'Хранилище активно',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.cardElevatedDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryColor.withOpacity(0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shield_rounded,
              color: AppTheme.primaryLight,
              size: 16,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.vaultName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowingWordmark(bool isCompact) {
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final val = _animCtrl.value;

        // Smoothly shifting gradient stops with Obsidian amethyst purple shades
        final gradient = LinearGradient(
          begin: Alignment(-1.5 + val * 1.5, -0.5),
          end: Alignment(1.5 + val * 1.5, 0.5),
          colors: const [
            Color(0xFF6D28D9), // Deep Obsidian amethyst
            Color(0xFF8B5CF6), // Royal purple
            Color(0xFFA78BFA), // Lavender lilac
            Color(0xFFC4B5FD), // Light amethyst highlight
            Color(0xFF9333EA), // Vivid purple
            Color(0xFF7C3AED), // Main brand amethyst
          ],
          stops: const [0.0, 0.25, 0.45, 0.65, 0.85, 1.0],
        );

        return Stack(
          alignment: Alignment.center,
          children: [
            // Ambient soft glowing text shadow layer
            Text(
              'VAULTEX',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: isCompact ? 16 : 19,
                fontWeight: FontWeight.w900,
                letterSpacing: isCompact ? 3.5 : 4.5,
                color: Colors.transparent,
                shadows: [
                  Shadow(
                    color: AppTheme.primaryLight.withOpacity(0.55 + 0.25 * sin(val * pi)),
                    blurRadius: 14 + 4 * sin(val * pi),
                  ),
                  Shadow(
                    color: AppTheme.primaryDark.withOpacity(0.7),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),

            // Foreground animated gradient text layer
            ShaderMask(
              shaderCallback: (bounds) => gradient.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Text(
                'VAULTEX',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: isCompact ? 16 : 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: isCompact ? 3.5 : 4.5,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons(bool isCompact) {
    final iconSize = isCompact ? 18.0 : 20.0;
    final padding = isCompact ? const EdgeInsets.all(6) : const EdgeInsets.all(8);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: isCompact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
          padding: padding,
          icon: Icon(Icons.vpn_key_outlined, size: iconSize),
          tooltip: 'Генератор паролей',
          onPressed: widget.onOpenGenerator,
        ),
        IconButton(
          constraints: isCompact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
          padding: padding,
          icon: Icon(Icons.settings_outlined, size: iconSize),
          tooltip: 'Настройки',
          onPressed: widget.onOpenSettings,
        ),
        IconButton(
          constraints: isCompact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
          padding: padding,
          icon: Icon(
            Icons.lock_outline,
            size: iconSize,
            color: Colors.amber.shade400,
          ),
          tooltip: 'Заблокировать хранилище',
          onPressed: widget.onLockVault,
        ),
      ],
    );
  }
}
