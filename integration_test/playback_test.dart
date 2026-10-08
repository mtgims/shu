// Plays real audio through the app's player: a fake addon inside the test serves two short
// generated WAV chapters as direct sources. Checks playback, the switch to the next chapter,
// saved progress and the end of the book. Needs no network or account.
import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/addons/addon_store.dart';
import 'package:audiobooks/main.dart';
import 'package:audiobooks/player/audiobook_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'example_extensions.dart';

/// Serves the addon protocol for one book with two chapters.
Future<HttpServer> fakeAddon() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://127.0.0.1:${server.port}';
  final audio = toneWav(seconds: 2);
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
    if (path.startsWith('/audio/')) {
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

      await until(
        () => player.current.value?.chapterIndex == 1,
        'second chapter starts',
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
}
