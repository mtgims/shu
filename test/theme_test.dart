import 'package:audiobooks/player/player_settings.dart';
import 'package:audiobooks/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'settings start on the system theme in amber, and keep a choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = PlayerSettings(await SharedPreferences.getInstance());
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.accent, 0);
      expect(settings.pureBlack, isFalse);
      expect(settings.miniPlayerCoverColors, isTrue);
      settings
        ..themeMode = ThemeMode.light
        ..accent = 2
        ..pureBlack = true
        ..miniPlayerCoverColors = false;
      final again = PlayerSettings(await SharedPreferences.getInstance());
      expect(again.themeMode, ThemeMode.light);
      expect(again.accent, 2);
      expect(again.pureBlack, isTrue);
      expect(again.miniPlayerCoverColors, isFalse);
    },
  );

  test(
    'dark themes use the accent itself; pure black makes the surface black',
    () {
      final amberDark = appTheme(Brightness.dark, 0).colorScheme;
      expect(amberDark.primary, amber);
      expect(amberDark.surface, const Color(0xFF14111B));

      final teal = accents[1].color;
      final tealDark = appTheme(Brightness.dark, 1).colorScheme;
      expect(tealDark.primary, teal);
      expect(tealDark.surface, isNot(amberDark.surface));

      final black = appTheme(Brightness.dark, 1, pureBlack: true).colorScheme;
      expect(black.surface, Colors.black);
      expect(black.primary, teal);

      // Pure black is for the dark theme only; light keeps Material's darker tone of the accent.
      final light = appTheme(Brightness.light, 1, pureBlack: true).colorScheme;
      expect(light.brightness, Brightness.light);
      expect(light.surface, isNot(Colors.black));

      // An index from a newer version falls back to a known accent.
      expect(
        appTheme(Brightness.dark, 99).colorScheme.primary,
        accents.last.color,
      );
    },
  );
}
