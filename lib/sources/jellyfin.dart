import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../addons/backend.dart';
import '../addons/models.dart';
import 'server.dart';

typedef _Item = Map<String, dynamic>;

/// A Jellyfin server (jellyfin.org). Jellyfin lists every audio file of a "books" library as
/// its own item, so the files of a folder (and album) are put together into books here. Book
/// ids are `<folder id>` or `<folder id>|<album>`.
class JellyfinBackend extends ServerBackend {
  JellyfinBackend({
    required this.base,
    required this.user,
    required this.userId,
    required this.deviceId,
    required this._token,
    this.libraries = const [],
    http.Client? client,
  }) : _http = ServerHttp(base, 'Jellyfin', client: client);

  factory JellyfinBackend.fromJson(
    Map<String, dynamic> json, {
    http.Client? client,
  }) => JellyfinBackend(
    base: Uri.parse(json['base'] as String),
    user: json['user'] as String,
    userId: json['userId'] as String,
    deviceId: json['deviceId'] as String,
    token: json['token'] as String,
    libraries: [
      for (final l
          in (json['libraries'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
        (id: l['id'] as String, name: l['name'] as String),
    ],
    client: client,
  );

  static Future<JellyfinBackend> signIn(
    Uri base,
    String user,
    String password, {
    http.Client? client,
  }) async {
    final deviceId = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final server = ServerHttp(base, 'Jellyfin', client: client);
    final (status, json) = await server.send(
      'POST',
      '/Users/AuthenticateByName',
      headers: {'authorization': _authorization(deviceId, null)},
      body: {'Username': user, 'Pw': password},
    );
    if (status == 401) throw AddonException('Wrong user name or password.');
    if (status >= 400 ||
        json is! Map<String, dynamic> ||
        json['AccessToken'] is! String) {
      throw AddonException(
        'That doesn’t look like a Jellyfin server (HTTP $status).',
      );
    }
    return JellyfinBackend(
      base: base,
      user: user,
      userId: (json['User'] as Map<String, dynamic>)['Id'] as String,
      deviceId: deviceId,
      token: json['AccessToken'] as String,
      client: client,
    );
  }

  static String _authorization(String deviceId, String? token) =>
      'MediaBrowser Client="Shu", Device="${Platform.operatingSystem}", '
      'DeviceId="$deviceId", Version="1"${token == null ? '' : ', Token="$token"'}';

  @override
  ServerKind get kind => ServerKind.jellyfin;
  @override
  final Uri base;
  @override
  final String user;
  final String userId;
  final String deviceId;
  List<({String id, String name})> libraries;
  final String _token;
  final ServerHttp _http;

  static const _page = 30;

  /// Files asked for at once to fill a page of books.
  static const _batch = 200;

  /// For each catalog, where (in files) the page that starts at a number of books begins.
  final _offsets = <String, Map<int, int>>{};

  /// For each catalog, the books listed so far.
  final _shown = <String, Set<String>>{};

  @override
  Manifest get manifest => Manifest(
    id: serverId(kind, base, userId),
    name: 'Jellyfin',
    version: '1',
    description: '$user on ${base.host}',
    catalogs: [
      for (final l in libraries)
        CatalogInfo(id: 'lib:${l.id}', name: l.name, search: false),
      const CatalogInfo(id: 'search', name: 'Jellyfin', search: true),
    ],
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'base': base.toString(),
    'user': user,
    'userId': userId,
    'deviceId': deviceId,
    'token': _token,
    'libraries': [
      for (final l in libraries) {'id': l.id, 'name': l.name},
    ],
  };

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final json = await _http.json(
      'GET',
      path,
      query: {'userId': userId, ...query},
      headers: {'authorization': _authorization(deviceId, _token)},
    );
    if (json is! Map<String, dynamic>) {
      throw AddonException('Jellyfin sent an unreadable reply.');
    }
    return json;
  }

  Future<List<_Item>> _items(Map<String, String> query) async =>
      ((await _get('/Items', query))['Items'] as List).cast<_Item>();

  @override
  Future<void> refreshLibraries() async {
    final json = await _get('/UserViews');
    libraries = [
      for (final v in (json['Items'] as List).cast<_Item>())
        if (v['CollectionType'] == 'books')
          (id: v['Id'] as String, name: v['Name'] as String),
    ];
  }

  static String _album(_Item item) => (item['Album'] as String?)?.trim() ?? '';

  static String _bookKey(_Item item) {
    final album = _album(item);
    return album.isEmpty
        ? item['ParentId'] as String
        : '${item['ParentId']}|$album';
  }

  /// Files grouped into books, in the order they first appear.
  static Map<String, List<_Item>> _group(Iterable<_Item> items) {
    final books = <String, List<_Item>>{};
    for (final item in items) {
      books.putIfAbsent(_bookKey(item), () => []).add(item);
    }
    return books;
  }

  @override
  Future<CatalogPage> catalog(
    String catalogId, {
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    if (catalogId == 'search') {
      return (books: await _search(search ?? ''), hasMore: false);
    }
    final offsets = skip == 0
        ? (_offsets[catalogId] = {})
        : _offsets[catalogId] ?? {};
    final start = skip == 0 ? 0 : offsets[skip];
    if (start == null) return (books: <BookSummary>[], hasMore: false);

    final json = await _get('/Items', {
      'ParentId': catalogId.substring('lib:'.length),
      'Recursive': 'true',
      'IncludeItemTypes': 'AudioBook',
      'SortBy': 'DateCreated,SortName',
      'SortOrder': 'Descending',
      'StartIndex': '$start',
      'Limit': '$_batch',
      'Fields': 'ParentId',
    });
    final items = (json['Items'] as List).cast<_Item>();
    final total = (json['TotalRecordCount'] as num?)?.toInt() ?? 0;
    final more = start + items.length < total;

    // Books in order, with the position of their first file.
    final firstIndex = <String, int>{};
    for (final (i, item) in items.indexed) {
      firstIndex.putIfAbsent(_bookKey(item), () => start + i);
    }
    final keys = firstIndex.keys.toList();
    // The last book may go on in the next batch: it starts the next page instead.
    if (more && keys.length > 1) keys.removeLast();
    final page = keys.take(_page).toList();
    final next = page.length < firstIndex.length
        ? firstIndex[firstIndex.keys.elementAt(page.length)]!
        : more
        ? start + items.length
        : total;
    offsets[skip + page.length] = next;

    // A book with more files than a batch would show up again on the next page.
    final shown = skip == 0
        ? (_shown[catalogId] = {})
        : _shown[catalogId] ?? {};
    final groups = _group(items);
    return (
      books: await _summaries([
        for (final k in page)
          if (shown.add(k)) groups[k]!,
      ]),
      hasMore: next < total,
    );
  }

  Future<List<BookSummary>> _search(String text) async {
    final query = text.trim();
    if (query.isEmpty) return const [];
    final hits = await _items({
      'Recursive': 'true',
      'searchTerm': query,
      'IncludeItemTypes': 'AudioBook,Folder',
      'Limit': '60',
      'Fields': 'ParentId',
    });
    final files = hits.where((h) => h['Type'] == 'AudioBook').toList();
    // A folder matching by name is a book when audio files are right inside it.
    for (final folder in hits.where((h) => h['Type'] == 'Folder').take(8)) {
      files.addAll(
        await _items({
          'ParentId': folder['Id'] as String,
          'IncludeItemTypes': 'AudioBook',
          'Limit': '$_batch',
          'Fields': 'ParentId',
        }),
      );
    }
    return _summaries(_group(files).values.toList());
  }

  /// Folders of the given items, for their names and pictures.
  Future<Map<String, _Item>> _parents(Iterable<_Item> items) async {
    final ids = {for (final i in items) i['ParentId'] as String};
    if (ids.isEmpty) return const {};
    return {
      for (final p in await _items({
        'Ids': ids.join(','),
        'Fields': 'Overview',
      }))
        p['Id'] as String: p,
    };
  }

  Future<List<BookSummary>> _summaries(List<List<_Item>> books) async {
    final parents = await _parents([for (final b in books) b.first]);
    return [
      for (final files in books)
        _summary(files, parents[files.first['ParentId']]),
    ];
  }

  String? _image(_Item? item) {
    final tag = (item?['ImageTags'] as Map?)?['Primary'];
    if (tag is! String) return null;
    return _http.url('/Items/${item!['Id']}/Images/Primary', {
      'maxHeight': '480',
      'tag': tag,
    }).toString();
  }

  BookSummary _summary(List<_Item> files, _Item? parent) {
    final first = files.first;
    final album = _album(first);
    final artist =
        first['AlbumArtist'] as String? ??
        (first['Artists'] as List?)?.whereType<String>().firstOrNull;
    return BookSummary(
      id: _bookKey(first),
      title: album.isNotEmpty
          ? album
          : files.length == 1 || parent == null
          ? first['Name'] as String? ?? 'Untitled'
          : parent['Name'] as String? ?? 'Untitled',
      authors: [?artist],
      cover: _image(first) ?? _image(parent),
    );
  }

  @override
  Future<Book> book(String bookId) async {
    final bar = bookId.indexOf('|');
    final parentId = bar < 0 ? bookId : bookId.substring(0, bar);
    final album = bar < 0 ? '' : bookId.substring(bar + 1);
    final files = (await _items({
      'ParentId': parentId,
      'IncludeItemTypes': 'AudioBook',
      'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
      'Limit': '1000',
      'Fields': 'ParentId,Chapters,Overview,Genres,People,MediaSources',
    })).where((f) => _album(f) == album).toList();
    if (files.isEmpty) {
      throw AddonException('This book is no longer on the Jellyfin server.');
    }
    final parent = (await _parents(files.take(1)))[parentId];
    final summary = _summary(files, parent);
    final first = files.first;
    List<String> people(String type) => [
      for (final p in (first['People'] as List? ?? const []).cast<_Item>())
        if (p['Type'] == type && p['Name'] is String) p['Name'] as String,
    ];
    final ticks = files.fold<num>(
      0,
      (t, f) => t + ((f['RunTimeTicks'] as num?) ?? 0),
    );
    final authors = people('Author');
    return Book(
      id: summary.id,
      title: summary.title,
      authors: authors.isNotEmpty ? authors : summary.authors,
      narrators: people('Narrator'),
      cover: summary.cover,
      description: plainText(first['Overview'] ?? parent?['Overview']),
      year: first['ProductionYear']?.toString(),
      durationMinutes: ticks == 0 ? null : (ticks / 600000000).round(),
      genres: (first['Genres'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      chapters: [for (final f in files) ..._chapters(f)],
    );
  }

  static List<Chapter> _chapters(_Item file) {
    final id = file['Id'] as String;
    final title = file['Name'] as String? ?? 'Part';
    final ticks = (file['RunTimeTicks'] as num?)?.toInt();
    final size =
        ((file['MediaSources'] as List?)?.firstOrNull as Map?)?['Size'];
    final marks = (file['Chapters'] as List? ?? const []).cast<_Item>();
    if (marks.length < 2) {
      return [
        Chapter(
          id: id,
          title: title,
          size: size is num ? size.toInt() : null,
          duration: ticks == null ? null : ticks ~/ 10000000,
        ),
      ];
    }
    return [
      for (final (j, m) in marks.indexed)
        Chapter(
          id: '$id@$j',
          title: m['Name'] as String? ?? 'Chapter ${j + 1}',
          duration: () {
            final end = j + 1 < marks.length
                ? (marks[j + 1]['StartPositionTicks'] as num).toInt()
                : ticks;
            return end == null
                ? null
                : (end - (m['StartPositionTicks'] as num).toInt()) ~/ 10000000;
          }(),
          file: id,
          start: Duration(
            microseconds: (m['StartPositionTicks'] as num).toInt() ~/ 10,
          ),
        ),
    ];
  }

  @override
  Future<SourceList> sources(String bookId, String chapterId) async =>
      SourceList([
        Source(
          id: 'stream',
          name: 'Jellyfin',
          description: base.host,
          resolve: chapterId.split('@').first,
        ),
      ], null);

  @override
  Future<Resolved> resolve(Source source) async => Playable(
    _http.url('/Audio/${source.resolve}/stream', {
      'static': 'true',
      'api_key': _token,
    }).toString(),
  );

  @override
  Future<List<BookSummary>> releases(Book work) async => const [];

  @override
  void dispose() => _http.close();
}
