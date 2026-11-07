import 'package:flutter/material.dart';

class AppTheme {
  // Brand color: Obsidian Amethyst Purple
  static const primaryColor = Color(0xFF7C3AED); // Vibrant amethyst
  static const primaryLight = Color(0xFFA78BFA); // Soft amethyst light
  static const primaryDark = Color(0xFF6D28D9);  // Deep royal amethyst
  static const primaryGlow = Color(0xFF8B5CF6);

  // Background and Surfaces: Pure neutral dark graphite-black (no blue/slate tints)
  static const backgroundDark = Color(0xFF0D0D11); // Deep near-black graphite
  static const surfaceDark = Color(0xFF141419);    // Top header & dialog background
  static const cardDark = Color(0xFF1A1A22);       // Cards and containers
  static const cardElevatedDark = Color(0xFF22222C); // Hover/elevated elements
  static const cardBorderDark = Color(0xFF2B2B36); // Subtle neutral border

  // Text Colors
  static const textPrimaryDark = Color(0xFFEDEDF2);
  static const textSecondaryDark = Color(0xFF9898A6);
  static const textMutedDark = Color(0xFF646472);

  // Light theme fallbacks
  static const surfaceLight = Color(0xFFF8FAFC);
  static const cardLight = Color(0xFFFFFFFF);
  static const cardBorderLight = Color(0xFFE2E8F0);
  static const backgroundLight = Color(0xFFF1F5F9);

  // Category Colors
  static const accountColor = Color(0xFF38BDF8); // Sky blue
  static const tokenColor = Color(0xFF34D399);   // Emerald mint
  static const secretColor = Color(0xFFFBBF24);  // Amber gold
  static const noteColor = Color(0xFFA78BFA);    // Amethyst purple

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: primaryLight,
        surface: surfaceDark,
        surfaceContainerHighest: cardDark,
        onSurface: textPrimaryDark,
      ),
      cardTheme: CardTheme(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: cardBorderDark, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: cardBorderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: cardBorderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: primaryDark,
        surface: surfaceLight,
        surfaceContainerHighest: cardLight,
        onSurface: Color(0xFF0F172A),
      ),
      cardTheme: CardTheme(
        color: cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: cardBorderLight, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: cardBorderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: cardBorderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
      ),
    );
  }
}
