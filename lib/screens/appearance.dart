import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';

/// Light or dark, the accent colour and pure black, at the top of Settings. Changes show at
/// once.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).player.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => settings.themeMode = s.single,
            ),
          ),
          const SizedBox(height: 20),
          Text('Accent', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (i, a) in accents.indexed)
                _Swatch(
                  name: a.name,
                  color: a.color,
                  selected: settings.accent.clamp(0, accents.length - 1) == i,
                  onTap: () => settings.accent = i,
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pure black'),
            subtitle: const Text(
              'Black instead of dark grey in the dark theme. Saves battery on OLED screens',
            ),
            value: settings.pureBlack,
            onChanged: (on) => settings.pureBlack = on,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Mini player in the cover's colours"),
            subtitle: const Text('Otherwise in the accent colour'),
            value: settings.miniPlayerCoverColors,
            onChanged: (on) => settings.miniPlayerCoverColors = on,
          ),
        ],
      ),
    );
  }
}

/// One accent colour: a dot, ticked while chosen.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: Tooltip(
        message: name,
        child: Material(
          color: color,
          shape: CircleBorder(
            side: selected
                ? BorderSide(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2,
                  )
                : BorderSide.none,
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 44,
              child: selected ? Icon(Icons.check, color: ink) : null,
            ),
          ),
        ),
      ),
    );
  }
}
