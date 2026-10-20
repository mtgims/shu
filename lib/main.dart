import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'addons/addon_store.dart';
import 'app.dart';
import 'library/library_store.dart';
import 'peer/torrent_engine.dart';
import 'player/audiobook_player.dart';
import 'player/player_settings.dart';
import 'updates/update_banner.dart';
import 'updates/updater.dart';
import 'widgets/cover_colors.dart';
import 'widgets/cover_image.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Last resort for errors nothing caught, so they show up in the log.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unexpected error: ${withoutLinks(error)}\n$stack');
    return true;
  };
  final app = await createApp();
  runApp(app);
  // Off the startup path: cover cache upkeep, and extension updates (at most one small request
  // per extension a day).
  Future.delayed(const Duration(seconds: 30), () async {
    try {
      await CoverImage.trim();
    } on Object catch (e) {
      debugPrint('Cover cache upkeep failed: ${withoutLinks(e)}');
    }
  });
  Future.delayed(const Duration(seconds: 15), () async {
    try {
      final (:updated, :waiting) = await app.addons.checkUpdates();
      final messenger = messengerKey.currentState;
      if (updated.isNotEmpty) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Updated ${updated.join(', ')}')),
        );
      }
      if (waiting.isNotEmpty) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              waiting.length == 1
                  ? 'An update of ${waiting.single.manifest.name} needs your OK'
                  : 'Updates of ${waiting.map((a) => a.manifest.name).join(', ')} need your OK',
            ),
            action: SnackBarAction(
              label: 'Review',
              onPressed: () => goToTab(3),
            ),
          ),
        );
      }
    } on Object catch (e) {
      debugPrint('Extension update check failed: ${withoutLinks(e)}');
    }
  });
  // A newer Shu on the releases page: at most one small request a day.
  Future.delayed(const Duration(seconds: 20), () async {
    try {
      final update = await app.updater.check();
      if (update != null) offerUpdate(app.updater, update);
    } on Object catch (e) {
      debugPrint('Update check failed: ${withoutLinks(e)}');
    }
  });
}

/// Sets up storage and the player. `systemControls: false` skips audio_service (background
/// playback, lock screen and media keys), which the integration test does not need.
Future<AudiobooksApp> createApp({bool systemControls = true}) async {
  // just_audio has no native Linux/Windows backend; media_kit (libmpv) provides one.
  JustAudioMediaKit.title = 'Shu';
  // Torrents can go quiet for a while as they find people to download from.
  JustAudioMediaKit.networkTimeout = 60;
  JustAudioMediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final addons = await AddonStore.load(prefs);
  final library = LibraryStore(prefs);
  // Torrent extensions play through it; finished or removed books may take their download.
  final torrents = addons.host.torrents = TorrentEngine(prefs);
  library.addListener(() => torrents.tidy(library));

  final settings = PlayerSettings(prefs);
  AudiobookPlayer build() => AudiobookPlayer(library, addons, settings);
  // audio_service gives background playback and system media controls on Android, iOS,
  // macOS and Linux (MPRIS). It has no Windows backend, where the player runs on its own.
  final player = !systemControls || Platform.isWindows
      ? build()
      : await AudioService.init(
          builder: build,
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'io.player.shu.playback',
            androidNotificationChannelName: 'Audiobook playback',
            androidNotificationIcon: 'drawable/ic_stat_shu',
            androidNotificationOngoing: true,
            androidStopForegroundOnPause: true,
            fastForwardInterval: AudiobookPlayer.skipForward,
            rewindInterval: AudiobookPlayer.skipBack,
          ),
        );

  player.onServerMove = (from, before) =>
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Carrying on from where you got to on $from'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => player.jumpTo(before),
          ),
        ),
      );

  // The player opens in the cover's colours, over its blurred copy: both are made as soon as a
  // book is open.
  player.current.addListener(() {
    final cover = player.current.value?.book.cover;
    if (cover == null) return;
    unawaited(CoverColors.seedOf(cover));
    unawaited(CoverColors.blurredOf(cover));
  });

  // Decoded images kept in memory; covers are decoded small, so this holds plenty.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  player.restoreLastSession();
  return AudiobooksApp(
    addons: addons,
    library: library,
    player: player,
    updater: Updater(prefs),
  );
}

/// [error]'s text with its links left out: they can hold an addon's API key.
@visibleForTesting
String withoutLinks(Object error) => '$error'.replaceAll(
  RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false),
  '<link>',
);
