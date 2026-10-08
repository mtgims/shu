import 'package:audiobooks/addons/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a saved extension manifest keeps its settings, genres and releases flag',
    () {
      final manifest = Manifest.fromExtensionJson({
        'id': 'x.catalog',
        'name': 'Catalog',
        'version': '1.0.0',
        'releases': true,
        'catalogs': [
          {
            'id': 'genres',
            'name': 'Browse by genre',
            'genres': ['Fantasy', 'Romance'],
          },
        ],
        'settings': [
          {
            'key': 'region',
            'label': 'Store',
            'type': 'select',
            'default': 'us',
          },
        ],
      });
      // Saved to preferences and read back after a restart.
      final restored = Manifest.fromJson(manifest.toJson());
      expect(restored.settings.single.key, 'region');
      expect(restored.defaultSettings, {'region': 'us'});
      expect(restored.catalogs.single.genres, ['Fantasy', 'Romance']);
      expect(restored.releases, isTrue);
    },
  );

  test('a catalog book has no chapters and carries listening details', () {
    final work = Book.fromJson({
      'id': 'ol:OL82563W',
      'title': "Harry Potter and the Philosopher's Stone",
      'authors': ['J. K. Rowling'],
      'narrators': ['Stephen Fry'],
      'cover': 'https://example.com/hp.jpg',
      'durationMinutes': 505,
      'rating': 4.9,
      'genres': ['Fantasy'],
      'series': 'Harry Potter, book 1',
      'chapters': <Object>[],
    });
    expect(work.isWork, isTrue);
    expect(work.durationMinutes, 505);
    expect(work.rating, 4.9);
    expect(Book.fromJson(work.toJson()).series, 'Harry Potter, book 1');
  });

  test(
    'a version takes the catalog look and keeps its own chapters and details',
    () {
      const work = Book(
        id: 'ol:1',
        title: 'Dune',
        authors: ['Frank Herbert'],
        narrators: ['Scott Brick'],
        cover: 'https://example.com/square.jpg',
        description: 'A desert planet.',
        durationMinutes: 1262,
        chapters: [],
      );
      const release = Book(
        id: 'lib:abc',
        title: 'Frank Herbert - Dune (Unabridged) [MP3]',
        tags: ['MP3'],
        details: '64 kbps · Example Library',
        chapters: [Chapter(id: '0', title: 'Part 1')],
      );
      final dressed = release.withLookOf(work);
      expect(dressed.id, 'lib:abc');
      expect(dressed.title, 'Dune');
      expect(dressed.narrators, ['Scott Brick']);
      expect(dressed.cover, 'https://example.com/square.jpg');
      expect(dressed.details, '64 kbps · Example Library');
      expect(dressed.chapters.single.title, 'Part 1');
      expect(dressed.isWork, isFalse);
    },
  );
}
