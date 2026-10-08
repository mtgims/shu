import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'addons/addon_store.dart';
import 'app.dart';
import 'library/library_store.dart';
import 'player/audiobook_player.dart';
import 'widgets/cover_image.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await createApp();
  runApp(app);
  // Off the startup path: cover cache upkeep, and extension updates (at most one small request
  // per extension a day).
  Future.delayed(const Duration(seconds: 30), CoverImage.trim);
  Future.delayed(const Duration(seconds: 15), () async {
    final updated = await app.addons.checkUpdates();
    if (updated.isEmpty) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text('Updated ${updated.join(', ')}')),
    );
  });
}

/// Sets up storage and the player. `systemControls: false` skips audio_service (background
/// playback, lock screen and media keys), which the integration test does not need.
Future<AudiobooksApp> createApp({bool systemControls = true}) async {
  // just_audio has no native Linux/Windows backend; media_kit (libmpv) provides one.
  JustAudioMediaKit.title = 'Shu';
  JustAudioMediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final addons = await AddonStore.load(prefs);
  final library = LibraryStore(prefs);

  AudiobookPlayer build() => AudiobookPlayer(library, addons, prefs);
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

  // Decoded images kept in memory; covers are decoded small, so this holds plenty.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  player.restoreLastSession();
  return AudiobooksApp(addons: addons, library: library, player: player);
}
