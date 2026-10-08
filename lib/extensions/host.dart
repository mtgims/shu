import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// The work behind an extension's `host.*` calls, shared by all extensions. Parsing HTML here,
/// in compiled Dart, is much faster than in the JS interpreter.
class ExtensionHost {
  ExtensionHost({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// One client for every extension, so connections to the same sites are reused.
  final http.Client _http;

  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/130.0 Safari/537.36';

  /// Responses larger than this are cut off; no audiobook page or API reply comes close.
  static const _maxBody = 8 << 20;

  final _cache = <String, ({Object? value, DateTime expires})>{};
  static const _maxCacheEntries = 1000;

  /// The last parsed pages: extensions usually query the same page several times in a row.
  final _documents = <({String html, dom.Document doc})>[];

  Future<Object?> run(String op, List<Object?> args) async {
    switch (op) {
      case 'fetch':
        return fetch(
          args[0] as String,
          (args.elementAtOrNull(1) as Map?) ?? const {},
        );
      case 'select':
        return select(
          args[0] as String,
          args[1] as String,
          args.elementAtOrNull(2) as Map?,
        );
      case 'cacheGet':
        return cacheGet(args[0] as String);
      case 'cacheSet':
        cacheSet(
          args[0] as String,
          args[1],
          (args.elementAtOrNull(2) as num?)?.toInt() ?? 600,
        );
        return null;
      case 'sleep':
        await Future<void>.delayed(
          Duration(
            milliseconds: ((args[0] as num?) ?? 0).toInt().clamp(0, 60000),
          ),
        );
        return null;
      default:
        throw ArgumentError('unknown host call "$op"');
    }
  }

  Future<Map<String, Object?>> fetch(
    String url,
    Map<Object?, Object?> options,
  ) async {
    var uri = Uri.parse(url);
    final query = options['query'];
    if (query is Map && query.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          for (final e in query.entries)
            if (e.value != null) '${e.key}': '${e.value}',
        },
      );
    }
    final headers = <String, String>{'user-agent': _userAgent};
    final given = options['headers'];
    if (given is Map) {
      for (final e in given.entries) {
        headers['${e.key}'.toLowerCase()] = '${e.value}';
      }
    }
    final hasBody = [
      'json',
      'form',
      'multipart',
      'body',
    ].any(options.containsKey);
    final method =
        ((options['method'] as String?) ?? (hasBody ? 'POST' : 'GET'))
            .toUpperCase();

    final http.BaseRequest request;
    final multipart = options['multipart'];
    if (multipart is Map) {
      request = http.MultipartRequest(method, uri)
        ..fields.addAll({
          for (final e in multipart.entries) '${e.key}': '${e.value}',
        });
    } else {
      final r = http.Request(method, uri);
      if (options.containsKey('json')) {
        r.body = jsonEncode(options['json']);
        headers.putIfAbsent('content-type', () => 'application/json');
      } else if (options['form'] is Map) {
        r.body = encodeForm(options['form'] as Map);
        headers.putIfAbsent(
          'content-type',
          () => 'application/x-www-form-urlencoded',
        );
      } else if (options['body'] is String) {
        r.body = options['body'] as String;
      }
      request = r;
    }
    request.headers.addAll(headers);

    final timeout = Duration(
      milliseconds: ((options['timeout'] as num?) ?? 15000).toInt(),
    );
    final response = await _http.send(request).timeout(timeout);
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) break;
    }
    return {
      'status': response.statusCode,
      'headers': response.headers,
      'text': utf8.decode(bytes, allowMalformed: true),
    };
  }

  /// URL-encoded form; list values repeat the key (`tags[]=a&tags[]=b`).
  static String encodeForm(Map<Object?, Object?> form) => [
    for (final e in form.entries)
      for (final v in e.value is List ? e.value as List : [e.value])
        if (v != null)
          '${Uri.encodeQueryComponent('${e.key}')}=${Uri.encodeQueryComponent('$v')}',
  ].join('&');

  /// Without [fields]: each match as `{text, html, attrs}`. With fields (`{name: 'sub selector'}`,
  /// `'sel@attr'` for an attribute, `['sel']` for all matches), each match as an object of just
  /// those strings: one parse, one round trip, no HTML sent back to JS.
  List<Map<String, Object?>> select(
    String html,
    String selector, [
    Map<Object?, Object?>? fields,
  ]) {
    final doc = _parse(html);
    final matches = doc.querySelectorAll(selector);
    if (fields == null) {
      return [
        for (final e in matches)
          {
            'text': e.text,
            'html': e.outerHtml,
            'attrs': {
              for (final a in e.attributes.entries) '${a.key}': a.value,
            },
          },
      ];
    }
    return [
      for (final e in matches)
        {
          for (final f in fields.entries)
            '${f.key}': f.value is List
                ? [
                    for (final hit in _query(
                      e,
                      '${(f.value as List).first}',
                      all: true,
                    ))
                      _read(hit, '${(f.value as List).first}'),
                  ]
                : _query(
                    e,
                    '${f.value}',
                  ).map((hit) => _read(hit, '${f.value}')).firstOrNull,
        },
    ];
  }

  static Iterable<dom.Element> _query(
    dom.Element root,
    String field, {
    bool all = false,
  }) {
    final at = field.lastIndexOf('@');
    final sel = (at >= 0 ? field.substring(0, at) : field).trim();
    if (sel.isEmpty) return [root];
    return all ? root.querySelectorAll(sel) : [?root.querySelector(sel)];
  }

  static String? _read(dom.Element e, String field) {
    final at = field.lastIndexOf('@');
    return at >= 0 ? e.attributes[field.substring(at + 1)] : e.text;
  }

  dom.Document _parse(String html) {
    for (final d in _documents) {
      if (identical(d.html, html) || d.html == html) return d.doc;
    }
    final doc = html_parser.parse(html);
    _documents.insert(0, (html: html, doc: doc));
    if (_documents.length > 2) _documents.removeLast();
    return doc;
  }

  Object? cacheGet(String key) {
    final hit = _cache[key];
    if (hit == null) return null;
    if (hit.expires.isBefore(DateTime.now())) {
      _cache.remove(key);
      return null;
    }
    return hit.value;
  }

  void cacheSet(String key, Object? value, int seconds) {
    _cache.remove(key);
    _cache[key] = (
      value: value,
      expires: DateTime.now().add(Duration(seconds: seconds)),
    );
    if (_cache.length > _maxCacheEntries) _cache.remove(_cache.keys.first);
  }

  /// Drops parsed pages; called when no extension is running.
  void trim() => _documents.clear();
}
