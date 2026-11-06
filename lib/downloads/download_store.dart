import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../addons/addon_store.dart';
import '../addons/backend.dart';
import '../addons/links.dart';
import '../addons/models.dart';
import '../library/library_store.dart';
import '../peer/torrent_engine.dart';
import '../player/player_settings.dart';
import 'download_service.dart';

enum DownloadState {
  queued,
  waitingForWifi,
  waiting,
  downloading,
  failed,
  done,
}

/// Where a book's download is. [fraction] is null while it isn't known.
class DownloadProgress {
  const DownloadProgress(
    this.state, {
    this.fraction,
    this.message,
    this.detail,
  });
  final DownloadState state;
  final double? fraction;

  /// Why it failed or what it waits for.
  final String? message;

  /// While downloading: which file, how much of it and how fast, to show it is moving.
  final String? detail;

  bool get active =>
      state != DownloadState.failed && state != DownloadState.done;
}

/// Books kept on this device to play without a connection. One audio file is downloaded at a
/// time, books in the order they were asked for; what was cut off goes on where it stopped, also
/// after a restart. The files of a book are `downloads/<book key>/<first chapter><ext>`
/// (chapters inside one file share it), and a pref records which are complete.
class DownloadStore extends ChangeNotifier {
  DownloadStore._(
    this._prefs,
    this._root,
    this._library,
    this._addons,
    this._settings,
    this._client,
  ) {
    _service = DownloadService(
      onCancel: () {
        final key = _running;
        if (key != null) unawaited(remove(key));
      },
      onNetwork: _kick,
    );
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        _records.addAll(
          (jsonDecode(raw) as Map).map(
            (k, v) => MapEntry(k as String, (v as Map).cast<String, Object?>()),
          ),
        );
      } on Object catch (e) {
        // Set aside rather than lost; the files are cleaned up as unknown.
        debugPrint('Unreadable downloads, kept as $_key.bad: $e');
        unawaited(_prefs.setString('$_key.bad', raw));
      }
    }
  }

  /// [root] and [client] are for tests.
  static Future<DownloadStore> load(
    SharedPreferences prefs,
    LibraryStore library,
    AddonStore addons,
    PlayerSettings settings, {
    Directory? root,
    http.Client? client,
  }) async {
    final dir =
        root ??
        Directory('${(await getApplicationSupportDirectory()).path}/downloads');
    final store = DownloadStore._(
      prefs,
      dir,
      library,
      addons,
      settings,
      client ?? http.Client(),
    );
    library.addListener(store.tidy);
    // "Download on mobile data" or "Delete downloads of finished books" may have just changed.
    settings.addListener(() {
      store.tidy();
      store._kick();
    });
    await store._cleanUp();
    store._kick();
    return store;
  }

  static const _key = 'downloads';
  static const _retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// How long to wait before asking again about a book the service is still fetching.
  @visibleForTesting
  static Duration waitFor = const Duration(seconds: 30);

  final SharedPreferences _prefs;
  final Directory _root;
  final LibraryStore _library;
  final AddonStore _addons;
  final PlayerSettings _settings;
  final http.Client _client;
  late final DownloadService _service;

  /// Book key → `{files: {first chapter: file name}, done: bool}`, in the order asked for.
  final Map<String, Map<String, Object?>> _records = {};
  final Map<String, DownloadProgress> _progress = {};

  /// Ticks as downloads move along, see [_set].
  final moved = ValueNotifier<int>(0);

  /// The book being downloaded, and a flag that stops it.
  String? _running;
  bool _stop = false;
  Timer? _again;
  int _tries = 0;
  DateTime _shown = DateTime(0);

  TorrentEngine? get _torrents => _addons.host.torrents;

  /// Null for a book that was never downloaded.
  DownloadProgress? progressOf(String key) =>
      _progress[key] ??
      switch (_records[key]) {
        null => null,
        {'done': true} => const DownloadProgress(DownloadState.done),
        {'error': final String message} => DownloadProgress(
          DownloadState.failed,
          message: message,
        ),
        _ => const DownloadProgress(DownloadState.queued),
      };

  bool isDownloaded(String key) => _records[key]?['done'] == true;

  /// The downloaded file that plays chapter [index] of [entry], if there is one.
  String? fileFor(LibraryEntry entry, int index) {
    final files = _records[entry.key]?['files'];
    if (files is! Map) return null;
    final name = files['${_fileStart(entry.book, index)}'];
    if (name is! String) return null;
    final path = '${_folder(entry.key).path}/$name';
    return File(path).existsSync() ? path : null;
  }

  /// Bytes all downloads take.
  Future<int> bytesUsed() async {
    if (!_root.existsSync()) return 0;
    var total = 0;
    await for (final f in _root.list(recursive: true)) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  /// Queues [book] from [addon]. It joins the library (as not started) when it isn't there.
  Future<void> add(InstalledAddon addon, Book book, {String? workKey}) async {
    // The library's own entry, which the player may hold: entryFor would replace it.
    if (_library.find(addon.id, book.id) == null) {
      await _library.save(_library.entryFor(addon.id, book, workKey: workKey));
    }
    final key = LibraryEntry.keyOf(addon.id, book.id);
    _records[key] = {...?_records[key], 'done': false}..remove('error');
    _progress.remove(key);
    await _save();
    notifyListeners();
    _kick();
  }

  /// Stops and deletes the download of [key].
  Future<void> remove(String key) async {
    if (!_records.containsKey(key)) return;
    if (_running == key) _stop = true;
    _records.remove(key);
    _progress.remove(key);
    await _save();
    notifyListeners();
    // A download cut off this moment may still write its last piece; delete after it.
    if (_running != key) await _delete(key);
  }

  Future<void> removeAll() async {
    for (final key in _records.keys.toList()) {
      await remove(key);
    }
  }

  /// Deletes the downloads of books gone from the library, and of finished ones when the
  /// settings say so. Called whenever the library changes.
  void tidy() {
    for (final key in _records.keys.toList()) {
      final bar = key.indexOf('|');
      final entry = _library.find(
        key.substring(0, bar),
        key.substring(bar + 1),
      );
      if (entry == null ||
          (entry.finished && _settings.deleteFinishedDownloads)) {
        unawaited(remove(key));
      }
    }
  }

  /// Folders nobody knows of (a removed record, a damaged pref) are deleted. Not without any
  /// record at all: prefs that start empty (tests) must not take real downloads with them.
  Future<void> _cleanUp() async {
    if (!_root.existsSync() || !_prefs.containsKey(_key)) return;
    final known = {for (final k in _records.keys) _folder(k).path};
    await for (final dir in _root.list()) {
      if (dir is Directory && !known.contains(dir.path)) {
        await dir.delete(recursive: true);
      }
    }
  }

  /// Starts the next download unless the queue is being worked on.
  void _kick() {
    _again?.cancel();
    if (_busy) return;
    _busy = true;
    unawaited(
      _run()
          .catchError(
            (Object e) => debugPrint('Downloads stopped: ${_plain(e)}'),
          )
          .whenComplete(() => _busy = false),
    );
  }

  bool _busy = false;

  Future<void> _run() async {
    while (true) {
      final key = _records.entries
          .where((e) => e.value['done'] == false)
          .firstOrNull
          ?.key;
      if (key == null) {
        await _service.stop();
        return;
      }
      if (!_settings.downloadOnMobile && await _service.metered()) {
        _set(key, const DownloadProgress(DownloadState.waitingForWifi));
        // No service while waiting: it could be hours. Downloads go on when the network
        // changes while Shu runs, else at the next start.
        await _service.stop();
        await _service.watchNetwork(true);
        return;
      }
      await _service.watchNetwork(false);
      _running = key;
      _stop = false;
      final bool? next;
      try {
        next = await _download(key);
      } finally {
        _running = null;
      }
      if (_stop || !_records.containsKey(key)) {
        await _delete(key);
        continue;
      }
      if (next == null) return; // Waits on a timer.
      _tries = 0;
    }
  }

  /// Downloads what is missing of [key]: true when done or failed for good (go on with the next
  /// book), null when a timer will try again.
  Future<bool?> _download(String key) async {
    final bar = key.indexOf('|');
    final entry = _library.find(key.substring(0, bar), key.substring(bar + 1));
    final addon = _addons.byId(key.substring(0, bar));
    if (entry == null || addon == null) {
      _fail(key, 'The book or its addon is gone.');
      return true;
    }
    final chapters = entry.book.chapters;
    final starts = [
      for (var i = 0; i < chapters.length; i++)
        if (_fileStart(entry.book, i) == i) i,
    ];
    final files = ((_records[key]!['files'] as Map?) ?? {})
        .cast<String, Object?>();
    final torrentLinks = <String>{};
    try {
      for (final (n, start) in starts.indexed) {
        final name = files['$start'];
        if (name is String && File('${_folder(key).path}/$name').existsSync()) {
          continue;
        }
        _set(
          key,
          DownloadProgress(
            DownloadState.downloading,
            fraction: n / starts.length,
          ),
        );
        final (:link, sourceId: _) = await chapterLink(addon, entry, start);
        if (_stop) return true;
        switch (link) {
          case Downloading(:final message, :final progress):
            _set(
              key,
              DownloadProgress(
                DownloadState.waiting,
                fraction: progress,
                message: message,
              ),
            );
            await _service.show('${entry.book.title}: $message');
            _again = Timer(waitFor, _kick);
            return null;
          case Playable(:final url):
            final torrents = _torrents;
            final torrent = torrents?.hashOf(url) != null;
            if (torrent) {
              torrentLinks.add(url);
              torrents!.hold();
            }
            try {
              final saved = await _fetch(
                Uri.parse(url),
                key,
                start,
                (got, total, perSecond) => _set(
                  key,
                  DownloadProgress(
                    DownloadState.downloading,
                    fraction: total == null
                        ? n / starts.length
                        : (n + got / total) / starts.length,
                    detail: [
                      if (starts.length > 1)
                        'File ${n + 1} of ${starts.length}',
                      total == null
                          ? sizeText(got)
                          : '${sizeText(got)} of ${sizeText(total)}',
                      if (perSecond != null) '${sizeText(perSecond)}/s',
                    ].join(' · '),
                  ),
                  title: entry.book.title,
                ),
              );
              if (saved == null) {
                // Cancelled: the engine's copy goes too.
                for (final url in torrentLinks) {
                  unawaited(_torrents?.downloaded(url));
                }
                return true;
              }
              files['$start'] = saved;
              _records[key]?['files'] = files;
              await _save();
            } finally {
              if (torrent) torrents!.release();
            }
        }
      }
    } on Object catch (e) {
      if (_stop) return true;
      if (_tries < _retryDelays.length) {
        final delay = _retryDelays[_tries++];
        _set(
          key,
          DownloadProgress(
            DownloadState.waiting,
            message: 'Connection problem, trying again in ${delay.inSeconds} s',
          ),
        );
        _again = Timer(delay, _kick);
        return null;
      }
      _fail(key, e is AddonException ? e.message : _plain(e));
      return true;
    }
    _records[key]?['done'] = true;
    _progress.remove(key);
    await _save();
    notifyListeners();
    for (final url in torrentLinks) {
      unawaited(_torrents?.downloaded(url));
    }
    return true;
  }

  /// Downloads [url] as the file of chapter [start], going on from a cut-off `.part`. Returns
  /// the file's name, or null when stopped.
  Future<String?> _fetch(
    Uri url,
    String key,
    int start,
    void Function(int got, int? total, int? perSecond) onProgress,
  ) async {
    final dir = _folder(key);
    await dir.create(recursive: true);
    final part = File('${dir.path}/$start.part');
    var have = part.existsSync() ? await part.length() : 0;
    final request = http.Request('GET', url);
    if (have > 0) request.headers['range'] = 'bytes=$have-';
    final res = await _client.send(request);
    if (res.statusCode == 416) {
      // The part doesn't fit the file any more: start over.
      await res.stream.drain<void>();
      await part.delete();
      return _fetch(url, key, start, onProgress);
    }
    if (res.statusCode >= 400) {
      await res.stream.drain<void>();
      throw AddonException('The download failed (HTTP ${res.statusCode}).');
    }
    if (res.statusCode != 206) have = 0; // The server sent the whole file.
    final total = res.contentLength == null ? null : have + res.contentLength!;
    final sink = part.openWrite(
      mode: have > 0 ? FileMode.append : FileMode.write,
    );
    var got = have;
    // Speed over the last two seconds, so a stall shows as it happens.
    var mark = (at: DateTime.now(), got: got);
    int? perSecond; // Unknown until the first two seconds are in.
    try {
      await for (final chunk in res.stream) {
        if (_stop) return null;
        sink.add(chunk);
        got += chunk.length;
        final now = DateTime.now();
        final ms = now.difference(mark.at).inMilliseconds;
        if (ms >= 2000) {
          perSecond = (got - mark.got) * 1000 ~/ ms;
          mark = (at: now, got: got);
        }
        onProgress(got, total != null && total > 0 ? total : null, perSecond);
      }
    } finally {
      await sink.close();
    }
    if (total != null && got != total) {
      throw AddonException('The download stopped early.');
    }
    final name = '$start${_extension(url, res.headers['content-type'])}';
    await part.rename('${dir.path}/$name');
    return name;
  }

  /// Sets [key]'s progress. A change of state tells the store's listeners; a download moving
  /// along only [moved] (a few times a second), so lists of books aren't rebuilt for it.
  void _set(String key, DownloadProgress progress, {String? title}) {
    final before = _progress[key]?.state;
    _progress[key] = progress;
    if (progress.state != before) {
      notifyListeners();
    } else {
      final now = DateTime.now();
      if (now.difference(_shown) < const Duration(milliseconds: 300)) return;
      _shown = now;
      moved.value++;
    }
    if (title != null) {
      final percent = ((progress.fraction ?? 0) * 100).round();
      unawaited(
        _service.show(
          'Downloading $title',
          percent: percent,
          detail: progress.detail,
        ),
      );
    }
  }

  void _fail(String key, String message) {
    _tries = 0;
    _records[key]
      ?..['done'] = null
      ..['error'] = message;
    _progress.remove(key);
    unawaited(_save());
    notifyListeners();
  }

  Future<void> _delete(String key) async {
    final dir = _folder(key);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  Future<void> _save() => _prefs.setString(_key, jsonEncode(_records));

  Directory _folder(String key) =>
      Directory('${_root.path}/${base64Url.encode(utf8.encode(key))}');

  /// The first chapter of the file that plays chapter [index].
  static int _fileStart(Book book, int index) {
    final chapter = book.chapters[index];
    for (var i = 0; i < index; i++) {
      if (book.chapters[i].sharesFileWith(chapter)) return i;
    }
    return index;
  }

  static String _extension(Uri url, String? type) {
    final last = url.pathSegments.lastOrNull ?? '';
    final dot = RegExp(r'\.[A-Za-z0-9]{1,5}$').firstMatch(last);
    if (dot != null) return dot[0]!.toLowerCase();
    return switch (type?.split(';').first.trim()) {
      'audio/mpeg' => '.mp3',
      'audio/mp4' || 'audio/x-m4a' || 'audio/x-m4b' => '.m4b',
      'audio/ogg' || 'audio/opus' => '.ogg',
      'audio/flac' => '.flac',
      'audio/wav' || 'audio/x-wav' => '.wav',
      _ => '.audio',
    };
  }

  /// Network errors without their links (they can hold an API key).
  static String _plain(Object e) => e is http.ClientException
      ? e.message
      : '$e'.replaceAll(RegExp(r'[a-z][a-z0-9+.-]*://\S+'), '<link>');
}

/// [bytes] as MB or GB.
String sizeText(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
    : '${(bytes / (1 << 20)).toStringAsFixed(bytes >= 10 << 20 ? 0 : 1)} MB';
