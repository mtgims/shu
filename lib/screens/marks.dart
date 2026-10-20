import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../widgets/book_tiles.dart';
import '../widgets/more_menu.dart';
import 'now_playing_screen.dart' show ChapterList;

/// Chapters, bookmarks and the places jumped away from, as tabs: beside the player in wide
/// windows, in a sheet otherwise.
class MarksPane extends StatelessWidget {
  const MarksPane({
    super.key,
    required this.player,
    required this.entry,
    this.onPicked,
  });

  final AudiobookPlayer player;
  final LibraryEntry entry;

  /// Called after something was picked (the sheet closes).
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Chapters'),
            Tab(text: 'Bookmarks'),
            Tab(text: 'History'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              ChapterList(player: player, entry: entry, onPicked: onPicked),
              _MarkList(player: player, entry: entry, onPicked: onPicked),
              _MarkList(
                player: player,
                entry: entry,
                onPicked: onPicked,
                history: true,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MarkList extends StatelessWidget {
  const _MarkList({
    required this.player,
    required this.entry,
    this.onPicked,
    this.history = false,
  });

  final AudiobookPlayer player;
  final LibraryEntry entry;
  final VoidCallback? onPicked;
  final bool history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: player.current,
      builder: (context, _) {
        final marks = history
            ? entry.history
            : ([...entry.bookmarks]..sort(
                (a, b) => a.chapterIndex != b.chapterIndex
                    ? a.chapterIndex.compareTo(b.chapterIndex)
                    : a.position.compareTo(b.position),
              ));
        if (marks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              history
                  ? 'Places you jump away from show up here, so a slip of the finger is easy '
                        'to undo.'
                  : 'Mark a place with the bookmark button under the player.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: marks.length,
          itemBuilder: (context, i) {
            final mark = marks[i];
            final chapter = entry.book.chapters[mark.chapterIndex];
            final at = markTime(entry, mark);
            return ListTile(
              leading: Icon(history ? Icons.history : Icons.bookmark_outline),
              title: Text(
                mark.note ?? chapter.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (entry.book.chapters.length > 1)
                    'Chapter ${mark.chapterIndex + 1}',
                  at,
                  if (history) _ago(mark.createdAt),
                ].join(' · '),
              ),
              onTap: () {
                onPicked?.call();
                player.jumpTo(mark);
              },
              trailing: history
                  ? null
                  : MoreMenu(
                      items: [
                        MenuItemButton(
                          onPressed: () =>
                              editBookmarkNote(context, player, mark),
                          child: const Text('Edit note'),
                        ),
                        removeItem(
                          context,
                          'Delete',
                          () => player.changeBookmark(mark, null),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
  }
}

/// Where [mark] is inside its chapter, as the chapter's own clock reads.
String markTime(LibraryEntry entry, Mark mark) {
  final start = entry.book.chapters[mark.chapterIndex].start ?? Duration.zero;
  final into = mark.position - start;
  return formatDuration(into.isNegative ? Duration.zero : into);
}

/// Asks for a bookmark's note; an empty one shows the chapter title again.
Future<void> editBookmarkNote(
  BuildContext context,
  AudiobookPlayer player,
  Mark mark,
) async {
  // No controller: disposing one when the dialog returns would be too early, while it still
  // animates out.
  var text = mark.note ?? '';
  final note = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Bookmark note'),
      content: TextFormField(
        initialValue: text,
        onChanged: (value) => text = value,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(hintText: 'What happens here'),
        onFieldSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (note != null) await player.changeBookmark(mark, mark.withNote(note));
}
