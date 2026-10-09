import 'dart:convert';

import 'package:audiobooks/addons/models.dart';
import 'package:audiobooks/sources/audiobookshelf.dart';
import 'package:audiobooks/sources/jellyfin.dart';
import 'package:audiobooks/sources/server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// A JWT with only an `exp` claim (the signature is never checked here).
String jwt(DateTime expires) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'exp': expires.millisecondsSinceEpoch ~/ 1000})}.sig';
}

void main() {
  group('serverAddress', () {
    test('adds the default port only when nothing else is given', () {
      expect(
        serverAddress('192.168.1.5', ServerKind.audiobookshelf).toString(),
        'http://192.168.1.5:13378',
      );
      expect(
        serverAddress('nas.local:8097', ServerKind.jellyfin).toString(),
        'http://nas.local:8097',
      );
      expect(
        serverAddress(
          'https://media.example.org/jf/',
          ServerKind.jellyfin,
        ).toString(),
        'https://media.example.org/jf',
      );
    });

    test('rejects what is not an address', () {
      expect(
        () => serverAddress('ftp://x', ServerKind.jellyfin),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('absChapters', () {
    test('one chapter per file stays one plain chapter per file', () {
      final chapters = absChapters(
        [
          (ino: '1', title: '01.mp3', start: 0, duration: 20),
          (ino: '2', title: '02.mp3', start: 20, duration: 20),
        ],
        [(start: 0, title: 'Opening'), (start: 20, title: 'Middle')],
      );
      expect(chapters.map((c) => c.id), ['1', '2']);
      expect(chapters.map((c) => c.title), ['Opening', 'Middle']);
      expect(chapters.every((c) => c.file == null), isTrue);
    });

    test('a file with several chapters gets chapters inside it', () {
      final chapters = absChapters(
        [(ino: '9', title: 'book.m4b', start: 0, duration: 45)],
        [
          (start: 0, title: 'A'),
          (start: 15, title: 'B'),
          (start: 30, title: 'C'),
        ],
      );
      expect(chapters.map((c) => c.id), ['9@0', '9@1', '9@2']);
      expect(chapters.map((c) => c.file).toSet(), {'9'});
      expect(chapters[1].start, const Duration(seconds: 15));
      expect(chapters.map((c) => c.duration), [15, 15, 15]);
    });

    test('a file inside a long chapter keeps that chapter’s title', () {
      final chapters = absChapters(
        [
          (ino: '1', title: 'part1.mp3', start: 0, duration: 100),
          (ino: '2', title: 'part2.mp3', start: 100, duration: 100),
        ],
        [(start: 0, title: 'Everything'), (start: 150, title: 'Ending')],
      );
      expect(chapters.map((c) => c.title), [
        'Everything',
        'Everything',
        'Ending',
      ]);
      expect(chapters[2].start, const Duration(seconds: 50));
      expect(chapters[1].file, '2');
    });
  });

  group('AudiobookshelfBackend', () {
    test('renews an expired login and saves the new tokens', () async {
      final fresh = jwt(DateTime.now().add(const Duration(hours: 1)));
      final seen = <String>[];
      final client = MockClient((req) async {
        seen.add('${req.method} ${req.url.path}');
        if (req.url.path == '/auth/refresh') {
          expect(req.headers['x-refresh-token'], 'refresh-1');
          return jsonResponse({
            'user': {'accessToken': fresh, 'refreshToken': 'refresh-2'},
          });
        }
        expect(req.headers['authorization'], 'Bearer $fresh');
        return jsonResponse({'libraries': <Object>[]});
      });
      final server = AudiobookshelfBackend(
        base: Uri.parse('http://abs.test'),
        user: 'me',
        userId: 'u1',
        accessToken: jwt(DateTime.now().subtract(const Duration(minutes: 1))),
        refreshToken: 'refresh-1',
        client: client,
      );
      var saved = 0;
      server.onLoginChanged = () => saved++;
      await server.refreshLibraries();
      expect(seen, ['POST /auth/refresh', 'GET /api/libraries']);
      expect(saved, 1);
      expect(server.toJson()['refreshToken'], 'refresh-2');

      final link = await server.resolve(
        const Source(
          id: 'stream',
          name: 'Audiobookshelf',
          resolve: {'item': 'i1', 'file': '7'},
        ),
      ) as Playable;
      expect(link.url, contains('/api/items/i1/file/7?token='));
      expect(link.validFor!.inMinutes, inInclusiveRange(55, 60));
    });
  });

  group('JellyfinBackend', () {
    Map<String, Object?> file(String id, String parent, {String? album}) => {
      'Id': id,
      'Name': 'File $id',
      'Type': 'AudioBook',
      'ParentId': parent,
      'Album': album,
    };

    test('puts files together into books and pages by books', () async {
      // 70 books of two files each, newest first.
      final files = [
        for (var b = 0; b < 70; b++) ...[
          file('$b-1', 'folder$b', album: 'Book $b'),
          file('$b-2', 'folder$b', album: 'Book $b'),
        ],
      ];
      final client = MockClient((req) async {
        final q = req.url.queryParameters;
        if (q['Ids'] != null) {
          return jsonResponse({
            'Items': [
              for (final id in q['Ids']!.split(','))
                {'Id': id, 'Name': id, 'ImageTags': <String, String>{}},
            ],
          });
        }
        final start = int.parse(q['StartIndex']!);
        final limit = int.parse(q['Limit']!);
        return jsonResponse({
          'Items': files.skip(start).take(limit).toList(),
          'TotalRecordCount': files.length,
        });
      });
      final server = JellyfinBackend(
        base: Uri.parse('http://jf.test'),
        user: 'me',
        userId: 'u1',
        deviceId: 'd1',
        token: 't',
        client: client,
      );
      final titles = <String>[];
      var page = await server.catalog('lib:L');
      titles.addAll(page.books.map((b) => b.title));
      while (page.hasMore) {
        page = await server.catalog('lib:L', skip: titles.length);
        titles.addAll(page.books.map((b) => b.title));
      }
      expect(titles, [for (var b = 0; b < 70; b++) 'Book $b']);
      expect((await server.catalog('lib:L')).books.first.id, 'folder0|Book 0');
    });

    test(
      'a file with chapter marks becomes chapters inside the file',
      () async {
        final client = MockClient(
          (req) async => jsonResponse({
            'Items': [
              {
                ...file('m', 'folder'),
                'Name': 'Story',
                'RunTimeTicks': 450000000,
                'Chapters': [
                  {'StartPositionTicks': 0, 'Name': 'Opening'},
                  {'StartPositionTicks': 150000000, 'Name': 'Middle'},
                ],
              },
            ],
          }),
        );
        final server = JellyfinBackend(
          base: Uri.parse('http://jf.test'),
          user: 'me',
          userId: 'u1',
          deviceId: 'd1',
          token: 't',
          client: client,
        );
        final book = await server.book('folder');
        expect(book.title, 'Story');
        expect(book.chapters.map((c) => c.title), ['Opening', 'Middle']);
        expect(book.chapters[1].start, const Duration(seconds: 15));
        expect(book.chapters[1].duration, 30);
        expect(book.chapters.map((c) => c.file).toSet(), {'m'});
      },
    );
  });
}
