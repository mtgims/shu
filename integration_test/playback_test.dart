// Plays real audio through the app's player: a fake addon inside the test serves two short
// generated WAV chapters as direct sources. Checks playback, the switch to the next chapter
// (which fails once and is tried again), saved progress and the end of the book. Needs no network
// or account.
import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/addons/addon_store.dart';
import 'package:audiobooks/library/library_store.dart';
import 'package:audiobooks/main.dart';
import 'package:audiobooks/player/audiobook_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'example_extensions.dart';

/// Serves the addon protocol for one book with two chapters.
Future<HttpServer> fakeAddon({double seconds = 2}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://127.0.0.1:${server.port}';
  final audio = toneWav(seconds: seconds);
  // The second chapter fails once, like a connection still waking up with the screen off.
  var secondRefused = false;
  final routes = <String, Object>{
    '/manifest.json': {
      'protocol': 1,
      'id': 'test.tones',
      'name': 'Tones',
      'version': '1.0.0',
      'catalogs': [
        {'id': 'all', 'name': 'All'},
      ],
    },
    '/book/tones.json': {
      'book': {
        'id': 'tones',
        'title': 'Two Tones',
        'authors': ['Test'],
        'chapters': [
          {'id': 'a', 'title': 'First tone'},
          {'id': 'b', 'title': 'Second tone'},
        ],
      },
    },
    for (final ch in ['a', 'b'])
      '/sources/tones/$ch.json': {
        'sources': [
          {'id': 'direct', 'name': 'Direct', 'url': '$base/audio/$ch.wav'},
        ],
      },
  };
  server.listen((req) async {
    final path = Uri.decodeComponent(req.uri.path);
    if (path == '/audio/b.wav' && !secondRefused) {
      secondRefused = true;
      req.response.statusCode = 503;
    } else if (path.startsWith('/audio/')) {
      req.response.headers.contentType = ContentType('audio', 'wav');
      req.response.add(audio);
    } else if (routes[path] case final body?) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(body));
    } else {
      req.response.statusCode = 404;
      req.response.write('{"error":"not found"}');
    }
    await req.response.close();
  });
  return server;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plays chapters back to back and finishes the book', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final server = await fakeAddon();
      final app = await createApp(systemControls: false);
      final installed = await app.addons.install(
        'http://127.0.0.1:${server.port}/manifest.json',
      );
      final addon = (installed as Installed).addon;
      final book = await addon.client.book('tones');
      final player = app.player;

      Future<void> until(bool Function() ok, String what) async {
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (!ok()) {
          if (DateTime.now().isAfter(end)) {
            fail(
              'Timed out: $what (status ${player.status.value.phase} '
              '${player.status.value.message ?? ''})',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      await player.openBook(addon, book);
      await until(
        () => player.status.value.phase == PlayerPhase.ready,
        'first chapter ready',
      );
      await until(() => player.playing, 'playing');
      await until(
        () => player.position > const Duration(milliseconds: 500),
        'position moves',
      );
      expect(player.current.value!.chapterIndex, 0);

      // The player must not pause between chapters: on Android a pause ends the foreground
      // service and its wake lock, and with the screen off the next chapter never loads.
      var paused = false;
      final watch = player.playingStream.listen((p) => paused |= !p);
      await until(
        () => player.current.value?.chapterIndex == 1,
        'second chapter starts',
      );
      await until(
        () => player.status.value.phase == PlayerPhase.ready,
        'second chapter ready',
      );
      await watch.cancel();
      expect(
        paused,
        isFalse,
        reason: 'paused while moving to the next chapter',
      );
      await until(
        () => app.library.find('test.tones', 'tones')?.finished == true,
        'book finished',
      );
      expect(player.status.value.message, 'Finished');

      await player.stop();
      await server.close(force: true);
    });
  });

  testWidgets('closing the window saves the position', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final server = (await tester.runAsync(fakeAddon))!;
    final app = (await tester.runAsync(
      () => createApp(systemControls: false),
    ))!;
    await tester.pumpWidget(app);
    await tester.runAsync(() async {
      final installed = await app.addons.install(
        'http://127.0.0.1:${server.port}/manifest.json',
      );
      final addon = (installed as Installed).addon;
      final player = app.player;
      await player.openBook(addon, await addon.client.book('tones'));
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (player.position < const Duration(milliseconds: 800)) {
        if (DateTime.now().isAfter(end)) fail('Timed out: position moves');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // What the desktop engine sends when the window's close button is pressed.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/platform',
        const JSONMethodCodec().encodeMethodCall(
          const MethodCall('System.requestAppExit'),
        ),
        (_) {},
      );
      final saved = app.library.find('test.tones', 'tones')!;
      expect(saved.chapterIndex, 0);
      expect(saved.position, greaterThan(const Duration(milliseconds: 500)));

      await player.stop();
      await server.close(force: true);
    });
  });

  testWidgets('pausing, seeking and bookmarks keep the place', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final server = await fakeAddon(seconds: 20);
      final app = await createApp(systemControls: false);
      final installed = await app.addons.install(
        'http://127.0.0.1:${server.port}/manifest.json',
      );
      final addon = (installed as Installed).addon;
      final player = app.player;
      final prefs = await SharedPreferences.getInstance();
      LibraryEntry saved() => LibraryStore(prefs).find('test.tones', 'tones')!;
      Future<void> until(bool Function() ok, String what) async {
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (!ok()) {
          if (DateTime.now().isAfter(end)) fail('Timed out: $what');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await player.openBook(addon, await addon.client.book('tones'));
      await until(
        () => player.position > const Duration(seconds: 1),
        'position moves',
      );
      await player.pause();

      // Moved while paused: saved at once, nothing else would save it.
      await player.seek(const Duration(seconds: 12));
      expect(saved().position, const Duration(seconds: 12));
      await player.addBookmark();
      expect(saved().bookmarks.single.position, const Duration(seconds: 12));

      // Back two minutes later: a few seconds back, to find the thread.
      final pausedAt = DateTime.now();
      player.now = () => pausedAt.add(const Duration(minutes: 2));
      await player.play();
      expect(
        player.position.inMilliseconds,
        closeTo(9000, 600),
        reason: 'stepped back 3 s',
      );

      // A chapter picked by mistake: the history leads back.
      await player.playChapter(1);
      await until(
        () =>
            player.current.value!.chapterIndex == 1 &&
            player.status.value.phase == PlayerPhase.ready,
        'second chapter',
      );
      final back = player.current.value!.history.first;
      expect(back.chapterIndex, 0);
      await player.jumpTo(back);
      await until(
        () =>
            player.current.value!.chapterIndex == 0 &&
            player.status.value.phase == PlayerPhase.ready,
        'back in the first chapter',
      );
      // The audio opens at that place (the desktop backend reports it a moment later).
      await until(
        () =>
            (player.position - back.position).abs() <
            const Duration(seconds: 1),
        'playing from where it was',
      );

      await player.stop();
      await server.close(force: true);
    });
  });
}
