import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../screens/now_playing_screen.dart';
import 'cover.dart';

/// The bar above the navigation showing the current book; tap it for the full player.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ValueListenableBuilder<LibraryEntry?>(
      valueListenable: player.current,
      builder: (context, entry, _) {
        if (entry == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final chapter = entry.book.chapters[entry.chapterIndex];
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
                      BookCover(
                        title: entry.book.title,
                        url: entry.book.cover,
                        size: 44,
                        radius: 6,
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
                            ValueListenableBuilder<PlayerStatus>(
                              valueListenable: player.status,
                              builder: (_, status, _) => Text(
                                switch (status.phase) {
                                  PlayerPhase.loading => 'Loading…',
                                  PlayerPhase.downloading =>
                                    'Waiting for download…',
                                  PlayerPhase.error =>
                                    'Playback problem, tap for details',
                                  _ => chapter.title,
                                },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: status.phase == PlayerPhase.error
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
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
