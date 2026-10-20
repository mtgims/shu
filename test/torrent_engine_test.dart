import 'dart:io';

import 'package:audiobooks/addons/backend.dart';
import 'package:audiobooks/addons/models.dart';
import 'package:audiobooks/library/library_store.dart';
import 'package:audiobooks/peer/torrent_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/temp_paths.dart';

const hash = '0f54898dc1b8e49d96e32827377f651ea6c935af';

void main() {
  late Directory root;
  late SharedPreferences prefs;
  setUp(() async {
    root = useTempAppStorage();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => root.delete(recursive: true));

  // No engine program: only what works without one.
  TorrentEngine engine() => TorrentEngine(prefs, binary: () async => null);

  test('options read from an extension, with defaults for what is missing', () {
    expect(TorrentOptions.fromJson(null), const TorrentOptions());
    final json = {
      'folder': ' /media/books ',
      'deleteWhenFinished': false,
      'keepDays': 30,
      'storageLimit': 1 << 30,
      'downloadLimit': 1 << 20,
    };
    final o = TorrentOptions.fromJson(json);
    expect(o.folder, '/media/books');
    expect(o.deleteWhenFinished, isFalse);
    expect(o.keepDays, 30);
    // Equal options from each call: the engine's settings are only sent when they change.
    expect(TorrentOptions.fromJson(json), o);
    expect(TorrentOptions.fromJson({'folder': '  '}).folder, isNull);
  });

  test(
    'TorrServer settings: ours applied, its others kept, LAN announcing off',
    () {
      final sets = TorrentEngine.settingsFor(
        {'CacheSize': 1, 'ConnectionsLimit': 25, 'EnableBonjour': true},
        const TorrentOptions(storageLimit: 2 << 30, uploadLimit: 50 << 10),
        '/data/torrents',
      );
      expect(sets['ConnectionsLimit'], 25);
      expect(sets['TorrentsSavePath'], '/data/torrents');
      expect(sets['UseDisk'], isTrue);
      expect(sets['CacheSize'], 2 << 30);
      expect(sets['UploadRateLimit'], 50);
      expect(sets['DownloadRateLimit'], 0);
      expect(sets['EnableBonjour'], isFalse);
      expect(sets['EnableDLNA'], isFalse);
    },
  );

  test('a magnet link gives its hash in hex, also from base32', () {
    expect(TorrentEngine.magnetHash('magnet:?xt=urn:btih:$hash&dn=x'), hash);
    expect(
      TorrentEngine.magnetHash('magnet:?xt=urn:btih:${hash.toUpperCase()}'),
      hash,
    );
    expect(
      TorrentEngine.magnetHash(
        'magnet:?xt=urn:btih:B5KITDOBXDSJ3FXDFATTO73FD2TMSNNP&dn=x',
      ),
      hash,
    );
    expect(
      TorrentEngine.magnetHash(
        'magnet:?xt=urn:btih:b5kitdobxdsj3fxdfatto73fd2tmsnnp',
      ),
      hash,
    );
    for (final bad in [
      'https://example.org/a.torrent',
      'magnet:?xt=urn:btih:${hash}00',
      'magnet:?xt=urn:btih:B5KITDOBXDSJ3FXDFATTO73FD2TMSNN',
    ]) {
      expect(
        () => TorrentEngine.magnetHash(bad),
        throwsA(isA<AddonException>()),
        reason: bad,
      );
    }
  });

  test('a start that failed is tried again on the next call', () async {
    var tries = 0;
    final e = TorrentEngine(
      prefs,
      binary: () async {
        if (tries++ == 0) throw const FileSystemException('disk gone');
        return null;
      },
    );
    final magnet = 'magnet:?xt=urn:btih:$hash';
    await expectLater(
      e.files(magnet, const TorrentOptions()),
      throwsA(isA<FileSystemException>()),
    );
    // Not the first error again: the start ran a second time.
    await expectLater(
      e.files(magnet, const TorrentOptions()),
      throwsA(isA<AddonException>()),
    );
    expect(tries, 2);
  });

  test('without the engine program, playing says so', () async {
    await expectLater(
      engine().files('magnet:?xt=urn:btih:$hash', const TorrentOptions()),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'message',
          contains('can\'t play torrents'),
        ),
      ),
    );
  });

  test('only links of the running engine count as its own', () async {
    await prefs.setInt('torrent.port', 4100);
    final e = engine();
    expect(
      e.hashOf('http://127.0.0.1:4100/stream/a.mp3?link=$hash&index=1&play'),
      hash,
    );
    expect(e.hashOf('http://127.0.0.1:4101/stream/a.mp3?link=$hash'), isNull);
    expect(e.hashOf('https://example.org/stream/a.mp3?link=$hash'), isNull);
  });

  group('deleting downloads', () {
    late Directory folder;
    setUp(() {
      folder = Directory('${root.path}/support/torrents/$hash')
        ..createSync(recursive: true);
      File('${folder.path}/0').writeAsStringSync('piece');
    });

    test('only a folder Shu marked as its own is deleted', () async {
      await engine().forget(hash);
      expect(folder.existsSync(), isTrue, reason: 'no marker');
      File('${folder.path}/.shu-download').writeAsStringSync('');
      await engine().forget(hash);
      expect(folder.existsSync(), isFalse);
    });

    test('a finished or removed book takes its download along', () async {
      File('${folder.path}/.shu-download').writeAsStringSync('');
      await prefs.setInt('torrent.port', 4100);
      final library = LibraryStore(prefs);
      const book = Book(
        id: 'b1',
        title: 'Book',
        chapters: [Chapter(id: '0', title: 'One')],
      );
      final entry = library.entryFor('ext', book);
      await library.save(entry);
      final e = engine()
        ..loaded(
          'http://127.0.0.1:4100/stream/a.mp3?link=$hash&index=1',
          entry.key,
        )
        ..loaded(null, null);
      await Future<void>.delayed(Duration.zero);

      await e.tidy(library);
      expect(folder.existsSync(), isTrue, reason: 'still listening');
      entry.finished = true;
      await library.save(entry);
      await e.tidy(library);
      expect(folder.existsSync(), isFalse);
    });
  });
}
