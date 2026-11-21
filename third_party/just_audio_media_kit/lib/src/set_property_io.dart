library just_audio_media_kit;

import 'package:media_kit/media_kit.dart';

Future<void> setProperty(Player player, String key, dynamic value) async {
  if (player.platform is! NativePlayer) return;
  await (player.platform as NativePlayer).setProperty(key, value);
}

/// Shu: reads an mpv property; null on other platforms or when mpv has no value.
Future<String?> getProperty(Player player, String key) async {
  if (player.platform is! NativePlayer) return null;
  try {
    return await (player.platform as NativePlayer).getProperty(key);
  } on Object {
    return null;
  }
}

/// Shu: adds [value] to the mpv list option [key], keeping what media_kit put there.
Future<void> appendToList(Player player, String key, String value) async {
  if (player.platform is! NativePlayer) return;
  await (player.platform as NativePlayer)
      .command(['change-list', key, 'append', value]);
}
