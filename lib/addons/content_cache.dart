import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'addon_store.dart';
import 'models.dart';

/// What lets screens show something at once instead of waiting on the network: the last-known
/// catalogs on disk, and recently opened (or about to be opened) books in memory.
class ContentCache {
  ContentCache._();

  static Future<Directory>? _dir;

  static Future<Directory> _catalogDir() => _dir ??= () async {
    final dir = Directory(
      '${(await getApplicationCacheDirectory()).path}/catalogs',
    );
    await dir.create(recursive: true);
    return dir;
  }();

  static String _safe(String s) => s.replaceAll(RegExp(r'[^\w.-]'), '_');

  static Future<File> _catalogFile(
    String addonId,
    String catalogId,
  ) async => File(
    '${(await _catalogDir()).path}/${_safe(addonId)}__${_safe(catalogId)}.json',
  );

  /// The catalog as it was last seen, or null.
  static Future<List<BookSummary>?> lastCatalog(
    String addonId,
    String catalogId,
  ) async {
    try {
      final file = await _catalogFile(addonId, catalogId);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as List;
      return json
          .whereType<Map<String, dynamic>>()
          .map(BookSummary.fromJson)
          .toList();
    } on Object catch (e) {
      debugPrint('Unreadable catalog cache: $e');
      return null;
    }
  }

  static Future<void> saveCatalog(
    String addonId,
    String catalogId,
    List<BookSummary> books,
  ) async {
    final file = await _catalogFile(addonId, catalogId);
    await file.writeAsString(jsonEncode([for (final b in books) b.toJson()]));
  }

  /// Recently requested books, newest last. Small: books are a few kilobytes.
  static final _books = <String, Future<Book>>{};
  static const _maxBooks = 30;

  /// The book, loading it only if it isn't loaded or loading already. Starting this when the
  /// user touches a result (before the tap completes) hides most of the wait.
  static Future<Book> book(InstalledAddon addon, String bookId) {
    final key = '${addon.id}|$bookId';
    final hit = _books.remove(key);
    final future = hit ?? addon.client.book(bookId);
    _books[key] = future;
    if (_books.length > _maxBooks) _books.remove(_books.keys.first);
    // A failed load must not stick: the next request tries again.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_books[key], future)) _books.remove(key);
        },
      ),
    );
    return future;
  }

  static void forgetBook(InstalledAddon addon, String bookId) =>
      _books.remove('${addon.id}|$bookId');
}
