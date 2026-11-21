library just_audio_media_kit;

import 'package:media_kit/media_kit.dart';

Future<void> setProperty(Player player, String key, dynamic value) {
  // noop
  return Future.value();
}

/// Shu: reads an mpv property; null on other platforms or when mpv has no value.
Future<String?> getProperty(Player player, String key) => Future.value();

/// Shu: adds [value] to the mpv list option [key], keeping what media_kit put there.
Future<void> appendToList(Player player, String key, String value) =>
    Future.value();
