import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../screens/now_playing_screen.dart';
import 'adaptive.dart';
import 'cover.dart';

/// The bar showing the current book: on phones a small one above the navigation (tap it for the
/// full player), in wide windows a full player bar.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ValueListenableBuilder<LibraryEntry?>(
      valueListenable: player.current,
      builder: (context, entry, _) {
        if (entry == null) return const SizedBox.shrink();
        if (isWide(context)) return _PlayerBar(player: player, entry: entry);
        final theme = Theme.of(context);
        return Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: InkWell(
            onTap: () => Navigator.of(context).push(NowPlayingScreen.route()),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ProgressLine(player: player),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Hero(
                        tag: playerCoverTag,
                        transitionOnUserGestures: true,
                        child: BookCover(
                          title: entry.book.title,
                          url: entry.book.cover,
                          size: 44,
                          radius: 6,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            _StatusLine(player: player, entry: entry),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Back 15 seconds',
                        onPressed: player.rewind,
                        icon: const Icon(Icons.replay),
                      ),
                      StreamBuilder<bool>(
                        stream: player.playingStream,
                        initialData: player.playing,
                        builder: (_, snap) => IconButton(
                          tooltip: snap.data == true ? 'Pause' : 'Play',
                          onPressed: player.togglePlay,
                          icon: Icon(
                            snap.data == true
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.player});
  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: player.slowPositionStream,
        builder: (context, snap) {
          final total = player.duration?.inMilliseconds ?? 0;
          final value = total > 0
              ? (snap.data?.inMilliseconds ?? 0) / total
              : 0.0;
          return LinearProgressIndicator(
            value: value.clamp(0, 1).toDouble(),
            minHeight: 2,
          );
        },
      ),
    );
  }
}

/// The chapter, or what keeps it from playing.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.player, required this.entry});
  final AudiobookPlayer player;
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<PlayerStatus>(
      valueListenable: player.status,
      builder: (_, status, _) => Text(
        switch (status.phase) {
          PlayerPhase.loading => 'Loading…',
          PlayerPhase.downloading => 'Waiting for download…',
          PlayerPhase.error => 'Playback problem, open the player for details',
          _ => entry.book.chapters[entry.chapterIndex].title,
        },
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: status.phase == PlayerPhase.error
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Wide windows: every control at hand, as in desktop music players, so listening never needs
/// the full-screen player. The book on the left opens it.
class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.player, required this.entry});
  final AudiobookPlayer player;
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomy = MediaQuery.sizeOf(context).width >= 1100;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      // As tall as its contents, also in a page's bottom bar slot (which offers the whole height).
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Tooltip(
                    message: 'Open the player',
                    waitDuration: const Duration(milliseconds: 600),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          Navigator.of(context).push(NowPlayingScreen.route()),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Hero(
                              tag: playerCoverTag,
                              transitionOnUserGestures: true,
                              child: BookCover(
                                title: entry.book.title,
                                url: entry.book.cover,
                                size: 56,
                                radius: 6,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.book.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  _StatusLine(player: player, entry: entry),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PlayerTransport(
                        player: player,
                        entry: entry,
                        compact: true,
                      ),
                      // Repaints often; keep it from repainting the rest of the bar.
                      RepaintBoundary(
                        child: PlayerSeekBar(player: player, compact: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: roomy
                        ? PlayerExtras(player: player)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
