import 'dart:convert';

import 'package:audiobooks/addons/models.dart';
import 'package:audiobooks/library/library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const book = Book(
  id: 'b1',
  title: 'Book',
  chapters: [
    Chapter(id: '0', title: 'One'),
    Chapter(id: '1', title: 'Two'),
    Chapter(id: '2', title: 'Three'),
  ],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('progress survives a restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LibraryStore(prefs);
    final entry = store.entryFor('addon', book)
      ..chapterIndex = 2
      ..position = const Duration(minutes: 3)
      ..sourceId = 'mirror';
    await store.save(entry);

    final reloaded = LibraryStore(prefs).find('addon', 'b1');
    expect(reloaded, isNotNull);
    expect(reloaded!.chapterIndex, 2);
    expect(reloaded.position, const Duration(minutes: 3));
    expect(reloaded.sourceId, 'mirror');
    expect(reloaded.book.chapters.length, 3);
    expect(reloaded.progress, closeTo(2 / 3, 0.001));
  });

  test('progress counts the position inside the chapter', () {
    LibraryEntry at(Book b, int chapter, int minutes) => LibraryEntry(
      addonId: 'a',
      book: b,
      chapterIndex: chapter,
      position: Duration(minutes: minutes),
    );
    const timed = Book(
      id: 't',
      title: 'Timed',
      chapters: [
        Chapter(id: '0', title: 'One', duration: 600),
        Chapter(id: '1', title: 'Two', duration: 600),
      ],
    );
    expect(at(timed, 1, 5).progress, closeTo(0.75, 0.001));
    // Chapters inside one file: the position counts from the chapter's start.
    const m4b = Book(
      id: 'm',
      title: 'M4B',
      chapters: [
        Chapter(id: '0', title: 'One', duration: 600, file: 'f'),
        Chapter(
          id: '1',
          title: 'Two',
          duration: 600,
          file: 'f',
          start: Duration(minutes: 10),
        ),
      ],
    );
    expect(at(m4b, 1, 15).progress, closeTo(0.75, 0.001));
    // One file of unknown length: the book's length from the catalog.
    const single = Book(
      id: 's',
      title: 'Single',
      durationMinutes: 100,
      chapters: [Chapter(id: '-1', title: 'All')],
    );
    expect(at(single, 0, 25).progress, closeTo(0.25, 0.001));
  });

  test('a book that lost chapters keeps a valid chapter index', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LibraryStore(prefs);
    await store.save(store.entryFor('addon', book)..chapterIndex = 2);

    const shorter = Book(
      id: 'b1',
      title: 'Book',
      chapters: [Chapter(id: '0', title: 'One')],
    );
    expect(store.entryFor('addon', shorter).chapterIndex, 0);
    const none = Book(id: 'b1', title: 'Book', chapters: []);
    expect(store.entryFor('addon', none).chapterIndex, 0);
  });

  test('entries are listed most recent first and can be removed', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LibraryStore(prefs);
    final first = store.entryFor('addon', book);
    await store.save(first);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    const other = Book(
      id: 'b2',
      title: 'Other',
      chapters: [Chapter(id: '0', title: 'One')],
    );
    await store.save(store.entryFor('addon', other));

    expect(store.entries.map((e) => e.book.id), ['b2', 'b1']);
    await store.remove(first);
    expect(LibraryStore(prefs).entries.map((e) => e.book.id), ['b2']);
  });

  test('bookmarks and history survive a restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LibraryStore(prefs);
    final entry = store.entryFor('addon', book)
      ..chapterIndex = 1
      ..position = const Duration(minutes: 2);
    entry.bookmarks.add(entry.here(note: 'The twist'));
    for (var i = 0; i < 12; i++) {
      entry.remember(
        Mark(
          chapterIndex: 0,
          position: Duration(seconds: i),
          createdAt: DateTime(2026),
        ),
      );
    }
    await store.save(entry);

    final reloaded = LibraryStore(prefs).find('addon', 'b1')!;
    expect(reloaded.bookmarks.single.note, 'The twist');
    expect(reloaded.bookmarks.single.chapterIndex, 1);
    expect(reloaded.bookmarks.single.position, const Duration(minutes: 2));
    expect(reloaded.history.length, LibraryEntry.historyLength);
    expect(reloaded.history.first.position, const Duration(seconds: 11));
  });

  test('marks outside a book that now has fewer chapters are dropped', () {
    final json = LibraryEntry(addonId: 'a', book: book).toJson()
      ..['bookmarks'] = [
        {'chapter': 2, 'positionMs': 1000, 'at': '2026-01-01T00:00:00Z'},
        {'chapter': 9, 'positionMs': 1000, 'at': '2026-01-01T00:00:00Z'},
        {'chapter': 'bad'},
      ];
    final entry = LibraryEntry.fromJson(json);
    expect(entry.bookmarks.map((m) => m.chapterIndex), [2]);
    // Entries saved before bookmarks existed load with none.
    expect(
      LibraryEntry.fromJson(LibraryEntry(addonId: 'a', book: book).toJson())
          .history,
      isEmpty,
    );
  });

  test('saving splices the encoded book in: same data as toJson', () {
    final entry = LibraryEntry(addonId: 'a', book: book, workKey: 'w|1')
      ..chapterIndex = 1
      ..position = const Duration(seconds: 42);
    entry.bookmarks.add(entry.here(note: 'Here "quoted"'));
    expect(jsonDecode(entry.encode()), jsonDecode(jsonEncode(entry.toJson())));
    // Encoded again after a change, the place follows (the book is reused).
    entry.position = const Duration(seconds: 50);
    expect((jsonDecode(entry.encode()) as Map)['positionMs'], 50000);
  });

  test('the newest first, also right after a save', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LibraryStore(prefs);
    final first = store.entryFor('addon', book);
    await store.save(first);
    final second = store.entryFor(
      'addon',
      const Book(
        id: 'b2',
        title: 'Two',
        chapters: [Chapter(id: '0', title: 'x')],
      ),
    );
    await store.save(second);
    expect(store.entries.map((e) => e.book.id), ['b2', 'b1']);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.save(first);
    expect(store.entries.map((e) => e.book.id), ['b1', 'b2']);
    expect(LibraryStore(prefs).entries.map((e) => e.book.id), [
      'b1',
      'b2',
    ], reason: 'what was written reads back');
  });

  test('an entry this version can\'t read is kept on the next save', () async {
    final prefs = await SharedPreferences.getInstance();
    await LibraryStore(prefs).save(LibraryStore(prefs).entryFor('addon', book));
    const unknown = {'book': 'from a newer version', 'addonId': 'addon'};
    await prefs.setString(
      'library',
      '[${jsonEncode(unknown)},${prefs.getString('library')!.substring(1)}',
    );

    final store = LibraryStore(prefs);
    expect(store.entries.map((e) => e.book.id), ['b1']);
    await store.save(store.find('addon', 'b1')!);
    final saved = jsonDecode(prefs.getString('library')!) as List;
    expect(saved.first, unknown);
    expect(LibraryStore(prefs).find('addon', 'b1'), isNotNull);
  });

  test('a damaged library is set aside, not lost', () async {
    SharedPreferences.setMockInitialValues({'library': '[{"book":'});
    final prefs = await SharedPreferences.getInstance();
    expect(LibraryStore(prefs).entries, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString('library.bad'), '[{"book":');
  });
}
