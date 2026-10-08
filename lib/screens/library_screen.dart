import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../widgets/book_tiles.dart';
import '../widgets/cover.dart';

/// Every book the user has started, most recent first.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListenableBuilder(
        listenable: scope.library,
        builder: (context, _) {
          final entries = scope.library.entries;
          if (entries.isEmpty) {
            return Center(
              child: Text(
                'Books you start listening to show up here.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) => _EntryTile(entry: entries[i]),
          );
        },
      ),
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
