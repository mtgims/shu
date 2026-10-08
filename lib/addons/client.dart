import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend.dart';
import 'models.dart';

export 'backend.dart' show AddonException;

/// Turns what the user pasted into the manifest URL and base URL of an addon.
({Uri manifest, String base}) normalizeAddonUrl(String input) {
  var text = input.trim();
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    throw AddonException('That is not a web address.');
  }
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (!path.endsWith('/manifest.json')) path = '$path/manifest.json';
  // Built fresh: Uri.replace(query: null) would keep the old query.
  final manifest = Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
  final base = manifest.toString().substring(
    0,
    manifest.toString().length - '/manifest.json'.length,
  );
  return (manifest: manifest, base: base);
}

/// A remote addon: talks the HTTP protocol of docs/PROTOCOL.md.
class AddonClient implements AddonBackend {
  AddonClient(this.base, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String base;
  final http.Client _http;

  static const _timeout = Duration(seconds: 30);

  Future<(int, Map<String, dynamic>)> _get(Uri uri) async {
    final http.Response res;
    try {
      res = await _http.get(uri).timeout(_timeout);
    } on Exception catch (e) {
      throw AddonException('Could not reach the addon (${uri.host}): $e');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      throw AddonException(
        'The addon sent an unreadable reply (HTTP ${res.statusCode}).',
      );
    }
    if (res.statusCode >= 400) {
      throw AddonException(
        body['error']?.toString() ??
            'The addon failed (HTTP ${res.statusCode}).',
      );
    }
    return (res.statusCode, body);
  }

  Uri _path(List<String> segments, [Map<String, String>? query]) {
    final encoded = segments.map(Uri.encodeComponent).join('/');
    final uri = Uri.parse('$base/$encoded');
    return query == null || query.isEmpty
        ? uri
        : uri.replace(queryParameters: query);
  }

  static Future<Manifest> fetchManifest(
    Uri manifestUrl, {
    http.Client? httpClient,
  }) async {
    final client = AddonClient('', httpClient: httpClient);
    final (_, body) = await client._get(manifestUrl);
    try {
      return Manifest.fromJson(body);
    } on FormatException catch (e) {
      throw AddonException(e.message);
    }
  }

  @override
  Future<CatalogPage> catalog(
    String catalogId, {
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    final query = <String, String>{
      'search': ?search,
      'genre': ?genre,
      if (skip > 0) 'skip': '$skip',
    };
    final (_, body) = await _get(_path(['catalog', '$catalogId.json'], query));
    return catalogPageFromJson(body);
  }

  @override
  Future<Book> book(String bookId) async {
    final (_, body) = await _get(_path(['book', '$bookId.json']));
    try {
      return Book.fromJson(body['book'] as Map<String, dynamic>);
    } on Object catch (e) {
      throw AddonException('The addon sent a broken book: $e');
    }
  }

  @override
  Future<SourceList> sources(String bookId, String chapterId) async {
    final (_, body) = await _get(_path(['sources', bookId, '$chapterId.json']));
    return SourceList.fromJson(body);
  }

  @override
  Future<Resolved> resolve(Source source) async {
    if (source.url != null) return Playable(source.url!);
    final link = source.resolve;
    if (link is! String) {
      throw AddonException('The addon gave no way to play this.');
    }
    final (_, body) = await _get(Uri.parse(link));
    return resolvedFromJson(body) ??
        (throw AddonException('The addon gave no playable link.'));
  }

  /// The HTTP protocol has no versions lookup (yet).
  @override
  Future<List<BookSummary>> releases(Book work) async => const [];

  @override
  void dispose() => _http.close();
}
