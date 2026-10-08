import 'models.dart';

class AddonException implements Exception {
  AddonException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What the app needs from a content provider. Implemented by remote addons (HTTP) and by
/// extensions (JavaScript running on the device).
abstract interface class AddonBackend {
  Future<CatalogPage> catalog(
    String catalogId, {
    String? search,
    String? genre,
    int skip = 0,
  });

  Future<Book> book(String bookId);

  Future<SourceList> sources(String bookId, String chapterId);

  /// Playable versions of a book from a catalog extension (empty unless [Manifest.releases]).
  Future<List<BookSummary>> releases(Book work);

  /// A source's playable URL, or "still downloading".
  Future<Resolved> resolve(Source source);

  /// Frees what the backend holds (connections, a JS engine).
  void dispose();
}
