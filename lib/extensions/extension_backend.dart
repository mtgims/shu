import '../addons/backend.dart';
import '../addons/models.dart';
import 'engine.dart';

/// An extension: JavaScript on this device implementing docs/EXTENSIONS.md.
class ExtensionBackend implements AddonBackend {
  ExtensionBackend(this.engine);

  final ExtensionEngine engine;

  Future<Map<String, dynamic>> _call(String method, List<Object?> args) async {
    final value = await engine.call(method, args);
    if (value is! Map<String, dynamic>) {
      throw AddonException(
        'The extension sent an unreadable reply to $method().',
      );
    }
    return value;
  }

  @override
  Future<CatalogPage> catalog(
    String catalogId, {
    String? search,
    String? genre,
    int skip = 0,
  }) async => catalogPageFromJson(
    await _call('catalog', [
      catalogId,
      {'search': search, 'genre': genre, 'skip': skip},
    ]),
  );

  @override
  Future<List<BookSummary>> releases(Book work) async {
    final query = {
      'title': work.title,
      'authors': work.authors,
      'narrators': work.narrators,
      'durationMinutes': work.durationMinutes,
      'year': work.year,
    };
    return catalogPageFromJson(await _call('releases', [query])).books;
  }

  @override
  Future<Book> book(String bookId) async {
    final json = await _call('book', [bookId]);
    try {
      return Book.fromJson(json);
    } on Object catch (e) {
      throw AddonException('The extension sent a broken book: $e');
    }
  }

  @override
  Future<SourceList> sources(String bookId, String chapterId) async =>
      SourceList.fromJson(await _call('sources', [bookId, chapterId]));

  @override
  Future<Resolved> resolve(Source source) async {
    if (source.url != null) return Playable(source.url!);
    final json = await _call('resolve', [source.resolve]);
    return resolvedFromJson(json) ??
        (throw AddonException('The extension gave no playable link.'));
  }

  @override
  void dispose() => engine.dispose();
}
