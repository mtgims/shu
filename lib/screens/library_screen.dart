import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../sources/local_library.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/book_tiles.dart';
import '../widgets/cover.dart';
import '../widgets/download_button.dart';
import '../widgets/more_menu.dart';
import 'add_books.dart';
import 'downloads_panel.dart';

/// Every book the user has started, most recent first, then the books added from this device
/// that haven't been started yet. A list, or in wide windows a grid of covers if chosen.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _Show { all, listening, finished, downloaded }

class _LibraryScreenState extends State<LibraryScreen> {
  var _show = _Show.all;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.player.settings;
    final theme = Theme.of(context);
    final wide = isWide(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.library,
        scope.addons.local,
        scope.downloads,
        settings,
      ]),
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
          _Show.downloaded => [
            for (final e in all)
              if (scope.downloads.progressOf(e.key) != null) e,
          ],
        };
        final unstarted = [
          for (final b in scope.addons.local.books)
            if (scope.library.find(LocalBackend.id, b.id) == null) b,
        ];
        final grid = wide && settings.libraryGrid;
        // Filters only help once there is something to sort through.
        final filters = all.length >= 4
            ? _Filters(show: _show, onChanged: (s) => setState(() => _show = s))
            : null;
        // A little wider than other pages: the top bar holds the filters too.
        final side = readableInset(context, maxWidth: 1100);
        final showUnstarted =
            unstarted.isNotEmpty &&
            (_show == _Show.all || _show == _Show.listening);

        final Widget body;
        if (all.isEmpty && unstarted.isEmpty) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Books you start listening to show up here. Audiobooks you have as files can '
                'be added with the + button at the top.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        } else {
          final heading = Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
            child: Text(
              'On this device',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          );
          // Rows keep 8 from the window's edges (their highlight is rounded), and 8 less
          // padding inside, so their text still lines up with the title.
          body = ListTileTheme.merge(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(8 + side, 8, 8 + side, 16),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      // Phones have no room for the filters in the top bar.
                      if (filters != null && !wide)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: filters,
                          ),
                        ),
                      if (grid) ...[
                        _CoverGrid(
                          count: entries.length,
                          card: (i) => _EntryCard(entry: entries[i]),
                        ),
                        if (showUnstarted) ...[
                          SliverToBoxAdapter(child: heading),
                          _CoverGrid(
                            count: unstarted.length,
                            card: (i) => _LocalCard(book: unstarted[i]),
                          ),
                        ],
                      ] else
                        SliverList.list(
                          children: [
                            for (final entry in entries) ...[
                              _EntryTile(entry: entry),
                              const SizedBox(height: 4),
                            ],
                            if (showUnstarted) ...[
                              heading,
                              for (final book in unstarted)
                                _LocalTile(book: book),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            // The side space goes inside the title: the bar takes titleSpacing off both sides
            // when it measures the title, which would leave the filters little room.
            titleSpacing: 16,
            // Wide windows: title, filters and actions on one line.
            title: Padding(
              padding: EdgeInsets.only(left: side),
              child: wide && filters != null
                  ? Row(
                      children: [
                        const Text('Library'),
                        const SizedBox(width: 24),
                        Flexible(child: filters),
                      ],
                    )
                  : const Text('Library'),
            ),
            actions: [
              IconButton(
                tooltip: 'Downloads',
                icon: const Icon(Icons.download_for_offline_outlined),
                onPressed: () => showDownloadSettings(context),
              ),
              if (wide)
                IconButton(
                  tooltip: grid ? 'Show as a list' : 'Show as a grid',
                  icon: Icon(grid ? Icons.view_list : Icons.grid_view),
                  onPressed: () => settings.libraryGrid = !grid,
                ),
              const SizedBox(width: 4),
              AddButton(
                label: 'Add audiobooks',
                onPressed: () => addBooksFromDevice(context),
              ),
              SizedBox(width: 8 + side),
            ],
          ),
          body: body,
        );
      },
    );
  }
}

/// All, in progress, finished or downloaded books.
class _Filters extends StatelessWidget {
  const _Filters({required this.show, required this.onChanged});
  final _Show show;
  final ValueChanged<_Show> onChanged;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final chips = [
      for (final (s, label) in const [
        (_Show.all, 'All'),
        (_Show.listening, 'Listening'),
        (_Show.finished, 'Finished'),
        (_Show.downloaded, 'Downloaded'),
      ])
        ChoiceChip(
          label: Text(label),
          selected: show == s,
          // The top bar has room for one line of slim chips.
          showCheckmark: !wide,
          visualDensity: wide ? VisualDensity.compact : null,
          onSelected: (_) => onChanged(s),
        ),
    ];
    if (wide) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final chip in chips) ...[chip, const SizedBox(width: 6)],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(spacing: 8, children: chips),
    );
  }
}

/// Covers in as many columns as fit, each as tall as its square cover plus three lines.
class _CoverGrid extends StatelessWidget {
  const _CoverGrid({required this.count, required this.card});
  final int count;
  final Widget Function(int) card;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.crossAxisExtent / 180).ceil().clamp(2, 12);
      final cell = (constraints.crossAxisExtent - (columns - 1) * 4) / columns;
      return SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: cell + 84,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: count,
        itemBuilder: (context, i) => card(i),
      );
    },
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
      title: Text(
        book.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: bookTitle(Theme.of(context).textTheme.titleMedium),
      ),
      subtitle: Text(_localDetails(book)),
      onTap: local == null ? null : () => openBook(context, local, summary),
    );
  }
}

class _LocalCard extends StatelessWidget {
  const _LocalCard({required this.book});
  final LocalBook book;

  @override
  Widget build(BuildContext context) {
    final local = AppScope.of(context).addons.byId(LocalBackend.id);
    return BookCard(
      width: double.infinity,
      title: book.title,
      subtitle: _localDetails(book),
      cover: book.summary.cover,
      onTap: () {
        if (local != null) openBook(context, local, book.summary);
      },
    );
  }
}

String _localDetails(LocalBook book) => [
  if (book.summary.byline.isNotEmpty) book.summary.byline,
  book.files.length == 1 ? '1 file' : '${book.files.length} files',
].join(' · ');

/// Where the listener is in [entry].
String _whereIn(LibraryEntry entry, double speed) {
  final chapters = entry.book.chapters.length;
  final left = timeLeftText(entry, speed);
  final chapter = 'Chapter ${entry.chapterIndex + 1} of $chapters';
  return entry.finished
      ? 'Finished'
      : !entry.started
      ? 'Not started'
      : chapters == 1
      ? left ?? 'At ${formatDuration(entry.position)}'
      : '$chapter · ${left ?? formatDuration(entry.position)}';
}

/// The ⋮ and right-click menu of a book in the library.
List<Widget> entryMenu(BuildContext context, LibraryEntry entry) {
  final scope = AppScope.of(context);
  Future<void> remove() async {
    if (scope.player.current.value?.key == entry.key) {
      await scope.player.stop();
    }
    await scope.library.remove(entry);
  }

  return [
    MenuItemButton(
      leadingIcon: Icon(
        entry.finished ? Icons.replay : Icons.check_circle_outline,
      ),
      onPressed: () => scope.player.markFinished(entry, !entry.finished),
      child: Text(entry.finished ? 'Mark as not finished' : 'Mark as finished'),
    ),
    ?downloadItem(context, scope.addons.byId(entry.addonId), entry),
    removeItem(
      context,
      'Remove from library',
      remove,
      icon: Icons.delete_outline,
    ),
  ];
}

/// Right-click on [child] opens [menu] where the pointer is.
Widget _withRightClickMenu(List<Widget> menu, Widget child) => MenuAnchor(
  menuChildren: menu,
  builder: (context, rightClick, child) => GestureDetector(
    onSecondaryTapUp: (d) => rightClick.open(position: d.localPosition),
    child: child,
  ),
  child: child,
);

/// The listening progress, shown only while a book is under way.
double? _progressOf(LibraryEntry entry) =>
    entry.started && !entry.finished ? entry.progress : null;

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final addon = scope.addons.byId(entry.addonId);
    final where = _whereIn(entry, scope.player.settings.speed);
    final progress = _progressOf(entry);
    final menu = entryMenu(context, entry);
    return _withRightClickMenu(
      menu,
      ListTile(
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
          style: bookTitle(Theme.of(context).textTheme.titleMedium),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (scope.downloads.isDownloaded(entry.key)) ...[
                  Icon(
                    Icons.download_done,
                    size: 16,
                    semanticLabel: 'Downloaded',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: scope.downloads.progressOf(entry.key)?.active == true
                      ? DownloadStatus(
                          bookKey: entry.key,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : Text(addon == null ? '$where · addon removed' : where),
                ),
              ],
            ),
            // Same height with or without the line, so rows stay even.
            const SizedBox(height: 4),
            SizedBox(
              height: 3,
              child: progress == null
                  ? null
                  : LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
            ),
          ],
        ),
        isThreeLine: true,
        onTap: addon == null ? null : () => openEntry(context, addon, entry),
        trailing: MoreMenu(items: menu),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final addon = scope.addons.byId(entry.addonId);
    final speed = scope.player.settings.speed;
    final downloading = scope.downloads.progressOf(entry.key)?.active == true;
    return _withRightClickMenu(
      entryMenu(context, entry),
      Stack(
        children: [
          BookCard(
            width: double.infinity,
            title: entry.book.title,
            subtitle: downloading
                ? null
                : addon == null
                ? '${_whereIn(entry, speed)} · addon removed'
                : timeLeftText(entry, speed) ?? _whereIn(entry, speed),
            cover: entry.book.cover,
            // Every card keeps its line, so titles stay level across a row.
            progress: entry.progress,
            onTap: () {
              if (addon != null) openEntry(context, addon, entry);
            },
          ),
          if (downloading)
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: DownloadStatus(bookKey: entry.key),
            ),
          if (scope.downloads.isDownloaded(entry.key))
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(
                  Icons.download_done,
                  size: 16,
                  semanticLabel: 'Downloaded',
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
