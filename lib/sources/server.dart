import 'dart:convert';

import 'package:http/http.dart' as http;

import '../addons/backend.dart';
import '../addons/models.dart';
import 'audiobookshelf.dart';
import 'jellyfin.dart';

enum ServerKind {
  audiobookshelf('Audiobookshelf', 13378),
  jellyfin('Jellyfin', 8096);

  const ServerKind(this.label, this.defaultPort);
  final String label;

  /// Used when the address has no port and no scheme ("192.168.1.5").
  final int defaultPort;
}

/// A media server the user signed in to: its libraries become catalogs, its books play from
/// it. [toJson] holds the login (tokens): never log it.
abstract class ServerBackend implements AddonBackend {
  ServerKind get kind;
  Uri get base;

  /// The user name signed in with.
  String get user;

  /// Catalogs: a row per book library, and search.
  Manifest get manifest;

  /// Called when the login changes on its own (tokens are renewed), so it can be saved.
  void Function()? onLoginChanged;

  /// Reads the libraries again; the manifest follows.
  Future<void> refreshLibraries();

  Map<String, Object?> toJson();

  static ServerBackend fromJson(Map<String, dynamic> json) =>
      switch (json['kind']) {
        'audiobookshelf' => AudiobookshelfBackend.fromJson(json),
        'jellyfin' => JellyfinBackend.fromJson(json),
        _ => throw FormatException('Unknown server ${json['kind']}'),
      };

  static Future<ServerBackend> signIn(
    ServerKind kind,
    String address,
    String user,
    String password,
  ) async {
    final base = serverAddress(address, kind);
    final ServerBackend server = switch (kind) {
      ServerKind.audiobookshelf => await AudiobookshelfBackend.signIn(
        base,
        user,
        password,
      ),
      ServerKind.jellyfin => await JellyfinBackend.signIn(base, user, password),
    };
    await server.refreshLibraries();
    return server;
  }
}

/// The server's base address from what the user typed: `host`, `host:port` or a full URL,
/// possibly with a path (servers behind a reverse proxy).
Uri serverAddress(String input, ServerKind kind) {
  var text = input.trim();
  final schemeless = !text.contains('://');
  if (schemeless) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    throw AddonException('That is not a server address.');
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort
        ? uri.port
        : schemeless
        ? kind.defaultPort
        : null,
    path: uri.path.replaceAll(RegExp(r'/+$'), ''),
  );
}

/// A manifest id for a server and user, stable across restarts.
String serverId(ServerKind kind, Uri base, String userId) {
  final where = '${base.host}:${base.port}${base.path}'.replaceAll(
    RegExp(r'[^\w.:-]'),
    '_',
  );
  return '${kind.name}:$where:$userId';
}

/// JSON requests with the errors people can act on.
class ServerHttp {
  ServerHttp(this.base, this.name, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri base;

  /// What to call the server in messages.
  final String name;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Uri url(String path, [Map<String, String>? query]) => base.replace(
    path: '${base.path}$path',
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  /// Sends a request and returns the status code and decoded body (null when not JSON).
  Future<(int, Object?)> send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final request = http.Request(method, url(path, query))
      ..headers.addAll(headers);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on Object catch (e) {
      throw AddonException('Could not reach $name (${base.host}): $e');
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      json = null;
    }
    return (res.statusCode, json);
  }

  /// [send], failing on anything but success.
  Future<Object?> json(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final (status, json) = await send(
      method,
      path,
      query: query,
      headers: headers,
      body: body,
    );
    if (status == 401 || status == 403) {
      throw SignedOut(name);
    }
    if (status >= 400) {
      throw AddonException('$name answered HTTP $status.');
    }
    return json;
  }

  void close() => _client.close();
}

/// The server no longer accepts the login: the user has to sign in again.
class SignedOut extends AddonException {
  SignedOut(String name)
    : super('$name signed you out. Sign in again from Addons.');
}

/// Plain text from descriptions that may hold HTML.
String? plainText(Object? value) {
  if (value is! String) return null;
  final text = value
      .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return text.isEmpty ? null : text;
}

/// Seconds of a JWT's `exp` claim, or null.
DateTime? tokenExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final exp = payload['exp'];
    return exp is num
        ? DateTime.fromMillisecondsSinceEpoch((exp * 1000).toInt())
        : null;
  } on Object {
    return null;
  }
}
