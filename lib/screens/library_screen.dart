import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../sources/local_library.dart';
import '../widgets/adaptive.dart';
import '../widgets/book_tiles.dart';
import '../widgets/cover.dart';
import '../widgets/more_menu.dart';
import 'add_books.dart';

/// Every book the user has started, most recent first, then the books added from this device
/// that haven't been started yet.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _Show { all, listening, finished }

class _LibraryScreenState extends State<LibraryScreen> {
  var _show = _Show.all;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        titleSpacing: 16 + readableInset(context),
      ),
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
          final all = scope.library.entries;
          final entries = switch (_show) {
            _Show.all => all,
            _Show.listening => [
              for (final e in all)
                if (!e.finished) e,
            ],
            _Show.finished => [
              for (final e in all)
                if (e.finished) e,
            ],
          };
          final unstarted = [
            for (final b in scope.addons.local.books)
              if (scope.library.find(LocalBackend.id, b.id) == null) b,
          ];
          if (all.isEmpty && unstarted.isEmpty) {
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
          final side = readableInset(context);
          // Rows keep 8 from the window's edges (their highlight is rounded), and 8 less
          // padding inside, so their text still lines up with the title.
          return ListTileTheme.merge(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView(
              padding: EdgeInsets.fromLTRB(8 + side, 8, 8 + side, 96),
              children: [
                // Filters only help once there is something to sort through.
                if (all.length >= 4) ...[
                  _Filters(
                    show: _show,
                    onChanged: (s) => setState(() => _show = s),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final entry in entries) ...[
                  _EntryTile(entry: entry),
                  const SizedBox(height: 4),
                ],
                if (unstarted.isNotEmpty && _show != _Show.finished) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
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
            ),
          );
        },
      ),
    );
  }
}

/// All, in progress or finished books.
class _Filters extends StatelessWidget {
  const _Filters({required this.show, required this.onChanged});
  final _Show show;
  final ValueChanged<_Show> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Wrap(
      spacing: 8,
      children: [
        for (final (s, label) in const [
          (_Show.all, 'All'),
          (_Show.listening, 'Listening'),
          (_Show.finished, 'Finished'),
        ])
          ChoiceChip(
            label: Text(label),
            selected: show == s,
            onSelected: (_) => onChanged(s),
          ),
      ],
    ),
  );
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
    final addon = scope.addons.byId(entry.addonId);
    final chapters = entry.book.chapters.length;
    final where = entry.finished
        ? 'Finished'
        : chapters == 1
        ? 'At ${formatDuration(entry.position)}'
        : 'Chapter ${entry.chapterIndex + 1} of $chapters · ${formatDuration(entry.position)}';
    Future<void> remove() async {
      if (scope.player.current.value?.key == entry.key) {
        await scope.player.stop();
      }
      await scope.library.remove(entry);
    }

    List<Widget> menu() => [
      MenuItemButton(
        onPressed: () => scope.player.markFinished(entry, !entry.finished),
        child: Text(
          entry.finished ? 'Mark as not finished' : 'Mark as finished',
        ),
      ),
      removeItem(context, 'Remove from library', remove),
    ];

    // Right-click opens the same menu as the ⋮ button, where the pointer is.
    return MenuAnchor(
      menuChildren: menu(),
      builder: (context, rightClick, child) => GestureDetector(
        onSecondaryTapUp: (d) => rightClick.open(position: d.localPosition),
        child: child,
      ),
      child: ListTile(
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
        trailing: MoreMenu(items: menu()),
      ),
    );
  }
}
