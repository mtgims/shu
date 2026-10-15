import 'dart:async';

import 'package:audiobooks/player/player_settings.dart';
import 'package:audiobooks/player/sleep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('steps back more the longer the pause', () {
    expect(rewindAfter(const Duration(seconds: 5)), Duration.zero);
    expect(rewindAfter(const Duration(minutes: 2)), const Duration(seconds: 3));
    expect(
      rewindAfter(const Duration(minutes: 30)),
      const Duration(seconds: 10),
    );
    expect(rewindAfter(const Duration(days: 1)), const Duration(seconds: 20));
  });

  // The test binding fakes timers; [clock] moves along with them.
  late DateTime clock;
  late PlayerSettings settings;
  late List<double> volumes;
  late int sleeps;
  late StreamController<UserAccelerometerEvent> motion;

  SleepControl control() => SleepControl(
    settings,
    onSleep: () async => sleeps++,
    onVolume: volumes.add,
    now: () => clock,
    motion: () => motion.stream,
  );

  Future<void> wait(WidgetTester tester, Duration d) async {
    clock = clock.add(d);
    await tester.pump(d);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = PlayerSettings(await SharedPreferences.getInstance());
    clock = DateTime(2026, 10, 15, 23);
    volumes = [];
    sleeps = 0;
    motion = StreamController.broadcast();
  });

  testWidgets('fades out over the last seconds, then pauses', (tester) async {
    final sleep = control()..setFor(const Duration(minutes: 1));
    await wait(tester, const Duration(seconds: 49));
    expect(volumes, isEmpty);
    await wait(tester, const Duration(seconds: 6));
    expect(volumes.length, 5);
    expect(volumes.last, lessThan(volumes.first));
    expect(sleeps, 0);
    await wait(tester, const Duration(seconds: 6));
    expect(sleeps, 1);
    expect(volumes.last, 1, reason: 'the volume comes back for next time');
    expect(sleep.value, isNull);
  });

  testWidgets('+5 minutes while fading brings the volume back', (tester) async {
    final sleep = control()..setFor(const Duration(minutes: 1));
    await wait(tester, const Duration(seconds: 55));
    sleep.extend();
    expect(volumes.last, 1);
    expect(
      sleep.value!.endsAt,
      clock.add(const Duration(minutes: 5, seconds: 5)),
    );
    await wait(tester, const Duration(minutes: 5));
    expect(sleeps, 0);
    await wait(tester, const Duration(seconds: 10));
    expect(sleeps, 1);
  });

  testWidgets('a shake near the end adds 5 minutes', (tester) async {
    final sleep = control()..setFor(const Duration(minutes: 10));
    void jolt() => motion.add(UserAccelerometerEvent(15, 0, 0, DateTime.now()));

    // Too early: nobody listens yet.
    expect(motion.hasListener, isFalse);
    await wait(tester, const Duration(minutes: 8, seconds: 30));
    expect(motion.hasListener, isTrue);
    jolt();
    await wait(tester, const Duration(milliseconds: 200));
    jolt();
    await tester.pump();
    expect(
      sleep.value!.endsAt,
      DateTime(2026, 10, 15, 23, 15),
      reason: 'ten minutes, plus five',
    );
    expect(motion.hasListener, isFalse, reason: 'more than 2 minutes left');
    sleep.cancel();
  });

  testWidgets('without the fade it simply pauses on time', (tester) async {
    settings.sleepFade = false;
    control().setFor(const Duration(seconds: 30));
    await wait(tester, const Duration(seconds: 30));
    expect(volumes, isEmpty);
    expect(sleeps, 1);
  });
}
