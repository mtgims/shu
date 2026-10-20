import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../addons/backend.dart';
import '../library/library_store.dart';

/// What the user chose in a torrent extension's settings; the latest call's choices apply.
class TorrentOptions {
  const TorrentOptions({
    this.folder,
    this.deleteWhenFinished = true,
    this.keepDays,
    this.storageLimit = 5 << 30,
    this.downloadLimit = 0,
    this.uploadLimit = 0,
    this.shareAfter = false,
  });

  /// Where the pieces are kept; null for the app's own folder.
  final String? folder;
  final bool deleteWhenFinished;

  /// Downloads not played for this many days are deleted; null keeps them.
  final int? keepDays;

  /// Bytes all downloads may take together; 0 for no limit.
  final int storageLimit;

  /// Bytes a second; 0 for no limit.
  final int downloadLimit;
  final int uploadLimit;

  /// Keeps sharing (the engine running) while the app is open, not only while a book plays.
  final bool shareAfter;

  static TorrentOptions fromJson(Map<Object?, Object?>? json) {
    int number(String key, int fallback) =>
        (json?[key] as num?)?.toInt() ?? fallback;
    final folder = json?['folder'];
    return TorrentOptions(
      folder: folder is String && folder.trim().isNotEmpty
          ? folder.trim()
          : null,
      deleteWhenFinished: json?['deleteWhenFinished'] != false,
      keepDays: (json?['keepDays'] as num?)?.toInt(),
      storageLimit: number('storageLimit', 5 << 30),
      downloadLimit: number('downloadLimit', 0),
      uploadLimit: number('uploadLimit', 0),
      shareAfter: json?['shareAfter'] == true,
    );
  }

  Object get _fields => (
    folder,
    deleteWhenFinished,
    keepDays,
    storageLimit,
    downloadLimit,
    uploadLimit,
    shareAfter,
  );

  @override
  bool operator ==(Object other) =>
      other is TorrentOptions && other._fields == _fields;

  @override
  int get hashCode => _fields.hashCode;
}

/// A file inside a torrent.
typedef TorrentFile = ({int index, String path, int size});

/// Plays torrents through TorrServer (github.com/YouROK/TorrServer), shipped with the app and
/// run as a hidden process that only listens on this device. It starts on the first call and
/// is stopped when no book needs it, so nothing runs while the app is idle.
class TorrentEngine {
  TorrentEngine(this._prefs, {Future<String?> Function()? binary})
    : _findBinary = binary ?? findBinary;

  final SharedPreferences _prefs;
  final Future<String?> Function() _findBinary;
  final _http = http.Client();

  /// How long the engine stays up once no book needs it.
  static Duration idleTimeout = const Duration(minutes: 10);

  static const _marker = '.shu-download';
  static const _booksKey = 'torrent.books';
  static const _portKey = 'torrent.port';

  Future<Uri>? _base;
  Process? _process;
  TorrentOptions _options = const TorrentOptions();
  Timer? _idle;
  String? _playing;

  /// Torrents asked for since the engine started: clean-up leaves them alone.
  final _inUse = <String>{};

  /// The TorrServer program: SHU_TORRSERVER (dev shell, Nix package), else the copy shipped
  /// beside the app. Null when this build has none.
  static Future<String?> findBinary() async {
    final given = Platform.environment['SHU_TORRSERVER'];
    if (given != null && given.isNotEmpty) return given;
    final String path;
    if (Platform.isAndroid) {
      // Android only runs programs from the app's library folder.
      final dir = await const MethodChannel('io.player.shu/update')
          .invokeMethod<String>('nativeLibraryDir');
      path = '$dir/libtorrserver.so';
    } else {
      final dir = File(Platform.resolvedExecutable).parent.path;
      path = Platform.isWindows
          ? '$dir\\torrserver.exe'
          : '$dir/lib/torrserver';
    }
    return File(path).existsSync() ? path : null;
  }

  /// The files of the torrent behind [magnet], once peers have sent its description.
  Future<List<TorrentFile>> files(String magnet, TorrentOptions options) async {
    final hash = await _add(magnet, options);
    // Within the 60 s an extension call may take, so this message is the one shown.
    final end = DateTime.now().add(const Duration(seconds: 45));
    while (true) {
      final stats = (await _torrents({
        'action': 'get',
        'hash': hash,
      }))['file_stats'];
      if (stats is List && stats.isNotEmpty) {
        return [
          for (final f in stats.cast<Map<String, dynamic>>())
            (
              index: (f['id'] as num).toInt(),
              path: f['path'] as String,
              size: (f['length'] as num).toInt(),
            ),
        ];
      }
      if (DateTime.now().isAfter(end)) {
        throw AddonException(
          'No one sharing this torrent answered. Try another version.',
        );
      }
      // Waits on the user's request, never while idle.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// A link on this device that streams file [index] of [magnet], downloading as it plays.
  Future<String> stream(
    String magnet,
    int index,
    TorrentOptions options,
  ) async {
    final hash = magnetHash(magnet);
    final file = (await files(magnet, options)).where((f) => f.index == index);
    if (file.isEmpty) throw AddonException('The torrent has no file $index.');
    final name = file.first.path.split('/').last;
    final base = await _start();
    final url = base.replace(
      path: '/stream/${Uri.encodeComponent(name)}',
      query: 'link=$hash&index=$index&play',
    );
    await _warmUp(url, file.first.size, name);
    return url.toString();
  }

  /// Fetches the start of the file (and its end, where MP4 audio keeps its index) before the
  /// player opens it: players give up on a link that sends nothing for a few seconds (mpv
  /// after 5), while a torrent with few people sharing it can take longer to start.
  Future<void> _warmUp(Uri url, int size, String name) async {
    const part = 256 << 10;
    Future<void> read(int from, int to) async {
      final request = http.Request('GET', url)
        ..headers['range'] = 'bytes=$from-$to';
      final res = await _http.send(request);
      await res.stream.drain<void>();
    }

    final mp4 = RegExp(r'\.(m4b|m4a|mp4|aac)$', caseSensitive: false);
    try {
      await Future.wait([
        read(0, min(part, size) - 1),
        if (mp4.hasMatch(name) && size > part) read(size - part, size - 1),
      ]).timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      // The player tries anyway, and says why if it can't start.
      debugPrint('Torrent warm-up: $e');
    }
  }

  /// The torrent a link from [stream] plays, or null for any other link.
  String? hashOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host != '127.0.0.1' ||
        !uri.path.startsWith('/stream/')) {
      return null;
    }
    final port = _prefs.getInt(_portKey);
    return uri.port == port ? uri.queryParameters['link'] : null;
  }

  /// The player loaded [url] for the book [bookKey] (or something else, when it isn't ours):
  /// the engine stays up while one of its links plays, and remembers which book a torrent is.
  void loaded(String? url, String? bookKey) {
    final hash = url == null ? null : hashOf(url);
    _playing = hash;
    if (hash != null && bookKey != null) {
      final keys = (_books()[hash]?['keys'] as List?) ?? const [];
      unawaited(
        _remember(hash, {
          'keys': {...keys, bookKey}.toList(),
          'delete': _options.deleteWhenFinished,
          'played': DateTime.now().toIso8601String(),
        }),
      );
    }
    _scheduleIdle();
  }

  /// What is known of each torrent: the books it plays (`keys`), whether to delete it when
  /// they are finished, when it last played and the folder it is in.
  Map<String, Map<String, Object?>> _books() {
    try {
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(_prefs.getString(_booksKey) ?? '{}') as Map).entries)
          key as String: (value as Map).cast<String, Object?>(),
      };
    } on Object {
      return {};
    }
  }

  Future<void> _remember(String hash, Map<String, Object?> info) async {
    final books = _books();
    books[hash] = {...?books[hash], ...info};
    await _prefs.setString(_booksKey, jsonEncode(books));
  }

  /// Deletes the downloads of books that are finished or gone from [library], when their
  /// options say so. Called whenever the library changes.
  Future<void> tidy(LibraryStore library) async {
    if (_tidying) return;
    _tidying = true;
    try {
      await _tidy(library);
    } finally {
      _tidying = false;
    }
  }

  bool _tidying = false;

  Future<void> _tidy(LibraryStore library) async {
    for (final MapEntry(key: hash, value: info) in _books().entries) {
      if (hash == _playing || info['delete'] != true) continue;
      final keys = ((info['keys'] as List?) ?? const []).cast<String>();
      final done = keys.every((key) {
        final bar = key.indexOf('|');
        if (bar < 0) return true;
        final entry = library.find(
          key.substring(0, bar),
          key.substring(bar + 1),
        );
        return entry?.finished ?? true;
      });
      if (done) await forget(hash);
    }
  }

  /// Stops [hash] and deletes what was downloaded of it. Only folders Shu made are deleted.
  Future<void> forget(String hash) async {
    if (_base != null) {
      try {
        await _torrents({'action': 'rem', 'hash': hash});
      } on Object catch (e) {
        debugPrint('Removing a torrent failed: $e');
      }
    }
    final books = _books();
    final folder = books[hash]?['folder'] as String? ?? await _folder(_options);
    final dir = Directory('$folder/$hash');
    if (File('${dir.path}/$_marker').existsSync()) {
      await dir.delete(recursive: true);
    }
    books.remove(hash);
    await _prefs.setString(_booksKey, jsonEncode(books));
  }

  /// Deletes downloads not played for the chosen number of days, then the least recently
  /// played ones while all of them take more than the storage limit.
  Future<void> _cleanUp(TorrentOptions options) async {
    var books = _books();
    // Torrents Shu let go of while the engine was stopped are removed from its list now.
    final listed = await _post('/torrents', {'action': 'list'});
    for (final t in listed is List ? listed : const []) {
      final hash = (t as Map)['hash'] as String?;
      if (hash != null && !books.containsKey(hash) && !_inUse.contains(hash)) {
        await _torrents({'action': 'rem', 'hash': hash});
      }
    }
    books = _books();
    DateTime played(String hash) =>
        DateTime.tryParse('${books[hash]?['played']}') ?? DateTime(2000);
    final folder = await _folder(options);
    final dirs = <String, int>{};
    final root = Directory(folder);
    if (!root.existsSync()) return;
    for (final dir in root.listSync().whereType<Directory>()) {
      if (!File('${dir.path}/$_marker').existsSync()) continue;
      var size = 0;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        size += f.lengthSync();
      }
      dirs[dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty)] = size;
    }
    final now = DateTime.now();
    final old = [
      for (final hash in dirs.keys)
        if (!_inUse.contains(hash) &&
            options.keepDays != null &&
            now.difference(played(hash)).inDays >= options.keepDays!)
          hash,
    ];
    for (final hash in old) {
      await forget(hash);
      dirs.remove(hash);
    }
    if (options.storageLimit <= 0) return;
    var total = dirs.values.fold(0, (a, b) => a + b);
    final byAge = dirs.keys.where((h) => !_inUse.contains(h)).toList()
      ..sort((a, b) => played(a).compareTo(played(b)));
    for (final hash in byAge) {
      if (total <= options.storageLimit) break;
      total -= dirs[hash]!;
      await forget(hash);
    }
  }

  /// TorrServer deletes any folder in its save path it doesn't know at start, so it only ever
  /// gets a folder of its own, also inside a folder the user picked.
  Future<String> _folder(TorrentOptions options) async => options.folder != null
      ? '${options.folder}/Shu torrents'
      : '${(await getApplicationSupportDirectory()).path}/torrents';

  /// Adds [magnet] (again, harmlessly, when it is there already) with [options] applied.
  Future<String> _add(String magnet, TorrentOptions options) async {
    final hash = magnetHash(magnet);
    _inUse.add(hash);
    _idle?.cancel();
    final changed = options != _options;
    _options = options;
    final first = _base == null;
    await _start();
    if (changed && !first) await _applySettings();
    final folder = await _folder(options);
    final dir = Directory('$folder/$hash');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
      await File('${dir.path}/$_marker').writeAsString('Downloaded by Shu\n');
      await _remember(hash, {'folder': folder});
    }
    // Kept in TorrServer's list: at start it deletes the downloads of torrents not in it.
    await _torrents({'action': 'add', 'link': magnet, 'save_to_db': true});
    _scheduleIdle();
    return hash;
  }

  /// The info hash of [magnet] in lowercase hex, also when the link has it in base32.
  @visibleForTesting
  static String magnetHash(String magnet) {
    final m = RegExp(
      r'xt=urn:btih:([0-9a-fA-F]{40}|[A-Za-z2-7]{32})(?![0-9A-Za-z])',
    ).firstMatch(magnet);
    if (m == null) throw AddonException('Not a torrent link.');
    final hash = m.group(1)!.toLowerCase();
    if (hash.length == 40) return hash;
    final out = StringBuffer();
    var bits = 0, value = 0;
    for (final c in hash.codeUnits) {
      value = value << 5 | (c >= 0x61 ? c - 0x61 : c - 0x32 + 26);
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.write(((value >> bits) & 0xff).toRadixString(16).padLeft(2, '0'));
      }
    }
    return out.toString();
  }

  Future<Map<String, dynamic>> _torrents(Map<String, Object?> body) async =>
      (await _post('/torrents', body) as Map?)?.cast() ?? const {};

  Future<Object?> _post(String path, Map<String, Object?> body) async {
    final base = await _start();
    final res = await _http
        .post(base.replace(path: path), body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw AddonException(
        'The torrent engine failed (HTTP ${res.statusCode}).',
      );
    }
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<Uri> _start() => _base ??= () async {
    final binary = await _findBinary();
    if (binary == null) {
      _base = null;
      throw AddonException('This build of Shu can\'t play torrents.');
    }
    // A copy left running by a crash answers on its old port: it is asked to stop.
    if (_prefs.getInt(_portKey) case final old?) {
      try {
        await _http
            .get(Uri.parse('http://127.0.0.1:$old/shutdown'))
            .timeout(const Duration(seconds: 1));
      } on Object {
        // Nothing there.
      }
    }
    // The same port as last time when it is free, so links the player kept still work.
    ServerSocket free;
    try {
      free = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _prefs.getInt(_portKey) ?? 0,
      );
    } on SocketException {
      free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    }
    final port = free.port;
    await free.close();
    final home = Directory(
      '${(await getApplicationSupportDirectory()).path}/torrserver',
    )..createSync(recursive: true);
    final process = _process = await Process.start(binary, [
      '--ip',
      '127.0.0.1',
      '--port',
      '$port',
      '--path',
      home.path,
    ]);
    // Its log is not needed; unread pipes would fill up and stall it.
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    unawaited(
      process.exitCode.then((_) {
        if (identical(_process, process)) {
          _process = null;
          _base = null;
        }
      }),
    );
    await _prefs.setInt(_portKey, port);
    final base = Uri.parse('http://127.0.0.1:$port');
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      try {
        final res = await _http
            .get(base.replace(path: '/echo'))
            .timeout(const Duration(seconds: 1));
        if (res.statusCode == 200) break;
      } on Object {
        // Not listening yet.
      }
      if (DateTime.now().isAfter(end) || _process == null) {
        process.kill();
        _base = null;
        throw AddonException('The torrent engine did not start.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _base = Future.value(base);
    await _applySettings();
    unawaited(_cleanUp(_options));
    return base;
  }();

  /// TorrServer's settings from [_options]; everything else it does on the network beyond
  /// torrents (announcing itself on the LAN) is turned off.
  Future<void> _applySettings() async {
    final current =
        ((await _post('/settings', {'action': 'get'})) as Map?)
            ?.cast<String, Object?>() ??
        {};
    final o = _options;
    await _post('/settings', {
      'action': 'set',
      'sets': settingsFor(current, o, await _folder(o)),
    });
  }

  /// [current] TorrServer settings with [options] applied.
  @visibleForTesting
  static Map<String, Object?> settingsFor(
    Map<String, Object?> current,
    TorrentOptions options,
    String folder,
  ) => {
    ...current,
    'UseDisk': true,
    'TorrentsSavePath': folder,
    // A whole book fits in what is kept of one torrent, within the storage limit.
    'CacheSize': options.storageLimit > 0 ? options.storageLimit : 64 << 30,
    'RemoveCacheOnDrop': false,
    'DownloadRateLimit': options.downloadLimit ~/ 1024,
    'UploadRateLimit': options.uploadLimit ~/ 1024,
    'EnableBonjour': false,
    'EnableDLNA': false,
    'EnableLPD': false,
  };

  void _scheduleIdle() {
    _idle?.cancel();
    if (_base == null || _playing != null || _options.shareAfter) return;
    _idle = Timer(idleTimeout, stop);
  }

  /// Ends the engine process (it is started again when needed).
  Future<void> stop() async {
    _idle?.cancel();
    final process = _process;
    _process = null;
    _base = null;
    _inUse.clear();
    if (process == null) return;
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}
