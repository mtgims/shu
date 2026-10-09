import 'package:http/http.dart' as http;

import '../addons/backend.dart';
import '../addons/models.dart';
import 'server.dart';

/// An Audiobookshelf server (audiobookshelf.org). Signs in with a user name and password and
/// keeps the session alive with its refresh token; covers are public, audio links carry the
/// access token, which lasts an hour.
class AudiobookshelfBackend extends ServerBackend {
  AudiobookshelfBackend({
    required this.base,
    required this.user,
    required this.userId,
    required String accessToken,
    String? refreshToken,
    this.libraries = const [],
    http.Client? client,
  }) : _access = accessToken,
       _refresh = refreshToken,
       _http = ServerHttp(base, 'Audiobookshelf', client: client);

  factory AudiobookshelfBackend.fromJson(
    Map<String, dynamic> json, {
    http.Client? client,
  }) => AudiobookshelfBackend(
    base: Uri.parse(json['base'] as String),
    user: json['user'] as String,
    userId: json['userId'] as String,
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
    libraries: [
      for (final l
          in (json['libraries'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
        (id: l['id'] as String, name: l['name'] as String),
    ],
    client: client,
  );

  static Future<AudiobookshelfBackend> signIn(
    Uri base,
    String user,
    String password, {
    http.Client? client,
  }) async {
    final server = ServerHttp(base, 'Audiobookshelf', client: client);
    final (status, json) = await server.send(
      'POST',
      '/login',
      headers: {'x-return-tokens': 'true'},
      body: {'username': user, 'password': password},
    );
    if (status == 401) throw AddonException('Wrong user name or password.');
    final u = json is Map<String, dynamic> ? json['user'] : null;
    if (status >= 400 || u is! Map<String, dynamic>) {
      throw AddonException(
        'That doesn’t look like an Audiobookshelf server (HTTP $status).',
      );
    }
    return AudiobookshelfBackend(
      base: base,
      user: user,
      userId: u['id'] as String,
      // Servers before 2.26 only have the old token that never expires.
      accessToken: (u['accessToken'] ?? u['token']) as String,
      refreshToken: u['refreshToken'] as String?,
      client: client,
    );
  }

  @override
  ServerKind get kind => ServerKind.audiobookshelf;
  @override
  final Uri base;
  @override
  final String user;
  final String userId;
  List<({String id, String name})> libraries;

  String _access;
  String? _refresh;
  Future<void>? _refreshing;
  final ServerHttp _http;

  static const _page = 30;

  @override
  Manifest get manifest => Manifest(
    id: serverId(kind, base, userId),
    name: 'Audiobookshelf',
    version: '1',
    description: '$user on ${base.host}',
    catalogs: [
      for (final l in libraries)
        CatalogInfo(id: 'lib:${l.id}', name: l.name, search: false),
      const CatalogInfo(id: 'search', name: 'Audiobookshelf', search: true),
    ],
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'base': base.toString(),
    'user': user,
    'userId': userId,
    'accessToken': _access,
    'refreshToken': _refresh,
    'libraries': [
      for (final l in libraries) {'id': l.id, 'name': l.name},
    ],
  };

  /// A new access token from the refresh token. One at a time: tokens rotate.
  Future<void> _renew() => _refreshing ??= () async {
    try {
      final refresh = _refresh;
      if (refresh == null) throw SignedOut(_http.name);
      final (status, json) = await _http.send(
        'POST',
        '/auth/refresh',
        headers: {'x-refresh-token': refresh},
      );
      final u = json is Map<String, dynamic> ? json['user'] : null;
      if (status >= 400 || u is! Map<String, dynamic>) {
        throw SignedOut(_http.name);
      }
      _access = u['accessToken'] as String;
      _refresh = u['refreshToken'] as String? ?? _refresh;
      onLoginChanged?.call();
    } finally {
      _refreshing = null;
    }
  }();

  bool get _expiring {
    final expiry = tokenExpiry(_access);
    return expiry != null &&
        expiry.difference(DateTime.now()) < const Duration(minutes: 2);
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    if (_expiring) await _renew();
    Future<Object?> get() => _http.json(
      'GET',
      path,
      query: query,
      headers: {'authorization': 'Bearer $_access'},
    );
    Object? json;
    try {
      json = await get();
    } on SignedOut {
      await _renew();
      json = await get();
    }
    if (json is! Map<String, dynamic>) {
      throw AddonException('Audiobookshelf sent an unreadable reply.');
    }
    return json;
  }

  @override
  Future<void> refreshLibraries() async {
    final json = await _get('/api/libraries');
    libraries = [
      for (final l in (json['libraries'] as List).cast<Map<String, dynamic>>())
        if (l['mediaType'] == 'book')
          (id: l['id'] as String, name: l['name'] as String),
    ];
  }

  @override
  Future<CatalogPage> catalog(
    String catalogId, {
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    if (catalogId == 'search') {
      final query = search?.trim() ?? '';
      if (query.isEmpty) return (books: <BookSummary>[], hasMore: false);
      final books = <BookSummary>[];
      for (final l in libraries) {
        final json = await _get('/api/libraries/${l.id}/search', {
          'q': query,
          'limit': '25',
        });
        for (final hit
            in (json['book'] as List? ?? const [])
                .cast<Map<String, dynamic>>()) {
          books.add(_summary(hit['libraryItem'] as Map<String, dynamic>));
        }
      }
      return (books: books, hasMore: false);
    }
    final library = catalogId.substring('lib:'.length);
    final json = await _get('/api/libraries/$library/items', {
      'limit': '$_page',
      'page': '${skip ~/ _page}',
      'sort': 'addedAt',
      'desc': '1',
      'minified': '1',
    });
    final total = (json['total'] as num?)?.toInt() ?? 0;
    return (
      books: [
        for (final item
            in (json['results'] as List).cast<Map<String, dynamic>>())
          _summary(item),
      ],
      hasMore: skip + _page < total,
    );
  }

  String _cover(String itemId) =>
      _http.url('/api/items/$itemId/cover', {'width': '400'}).toString();

  BookSummary _summary(Map<String, dynamic> item) {
    final media = item['media'] as Map<String, dynamic>;
    final meta = media['metadata'] as Map<String, dynamic>;
    List<String> names(Object? value) => value is String && value.isNotEmpty
        ? value.split(', ')
        : value is List
        ? [
            for (final v in value)
              if (v is Map && v['name'] is String)
                v['name'] as String
              else if (v is String)
                v,
          ]
        : const [];
    final id = item['id'] as String;
    return BookSummary(
      id: id,
      title: meta['title'] as String? ?? 'Untitled',
      authors: names(meta['authors'] ?? meta['authorName']),
      narrators: names(meta['narrators'] ?? meta['narratorName']),
      cover: media['coverPath'] != null ? _cover(id) : null,
    );
  }

  @override
  Future<Book> book(String bookId) async {
    final item = await _get('/api/items/$bookId', {'expanded': '1'});
    final media = item['media'] as Map<String, dynamic>;
    final meta = media['metadata'] as Map<String, dynamic>;
    final summary = _summary(item);
    final series = (meta['series'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (s) => s['sequence'] == null
              ? s['name']
              : '${s['name']} #${s['sequence']}',
        );
    final duration = media['duration'];
    return Book(
      id: summary.id,
      title: summary.title,
      authors: summary.authors,
      narrators: summary.narrators,
      cover: summary.cover,
      description: plainText(meta['description']),
      year: meta['publishedYear']?.toString(),
      durationMinutes: duration is num ? (duration / 60).round() : null,
      genres: (meta['genres'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      series: series.isEmpty ? null : series.join(', '),
      chapters: absChapters(
        [
          for (final t
              in (media['tracks'] as List? ?? const [])
                  .cast<Map<String, dynamic>>())
            (
              ino: (t['contentUrl'] as String).split('/').last,
              title: t['title'] as String? ?? 'Part ${t['index']}',
              start: (t['startOffset'] as num).toDouble(),
              duration: (t['duration'] as num).toDouble(),
            ),
        ],
        [
          for (final c
              in (media['chapters'] as List? ?? const [])
                  .cast<Map<String, dynamic>>())
            (
              start: (c['start'] as num).toDouble(),
              title: c['title'] as String? ?? '',
            ),
        ],
      ),
    );
  }

  @override
  Future<SourceList> sources(String bookId, String chapterId) async =>
      SourceList([
        Source(
          id: 'stream',
          name: 'Audiobookshelf',
          description: base.host,
          resolve: {'item': bookId, 'file': chapterId.split('@').first},
        ),
      ], null);

  @override
  Future<Resolved> resolve(Source source) async {
    if (_expiring) await _renew();
    final at = source.resolve as Map<String, dynamic>;
    final left = tokenExpiry(_access)?.difference(DateTime.now());
    return Playable(
      _http.url('/api/items/${at['item']}/file/${at['file']}', {
        'token': _access,
      }).toString(),
      validFor: left == null ? null : left - const Duration(minutes: 1),
    );
  }

  @override
  Future<List<BookSummary>> releases(Book work) async => const [];

  @override
  void dispose() => _http.close();
}

/// Chapters to play from Audiobookshelf's tracks (audio files) and chapters (marks on the
/// whole book's timeline, in seconds). A file with several chapters becomes chapters inside
/// that file; a file without its own chapter keeps the title of the one it continues.
List<Chapter> absChapters(
  List<({String ino, String title, double start, double duration})> tracks,
  List<({double start, String title})> chapters,
) {
  final result = <Chapter>[];
  for (final t in tracks) {
    final end = t.start + t.duration;
    final inside = [
      for (final c in chapters)
        if (c.start >= t.start - 0.5 && c.start < end - 0.5) c,
    ];
    final before = chapters.where((c) => c.start < t.start - 0.5).lastOrNull;
    if (inside.isEmpty || inside.first.start > t.start + 1) {
      inside.insert(0, (start: t.start, title: before?.title ?? t.title));
    }
    if (inside.length == 1) {
      result.add(
        Chapter(
          id: t.ino,
          title: inside.single.title.isEmpty ? t.title : inside.single.title,
          duration: t.duration.round(),
        ),
      );
      continue;
    }
    for (final (j, c) in inside.indexed) {
      final next = j + 1 < inside.length ? inside[j + 1].start : end;
      result.add(
        Chapter(
          id: '${t.ino}@$j',
          title: c.title.isEmpty ? 'Chapter ${result.length + 1}' : c.title,
          duration: (next - c.start).round(),
          file: t.ino,
          start: Duration(milliseconds: ((c.start - t.start) * 1000).round()),
        ),
      );
    }
  }
  return result;
}
