import 'dart:async';

import 'package:flutter/widgets.dart';

/// The playing position now and then, for seek bars and progress lines. Ticks only while
/// something listens, the audio plays and the app is on screen.
///
/// just_audio's own position streams can't be used for this: each time one is listened to again
/// it starts a new timer and the old one never stops, and they keep ticking with the screen off.
class PositionTicks with WidgetsBindingObserver {
  PositionTicks({
    required this.position,
    required this.playing,
    required this.changes,
    required this.every,
  }) {
    _out = StreamController<Duration>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  /// Where playback is right now.
  final Duration Function() position;
  final bool Function() playing;

  /// Fires when playback starts, stops, seeks or moves on: the moments to look again.
  final Stream<Object?> changes;

  /// How long between ticks while playing.
  final Duration Function() every;

  late final StreamController<Duration> _out;
  StreamSubscription<Object?>? _changes;
  Timer? _timer;
  Duration? _period;
  Duration? _last;
  bool _visible = true;

  /// Every listener starts with where playback is now (also while paused, when nothing ticks).
  /// One stream for everyone (widgets rebuilding with it don't subscribe again).
  late final Stream<Duration> stream = Stream.multi((listener) {
    listener.add(position());
    final ticks = _out.stream.listen(listener.addSync);
    listener.onCancel = ticks.cancel;
  });

  void _start() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _visible = _shows(binding.lifecycleState);
    _changes = changes.listen((_) => _update());
    // Each listener got the position as it started listening.
    _last = position();
    _update(emit: false);
  }

  void _stop() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    _changes = null;
    _timer?.cancel();
    _timer = null;
    _last = null;
  }

  static bool _shows(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = _shows(state);
    _update();
  }

  /// Sends the position (when it moved) and runs the timer only while it is worth it.
  void _update({bool emit = true}) {
    if (!_out.hasListener) return;
    if (emit) _emit();
    final run = _visible && playing();
    if (!run) {
      _timer?.cancel();
      _timer = null;
    } else {
      // A new chapter may want another pace.
      final period = every();
      if (_timer == null || period != _period) {
        _timer?.cancel();
        _period = period;
        _timer = Timer.periodic(period, (_) => _emit());
      }
    }
  }

  void _emit() {
    final now = position();
    if (now == _last) return;
    _last = now;
    _out.add(now);
  }
}
