import 'dart:async';
import 'dart:ui';

import 'package:audiobooks/player/position_ticks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Duration position;
  late bool playing;
  late StreamController<void> changes;

  PositionTicks ticks() => PositionTicks(
    position: () => position,
    playing: () => playing,
    changes: changes.stream,
    every: () => const Duration(milliseconds: 200),
  );

  setUp(() {
    position = const Duration(seconds: 5);
    playing = false;
    changes = StreamController<void>.broadcast(sync: true);
  });

  testWidgets('starts with the position, ticks only while playing', (
    tester,
  ) async {
    final seen = <Duration>[];
    final sub = ticks().stream.listen(seen.add);
    await tester.binding.delayed(Duration.zero);
    expect(seen, [const Duration(seconds: 5)], reason: 'paused: no ticks');

    playing = true;
    changes.add(null);
    for (var i = 1; i <= 5; i++) {
      position += const Duration(milliseconds: 200);
      await tester.binding.delayed(const Duration(milliseconds: 200));
    }
    expect(seen.length, 6);
    expect(seen.last, const Duration(seconds: 6));

    playing = false;
    changes.add(null);
    final count = seen.length;
    position += const Duration(seconds: 1);
    await tester.binding.delayed(const Duration(seconds: 2));
    expect(seen.length, count, reason: 'quiet once paused');
    unawaited(sub.cancel());
  });

  testWidgets('quiet while the app is hidden', (tester) async {
    final seen = <Duration>[];
    final sub = ticks().stream.listen(seen.add);
    playing = true;
    changes.add(null);
    await tester.binding.delayed(Duration.zero);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final count = seen.length;
    for (var i = 0; i < 10; i++) {
      position += const Duration(milliseconds: 200);
      await tester.binding.delayed(const Duration(milliseconds: 200));
    }
    expect(seen.length, count, reason: 'nothing while hidden');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    position += const Duration(milliseconds: 200);
    await tester.binding.delayed(const Duration(milliseconds: 200));
    expect(seen.length, greaterThan(count), reason: 'ticking again');
    unawaited(sub.cancel());
  });

  testWidgets(
    'every listener starts with the position; no timer after the last leaves',
    (tester) async {
      final shared = ticks();
      final a = <Duration>[], b = <Duration>[];
      final subA = shared.stream.listen(a.add);
      playing = true;
      changes.add(null);
      await tester.binding.delayed(const Duration(milliseconds: 200));
      final subB = shared.stream.listen(b.add);
      await tester.binding.delayed(Duration.zero);
      expect(
        b.first,
        position,
        reason: 'a later listener gets the position at once',
      );

      unawaited(subA.cancel());
      unawaited(subB.cancel());
      // A timer still running here would make the test fail for pending timers.
    },
  );
}
