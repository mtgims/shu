// Books on this device and chapters inside one file, played through the app's player with
// generated WAV files. App storage goes to a temporary folder. Needs no network or account.
import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/addons/addon_store.dart';
import 'package:audiobooks/main.dart';
import 'package:audiobooks/player/audiobook_player.dart';
import 'package:audiobooks/sources/local_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'example_extensions.dart';

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// One book whose first three chapters are marks inside one file, then a chapter of its own.
Future<HttpServer> fakeAddon() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://127.0.0.1:${server.port}';
  final audio = {'long': toneWav(seconds: 4.5), 'short': toneWav(seconds: 1)};
  final chapters = [
    {'id': 'long@0', 'title': 'One', 'file': 'long', 'start': 0},
    {'id': 'long@1', 'title': 'Two', 'file': 'long', 'start': 1.5},
    {'id': 'long@2', 'title': 'Three', 'file': 'long', 'start': 3},
    {'id': 'short', 'title': 'Four'},
  ];
  final routes = <String, Object>{
    '/manifest.json': {
      'protocol': 1,
      'id': 'test.marks',
      'name': 'Marks',
      'version': '1.0.0',
      'catalogs': <Object>[],
    },
    '/book/marks.json': {
      'book': {'id': 'marks', 'title': 'Marks', 'chapters': chapters},
    },
    for (final c in chapters)
      '/sources/marks/${c['id']}.json': {
        'sources': [
          {
            'id': 'direct',
            'name': 'Direct',
            'url': '$base/audio/${(c['id'] as String).split('@').first}.wav',
          },
        ],
      },
  };
  server.listen((req) async {
    final path = Uri.decodeComponent(req.uri.path);
    final wav = audio[path.replaceAll(RegExp(r'^/audio/|\.wav$'), '')];
    if (wav != null) {
      req.response.headers.contentType = ContentType('audio', 'wav');
      req.response.add(wav);
    } else if (routes[path] case final body?) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(body));
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  return server;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shu-test-');
    PathProviderPlatform.instance = _TempPaths(root.path);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> until(
    AudiobookPlayer player,
    bool Function() ok,
    String what,
  ) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (!ok()) {
      if (DateTime.now().isAfter(end)) {
        fail(
          'Timed out: $what (status ${player.status.value.phase} '
          '${player.status.value.message ?? ''})',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  testWidgets('follows chapters inside one file, then plays the next file', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final server = await fakeAddon();
      final app = await createApp(systemControls: false);
      final installed = await app.addons.install(
        'http://127.0.0.1:${server.port}/manifest.json',
      );
      final addon = (installed as Installed).addon;
      final book = await addon.client.book('marks');
      expect(book.chapters[1].start, const Duration(milliseconds: 1500));
      final player = app.player;
      int chapter() => player.current.value!.chapterIndex;

      // Picking a chapter of the open file seeks to it.
      await player.openBook(addon, book);
      await until(player, () => player.playing, 'playing');
      await player.playChapter(2);
      await until(player, () => player.playing, 'playing again');
      expect(player.position, greaterThanOrEqualTo(const Duration(seconds: 3)));
      await player.seek(Duration.zero);
      await until(player, () => chapter() == 0, 'back to the first mark');

      // Playback moves through the marks and on into the next file.
      await until(player, () => chapter() == 1, 'second mark');
      await until(player, () => chapter() == 2, 'third mark');
      await until(player, () => chapter() == 3, 'next file');
      await until(
        player,
        () => app.library.find('test.marks', 'marks')?.finished == true,
        'book finished',
      );

      await player.stop();
      await server.close(force: true);
    });
  });

  testWidgets('adds a folder of audio files as a book and plays it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final folder = Directory('${root.path}/books/Some Author/A Short Book');
      await folder.create(recursive: true);
      for (final name in [
        '2 - Second.wav',
        '10 - Third.wav',
        '1 - First.wav',
      ]) {
        await File('${folder.path}/$name').writeAsBytes(toneWav(seconds: 1));
      }
      final app = await createApp(systemControls: false);
      final local = app.addons.local;

      final added = await local.addFolder('${root.path}/books');
      expect(added, hasLength(1));
      expect(added.single.title, 'A Short Book');
      final addon = app.addons.byId(LocalBackend.id)!;
      final book = await addon.client.book(added.single.id);
      expect(book.chapters.map((c) => c.title), [
        '1 - First',
        '2 - Second',
        '10 - Third',
      ]);
      final search = await addon.client.catalog('search', search: 'short');
      expect(search.books.single.id, book.id);

      // Adding the folder again doesn't add the book twice.
      await local.addFolder('${root.path}/books');
      expect(local.books, hasLength(1));

      final player = app.player;
      await player.openBook(addon, book);
      await until(
        player,
        () => app.library.find(LocalBackend.id, book.id)?.finished == true,
        'book finished',
      );
      await player.stop();

      // The user's own files stay when the book is removed.
      await local.remove(local.books.single);
      expect(local.books, isEmpty);
      expect(await folder.list().length, 3);
    });
  });

  testWidgets(
    'moves picked files into the app and deletes them with the book',
    (tester) async {
      await tester.runAsync(() async {
        final picked = Directory('${root.path}/picked');
        await picked.create();
        final path = '${picked.path}/Whole Book.m4b';
        await File(path).writeAsBytes(toneWav(seconds: 1));
        final app = await createApp(systemControls: false);
        final local = app.addons.local;

        final added = await local.addFiles([path], copy: true);
        final book = added.single;
        expect(book.title, 'Whole Book');
        expect(book.owned, isTrue);
        expect(File(path).existsSync(), isFalse);
        final moved = File(book.files.single.path);
        expect(moved.existsSync(), isTrue);

        await local.remove(book);
        expect(moved.existsSync(), isFalse);
      });
    },
  );
}
