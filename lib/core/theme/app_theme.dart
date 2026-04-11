import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

/// Apple-style тёмная тема
/// Цвета взяты из macOS Sonoma / iOS 17 dark mode
class AppTheme {
  AppTheme._();

  // ── Цвета ─────────────────────────────────────────────────────────────
  static const background     = Color(0xFF1C1C1E);   // iOS systemBackground dark
  static const surface        = Color(0xFF2C2C2E);   // iOS secondarySystemBackground
  static const surfaceHigh    = Color(0xFF3A3A3C);   // iOS tertiarySystemBackground
  static const divider        = Color(0xFF38383A);
  static const accent         = Color(0xFF0A84FF);   // iOS blue dark
  static const accentGreen    = Color(0xFF30D158);   // iOS green dark
  static const accentRed      = Color(0xFFFF453A);   // iOS red dark
  static const accentOrange   = Color(0xFFFF9F0A);
  static const textPrimary    = Color(0xFFFFFFFF);
  static const textSecondary  = Color(0xFF8E8E93);   // iOS secondaryLabel
  static const textTertiary   = Color(0xFF48484A);
  static const messageBubble  = Color(0xFF0A84FF);   // Отправленные (синие)
  static const messageBubbleIn= Color(0xFF2C2C2E);   // Входящие (серые)

  // ── Frosted glass ─────────────────────────────────────────────────────
  static const glassColor     = Color(0x40FFFFFF);
  static const glassBorder    = Color(0x20FFFFFF);

  // ── Material тема (для Android) ───────────────────────────────────────
  static ThemeData materialDark() => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary:   accent,
          surface:   surface,
          onSurface: textPrimary,
        ),
        fontFamily: 'Inter',
        cardColor: surface,
        dividerColor: divider,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: textPrimary,
          ),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      );

  // ── macOS тема ────────────────────────────────────────────────────────
  static MacosThemeData macosTheme() => MacosThemeData(
        brightness: Brightness.dark,
        primaryColor: accent,
        canvasColor: background,
        sidebarStyle: const MacosSidebarStyle(
          decoration: BoxDecoration(color: Color(0xFF161618)),
        ),
        typography: MacosTypography(
          body:    const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: textPrimary,
          ),
          title1:  const TextStyle(
            fontFamily: 'Inter',
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
          headline: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          subheadline: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            color: textSecondary,
          ),
          caption1: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            color: textSecondary,
          ),
        ),
      );
}

// ── Вспомогательные декорации ─────────────────────────────────────────────
class ALDecoration {
  ALDecoration._();

  static BoxDecoration glass({
    double radius = 16,
    Color? color,
  }) =>
      BoxDecoration(
        color: color ?? AppTheme.glassColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.glassBorder, width: 0.5),
      );

  static BoxDecoration card({double radius = 12}) => BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(radius),
      );

  static BoxDecoration sidebar() => const BoxDecoration(
        color: Color(0xFF161618),
        border: Border(
          right: BorderSide(color: AppTheme.divider, width: 0.5),
        ),
      );
}
