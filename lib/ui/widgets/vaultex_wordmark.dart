import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class VaultexWordmark extends StatefulWidget {
  final double fontSize;
  final double letterSpacing;
  final bool centered;

  const VaultexWordmark({
    super.key,
    this.fontSize = 20,
    this.letterSpacing = 4.0,
    this.centered = false,
  });

  @override
  State<VaultexWordmark> createState() => _VaultexWordmarkState();
}

class _VaultexWordmarkState extends State<VaultexWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final double _direction;
  late final double _cycleDuration;

  @override
  void initState() {
    super.initState();
    // Vary direction and speed slightly per instance while keeping every cycle seamless.
    final random = Random(DateTime.now().microsecondsSinceEpoch);
    _direction = random.nextBool() ? 1.0 : -1.0;
    _cycleDuration = 7.0 + random.nextDouble() * 0.4;

    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_cycleDuration * 1000).round()),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        final t = _animController.value * 2 * pi * _direction;

        // Base brand purple and shifting highlights
        const basePurple = Color(0xFF7C3AED); // Vaultex signature amethyst
        const deepPurple = Color(0xFF6D28D9); // Deep royal amethyst
        const spotLavender = Color(0xFFA78BFA); // Soft lavender
        const spotLilac = Color(0xFFC4B5FD); // Luminous amethyst
        const spotEthereal = Color(0xFFDDD6FE); // Ethereal bright lavender

        // Non-deterministic organic fluid color spots shifting with incommensurate frequencies
        final c0 = Color.lerp(
          basePurple,
          deepPurple,
          (0.5 + 0.5 * sin(t * 1)).clamp(0.0, 1.0),
        )!;

        final c1 = Color.lerp(
          basePurple,
          spotLavender,
          (0.5 + 0.5 * cos(t * 2 + 0.4)).clamp(0.0, 1.0),
        )!;

        final c2 = Color.lerp(
          spotLilac,
          basePurple,
          (0.5 + 0.5 * sin(t * 2 + 1.2)).clamp(0.0, 1.0),
        )!;

        final c3 = Color.lerp(
          basePurple,
          spotEthereal,
          (0.45 + 0.45 * cos(t * 3 + 2.0)).clamp(0.0, 1.0),
        )!;

        final c4 = Color.lerp(
          deepPurple,
          basePurple,
          (0.5 + 0.5 * sin(t * 1 + 0.8)).clamp(0.0, 1.0),
        )!;

        // Dynamically shifting stops that breathe and glide smoothly
        double s1 = (0.22 + 0.08 * sin(t * 2)).clamp(0.12, 0.36);
        double s2 = (0.48 + 0.10 * cos(t * 1 + 0.5)).clamp(0.38, 0.62);
        double s3 = (0.76 + 0.08 * sin(t * 3 + 1.0)).clamp(0.64, 0.88);

        // Shifting alignment vector creating 2D fluid rotation
        final beginAlign = Alignment(
          (-1.0 + 0.35 * sin(t * 1)),
          (-0.3 + 0.4 * cos(t * 2)),
        );
        final endAlign = Alignment(
          (1.0 + 0.35 * cos(t * 1)),
          (0.3 + 0.4 * sin(t * 1)),
        );

        final gradient = LinearGradient(
          begin: beginAlign,
          end: endAlign,
          colors: [c0, c1, c2, c3, c4],
          stops: [0.0, s1, s2, s3, 1.0],
        );

        // Breathing subtle glow intensity
        final glowOpacity = (0.35 + 0.15 * sin(t * 2)).clamp(0.2, 0.5);

        return Stack(
          alignment: widget.centered ? Alignment.center : Alignment.centerLeft,
          children: [
            // Layer 1: Soft ambient glow behind the wordmark
            Text(
              'VAULTEX',
              textAlign: widget.centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: widget.letterSpacing,
                color: Colors.transparent,
                shadows: [
                  Shadow(
                    color: AppTheme.primaryGlow.withOpacity(glowOpacity),
                    blurRadius: 14,
                    offset: Offset.zero,
                  ),
                  Shadow(
                    color: AppTheme.primaryColor.withOpacity(0.32),
                    blurRadius: 22,
                    offset: Offset.zero,
                  ),
                ],
              ),
            ),

            // Layer 2: Shimmering organic gradient foreground
            ShaderMask(
              shaderCallback: (bounds) => gradient.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Text(
                'VAULTEX',
                textAlign: widget.centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: widget.letterSpacing,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
