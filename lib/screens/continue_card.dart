import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../theme.dart';
import '../widgets/book_tiles.dart';
import '../widgets/cover.dart';
import '../widgets/cover_colors.dart';
import 'library_screen.dart' show entryMenu;

/// The book listened to last, large at the top of Home in its cover's colours (the player's
/// too, so opening it doesn't jump): how far along, the time left, and a button to go on.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.entry});
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return CoverTheme(
      url: entry.book.cover,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          // Containers can be bright for warm covers in the dark: kept subtle there.
          final tint = theme.brightness == Brightness.dark ? 0.35 : 0.85;
          Color over(Color c) => Color.alphaBlend(
            c.withValues(alpha: tint),
            colors.surfaceContainerHigh,
          );
          final percent = (entry.progress * 100).floor();
          final left = timeLeftText(entry, scope.player.settings.speed);
          void open() {
            final addon = scope.addons.byId(entry.addonId);
            if (addon != null) openEntry(context, addon, entry);
          }

          return MenuAnchor(
            menuChildren: entryMenu(context, entry),
            builder: (context, menu, child) => GestureDetector(
              onSecondaryTapUp: (d) => menu.open(position: d.localPosition),
              onLongPressStart: (d) => menu.open(position: d.localPosition),
              child: child,
            ),
            child: Material(
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      over(colors.primaryContainer),
                      over(colors.tertiaryContainer),
                    ],
                  ),
                ),
                child: InkWell(
                  onTap: open,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            BookCover(
                              title: entry.book.title,
                              url: entry.book.cover,
                              size: 112,
                              radius: 12,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Continue listening',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    entry.book.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: bookTitle(
                                      theme.textTheme.headlineSmall,
                                    ),
                                  ),
                                  if (entry.book.byline.isNotEmpty)
                                    Text(
                                      entry.book.byline,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: bookTitle(
                                        theme.textTheme.bodyLarge?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LinearProgressIndicator(
                                    value: entry.progress,
                                    minHeight: 6,
                                    borderRadius: BorderRadius.circular(3),
                                    color: colors.primary,
                                    backgroundColor: colors.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        '$percent % read',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(color: colors.primary),
                                      ),
                                      const Spacer(),
                                      if (left != null)
                                        Text(
                                          left,
                                          style: theme.textTheme.labelLarge,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            _PlayButton(entry: entry),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Plays or pauses this book when it is the one open, otherwise goes on with it.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.entry});
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: player.current,
      builder: (context, _) {
        final open = player.current.value?.key == entry.key;
        return StreamBuilder<bool>(
          stream: player.playingStream,
          initialData: player.playing,
          builder: (context, snap) {
            final playing = open && snap.data == true;
            return IconButton.filled(
              tooltip: playing ? 'Pause' : 'Play',
              iconSize: 32,
              style: IconButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size.square(56),
              ),
              onPressed: open ? player.togglePlay : () => player.resume(entry),
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            );
          },
        );
      },
    );
  }
}
