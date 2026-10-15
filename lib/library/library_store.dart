import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../addons/models.dart';

/// A book the user has started, with where they stopped.
class LibraryEntry {
  LibraryEntry({
    required this.addonId,
    required this.book,
    this.chapterIndex = 0,
    this.position = Duration.zero,
    this.sourceId,
    this.finished = false,
    this.workKey,
    DateTime? updatedAt,
    List<Mark>? bookmarks,
    List<Mark>? history,
  }) : updatedAt = updatedAt ?? DateTime.now(),
       bookmarks = bookmarks ?? [],
       history = history ?? [];

  final String addonId;
  final Book book;
  int chapterIndex;
  Duration position;

  /// The source the user picked for this book, when an extension offers several.
  String? sourceId;
  bool finished;
  DateTime updatedAt;

  /// The catalog book this is a version of (`addonId|bookId`), if it was started from one.
  String? workKey;

  /// Places the user marked, in the order they were added.
  final List<Mark> bookmarks;

  /// Where the user was before their last jumps (picking a chapter, dragging far), newest first.
  final List<Mark> history;
  static const historyLength = 10;

  /// Adds [mark] to the front of the history, dropping the oldest beyond [historyLength].
  void remember(Mark mark) {
    history.insert(0, mark);
    if (history.length > historyLength) history.removeLast();
  }

  /// Where the user is now, as a mark.
  Mark here({String? note}) => Mark(
    chapterIndex: chapterIndex,
    position: position,
    note: note,
    createdAt: DateTime.now(),
  );

  String get key => keyOf(addonId, book.id);
  static String keyOf(String addonId, String bookId) => '$addonId|$bookId';

  double get progress {
    if (finished) return 1;
    if (book.chapters.isEmpty) return 0;
    final chapter = book.chapters[chapterIndex];
    // A single file of unknown length: the catalog's length stands in.
    final seconds =
        chapter.duration ??
        (book.chapters.length == 1 ? (book.durationMinutes ?? 0) * 60 : 0);
    final into = position - (chapter.start ?? Duration.zero);
    final part = seconds > 0 ? (into.inSeconds / seconds).clamp(0, 1) : 0;
    return ((chapterIndex + part) / book.chapters.length)
        .clamp(0, 1)
        .toDouble();
  }

  Map<String, dynamic> toJson() => {
    'addonId': addonId,
    'book': book.toJson(),
    'chapterIndex': chapterIndex,
    'positionMs': position.inMilliseconds,
    'sourceId': sourceId,
    'finished': finished,
    'workKey': ?workKey,
    'updatedAt': updatedAt.toIso8601String(),
    if (bookmarks.isNotEmpty)
      'bookmarks': [for (final m in bookmarks) m.toJson()],
    if (history.isNotEmpty) 'history': [for (final m in history) m.toJson()],
  };

  static LibraryEntry fromJson(Map<String, dynamic> json) {
    final book = Book.fromJson(json['book'] as Map<String, dynamic>);
    return LibraryEntry(
      addonId: json['addonId'] as String,
      book: book,
      chapterIndex: ((json['chapterIndex'] as num?)?.toInt() ?? 0).clamp(
        0,
        book.chapters.isEmpty ? 0 : book.chapters.length - 1,
      ),
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      sourceId: json['sourceId'] as String?,
      finished: json['finished'] == true,
      workKey: json['workKey'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      bookmarks: Mark.listFrom(json['bookmarks'], book),
      history: Mark.listFrom(json['history'], book),
    );
  }
}

/// A place in a book: a bookmark, or where the user was before a jump.
class Mark {
  const Mark({
    required this.chapterIndex,
    required this.position,
    required this.createdAt,
    this.note,
  });

  final int chapterIndex;

  /// In the chapter's audio file, like [LibraryEntry.position].
  final Duration position;
  final DateTime createdAt;
  final String? note;

  Mark withNote(String? note) => Mark(
    chapterIndex: chapterIndex,
    position: position,
    createdAt: createdAt,
    note: note == null || note.trim().isEmpty ? null : note.trim(),
  );

  /// Whether the book (maybe reloaded with other chapters) still has this place.
  bool fits(Book book) => chapterIndex < book.chapters.length;

  Map<String, dynamic> toJson() => {
    'chapter': chapterIndex,
    'positionMs': position.inMilliseconds,
    'at': createdAt.toIso8601String(),
    'note': ?note,
  };

  /// The marks in [json] that [book] still has; anything unreadable is left out.
  static List<Mark> listFrom(Object? json, Book book) => [
    if (json is List)
      for (final m in json.whereType<Map<String, dynamic>>())
        if (m['chapter'] case final int chapter)
          if (m['positionMs'] case final int ms)
            Mark(
              chapterIndex: chapter,
              position: Duration(milliseconds: ms),
              createdAt:
                  DateTime.tryParse(m['at'] as String? ?? '') ?? DateTime.now(),
              note: m['note'] as String?,
            ),
  ].where((m) => m.fits(book)).toList();
}

/// Books in progress, most recent first, kept in shared preferences.
class LibraryStore extends ChangeNotifier {
  LibraryStore(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    for (final item in jsonDecode(raw) as List) {
      try {
        final entry = LibraryEntry.fromJson(item as Map<String, dynamic>);
        _entries[entry.key] = entry;
      } on Object catch (e) {
        debugPrint('Dropping unreadable library entry: $e');
      }
    }
  }

  static const _key = 'library';
  final SharedPreferences _prefs;
  final Map<String, LibraryEntry> _entries = {};

  List<LibraryEntry> get entries =>
      _entries.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  LibraryEntry? find(String addonId, String bookId) =>
      _entries[LibraryEntry.keyOf(addonId, bookId)];

  /// The entry for a book, created when the user first plays it. The stored book is refreshed.
  LibraryEntry entryFor(String addonId, Book book, {String? workKey}) {
    final key = LibraryEntry.keyOf(addonId, book.id);
    final old = _entries[key];
    final entry = LibraryEntry(
      addonId: addonId,
      book: book,
      chapterIndex: (old?.chapterIndex ?? 0).clamp(0, book.chapters.length - 1),
      position: old?.position ?? Duration.zero,
      sourceId: old?.sourceId,
      finished: old?.finished ?? false,
      workKey: workKey ?? old?.workKey,
      bookmarks: old?.bookmarks.where((m) => m.fits(book)).toList(),
      history: old?.history.where((m) => m.fits(book)).toList(),
    );
    _entries[key] = entry;
    return entry;
  }

  /// The most recent entry started from a catalog book, whichever version it plays.
  LibraryEntry? findByWork(String addonId, String bookId) {
    final workKey = LibraryEntry.keyOf(addonId, bookId);
    for (final e in entries) {
      if (e.workKey == workKey) return e;
    }
    return null;
  }

  Future<void> save(LibraryEntry entry, {bool notify = true}) async {
    entry.updatedAt = DateTime.now();
    _entries[entry.key] = entry;
    await _prefs.setString(
      _key,
      jsonEncode(_entries.values.map((e) => e.toJson()).toList()),
    );
    if (notify) notifyListeners();
  }

  Future<void> remove(LibraryEntry entry) async {
    _entries.remove(entry.key);
    await _prefs.setString(
      _key,
      jsonEncode(_entries.values.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }
}
