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
  }) : updatedAt = updatedAt ?? DateTime.now();

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

  String get key => keyOf(addonId, book.id);
  static String keyOf(String addonId, String bookId) => '$addonId|$bookId';

  double get progress => finished
      ? 1
      : (chapterIndex / book.chapters.length).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
    'addonId': addonId,
    'book': book.toJson(),
    'chapterIndex': chapterIndex,
    'positionMs': position.inMilliseconds,
    'sourceId': sourceId,
    'finished': finished,
    'workKey': ?workKey,
    'updatedAt': updatedAt.toIso8601String(),
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
    );
  }
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
