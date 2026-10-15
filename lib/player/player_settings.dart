import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the player behaves, chosen by the user and kept in shared preferences.
class PlayerSettings extends ChangeNotifier {
  PlayerSettings(this._prefs);

  final SharedPreferences _prefs;

  /// Skipping silence and the voice boost are Android audio effects.
  static bool get hasAudioEffects => Platform.isAndroid;

  /// Phones have a motion sensor to shake.
  static bool get hasShake => Platform.isAndroid || Platform.isIOS;

  /// Steps back a little when playback resumes after a pause, see [rewindAfter].
  bool get autoRewind => _prefs.getBool('autoRewind') ?? true;
  set autoRewind(bool on) => _setBool('autoRewind', on);

  bool get skipSilence => _prefs.getBool('skipSilence') ?? false;
  set skipSilence(bool on) => _setBool('skipSilence', on);

  /// Louder, for quiet recordings.
  bool get voiceBoost => _prefs.getBool('voiceBoost') ?? false;
  set voiceBoost(bool on) => _setBool('voiceBoost', on);

  /// The sleep timer turns the volume down over its last seconds.
  bool get sleepFade => _prefs.getBool('sleepFade') ?? true;
  set sleepFade(bool on) => _setBool('sleepFade', on);

  /// Shaking the phone near the end of the sleep timer adds 5 minutes.
  bool get shakeToExtend => _prefs.getBool('shakeToExtend') ?? true;
  set shakeToExtend(bool on) => _setBool('shakeToExtend', on);

  double get speed => _prefs.getDouble('speed') ?? 1.0;

  /// Read when the player starts; the player reports changes itself (no notification).
  set speed(double value) => _prefs.setDouble('speed', value);

  /// The sleep timer chosen last: minutes, or 0 for the end of the chapter.
  int? get lastSleep => _prefs.getInt('lastSleep');
  set lastSleep(int? minutes) => minutes == null
      ? _prefs.remove('lastSleep')
      : _prefs.setInt('lastSleep', minutes);

  void _setBool(String key, bool on) {
    _prefs.setBool(key, on);
    notifyListeners();
  }
}

/// How far to step back after a pause of [paused]: nothing after a moment, more the longer the
/// listener was away, so they find the thread again.
Duration rewindAfter(Duration paused) {
  if (paused < const Duration(seconds: 10)) return Duration.zero;
  if (paused <= const Duration(minutes: 5)) return const Duration(seconds: 3);
  if (paused <= const Duration(hours: 1)) return const Duration(seconds: 10);
  return const Duration(seconds: 20);
}
