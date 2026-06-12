import 'package:flutter/material.dart';

class MetaColors {
  static const primary = Color(0xFF0064E0);
  static const primaryDeep = Color(0xFF0457CB);
  static const canvas = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF1F4F7);
  static const inkButton = Color(0xFF000000);
  static const inkDeep = Color(0xFF0A1317);
  static const ink = Color(0xFF1C1E21);
  static const steel = Color(0xFF5D6C7B);
  static const stone = Color(0xFF8595A4);
  static const hairline = Color(0xFFCED0D4);
  static const hairlineSoft = Color(0xFFDEE3E9);
  static const success = Color(0xFF31A24C);
  static const warning = Color(0xFFF7B928);
  static const critical = Color(0xFFE41E3F);
}

class MetaRadii {
  static const sm = 4.0;
  static const lg = 8.0;
  static const xl = 16.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const full = 100.0;
}

class MetaSpacing {
  static const xs = 8.0;
  static const md = 12.0;
  static const base = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const section = 64.0;
}

class MetaTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MetaColors.primary,
        primary: MetaColors.primary,
        surface: MetaColors.canvas,
      ),
      scaffoldBackgroundColor: MetaColors.canvas,
      fontFamily: 'Montserrat',
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 48,
          height: 1.17,
          fontWeight: FontWeight.w500,
          color: MetaColors.inkDeep,
          letterSpacing: 0,
        ),
        headlineLarge: const TextStyle(
          fontSize: 36,
          height: 1.28,
          fontWeight: FontWeight.w500,
          color: MetaColors.inkDeep,
          letterSpacing: 0,
        ),
        headlineMedium: const TextStyle(
          fontSize: 28,
          height: 1.21,
          fontWeight: FontWeight.w300,
          color: MetaColors.inkDeep,
          letterSpacing: 0,
        ),
        titleLarge: const TextStyle(
          fontSize: 24,
          height: 1.25,
          fontWeight: FontWeight.w500,
          color: MetaColors.inkDeep,
          letterSpacing: 0,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: MetaColors.ink,
          letterSpacing: -0.16,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          height: 1.43,
          fontWeight: FontWeight.w400,
          color: MetaColors.steel,
          letterSpacing: -0.14,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          height: 1.43,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MetaColors.inkButton,
          foregroundColor: MetaColors.canvas,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MetaRadii.full),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MetaColors.inkDeep,
          side: const BorderSide(color: MetaColors.inkDeep, width: 2),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MetaRadii.full),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MetaColors.canvas,
        contentPadding: const EdgeInsets.all(MetaSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MetaRadii.lg),
          borderSide: const BorderSide(color: MetaColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MetaRadii.lg),
          borderSide: const BorderSide(color: MetaColors.primary, width: 2),
        ),
      ),
    );
  }
}
