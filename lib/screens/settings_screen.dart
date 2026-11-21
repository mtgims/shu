import 'package:flutter/material.dart';

import '../app.dart';
import '../updates/update_banner.dart';
import '../updates/updater.dart';
import '../widgets/adaptive.dart';
import 'about.dart';
import 'appearance.dart';
import 'downloads_panel.dart';
import 'player_extras.dart';

/// Everything about Shu itself rather than its addons: appearance, playback and download
/// settings, app updates and About.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final side = 16 + readableInset(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), titleSpacing: side),
      body: ListView(
        padding: EdgeInsets.fromLTRB(side, 8, side, 16),
        children: [
          const _Heading('Appearance'),
          const AppearanceSettings(),
          const _Heading('Shu'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune),
            title: const Text('Playback'),
            subtitle: const Text('Stepping back, chapters, the sleep timer'),
            onTap: () => showAudioSettings(
              context,
              AppScope.of(context).player.settings,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('Downloads'),
            subtitle: const Text('When to download, space used'),
            onTap: () => showDownloadSettings(context),
          ),
          if (Updater.enabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('Check for updates'),
              onTap: () => _checkForUpdate(context),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('About Shu'),
            onTap: () => showAbout(context),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Asks GitHub for a newer Shu right away, and offers it.
Future<void> _checkForUpdate(BuildContext context) async {
  final updater = AppScope.of(context).updater;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final update = await updater.check(force: true);
    if (update != null) {
      offerUpdate(updater, update);
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Shu is up to date.')),
      );
    }
  } on Object catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not check for updates: $e')),
    );
  }
}
