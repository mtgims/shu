import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/content_cache.dart';
import '../addons/models.dart';
import '../app.dart';
import '../library/library_store.dart';
import '../widgets/book_tiles.dart';
import 'add_books.dart';
import 'addons_screen.dart';
import 'catalog_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Bumped by pull-to-refresh so every catalog row loads again.
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Shu')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          scope.addons,
          scope.library,
          scope.addons.local,
        ]),
        builder: (context, _) {
          final addons = scope.addons.addons;
          final inProgress = scope.library.entries
              .where((e) => !e.finished)
              .take(12)
              .toList();
          final local = scope.addons.local;
          if (local.books.isEmpty && addons.every((a) => a.isLocal)) {
            return const _Welcome();
          }

          // Catalog extensions first; sources (which find versions to play) after.
          final ordered = [
            ...addons.where((a) => !a.manifest.releases),
            ...addons.where((a) => a.manifest.releases),
          ];
          // Rows with the same name (a library called "Audiobooks" on two servers) say where
          // they come from.
          final names = <String, int>{};
          for (final a in ordered) {
            for (final c in a.manifest.catalogs.where((c) => !c.search)) {
              names[c.name] = (names[c.name] ?? 0) + 1;
            }
          }
          String titleOf(InstalledAddon a, CatalogInfo c) =>
              names[c.name]! > 1 ? '${c.name} · ${a.manifest.name}' : c.name;
          final rows = <Widget Function()>[
            if (inProgress.isNotEmpty)
              () => _continueListening(context, inProgress),
            for (final addon in ordered)
              for (final catalog in addon.manifest.catalogs.where(
                (c) => !c.search,
              ))
                catalog.genres.isNotEmpty
                    ? () => _GenreRow(addon: addon, catalog: catalog)
                    : () => _CatalogRow(
                        key: ValueKey(
                          '${addon.id}/${catalog.id}/$_generation/'
                          '${addon.isLocal ? local.revision : 0}',
                        ),
                        addon: addon,
                        catalog: catalog,
                        title: titleOf(addon, catalog),
                      ),
          ];

          return RefreshIndicator(
            onRefresh: () async => setState(() => _generation++),
            // Built lazily: rows further down load when they are scrolled to.
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: rows.length,
              itemBuilder: (_, i) => rows[i](),
            ),
          );
        },
      ),
    );
  }

  Widget _continueListening(BuildContext context, List<LibraryEntry> entries) {
    final scope = AppScope.of(context);
    return CardRow(
      title: 'Continue listening',
      children: [
        for (final entry in entries)
          BookCard(
            title: entry.book.title,
            subtitle: entry.book.chapters.length > 1
                ? 'Chapter ${entry.chapterIndex + 1} of ${entry.book.chapters.length}'
                : entry.book.byline,
            cover: entry.book.cover,
            progress: entry.progress,
            onTap: () {
              final addon = scope.addons.byId(entry.addonId);
              if (addon != null) openEntry(context, addon, entry);
            },
          ),
      ],
    );
  }
}

/// A catalog with genres to pick from: one chip per genre, each opening its list.
class _GenreRow extends StatelessWidget {
  const _GenreRow({required this.addon, required this.catalog});

  final InstalledAddon addon;
  final CatalogInfo catalog;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            catalog.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: catalog.genres.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ActionChip(
              label: Text(catalog.genres[i]),
              onPressed: () => Navigator.of(context).push(
                CatalogScreen.route(addon, catalog, genre: catalog.genres[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogRow extends StatefulWidget {
  const _CatalogRow({
    super.key,
    required this.addon,
    required this.catalog,
    required this.title,
  });

  final InstalledAddon addon;
  final CatalogInfo catalog;
  final String title;

  @override
  State<_CatalogRow> createState() => _CatalogRowState();
}

/// Shows the catalog as it was last seen right away, then swaps in the fresh one.
class _CatalogRowState extends State<_CatalogRow> {
  List<BookSummary>? _books;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final addon = widget.addon;
    final id = widget.catalog.id;
    final last = await ContentCache.lastCatalog(addon.id, id);
    if (mounted && last != null && _books == null) {
      setState(() => _books = last);
    }
    try {
      final fresh = (await addon.client.catalog(id)).books;
      if (!mounted) return;
      setState(() => _books = fresh);
      await ContentCache.saveCatalog(addon.id, id, fresh);
    } on Object catch (e) {
      // With a list on screen already, an offline refresh is not worth an error.
      if (mounted && _books == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final books = _books;
    if (books == null && _error != null) {
      return ListTile(
        title: Text(title),
        subtitle: Text('Could not load: $_error'),
        leading: const Icon(Icons.cloud_off),
      );
    }
    if (books == null) {
      return CardRow(
        title: title,
        children: const [
          SizedBox(
            width: BookCard.rowWidth,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (books.isEmpty) return const SizedBox.shrink();
    return CardRow(
      title: title,
      trailing: TextButton(
        onPressed: () =>
            Navigator.of(context)
                .push(CatalogScreen.route(widget.addon, widget.catalog)),
        child: const Text('See all'),
      ),
      children: [
        for (final book in books)
          BookCard(
            title: book.title,
            subtitle: book.byline.isEmpty ? book.tags.join(' · ') : book.byline,
            cover: book.cover,
            onTapDown: () => ContentCache.book(widget.addon, book.id),
            onTap: () => openBook(context, widget.addon, book),
          ),
      ],
    );
  }
}

/// The first screen: nothing to show until the user adds books, a server or an extension.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.headphones,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome to Shu',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Add audiobooks you have as files, sign in to your Audiobookshelf or Jellyfin '
                'server, or add an extension.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => addBooksFromDevice(context),
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Add audiobooks from this device'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showAddSource(context),
                icon: const Icon(Icons.dns_outlined),
                label: const Text('Add a server or extension'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
