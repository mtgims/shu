import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Warm amber on deep plum: the same palette as the addon's settings page.
const amber = Color(0xFFE8B04A);

/// The accent colours to choose from (Appearance); the first is the default.
const accents = [
  (name: 'Amber', color: amber),
  (name: 'Teal', color: Color(0xFF3FB8A8)),
  (name: 'Rose', color: Color(0xFFE5738F)),
  (name: 'Indigo', color: Color(0xFF8C8CF0)),
  (name: 'Green', color: Color(0xFF7CBF5A)),
  (name: 'Blue', color: Color(0xFF5AA7E8)),
];

final _appThemes = <(Brightness, int, bool), ThemeData>{};

/// The app's theme in the user's accent ([accents] index), built once per choice.
ThemeData appTheme(
  Brightness brightness,
  int accent, {
  bool pureBlack = false,
}) {
  final i = accent.clamp(0, accents.length - 1);
  return _appThemes[(brightness, i, pureBlack)] ??= buildTheme(
    brightness,
    accent: accents[i].color,
    pureBlack: pureBlack,
  );
}

/// The app's theme in [accent], or with [seed] one in the colours of a book cover (the player).
/// [pureBlack]: dark surfaces become black (OLED screens), keeping a trace of their tint.
ThemeData buildTheme(
  Brightness brightness, {
  Color? seed,
  Color accent = amber,
  bool pureBlack = false,
}) {
  final dark = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(
    seedColor: seed ?? accent,
    brightness: brightness,
    // Keeps a cover's own hue in the buttons instead of a pale tint of it.
    dynamicSchemeVariant: seed == null
        ? DynamicSchemeVariant.tonalSpot
        : DynamicSchemeVariant.fidelity,
  );
  if (dark && seed == null && accent == amber) {
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
  } else if (dark && seed == null) {
    // The accent itself, as bright as amber is, instead of a pale tint of it.
    scheme = scheme.copyWith(
      primary: accent,
      onPrimary: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : const Color(0xFF10141A),
    );
  }
  if (dark && pureBlack && seed == null) {
    Color darker(Color c) => Color.lerp(c, Colors.black, 0.6)!;
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: darker(scheme.surfaceContainerLow),
      surfaceContainer: darker(scheme.surfaceContainer),
      surfaceContainerHigh: darker(scheme.surfaceContainerHigh),
      surfaceContainerHighest: darker(scheme.surfaceContainerHighest),
      outlineVariant: darker(scheme.outlineVariant),
    );
  }
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    // Desktop pages fade forward instead of zooming; Android keeps predictive back.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
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
    // A snack bar with an action stays until dismissed unless it says `persist: false`
    // (Flutter's default); Shu's actions are all shortcuts, so every one passes it.
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

/// [style] in Literata, the serif for book titles and their authors (two weights: 400 and 600;
/// heavier asks get 600).
TextStyle? bookTitle(TextStyle? style) =>
    style?.copyWith(fontFamily: 'Literata') ??
    const TextStyle(fontFamily: 'Literata');
