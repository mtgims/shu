import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../downloads/download_store.dart';
import '../widgets/adaptive.dart';

/// Download settings, the space downloads take, and a way to delete them all.
void showDownloadSettings(BuildContext context) {
  final scope = AppScope.of(context);
  final settings = scope.player.settings;
  final downloads = scope.downloads;
  showPanel<void>(
    context,
    scrollControlled: true,
    builder: (context) => SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([settings, downloads]),
        builder: (context, _) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (Platform.isAndroid)
                SwitchListTile(
                  title: const Text('Download on mobile data'),
                  subtitle: const Text('Otherwise downloads wait for Wi-Fi'),
                  value: settings.downloadOnMobile,
                  onChanged: (on) => settings.downloadOnMobile = on,
                ),
              SwitchListTile(
                title: const Text('Delete downloads of finished books'),
                value: settings.deleteFinishedDownloads,
                onChanged: (on) => settings.deleteFinishedDownloads = on,
              ),
              FutureBuilder<int>(
                future: downloads.bytesUsed(),
                builder: (context, snap) => ListTile(
                  title: const Text('Space used'),
                  subtitle: Text(snap.hasData ? sizeText(snap.data!) : '…'),
                  trailing: TextButton(
                    onPressed: snap.data == 0
                        ? null
                        : () => _deleteAll(context),
                    child: const Text('Delete all'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _deleteAll(BuildContext context) async {
  final downloads = AppScope.of(context).downloads;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete all downloads?'),
      content: const Text(
        'The books stay in your library and play online again, from where you stopped.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) await downloads.removeAll();
}
