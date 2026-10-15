import 'dart:async';

import 'package:flutter/foundation.dart';

import '../addons/addon_store.dart';
import '../addons/backend.dart';
import '../library/library_store.dart';
import '../sources/server.dart';

/// Keeps the listening position in step with the media server a book plays from, so the
/// server's own apps carry on where Shu stopped and the other way round. Best effort: a server
/// that can't be reached never holds up playback.
class ServerSync {
  /// While playing, the position goes out with every [_every]th save (once a minute).
  static const _every = 4;
  static const _askFor = Duration(seconds: 3);

  /// Closer than this counts as the same place.
  static const _near = Duration(seconds: 5);

  int _ticks = 0;

  static ServerBackend? _server(InstalledAddon? addon) =>
      addon?.client is ServerBackend ? addon!.client as ServerBackend : null;

  /// The server's name when [addon] is a media server.
  static String? name(InstalledAddon? addon) => _server(addon)?.kind.label;

  /// Sends where the user is in [entry]. With [tick] (the regular save while playing), only
  /// every [_every]th time.
  void report(InstalledAddon? addon, LibraryEntry entry, {bool tick = false}) {
    final server = _server(addon);
    if (server == null || (tick && ++_ticks % _every != 0)) return;
    final place = (chapterIndex: entry.chapterIndex, position: entry.position);
    unawaited(
      server
          .report(entry.book, place, finished: entry.finished)
          .catchError(
            (Object e) => debugPrint('Progress not sent: ${_why(e)}'),
          ),
    );
  }

  /// The server's place in [entry] when the user listened elsewhere since Shu last saved it
  /// ([since], null for a book new to Shu) and it is somewhere else.
  Future<BookPlace?> newer(
    InstalledAddon? addon,
    LibraryEntry entry,
    DateTime? since,
  ) async {
    final server = _server(addon);
    if (server == null) return null;
    final RemoteProgress? remote;
    try {
      remote = await server.progress(entry.book).timeout(_askFor);
    } on Object catch (e) {
      // Also a book never played on the server, and a server too slow to wait for.
      debugPrint('No progress from the server: ${_why(e)}');
      return null;
    }
    if (remote == null || remote.finished) return null;
    if (since != null && !remote.updatedAt.isAfter(since.add(_near))) {
      return null;
    }
    final here = bookTime(entry.book, (
      chapterIndex: entry.chapterIndex,
      position: entry.position,
    ));
    final there = bookTime(entry.book, remote.place);
    return (here - there).abs() < _near ? null : remote.place;
  }

  /// Errors without addresses: server links carry tokens.
  static String _why(Object e) =>
      e is AddonException ? e.message : e.runtimeType.toString();
}
