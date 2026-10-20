import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/content_cache.dart';
import '../addons/models.dart';
import '../widgets/book_tiles.dart';
import '../widgets/mini_player.dart';

/// A whole catalog (or one genre of it) as a grid that loads more as you scroll.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.addon,
    required this.catalog,
    required this.title,
    this.genre,
  });

  final InstalledAddon addon;
  final CatalogInfo catalog;
  final String title;
  final String? genre;

  static Route<void> route(
    InstalledAddon addon,
    CatalogInfo catalog, {
    String? genre,
  }) => MaterialPageRoute(
    builder: (_) => CatalogScreen(
      addon: addon,
      catalog: catalog,
      genre: genre,
      title: genre ?? catalog.name,
    ),
  );

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _books = <BookSummary>[];
  final _scroll = ScrollController();

  /// How many books the source has sent, counting the duplicates left out of [_books].
  int _skip = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Loads on when the books are near the end of the view; a page that doesn't fill a large
  /// window gives no scrolling to wait for.
  void _moreWhenShort() {
    if (_error == null &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 800) {
      _more();
    }
  }

  Future<void> _more() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.addon.client.catalog(
        widget.catalog.id,
        genre: widget.genre,
        skip: _skip,
      );
      if (!mounted) return;
      final seen = {for (final b in _books) b.id};
      setState(() {
        _skip += page.books.length;
        _books.addAll(page.books.where((b) => seen.add(b.id)));
        _hasMore = page.hasMore && page.books.isNotEmpty;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moreWhenShort();
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Playback stays at hand on pages opened over the main screen.
      bottomNavigationBar: const MiniPlayer(),
      appBar: AppBar(title: Text(widget.title)),
      body: NotificationListener<ScrollNotification>(
        // Start the next page well before the end, so scrolling rarely stops. After an error
        // only "Try again" loads, so scrolling doesn't keep asking.
        onNotification: (n) {
          if (n.depth == 0) _moreWhenShort();
          return false;
        },
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              // Cells are as tall as their cover (square, as wide as the cell) plus two lines of
              // title and one of author, so rows sit close on any screen width.
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.crossAxisExtent / 170)
                      .ceil()
                      .clamp(2, 12);
                  final cellWidth =
                      (constraints.crossAxisExtent - (columns - 1) * 4) /
                      columns;
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: cellWidth + 76,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _books.length,
                    itemBuilder: (context, i) {
                      final book = _books[i];
                      return BookCard(
                        width: double.infinity,
                        title: book.title,
                        subtitle: book.byline.isEmpty
                            ? book.details
                            : book.byline,
                        cover: book.cover,
                        onTapDown: () =>
                            ContentCache.book(widget.addon, book.id),
                        onTap: () => openBook(context, widget.addon, book),
                      );
                    },
                  );
                },
              ),
            ),
            SliverToBoxAdapter(child: _footer(context)),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    if (_error != null) {
      return ListTile(
        leading: const Icon(Icons.cloud_off),
        title: Text('$_error'),
        trailing: TextButton(onPressed: _more, child: const Text('Try again')),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_books.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Nothing here.')),
      );
    }
    return const SizedBox(height: 24);
  }
}
