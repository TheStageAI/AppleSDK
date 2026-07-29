import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// ============================================================================
// Apple-leaning visual language for the Voice Agent example.
// ============================================================================
// System blue accent, iOS grouped backgrounds, SF-style type via platform
// typography — not Material indigo / generic M3 defaults.
// ============================================================================

abstract final class AppColors {
  static const systemBlue = Color(0xFF007AFF);
  static const systemBlueDark = Color(0xFF0A84FF);
  static const systemGreen = Color(0xFF34C759);
  static const systemOrange = Color(0xFFFF9500);
  static const systemRed = Color(0xFFFF3B30);
  static const systemGray = Color(0xFF8E8E93);

  static const groupedLight = Color(0xFFF2F2F7);
  static const groupedDark = Color(0xFF000000);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C1C1E);
  static const bubbleGrayLight = Color(0xFFE9E9EB);
  static const bubbleGrayDark = Color(0xFF2C2C2E);
  static const separatorLight = Color(0xFFC6C6C8);
  static const separatorDark = Color(0xFF38383A);
  static const labelSecondaryLight = Color(0xFF8E8E93);
  static const labelSecondaryDark = Color(0xFF98989D);
}

ThemeData buildVoiceAgentTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final primary = isDark ? AppColors.systemBlueDark : AppColors.systemBlue;
  final scaffold =
      isDark ? AppColors.groupedDark : AppColors.groupedLight;
  final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
  final onSurface = isDark ? Colors.white : const Color(0xFF1C1C1E);
  final secondary = isDark
      ? AppColors.labelSecondaryDark
      : AppColors.labelSecondaryLight;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: Colors.white,
    secondary: primary,
    onSecondary: Colors.white,
    tertiary: isDark ? AppColors.bubbleGrayDark : AppColors.bubbleGrayLight,
    onTertiary: onSurface,
    error: AppColors.systemRed,
    onError: Colors.white,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerLowest: scaffold,
    surfaceContainerLow: surface,
    surfaceContainer: isDark ? const Color(0xFF2C2C2E) : Colors.white,
    surfaceContainerHigh: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
    surfaceContainerHighest:
        isDark ? const Color(0xFF48484A) : const Color(0xFFD1D1D6),
    outline: isDark ? AppColors.separatorDark : AppColors.separatorLight,
    outlineVariant: secondary,
    onSurfaceVariant: secondary,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    platform: TargetPlatform.iOS,
    splashFactory: NoSplash.splashFactory,
    highlightColor: primary.withValues(alpha: 0.08),
    dividerColor: scheme.outline.withValues(alpha: 0.55),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      backgroundColor: scaffold.withValues(alpha: 0.92),
      foregroundColor: onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: onSurface,
      ),
      iconTheme: IconThemeData(color: primary, size: 22),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: primary.withValues(alpha: 0.35),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.3,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: primary,
      textColor: onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: primary,
      scaffoldBackgroundColor: scaffold,
      barBackgroundColor: scaffold.withValues(alpha: 0.86),
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    ),
  );
}
