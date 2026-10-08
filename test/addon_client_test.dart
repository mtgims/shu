import 'dart:convert';

import 'package:audiobooks/addons/client.dart';
import 'package:audiobooks/addons/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const base = 'http://addon.test/eyJjb25maWciOjF9';

final manifestJson = {
  'protocol': 1,
  'id': 'test.addon',
  'name': 'Test',
  'version': '1.0.0',
  'catalogs': [
    {'id': 'search', 'name': 'Search', 'search': true},
    {'id': 'latest', 'name': 'Latest'},
  ],
};

final bookJson = {
  'id': 'lib:abc',
  'title': 'Project Hail Mary',
  'authors': ['Andy Weir'],
  'tags': ['M4B'],
  'chapters': [
    {'id': '2', 'title': 'Part 1', 'size': 100},
    {'id': '0', 'title': 'Part 2'},
  ],
};

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('normalizeAddonUrl', () {
    test('accepts manifest URLs, base URLs and missing schemes', () {
      for (final input in [
        '$base/manifest.json',
        '$base/',
        ' $base ',
        'addon.test/eyJjb25maWciOjF9',
      ]) {
        final r = normalizeAddonUrl(input);
        expect(r.base, base, reason: input);
        expect(r.manifest.toString(), '$base/manifest.json', reason: input);
      }
    });

    test('drops query and fragment, keeps the port', () {
      final r = normalizeAddonUrl(
        'http://192.168.1.5:7000/manifest.json?x=1#y',
      );
      expect(r.manifest.toString(), 'http://192.168.1.5:7000/manifest.json');
      expect(r.base, 'http://192.168.1.5:7000');
    });

    test('rejects things that are not web addresses', () {
      expect(
        () => normalizeAddonUrl('ftp://x/manifest.json'),
        throwsA(isA<AddonException>()),
      );
      expect(
        () => normalizeAddonUrl('http://'),
        throwsA(isA<AddonException>()),
      );
    });
  });

  test('manifest parsing requires protocol 1 and an id', () {
    final m = Manifest.fromJson(manifestJson);
    expect(m.catalogs.map((c) => c.search), [true, false]);
    expect(Manifest.fromJson(m.toJson()).toJson(), m.toJson());
    expect(() => Manifest.fromJson({'id': 'x'}), throwsFormatException);
    expect(() => Manifest.fromJson({'protocol': 1}), throwsFormatException);
  });

  group('AddonClient', () {
    final requests = <Uri>[];
    late AddonClient client;

    setUp(() {
      requests.clear();
      client = AddonClient(
        base,
        httpClient: MockClient((req) async {
          requests.add(req.url);
          final path = Uri.decodeComponent(req.url.path)
              .replaceFirst('/eyJjb25maWciOjF9', '');
          return switch (path) {
            '/catalog/search.json' => jsonResponse({
              'books': [bookJson],
              'hasMore': false,
            }),
            '/book/lib:abc.json' => jsonResponse({'book': bookJson}),
            '/sources/lib:abc/2.json' => jsonResponse({
              'sources': [
                {
                  'id': 'main',
                  'name': 'Main server',
                  'resolve': 'http://addon.test/r/ready',
                },
                {
                  'id': 'mirror',
                  'name': 'Mirror',
                  'cached': true,
                  'resolve': 'http://addon.test/r/wait',
                },
                {'id': 'broken', 'name': 'No link'},
              ],
            }),
            '/sources/lib:abc/0.json' => jsonResponse({
              'sources': [],
              'message': 'Sign in to play',
            }),
            _ when req.url.path == '/r/ready' => jsonResponse({
              'url': 'https://cdn.test/a.mp3',
            }),
            _ when req.url.path == '/r/wait' => jsonResponse({
              'status': 'downloading',
              'message': 'Preparing: 42%',
              'progress': 0.42,
            }, 202),
            _ => jsonResponse({'error': 'unknown book'}, 404),
          };
        }),
      );
    });

    test('searches a catalog with an encoded query', () async {
      final r = await client.catalog('search', search: 'hail mary');
      expect(r.books.single.title, 'Project Hail Mary');
      expect(r.books.single.byline, 'Andy Weir');
      expect(r.hasMore, isFalse);
      expect(requests.single.queryParameters, {'search': 'hail mary'});
    });

    test('loads a book with ids encoded in the path', () async {
      final book = await client.book('lib:abc');
      expect(book.chapters.map((c) => c.id), ['2', '0']);
      expect(requests.single.toString(), '$base/book/lib%3Aabc.json');
    });

    test('lists sources, skipping ones without a link', () async {
      final list = await client.sources('lib:abc', '2');
      expect(list.sources.map((s) => s.id), ['main', 'mirror']);
      expect(list.sources[1].cached, isTrue);

      final none = await client.sources('lib:abc', '0');
      expect(none.sources, isEmpty);
      expect(none.message, 'Sign in to play');
    });

    test('resolves to a URL or a downloading state', () async {
      final list = await client.sources('lib:abc', '2');
      final ready = await client.resolve(list.sources[0]);
      expect(
        ready,
        isA<Playable>().having((p) => p.url, 'url', 'https://cdn.test/a.mp3'),
      );
      final waiting = await client.resolve(list.sources[1]);
      expect(
        waiting,
        isA<Downloading>().having((d) => d.progress, 'progress', 0.42),
      );
      final direct = await client.resolve(
        const Source(id: 'x', name: 'x', url: 'https://d'),
      );
      expect(direct, isA<Playable>());
    });

    test('reports addon errors with their message', () async {
      expect(
        () => client.book('nope'),
        throwsA(
          isA<AddonException>().having(
            (e) => e.message,
            'message',
            'unknown book',
          ),
        ),
      );
    });
  });
}
