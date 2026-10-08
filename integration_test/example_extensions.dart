// Test helpers: silent audio, and an extension repository with an example catalog and an
// example source, served from this machine so the tests need no network.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// A mono 16-bit WAV. Amplitude 0 by default: tests play silence, so it is never heard.
Uint8List toneWav({
  required double seconds,
  double hz = 440,
  double amplitude = 0,
  int rate = 8000,
}) {
  final samples = (seconds * rate).round();
  final data = ByteData(44 + samples * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final v = (sin(2 * pi * hz * i / rate) * amplitude).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A catalog: rows, genres, search and book pages; its books have no files of their own.
const _catalog = r'''
var titles = ['The Quiet Orchard', 'Salt and Iron', 'A Map of Small Hours', 'The Lantern Keeper',
  'North of the River', 'Glass Weather', 'The Long Table', 'Paper Comets', 'Winter Harbor',
  'The Clockmaker\'s Daughter', 'Field Notes', 'An Ordinary Sky'];
var books = titles.map(function (t, i) {
  return { id: 'c:' + i, title: t, authors: ['Author ' + (i + 1)], narrators: ['Narrator ' + (i + 1)],
    details: (6 + i) + ' h · ★ 4.' + (i % 10) };
});
extension = {
  manifest: {
    id: 'org.example.catalog', name: 'Example Catalog', version: '1.0.0',
    catalogs: [
      { id: 'search', name: 'Books', search: true },
      { id: 'popular', name: 'Popular' },
      { id: 'new', name: 'New releases' },
      { id: 'genres', name: 'Browse by genre', genres: ['Fantasy', 'Mystery'] },
    ],
    settings: [{ key: 'language', label: 'Language', type: 'select', default: 'en',
      options: [{ value: 'en', label: 'English' }] }],
  },
  async catalog(id, o) {
    var skip = o.skip || 0;
    if (id === 'search') {
      var q = (o.search || '').toLowerCase();
      return { books: books.filter(function (b) { return b.title.toLowerCase().indexOf(q) >= 0; }), hasMore: false };
    }
    if (id === 'genres') return { books: o.genre === 'Fantasy' ? books.slice(0, 6) : books.slice(6), hasMore: false };
    var list = id === 'popular' ? books : books.slice().reverse();
    return { books: list.slice(skip, skip + 8), hasMore: skip + 8 < list.length };
  },
  async book(id) {
    var b = books.filter(function (x) { return x.id === id; })[0];
    return Object.assign({}, b, { description: 'A book for testing.', durationMinutes: 552,
      rating: 4.6, genres: ['Fantasy'], chapters: [] });
  },
};
''';

/// A source: finds versions of catalog books and plays them from this machine.
String _source(String base) =>
    '''
extension = {
  manifest: {
    id: 'org.example.source', name: 'Example Source', version: '1.0.0', releases: true,
    catalogs: [{ id: 'search', name: 'Files', search: true }],
    settings: [{ key: 'server', label: 'Server', type: 'text', default: 'main' }],
  },
  async catalog() { return { books: [], hasMore: false }; },
  async releases(work) {
    return { books: [{ id: 's:' + work.title, title: work.title + ' (MP3)', tags: ['MP3'], details: '2 files' }] };
  },
  async book(id) {
    return { id: id, title: id.slice(2) + ' (MP3)',
      chapters: [{ id: 'a', title: 'Part 1' }, { id: 'b', title: 'Part 2' }] };
  },
  async sources(bookId, chapterId) {
    return { sources: [{ id: 'main', name: 'Main server', url: '$base/audio/' + chapterId + '.wav' }] };
  },
};
''';

/// Serves `/index.json`, both extensions and their audio. The repository URL is
/// `http://127.0.0.1:<port>/index.json`.
Future<HttpServer> serveExampleRepository() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://127.0.0.1:${server.port}';
  final audio = toneWav(seconds: 3);
  final index = jsonEncode({
    'name': 'Example extensions',
    'extensions': [
      {
        'id': 'org.example.catalog',
        'name': 'Example Catalog',
        'version': '1.0.0',
        'url': 'catalog.js',
      },
      {
        'id': 'org.example.source',
        'name': 'Example Source',
        'version': '1.0.0',
        'url': 'source.js',
      },
    ],
  });
  server.listen((req) async {
    final path = req.uri.path;
    if (path.startsWith('/audio/')) {
      req.response.headers.contentType = ContentType('audio', 'wav');
      req.response.add(audio);
    } else if (path == '/index.json') {
      req.response.write(index);
    } else if (path == '/catalog.js') {
      req.response.write(_catalog);
    } else if (path == '/source.js') {
      req.response.write(_source(base));
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  return server;
}
