import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../sources/local_library.dart';
import '../widgets/book_tiles.dart';
import '../widgets/cover.dart';
import 'add_books.dart';

/// Every book the user has started, most recent first, then the books added from this device
/// that haven't been started yet.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      // Tabs stay alive side by side, so their buttons must not share a hero tag.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => addBooksFromDevice(context),
        icon: const Icon(Icons.add),
        label: const Text('Add audiobooks'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([scope.library, scope.addons.local]),
        builder: (context, _) {
          final entries = scope.library.entries;
          final unstarted = [
            for (final b in scope.addons.local.books)
              if (scope.library.find(LocalBackend.id, b.id) == null) b,
          ];
          if (entries.isEmpty && unstarted.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Books you start listening to show up here. Audiobooks you have as files can '
                  'be added with the button below.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
            children: [
              for (final entry in entries) ...[
                _EntryTile(entry: entry),
                const SizedBox(height: 4),
              ],
              if (unstarted.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'On this device',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                for (final book in unstarted) _LocalTile(book: book),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A book added from this device that hasn't been played yet.
class _LocalTile extends StatelessWidget {
  const _LocalTile({required this.book});
  final LocalBook book;

  @override
  Widget build(BuildContext context) {
    final local = AppScope.of(context).addons.byId(LocalBackend.id);
    final summary = book.summary;
    return ListTile(
      leading: BookCover(
        title: book.title,
        url: summary.cover,
        size: 56,
        radius: 8,
      ),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (summary.byline.isNotEmpty) summary.byline,
          book.files.length == 1 ? '1 file' : '${book.files.length} files',
        ].join(' · '),
      ),
      onTap: local == null ? null : () => openBook(context, local, summary),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    final addon = scope.addons.byId(entry.addonId);
    final chapters = entry.book.chapters.length;
    final where = entry.finished
        ? 'Finished'
        : chapters == 1
        ? 'At ${formatDuration(entry.position)}'
        : 'Chapter ${entry.chapterIndex + 1} of $chapters · ${formatDuration(entry.position)}';
    return ListTile(
      leading: BookCover(
        title: entry.book.title,
        url: entry.book.cover,
        size: 56,
        radius: 8,
      ),
      title: Text(
        entry.book.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(addon == null ? '$where · addon removed' : where),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: entry.progress,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
      isThreeLine: true,
      onTap: addon == null ? null : () => openEntry(context, addon, entry),
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (action) async {
          if (action == 'remove') {
            if (scope.player.current.value?.key == entry.key) {
              await scope.player.stop();
            }
            await scope.library.remove(entry);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'remove',
            child: Text(
              'Remove from library',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
