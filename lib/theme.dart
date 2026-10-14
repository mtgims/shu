import 'package:flutter/foundation.dart';
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
    // On a computer a notice across the whole window looks broken; it gets a toast's width.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: _desktop ? 480 : null,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // List rows light up as rounded shapes, like the menus below, not as hard rectangles.
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // Menus (⋮ menus, dropdowns): rounded, with the row under the pointer lit as a rounded
    // shape inside them instead of a square running into their corners.
    menuTheme: MenuThemeData(style: menuStyle),
    dropdownMenuTheme: DropdownMenuThemeData(menuStyle: menuStyle),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        minimumSize: const Size(180, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

const menuStyle = MenuStyle(
  padding: WidgetStatePropertyAll(EdgeInsets.all(6)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
  ),
);

bool get _desktop => switch (defaultTargetPlatform) {
  TargetPlatform.linux ||
  TargetPlatform.windows ||
  TargetPlatform.macOS => true,
  _ => false,
};
