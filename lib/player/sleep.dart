import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'player_settings.dart';

/// When the sleep timer stops playback: at a time, or when the chapter ends.
class SleepTimer {
  const SleepTimer.at(DateTime this.endsAt) : endOfChapter = false;
  const SleepTimer.endOfChapter() : endsAt = null, endOfChapter = true;

  final DateTime? endsAt;
  final bool endOfChapter;
}

/// The running sleep timer. A timed one fades the volume out over its last seconds and, near
/// its end, listens for a shake that adds [extension]. Nothing runs while no timer is set.
///
/// The end of the chapter is the player's to notice; it calls [cancel] then.
class SleepControl extends ValueNotifier<SleepTimer?> {
  SleepControl(
    this._settings, {
    required this.onSleep,
    required this.onVolume,
    DateTime Function()? now,
    Stream<UserAccelerometerEvent> Function()? motion,
  }) : _now = now ?? DateTime.now,
       _motion =
           motion ??
           (PlayerSettings.hasShake ? userAccelerometerEventStream : null),
       super(null);

  static const fade = Duration(seconds: 10);
  static const extension = Duration(minutes: 5);

  /// How long before the end a shake counts.
  static const shakeWindow = Duration(minutes: 2);

  final PlayerSettings _settings;

  /// Pauses playback.
  final Future<void> Function() onSleep;
  final void Function(double volume) onVolume;
  final DateTime Function() _now;
  final Stream<UserAccelerometerEvent> Function()? _motion;

  Timer? _timer;
  Timer? _listenTimer;
  StreamSubscription<UserAccelerometerEvent>? _shake;
  bool _fading = false;

  void setFor(Duration duration) {
    _stop();
    value = SleepTimer.at(_now().add(duration));
    _schedule();
  }

  void setEndOfChapter() {
    _stop();
    value = const SleepTimer.endOfChapter();
  }

  /// Adds [extension] to a timed sleep timer; also brings back a volume fading out.
  void extend() {
    final ends = value?.endsAt;
    if (ends == null) return;
    final now = _now();
    value = SleepTimer.at((ends.isBefore(now) ? now : ends).add(extension));
    _schedule();
  }

  void cancel() {
    _stop();
    value = null;
  }

  void _schedule() {
    _stop();
    final left = value!.endsAt!.difference(_now());
    final fading = _settings.sleepFade;
    _timer = Timer(_notBefore(fading ? left - fade : left), () {
      if (fading) {
        _fadeOut();
      } else {
        unawaited(_sleep());
      }
    });
    if (_motion != null && _settings.shakeToExtend) {
      _listenTimer = Timer(_notBefore(left - shakeWindow), _listenForShake);
    }
  }

  static Duration _notBefore(Duration d) => d.isNegative ? Duration.zero : d;

  /// Ten steps down to silence, then the pause.
  void _fadeOut() {
    _fading = true;
    var step = 0;
    _timer = Timer.periodic(fade ~/ 10, (timer) {
      step++;
      if (step < 10) {
        // Squared: loudness falls off evenly to the ear.
        onVolume(pow(1 - step / 10, 2).toDouble());
      } else {
        timer.cancel();
        unawaited(_sleep());
      }
    });
  }

  Future<void> _sleep() async {
    final fading = _fading;
    _fading = false;
    _stop();
    value = null;
    await onSleep();
    if (fading) onVolume(1);
  }

  /// Two strong jolts within half a second add [extension].
  void _listenForShake() {
    DateTime? first;
    _shake = _motion!().listen((e) {
      if (sqrt(e.x * e.x + e.y * e.y + e.z * e.z) < 12) return;
      final now = _now();
      if (first != null &&
          now.difference(first!) < const Duration(milliseconds: 500)) {
        first = null;
        unawaited(HapticFeedback.mediumImpact());
        extend();
      } else {
        first = now;
      }
    });
  }

  /// Stops the timers and the sensor; a volume halfway down comes back.
  void _stop() {
    _timer?.cancel();
    _listenTimer?.cancel();
    unawaited(_shake?.cancel());
    _shake = null;
    if (_fading) {
      _fading = false;
      onVolume(1);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
