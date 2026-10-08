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
}
