import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/addons/addon_store.dart';
import 'package:audiobooks/downloads/download_store.dart';
import 'package:audiobooks/library/library_store.dart';
import 'package:audiobooks/player/player_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/temp_paths.dart';

/// An addon with three books: `two` (two files), `one` (two chapters in one M4B) and `slow`
/// (its service is still fetching it the first time it is asked).
class _Addon {
  late final HttpServer server;
  final audio = List<int>.generate(100000, (i) => i % 251);

  /// Requests for audio, with their Range header.
  final ranges = <String?>[];
  bool honourRange = true;
  int slowAsked = 0;

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      final res = req.response;
      Object? body;
      if (path == '/manifest.json') {
        body = {
          'protocol': 1,
          'id': 'test.dl',
          'name': 'Downloads',
          'version': '1.0.0',
          'catalogs': [],
        };
      } else if (path == '/book/two.json') {
        body = {
          'book': {
            'id': 'two',
            'title': 'Two Files',
            'chapters': [
              {'id': 'a', 'title': 'A'},
              {'id': 'b', 'title': 'B'},
            ],
          },
        };
      } else if (path == '/book/one.json') {
        body = {
          'book': {
            'id': 'one',
            'title': 'One File',
            'chapters': [
              {'id': 'a', 'title': 'A', 'file': 'f', 'start': 0},
              {'id': 'b', 'title': 'B', 'file': 'f', 'start': 60},
            ],
          },
        };
      } else if (path == '/book/slow.json') {
        body = {
          'book': {
            'id': 'slow',
            'title': 'Slow',
            'chapters': [
              {'id': 'a', 'title': 'A'},
            ],
          },
        };
      } else if (path.startsWith('/sources/slow/')) {
        body = {
          'sources': [
            {'id': 's', 'name': 'Service', 'resolve': '$base/resolve/slow'},
          ],
        };
      } else if (path == '/resolve/slow') {
        body = slowAsked++ == 0
            ? {'status': 'downloading', 'message': 'Fetching', 'progress': 0.5}
            : {'url': '$base/audio/slow.mp3'};
      } else if (path.startsWith('/sources/')) {
        final parts = path.split('/');
        final chapter = parts.last.replaceAll('.json', '');
        body = {
          'sources': [
            {
              'id': 'd',
              'name': 'Direct',
              'url': '$base/audio/${parts[2]}-$chapter.mp3',
            },
          ],
        };
      } else if (path.startsWith('/audio/')) {
        final range = req.headers.value('range');
        ranges.add(range);
        final from = range != null && honourRange
            ? int.parse(range.substring(6, range.length - 1))
            : 0;
        res.statusCode = from > 0 ? 206 : 200;
        res.headers.contentType = ContentType('audio', 'mpeg');
        res.contentLength = audio.length - from;
        res.add(audio.sublist(from));
        await res.close();
        return;
      }
      if (body == null) res.statusCode = 404;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body ?? {'error': 'not found'}));
      await res.close();
    });
  }
}

void main() {
  late Directory temp;
  late _Addon fake;
  late SharedPreferences prefs;
  late LibraryStore library;
  late AddonStore addons;
  late InstalledAddon addon;
  late PlayerSettings settings;

  setUp(() async {
    temp = useTempAppStorage();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fake = _Addon();
    await fake.start();
    library = LibraryStore(prefs);
    addons = await AddonStore.load(prefs);
    addon =
        (await addons.install('${fake.base}/manifest.json') as Installed).addon;
    settings = PlayerSettings(prefs);
  });

  tearDown(() async {
    await fake.server.close(force: true);
    temp.deleteSync(recursive: true);
  });

  Future<DownloadStore> load() => DownloadStore.load(
    prefs,
    library,
    addons,
    settings,
    root: Directory('${temp.path}/downloads'),
  );

  Future<void> until(bool Function() ok) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('Timed out');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test(
    'a book downloads, joins the library and plays from its files',
    () async {
      final store = await load();
      final book = await addon.client.book('two');
      await store.add(addon, book);
      final entry = library.find('test.dl', 'two')!;
      expect(entry.position, Duration.zero);
      await until(() => store.isDownloaded(entry.key));

      for (final i in [0, 1]) {
        final file = store.fileFor(entry, i)!;
        expect(file, endsWith('$i.mp3'));
        expect(File(file).readAsBytesSync(), fake.audio);
      }
      expect(await store.bytesUsed(), 2 * fake.audio.length);

      // Known again after a restart.
      final again = await load();
      expect(again.fileFor(entry, 1), store.fileFor(entry, 1));
    },
  );

  test('chapters inside one file share one download', () async {
    final store = await load();
    await store.add(addon, await addon.client.book('one'));
    final entry = library.find('test.dl', 'one')!;
    await until(() => store.isDownloaded(entry.key));
    expect(fake.ranges, hasLength(1));
    expect(store.fileFor(entry, 1), store.fileFor(entry, 0));
  });

  test('a cut-off file goes on where it stopped', () async {
    final store = await load();
    final book = await addon.client.book('two');
    // What an earlier run left: half of the first file.
    final key = LibraryEntry.keyOf('test.dl', 'two');
    final dir = Directory(
      '${temp.path}/downloads/${base64Url.encode(utf8.encode(key))}',
    )..createSync(recursive: true);
    File('${dir.path}/0.part').writeAsBytesSync(fake.audio.sublist(0, 40000));

    await store.add(addon, book);
    await until(() => store.isDownloaded(key));
    expect(fake.ranges.first, 'bytes=40000-');
    final entry = library.find('test.dl', 'two')!;
    expect(File(store.fileFor(entry, 0)!).readAsBytesSync(), fake.audio);
  });

  test('a server that ignores Range sends the whole file again', () async {
    fake.honourRange = false;
    final store = await load();
    final key = LibraryEntry.keyOf('test.dl', 'two');
    final dir = Directory(
      '${temp.path}/downloads/${base64Url.encode(utf8.encode(key))}',
    )..createSync(recursive: true);
    File('${dir.path}/0.part').writeAsBytesSync(fake.audio.sublist(0, 40000));

    await store.add(addon, await addon.client.book('two'));
    await until(() => store.isDownloaded(key));
    final entry = library.find('test.dl', 'two')!;
    expect(File(store.fileFor(entry, 0)!).readAsBytesSync(), fake.audio);
  });

  test('a book the service is still fetching is asked about again', () async {
    DownloadStore.waitFor = const Duration(milliseconds: 100);
    final store = await load();
    await store.add(addon, await addon.client.book('slow'));
    final key = LibraryEntry.keyOf('test.dl', 'slow');
    await until(() => store.progressOf(key)?.state == DownloadState.waiting);
    expect(store.progressOf(key)!.message, 'Fetching');
    await until(() => store.isDownloaded(key));
    expect(fake.slowAsked, 2);
  });

  test('removed and finished books lose their download', () async {
    final store = await load();
    await store.add(addon, await addon.client.book('two'));
    await store.add(addon, await addon.client.book('one'));
    final two = library.find('test.dl', 'two')!;
    final one = library.find('test.dl', 'one')!;
    await until(
      () => store.isDownloaded(two.key) && store.isDownloaded(one.key),
    );

    // Finished keeps it, unless the setting says otherwise.
    two.finished = true;
    await library.save(two);
    expect(store.isDownloaded(two.key), isTrue);
    settings.deleteFinishedDownloads = true;
    await until(() => store.progressOf(two.key) == null);

    await library.remove(one);
    await until(() => store.progressOf(one.key) == null);
    await until(() => Directory('${temp.path}/downloads').listSync().isEmpty);
  });

  test('folders nobody knows of are cleaned up at start', () async {
    await prefs.setString('downloads', '{}');
    final stray = Directory('${temp.path}/downloads/stray')
      ..createSync(recursive: true);
    File('${stray.path}/0.mp3').writeAsStringSync('x');
    await load();
    expect(stray.existsSync(), isFalse);
  });

  test('a damaged record is set aside', () async {
    await prefs.setString('downloads', '{broken');
    final store = await load();
    expect(store.progressOf('test.dl|two'), isNull);
    expect(prefs.getString('downloads.bad'), '{broken');
  });
}
