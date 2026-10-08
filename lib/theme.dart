import 'package:flutter/material.dart';

/// Warm amber on deep plum: the same palette as the addon's settings page.
const amber = Color(0xFFE8B04A);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: amber, brightness: brightness);
  if (dark) {
    scheme = scheme.copyWith(
      primary: amber,
      onPrimary: const Color(0xFF1A1408),
      surface: const Color(0xFF14111B),
      surfaceContainerLowest: const Color(0xFF100D16),
      surfaceContainerLow: const Color(0xFF1A1622),
      surfaceContainer: const Color(0xFF1D1927),
      surfaceContainerHigh: const Color(0xFF26202F),
      surfaceContainerHighest: const Color(0xFF2F2940),
      onSurface: const Color(0xFFF1ECE3),
      onSurfaceVariant: const Color(0xFFA59BB6),
      outlineVariant: const Color(0xFF2F2940),
    );
  }
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.22),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.22),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
