import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import 'desktop_install.dart';
import 'updater.dart';

/// Offers [update] in a banner at the top of the app: Later, or Update.
void offerUpdate(Updater updater, AppUpdate update) {
  final messenger = messengerKey.currentState;
  if (messenger == null) return;
  messenger.showMaterialBanner(
    MaterialBanner(
      leading: const Icon(Icons.system_update_outlined),
      content: Text('Shu ${update.version} is available.'),
      actions: [
        TextButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            unawaited(updater.skip(update));
          },
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            unawaited(_update(updater, update));
          },
          child: const Text('Update'),
        ),
      ],
    ),
  );
}

/// Downloads and installs the update, then restarts Shu on desktop. Builds that can't replace
/// themselves open the release page.
Future<void> _update(Updater updater, AppUpdate update) async {
  if (update.file == null) {
    await launchUrl(update.page, mode: LaunchMode.externalApplication);
    return;
  }
  final navigator = navigatorKey.currentState;
  final messenger = messengerKey.currentState;
  if (navigator == null || messenger == null) return;
  final progress = ValueNotifier<double?>(null);
  unawaited(
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Updating to Shu ${update.version}'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, value, _) => LinearProgressIndicator(value: value),
          ),
        ),
      ),
    ),
  );
  try {
    final result = await updater.install(
      update,
      onProgress: (p) => progress.value = p,
    );
    if (result == 'restart') return await _restart();
    navigator.pop();
    if (result == 'permission') {
      // Android opened its settings: once installs from Shu are allowed, Update works.
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Allow Shu to install apps, then come back and tap Update again.',
          ),
        ),
      );
      offerUpdate(updater, update);
    }
  } on Object catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Could not update Shu: $e')));
  }
}

/// Starts the new version, then closes this one the usual way (saving the place, stopping the
/// torrent engine).
Future<void> _restart() async {
  final env = Map.of(Platform.environment)
    // The old AppImage's mount goes away with this process; the new one sets its own.
    ..remove('APPDIR')
    ..remove('APPIMAGE');
  await Process.start(
    DesktopInstall.relaunchPath,
    const [],
    environment: env,
    includeParentEnvironment: false,
    mode: ProcessStartMode.detached,
  );
  await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
}
