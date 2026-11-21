import 'package:audiobooks/addons/models.dart';
import 'package:audiobooks/library/library_store.dart';
import 'package:audiobooks/widgets/book_tiles.dart';
import 'package:audiobooks/widgets/title_parts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('edition notes leave the title as labels', () {
    final red = splitTitle('Red Rising (Part 1 of 2) (Dramatized Adaptation)');
    expect(red.title, 'Red Rising');
    expect(red.labels, ['Part 1 of 2', 'Full cast']);
    expect(splitTitle('Dune [Unabridged]').title, 'Dune');
    expect(splitTitle('Dune [Unabridged]').labels, isEmpty);
    expect(splitTitle('The Way of Kings (Book 1)').labels, ['Book 1']);
    expect(splitTitle('Berserk Vol. 3 (Vol 3/41)').labels, ['Vol. 3 of 41']);
    // Brackets that aren't edition notes stay.
    expect(
      splitTitle('Leviathan Wakes (The Expanse)').title,
      'Leviathan Wakes (The Expanse)',
    );
    expect(splitTitle('(Unabridged)').title, '(Unabridged)');
  });

  test(
    'time left is estimated from the book length when chapters have none',
    () {
      final book = Book(
        id: 'b',
        title: 'Long',
        durationMinutes: 600,
        chapters: [for (var i = 0; i < 10; i++) Chapter(id: '$i', title: '$i')],
      );
      final entry = LibraryEntry(addonId: 'a', book: book, chapterIndex: 4);
      expect(timeLeftText(entry, 1), 'About 6 h left');
      expect(timeLeftText(entry, 2), 'About 3 h left');
      final unknown = LibraryEntry(
        addonId: 'a',
        book: Book(id: 'c', title: 'C', chapters: book.chapters),
        chapterIndex: 4,
      );
      expect(timeLeftText(unknown, 1), isNull);
    },
  );
}
