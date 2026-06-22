import 'package:flutter/material.dart';

class MetaColors {
  static const primary = Color(0xFFE8457A);
  static const primaryDeep = Color(0xFFC03260);
  static const primarySoft = Color(0xFFFFE4EC);
  static const canvas = Color(0xFFFFF5F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFFFE4EC);
  static const inkButton = Color(0xFFE8457A);
  static const inkDeep = Color(0xFF2D1B33);
  static const ink = Color(0xFF2D1B33);
  static const steel = Color(0xFF9B8A9F);
  static const stone = Color(0xFFD6CDD9);
  static const hairline = Color(0xFFF0D6E0);
  static const hairlineSoft = Color(0xFFF0D6E0);
  static const iconBase = Color(0xFFE8E0EB);
  static const characterRed = Color(0xFFF2426B);
  static const characterMagenta = Color(0xFFE34FCF);
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
  static const _fontFamily = 'MalgunGothic';
  static const _fontFallback = ['Roboto'];

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MetaColors.primary,
        primary: MetaColors.primary,
        onPrimary: MetaColors.surface,
        surface: MetaColors.canvas,
        onSurface: MetaColors.inkDeep,
      ),
      scaffoldBackgroundColor: MetaColors.canvas,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontSize: 24,
          height: 1.5,
          fontWeight: FontWeight.w700,
          color: MetaColors.inkDeep,
          letterSpacing: 0,
        ),
        headlineLarge: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontSize: 24,
          height: 1.5,
          fontWeight: FontWeight.w700,
          color: MetaColors.inkDeep,
          letterSpacing: 0,
        ),
        headlineMedium: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontSize: 20,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: MetaColors.inkDeep,
          letterSpacing: 0,
        ),
        titleLarge: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontSize: 18,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: MetaColors.inkDeep,
          letterSpacing: 0,
        ),
        bodyLarge: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: MetaColors.ink,
          letterSpacing: 0,
        ),
        bodyMedium: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: MetaColors.steel,
          letterSpacing: 0,
        ),
        labelLarge: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontSize: 12,
          height: 1.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: MetaColors.inkDeep,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MetaColors.primary,
          disabledBackgroundColor: MetaColors.stone,
          foregroundColor: MetaColors.surface,
          disabledForegroundColor: MetaColors.surface,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallback,
            fontSize: 15,
            height: 1.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MetaRadii.full),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MetaColors.primary,
          disabledForegroundColor: MetaColors.stone,
          side: const BorderSide(color: MetaColors.primary),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallback,
            fontSize: 15,
            height: 1.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MetaRadii.full),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MetaColors.primary,
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallback,
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MetaColors.surface,
        hintStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          color: MetaColors.steel,
        ),
        labelStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          color: MetaColors.steel,
        ),
        contentPadding: const EdgeInsets.all(MetaSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MetaRadii.xl),
          borderSide: const BorderSide(color: MetaColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MetaRadii.xl),
          borderSide: const BorderSide(color: MetaColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MetaRadii.xl),
          borderSide: const BorderSide(color: MetaColors.primary, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: MetaColors.surface,
        selectedColor: MetaColors.primarySoft,
        disabledColor: MetaColors.stone.withValues(alpha: 0.22),
        side: const BorderSide(color: MetaColors.hairline),
        labelStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          color: MetaColors.inkDeep,
          fontSize: 14,
          height: 1.5,
          letterSpacing: 0,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          color: MetaColors.primaryDeep,
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MetaRadii.full),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: MetaColors.surface,
        foregroundColor: MetaColors.inkDeep,
        surfaceTintColor: MetaColors.surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          color: MetaColors.inkDeep,
          fontSize: 20,
          height: 1.4,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: MetaColors.hairline,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MetaColors.inkDeep,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: MetaColors.surface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MetaRadii.xl),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MetaColors.surface,
        surfaceTintColor: MetaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MetaRadii.xxl),
          side: const BorderSide(color: MetaColors.hairline),
        ),
      ),
    );
  }
}
