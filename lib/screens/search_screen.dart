import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/models.dart';
import '../app.dart';
import '../widgets/book_tiles.dart';

/// One search catalog's results.
class _Section {
  _Section(this.addon, this.catalog, this.results);
  final InstalledAddon addon;
  final CatalogInfo catalog;
  final Future<List<BookSummary>> results;
}

/// Searches every search catalog of every installed addon at once.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<_Section> _sections = [];

  void _search(String text) {
    final query = text.trim();
    if (query.isEmpty) return;
    final all = AppScope.of(context).addons.addons;
    // Catalog results (books with covers and narrators) before results from sources.
    final addons = [
      ...all.where((a) => !a.manifest.releases),
      ...all.where((a) => a.manifest.releases),
    ];
    setState(() {
      _sections = [
        for (final addon in addons)
          for (final catalog in addon.manifest.catalogs.where((c) => c.search))
            _Section(
              addon,
              catalog,
              addon.client
                  .catalog(catalog.id, search: query)
                  .then((r) => r.books),
            ),
      ];
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSearchable = AppScope.of(context).addons.addons
        .any((a) => a.manifest.catalogs.any((c) => c.search));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Title, author or narrator',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _search(_controller.text),
                ),
              ),
            ),
          ),
        ),
      ),
      body: !hasSearchable
          ? const _Hint('Install an addon that supports search first.')
          : _sections.isEmpty
          ? const _Hint('Search all your addons at once.')
          // Slivers build rows lazily: covers further down load only when scrolled to.
          : CustomScrollView(
              slivers: [
                for (final section in _sections)
                  _SectionView(key: ObjectKey(section), section: section),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({super.key, required this.section});
  final _Section section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label =
        section.addon.manifest.catalogs.where((c) => c.search).length > 1
        ? '${section.addon.manifest.name} · ${section.catalog.name}'
        : section.addon.manifest.name;
    return FutureBuilder(
      future: section.results,
      builder: (context, snap) {
        final books = snap.data;
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  books != null ? '$label (${books.length})' : label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            if (snap.hasError)
              SliverToBoxAdapter(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off),
                  title: Text('${snap.error}'),
                ),
              )
            else if (books == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
              )
            else if (books.isEmpty)
              const SliverToBoxAdapter(
                child: ListTile(title: Text('Nothing found.')),
              )
            else
              SliverList.builder(
                itemCount: books.length,
                itemBuilder: (_, i) =>
                    BookListTile(addon: section.addon, book: books[i]),
              ),
          ],
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
