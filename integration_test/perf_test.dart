// Frame timings of the flows that must feel smooth, against the example extensions (no network).
// Run in profile mode, where timings mean something:
//   flutter drive --profile -d linux --driver test_driver/perf_driver.dart \
//     --target integration_test/perf_test.dart
// The summary per flow (build and raster times, missed frames) lands in build/perf.json.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:audiobooks/addons/models.dart';
import 'package:audiobooks/app.dart';
import 'package:audiobooks/main.dart';
import 'package:audiobooks/screens/book_screen.dart';
import 'package:audiobooks/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'example_extensions.dart';
import 'tour_test.dart' show back, rootKey, settle, tap, waitFor;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('perf', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final server = (await tester.runAsync(serveExampleRepository))!;
    final repository = 'http://127.0.0.1:${server.port}/index.json';
    final app = (await tester.runAsync(
      () => createApp(systemControls: false),
    ))!;
    await tester.pumpWidget(RepaintBoundary(key: rootKey, child: app));
    await tester.pump();

    // Key presses can't be simulated in profile mode: panels close through their navigator.
    Future<void> close(Finder inside) async {
      Navigator.of(tester.element(inside)).pop();
      await settle(tester, 500);
    }

    Future<void> flow(String name, Future<void> Function() steps) =>
        binding.watchPerformance(steps, reportKey: name);

    // Installed in code: the install screens are the tour's job, timings start after.
    await tester.runAsync(() async {
      for (final file in ['catalog.js', 'source.js']) {
        await app.addons.install(repository.replaceFirst('index.json', file));
      }
    });

    await flow('home', () async {
      await tap(tester, find.text('Home').last);
      await waitFor(tester, find.text('The Quiet Orchard'));
      await settle(tester);
      final list = find.byType(Scrollable).first;
      await tester.fling(list, const Offset(0, -600), 1500);
      await settle(tester, 1000);
      await tester.fling(list, const Offset(0, 600), 1500);
      await settle(tester, 1000);
    });

    await flow('book_page', () async {
      await tap(tester, find.text('The Quiet Orchard').first);
      await waitFor(tester, find.text('The Quiet Orchard (MP3)'));
      await waitFor(tester, find.text('In this series'));
      await settle(tester);
    });

    await flow('open_player_from_book', () async {
      await tap(tester, find.widgetWithText(FilledButton, 'Play'));
      await waitFor(tester, find.byIcon(Icons.pause_rounded));
      await settle(tester);
    });

    // Wide windows show the tabs beside the player; phones open them in a sheet.
    final sheet = find.byTooltip('Chapters and bookmarks');
    await flow('tabs', () async {
      if (sheet.evaluate().isNotEmpty) await tap(tester, sheet);
      for (var i = 0; i < 3; i++) {
        for (final tab in ['Bookmarks', 'History', 'Chapters']) {
          await tap(tester, find.text(tab));
        }
      }
      if (sheet.evaluate().isNotEmpty) await close(find.text('History'));
    });

    await flow('panels', () async {
      await tap(tester, find.byIcon(Icons.speed));
      await close(find.byTooltip('Faster'));
      await tap(tester, find.byIcon(Icons.bedtime_outlined));
      await close(find.text('30 minutes'));
      await tap(tester, find.byTooltip('More').last);
      await tap(tester, find.text('Playback settings'));
      await close(find.text('Step back after a pause'));
    });

    await flow('close_player', () async {
      // The example chapters are short: the book may have finished already.
      final pause = find.byIcon(Icons.pause_rounded);
      if (pause.evaluate().isNotEmpty) await tap(tester, pause.first);
      await tap(tester, find.byTooltip('Close'));
      await settle(tester);
    });

    await flow('open_player_from_bar', () async {
      await tap(
        tester,
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('The Quiet Orchard'),
        ),
      );
      await waitFor(tester, find.byIcon(Icons.play_arrow_rounded));
      await settle(tester);
      await tap(tester, find.byTooltip('Close'));
    });

    // Frame pacing of the opening itself: how many frames the 450 ms animation got, and the
    // longest wait between two (a stutter shows here, not in the build or raster times).
    for (var i = 0; i < 3; i++) {
      final frames = <FrameTiming>[];
      void collect(List<FrameTiming> t) => frames.addAll(t);
      binding.addTimingsCallback(collect);
      await tester.tap(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('The Quiet Orchard'),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      await tester.pump();
      binding.removeTimingsCallback(collect);
      final starts = [
        for (final t in frames)
          t.timestampInMicroseconds(FramePhase.vsyncStart),
      ]..sort();
      var gap = 0;
      for (var j = 1; j < starts.length; j++) {
        gap = max(gap, starts[j] - starts[j - 1]);
      }
      binding.reportData!['open_pacing_$i'] = {
        'frames': starts.length,
        'max_gap_ms': gap / 1000,
      };
      await settle(tester);
      await tap(tester, find.byTooltip('Close'));
    }
    await back(tester);

    await flow('search', () async {
      await tap(tester, find.text('Search').last);
      await tester.enterText(find.byType(TextField), 'orchard');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await waitFor(tester, find.text('The Quiet Orchard'));
      await settle(tester);
    });

    // A book of 300 chapters: opening its page, scrolling it, and the page while the player
    // and library change (each pause, chapter or bookmark notifies them).
    final source = app.addons.addons.firstWhere((a) => a.manifest.releases);
    await flow('big_book', () async {
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => BookScreen(
              addon: source,
              summary: const BookSummary(
                id: 's:big',
                title: 'A Very Long Book',
              ),
            ),
          ),
        ),
      );
      await waitFor(tester, find.text('Chapter 1'));
      await settle(tester);
      final list = find.byType(Scrollable).last;
      await tester.fling(list, const Offset(0, -2000), 3000);
      await settle(tester, 1000);
    });
    await flow('big_book_updates', () async {
      for (var i = 0; i < 20; i++) {
        app.player.current.changed();
        app.library.notifyListeners();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    });
    await back(tester);

    await flow('library', () async {
      await tap(tester, find.text('Library').last);
      await settle(tester);
    });

    await flow('addons', () async {
      await tap(tester, find.text('Addons').last);
      await waitFor(tester, find.text('Example Source'));
      await settle(tester);
    });

    // One line per flow, for the driver-less run (`flutter test --profile`).
    for (final MapEntry(:key, :value) in binding.reportData!.entries) {
      debugPrint('PERF $key ${jsonEncode(value)}');
    }
    await tester.runAsync(() => server.close(force: true));
  });
}
