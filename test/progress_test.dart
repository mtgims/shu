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

/// Three files of 100 s; the second holds two chapters (at 0 and 40 s).
const book = Book(
  id: 'b',
  title: 'Book',
  chapters: [
    Chapter(id: 'f1', title: 'One', duration: 100),
    Chapter(
      id: 'f2@0',
      title: 'Two',
      duration: 40,
      file: 'f2',
      start: Duration.zero,
    ),
    Chapter(
      id: 'f2@1',
      title: 'Three',
      duration: 60,
      file: 'f2',
      start: Duration(seconds: 40),
    ),
    Chapter(id: 'f3', title: 'Four', duration: 100),
  ],
);

BookPlace at(int chapter, int seconds) =>
    (chapterIndex: chapter, position: Duration(seconds: seconds));

void main() {
  group('book time', () {
    test('counts the files before the one playing', () {
      expect(bookTime(book, at(0, 30)), const Duration(seconds: 30));
      // Positions inside a file with chapters count from the file's start.
      expect(bookTime(book, at(1, 10)), const Duration(seconds: 110));
      expect(bookTime(book, at(2, 50)), const Duration(seconds: 150));
      expect(bookTime(book, at(3, 5)), const Duration(seconds: 205));
      expect(bookLength(book), const Duration(seconds: 300));
    });

    test('finds the chapter and file again', () {
      for (final place in [at(0, 30), at(1, 10), at(2, 50), at(3, 5)]) {
        expect(placeAt(book, bookTime(book, place)), place);
      }
      // Past the end stays in the last file.
      expect(placeAt(book, const Duration(seconds: 400)), at(3, 200));
      expect(placeAt(book, Duration.zero), at(0, 0));
    });
  });

  group('Audiobookshelf progress', () {
    AudiobookshelfBackend server(MockClient client) => AudiobookshelfBackend(
      base: Uri.parse('http://abs.test'),
      user: 'me',
      userId: 'u1',
      accessToken: 'old-style-token',
      client: client,
    );

    test('reads the book time and maps it to the chapter', () async {
      final abs = server(
        MockClient((req) async {
          expect(req.url.path, '/api/me/progress/b');
          return jsonResponse({
            'currentTime': 150.5,
            'isFinished': false,
            'lastUpdate': 1792016389732,
          });
        }),
      );
      final p = (await abs.progress(book))!;
      expect(p.place, (
        chapterIndex: 2,
        position: const Duration(milliseconds: 50500),
      ));
      expect(p.finished, isFalse);
      expect(p.updatedAt.millisecondsSinceEpoch, 1792016389732);
    });

    test('reports the book time', () async {
      late Map<String, dynamic> sent;
      final abs = server(
        MockClient((req) async {
          expect('${req.method} ${req.url.path}', 'PATCH /api/me/progress/b');
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('OK', 200);
        }),
      );
      await abs.report(book, at(2, 50), finished: false);
      expect(sent['currentTime'], 150);
      expect(sent['duration'], 300);
      expect(sent['progress'], closeTo(0.5, 0.001));
      expect(sent['isFinished'], isFalse);
    });
  });

  group('Jellyfin progress', () {
    JellyfinBackend server(MockClient client) => JellyfinBackend(
      base: Uri.parse('http://jf.test'),
      user: 'me',
      userId: 'u1',
      deviceId: 'd1',
      token: 't',
      client: client,
    );
    Map<String, Object?> file(String id, Map<String, Object?> data) => {
      'Id': id,
      'Type': 'AudioBook',
      'ParentId': 'b',
      'UserData': data,
    };

    test('the file played last is where the user is', () async {
      final jf = server(
        MockClient(
          (req) async => jsonResponse({
            'Items': [
              file('f1', {
                'Played': true,
                'PlaybackPositionTicks': 0,
                'LastPlayedDate': '2026-10-14T20:00:00.0000000Z',
              }),
              file('f2', {
                'PlaybackPositionTicks': 500000000,
                // Jellyfin writes seven digits of fractions.
                'LastPlayedDate': '2026-10-14T22:20:37.1234567Z',
              }),
              file('f3', {'PlaybackPositionTicks': 0}),
            ],
          }),
        ),
      );
      final p = (await jf.progress(book))!;
      expect(p.place, at(2, 50));
      expect(p.updatedAt.toUtc().hour, 22);
    });

    test('a file played to its end means the start of the next', () async {
      final jf = server(
        MockClient(
          (req) async => jsonResponse({
            'Items': [
              file('f1', {
                'Played': true,
                'PlaybackPositionTicks': 0,
                'LastPlayedDate': '2026-10-14T20:00:00Z',
              }),
              file('f2', {}),
              file('f3', {}),
            ],
          }),
        ),
      );
      expect((await jf.progress(book))!.place, at(1, 0));
    });

    test('nothing played there is no progress', () async {
      final jf = server(
        MockClient(
          (req) async => jsonResponse({
            'Items': [file('f1', {}), file('f2', {}), file('f3', {})],
          }),
        ),
      );
      expect(await jf.progress(book), isNull);
    });

    test('reports the position in the file, or every file played', () async {
      final sent = <String, Map<String, dynamic>>{};
      final jf = server(
        MockClient((req) async {
          expect(req.method, 'POST');
          expect(req.url.queryParameters['userId'], 'u1');
          sent[req.url.path] = jsonDecode(req.body) as Map<String, dynamic>;
          return jsonResponse({});
        }),
      );
      await jf.report(book, at(2, 50), finished: false);
      expect(sent.keys, ['/UserItems/f2/UserData']);
      expect(
        sent['/UserItems/f2/UserData']!['PlaybackPositionTicks'],
        500000000,
      );
      expect(sent['/UserItems/f2/UserData']!['Played'], isFalse);

      sent.clear();
      await jf.report(book, at(3, 100), finished: true);
      expect(sent.keys, [
        '/UserItems/f1/UserData',
        '/UserItems/f2/UserData',
        '/UserItems/f3/UserData',
      ]);
      expect(sent.values.every((d) => d['Played'] == true), isTrue);
    });
  });
}
