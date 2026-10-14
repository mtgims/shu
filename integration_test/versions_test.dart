// Play on a catalog book, through the book page: a version that is cached wins, a version that
// fails to start is replaced by the next good one, and when no version clearly is the book the
// user is asked. Uses a small catalog and source served from this machine; plays silence.
import 'dart:io';

import 'package:audiobooks/addons/models.dart';
import 'package:audiobooks/main.dart';
import 'package:audiobooks/player/audiobook_player.dart';
import 'package:audiobooks/screens/book_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'example_extensions.dart';
import 'temp_paths.dart';

const _catalog = r'''
extension = {
  manifest: { id: 'org.example.picks', name: 'Picks', version: '1.0.0',
    catalogs: [{ id: 'all', name: 'All' }] },
  async catalog() { return { books: [], hasMore: false }; },
  async book(id) { return { id: id, title: id, authors: ['Someone'], chapters: [] }; },
};
''';

/// Versions per catalog book; `audio` says whether a version's file exists, `cached` what its
/// source reports.
String _source(String base) =>
    '''
var versions = {
  'Cached Wins': [
    { id: 'slow', match: 'good', cached: false, audio: true },
    { id: 'fast', match: 'good', cached: true, audio: true },
  ],
  'Broken First': [
    { id: 'broken', match: 'good', cached: true, audio: false },
    { id: 'works', match: 'good', cached: false, audio: true },
  ],
  'Unsure': [
    { id: 'maybe', match: 'fair', cached: true, audio: true },
    { id: 'unlikely', match: 'poor', cached: true, audio: true },
  ],
};
function find(id) {
  for (var t in versions) for (var i = 0; i < versions[t].length; i++)
    if (versions[t][i].id === id) return versions[t][i];
}
extension = {
  manifest: { id: 'org.example.picker', name: 'Picker', version: '1.0.0', releases: true,
    catalogs: [] },
  async catalog() { return { books: [], hasMore: false }; },
  async releases(work) {
    return { books: (versions[work.title] || []).map(function (v) {
      return { id: v.id, title: work.title + ' (' + v.id + ')', match: v.match, tags: [v.match] };
    }) };
  },
  async book(id) { return { id: id, title: id, chapters: [{ id: 'a', title: 'Part 1' }] }; },
  async sources(bookId) {
    var v = find(bookId);
    return { sources: [{ id: 'main', name: 'Main', cached: v.cached,
      url: '$base/audio/' + (v.audio ? 'ok' : 'missing') + '.wav' }] };
  },
};
''';

Future<HttpServer> _serve() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final audio = toneWav(seconds: 30);
  server.listen((req) async {
    if (req.uri.path == '/audio/ok.wav') {
      req.response.headers.contentType = ContentType('audio', 'wav');
      req.response.add(audio);
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  return server;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late Directory root;
  setUp(() {
    root = useTempAppStorage();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() ok,
    String what, {
    int seconds = 30,
  }) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('Timed out: $what');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  testWidgets('Play picks a cached version, falls back, or asks', (
    tester,
  ) async {
    final server = (await tester.runAsync(_serve))!;
    final app = (await tester.runAsync(
      () => createApp(systemControls: false),
    ))!;
    final catalog = (await tester.runAsync(
      () => app.addons.installExtension(_catalog),
    ))!;
    await tester.runAsync(
      () => app.addons.installExtension(
        _source('http://127.0.0.1:${server.port}'),
      ),
    );
    await tester.pumpWidget(app);
    final player = app.player;

    Future<void> pressPlay(String title) async {
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => BookScreen(
                addon: catalog,
                summary: BookSummary(id: title, title: title),
              ),
            ),
          );
      await waitFor(
        tester,
        () => find.text('Play').evaluate().isNotEmpty,
        'the Play button of $title',
      );
      await tester.tap(find.text('Play'));
      await tester.pump();
    }

    Future<void> close() async {
      await tester.runAsync(player.stop);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.popUntil((r) => r.isFirst);
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Both versions are good: the one the source has cached starts.
    await pressPlay('Cached Wins');
    await waitFor(
      tester,
      () => player.status.value.phase == PlayerPhase.ready,
      'a version playing',
    );
    expect(player.current.value!.book.id, 'fast');
    await close();

    // The first good version has no audio: the next one plays, the failed one is forgotten.
    await pressPlay('Broken First');
    await waitFor(
      tester,
      () =>
          player.status.value.phase == PlayerPhase.ready &&
          player.current.value?.book.id == 'works',
      'the next version playing (status ${player.status.value.phase} '
      '${player.status.value.message})',
      // Well under the 30 s open timeout: the failed open itself starts the fallback.
      seconds: 10,
    );
    expect(app.library.find('org.example.picker', 'broken'), isNull);
    expect(app.library.find('org.example.picker', 'works'), isNotNull);
    await close();

    // No version is clearly the book: the user picks.
    await pressPlay('Unsure');
    await waitFor(
      tester,
      () => find.text('Which version?').evaluate().isNotEmpty,
      'the version picker',
    );
    expect(find.text('Unsure (maybe)'), findsWidgets);
    expect(player.current.value, isNull);
    // Let the sheet finish sliding up before tapping in it.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.tap(find.text('Unsure (maybe)').last);
    await waitFor(
      tester,
      () => player.current.value?.book.id == 'maybe',
      'the picked version playing',
    );
    await tester.runAsync(player.stop);
    await tester.runAsync(() => server.close(force: true));
  });
}
