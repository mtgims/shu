import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../addons/backend.dart';
import '../addons/models.dart';
import 'local_scan.dart';

/// An audiobook on this device: its files, in order, and what to call it.
class LocalBook {
  LocalBook({
    required this.id,
    required this.title,
    required this.files,
    this.authors = const [],
    this.narrators = const [],
    this.year,
    this.cover,
    this.owned = false,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  final String id;
  String title;
  List<String> authors;
  List<String> narrators;
  final String? year;
  final String? cover;
  final List<ScannedFile> files;

  /// The files were copied into the app (Android) and are deleted with the book.
  final bool owned;
  final DateTime addedAt;

  BookSummary get summary => BookSummary(
    id: id,
    title: title,
    authors: authors,
    narrators: narrators,
    cover: cover == null ? null : Uri.file(cover!).toString(),
    details: files.length == 1 ? null : '${files.length} files',
  );

  Book get book {
    final chapters = <Chapter>[];
    for (final (i, f) in files.indexed) {
      if (f.chapters.isEmpty) {
        chapters.add(
          Chapter(
            id: '$i',
            title: f.title,
            size: f.size,
            duration: f.duration?.inSeconds,
          ),
        );
        continue;
      }
      for (final (j, c) in f.chapters.indexed) {
        final end = j + 1 < f.chapters.length
            ? f.chapters[j + 1].start
            : f.duration;
        chapters.add(
          Chapter(
            id: '$i@$j',
            title: c.title,
            duration: end == null ? null : (end - c.start).inSeconds,
            file: '$i',
            start: c.start,
          ),
        );
      }
    }
    final total = files.every((f) => f.duration != null)
        ? files.fold(Duration.zero, (t, f) => t + f.duration!)
        : Duration.zero;
    final s = summary;
    return Book(
      id: id,
      title: s.title,
      authors: s.authors,
      narrators: s.narrators,
      cover: s.cover,
      details: s.details,
      year: year,
      durationMinutes: total == Duration.zero ? null : total.inMinutes,
      chapters: chapters,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'authors': authors,
    'narrators': narrators,
    'year': year,
    'cover': cover,
    'owned': owned,
    'addedAt': addedAt.toIso8601String(),
    'files': [
      for (final f in files)
        {
          'path': f.path,
          'title': f.title,
          'size': f.size,
          'durationMs': f.duration?.inMilliseconds,
          if (f.chapters.isNotEmpty)
            'chapters': [
              for (final c in f.chapters)
                {'startMs': c.start.inMilliseconds, 'title': c.title},
            ],
        },
    ],
  };

  factory LocalBook.fromJson(Map<String, dynamic> json) => LocalBook(
    id: json['id'] as String,
    title: json['title'] as String,
    authors: (json['authors'] as List).cast<String>(),
    narrators: (json['narrators'] as List? ?? const []).cast<String>(),
    year: json['year'] as String?,
    cover: json['cover'] as String?,
    owned: json['owned'] == true,
    addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
    files: [
      for (final f in (json['files'] as List).cast<Map<String, dynamic>>())
        ScannedFile(
          path: f['path'] as String,
          title: f['title'] as String,
          size: f['size'] as int?,
          duration: f['durationMs'] == null
              ? null
              : Duration(milliseconds: f['durationMs'] as int),
          chapters: [
            for (final c
                in (f['chapters'] as List? ?? const [])
                    .cast<Map<String, dynamic>>())
              (
                start: Duration(milliseconds: c['startMs'] as int),
                title: c['title'] as String,
              ),
          ],
        ),
    ],
  );
}

/// Audiobooks the user added from this device. The list is a JSON file; copied books live in
/// folders next to it.
class LocalLibrary extends ChangeNotifier {
  LocalLibrary._(this._dir);

  static Future<LocalLibrary> load(Directory dir) async {
    final library = LocalLibrary._(dir);
    try {
      final file = library._index;
      if (await file.exists()) {
        for (final item in jsonDecode(await file.readAsString()) as List) {
          library._books.add(LocalBook.fromJson(item as Map<String, dynamic>));
        }
      }
    } on Object catch (e) {
      debugPrint('Unreadable list of books on this device: $e');
    }
    return library;
  }

  final Directory _dir;
  final List<LocalBook> _books = [];

  /// Goes up with every change, so lists of these books know to load again.
  int revision = 0;

  File get _index => File('${_dir.path}/books.json');
  String get _coverDir => '${_dir.path}/covers';

  /// Newest first.
  List<LocalBook> get books => List.unmodifiable(_books.reversed);

  LocalBook? byId(String id) {
    for (final b in _books) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Adds every book in [folder] (desktop: the files stay where they are).
  Future<List<LocalBook>> addFolder(String folder) async =>
      _add(await scanFolder(folder, _coverDir), copy: false);

  /// Adds picked files as books. With [copy] (Android, where picked files are temporary copies)
  /// they are moved into the app.
  Future<List<LocalBook>> addFiles(
    List<String> paths, {
    required bool copy,
  }) async => _add(await scanFiles(paths, _coverDir), copy: copy);

  Future<List<LocalBook>> _add(
    List<ScannedBook> scanned, {
    required bool copy,
  }) async {
    final added = <LocalBook>[];
    for (final s in scanned) {
      // A folder added again replaces its book instead of showing it twice.
      final again = _books
          .where((b) => !b.owned && b.files.first.path == s.files.first.path)
          .toList();
      for (final b in again) {
        _books.remove(b);
      }
      final id = again.firstOrNull?.id ?? _newId();
      final files = copy ? await _moveIn(id, s.files) : s.files;
      final book = LocalBook(
        id: id,
        title: s.title,
        authors: s.authors,
        narrators: s.narrators,
        year: s.year,
        cover: s.cover,
        files: files,
        owned: copy,
      );
      _books.add(book);
      added.add(book);
    }
    await _save();
    return added;
  }

  Future<List<ScannedFile>> _moveIn(String id, List<ScannedFile> files) async {
    final dir = Directory('${_dir.path}/$id');
    await dir.create(recursive: true);
    return [
      for (final (i, f) in files.indexed)
        ScannedFile(
          path: await _move(
            File(f.path),
            '${dir.path}/${i.toString().padLeft(3, '0')}.${extensionOf(f.path)}',
          ),
          title: f.title,
          size: f.size,
          duration: f.duration,
          chapters: f.chapters,
        ),
    ];
  }

  static Future<String> _move(File from, String to) async {
    try {
      return (await from.rename(to)).path;
    } on FileSystemException {
      // Another file system: copy, then remove the temporary file.
      final copy = await from.copy(to);
      await from.delete();
      return copy.path;
    }
  }

  static String _newId() {
    final random = Random().nextInt(1 << 30).toRadixString(36);
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$random';
  }

  Future<void> update(
    LocalBook book, {
    required String title,
    required List<String> authors,
    required List<String> narrators,
  }) async {
    book
      ..title = title
      ..authors = authors
      ..narrators = narrators;
    await _save();
  }

  /// Forgets the book; files the app copied in are deleted, the user's own files are not.
  Future<void> remove(LocalBook book) async {
    _books.remove(book);
    await _save();
    if (book.owned) {
      final dir = Directory('${_dir.path}/${book.id}');
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    final cover = book.cover;
    if (cover != null && cover.startsWith(_coverDir)) {
      await File(cover).delete().catchError((_) => File(cover));
    }
  }

  Future<void> _save() async {
    await _dir.create(recursive: true);
    final tmp = File('${_index.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final b in _books) b.toJson()]));
    await tmp.rename(_index.path);
    revision++;
    notifyListeners();
  }
}

/// The local library as a source the rest of the app can browse, search and play.
class LocalBackend implements AddonBackend {
  LocalBackend(this.library);

  final LocalLibrary library;

  static const id = 'shu.local';
  static const _page = 40;

  static const manifest = Manifest(
    id: id,
    name: 'On this device',
    version: '1',
    description: 'Audiobooks you added from this device.',
    catalogs: [
      CatalogInfo(id: 'all', name: 'On this device', search: false),
      CatalogInfo(id: 'search', name: 'On this device', search: true),
    ],
  );

  @override
  Future<CatalogPage> catalog(
    String catalogId, {
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    var books = library.books;
    final query = search?.trim().toLowerCase();
    if (query != null && query.isNotEmpty) {
      books = books
          .where(
            (b) => [
              b.title,
              ...b.authors,
              ...b.narrators,
            ].any((s) => s.toLowerCase().contains(query)),
          )
          .toList();
    }
    final page = books.skip(skip).take(_page);
    return (
      books: [for (final b in page) b.summary],
      hasMore: skip + _page < books.length,
    );
  }

  @override
  Future<Book> book(String bookId) async =>
      (library.byId(bookId) ??
              (throw AddonException('This book is no longer on this device.')))
          .book;

  @override
  Future<SourceList> sources(String bookId, String chapterId) async {
    final book = library.byId(bookId);
    final index = int.tryParse(chapterId.split('@').first);
    if (book == null || index == null || index >= book.files.length) {
      return const SourceList([], 'This book is no longer on this device.');
    }
    final file = File(book.files[index].path);
    if (!await file.exists()) {
      return SourceList(const [], 'The file ${file.path} is missing.');
    }
    return SourceList([
      Source(
        id: 'file',
        name: 'this device',
        url: Uri.file(file.path).toString(),
      ),
    ], null);
  }

  @override
  Future<List<BookSummary>> releases(Book work) async => const [];

  @override
  Future<Resolved> resolve(Source source) async => Playable(source.url!);

  @override
  void dispose() {}
}
