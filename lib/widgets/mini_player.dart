import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../screens/now_playing_screen.dart';
import '../screens/player_sheet.dart';
import '../screens/player_cover.dart' show straightFlight;
import '../theme.dart';
import 'adaptive.dart';
import 'cover.dart';
import 'cover_colors.dart';

/// The bar showing the current book: on phones a small one above the navigation (tap it or pull
/// it up for the full player), in wide windows a full player bar.
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
        return _SwipeAway(
          key: ValueKey(entry.key),
          onGone: player.stop,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _Unfolds(
              child: MiniCard(player: player, entry: entry),
            ),
          ),
        );
      },
    );
  }
}

/// The phone's mini player card, floating above the navigation in the colours of the book's
/// cover, the progress along its bottom edge. It is also the player folded up: the player's
/// sheet draws it [flying] (its cover in the air, its [row] fading, [rowWidth] wide) while it
/// unfolds.
class MiniCard extends StatelessWidget {
  const MiniCard({
    super.key,
    required this.player,
    required this.entry,
    this.flying = false,
    this.row = 1,
    this.rowWidth,
  });

  final AudiobookPlayer player;
  final LibraryEntry entry;
  final bool flying;
  final double row;
  final double? rowWidth;

  /// Where the cover sits in the card: the player sheet moves it from here.
  static const coverRect = Rect.fromLTWH(8, 8, 40, 40);

  @override
  Widget build(BuildContext context) {
    return CoverTheme(
      url: entry.book.cover,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Material(
            color: Color.alphaBlend(
              theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
              theme.colorScheme.surfaceContainerHigh,
            ),
            elevation: 3,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: IgnorePointer(
              ignoring: flying,
              child: InkWell(
                onTap: () => openPlayer(context),
                // Flying, the row keeps the card's width while the sheet is wider: the title
                // would be cut at another place, then again as the mini player takes over.
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: 1,
                  child: SizedBox(
                    width: rowWidth,
                    child: Opacity(
                      opacity: row,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              coverRect.left,
                              coverRect.top,
                              4,
                              6,
                            ),
                            child: Row(
                              children: [
                                if (flying)
                                  SizedBox.fromSize(size: coverRect.size)
                                else
                                  _CoverSpot(
                                    child: Hero(
                                      tag: playerCoverTag,
                                      transitionOnUserGestures: true,
                                      createRectTween: straightFlight,
                                      child: BookCover(
                                        title: entry.book.title,
                                        url: entry.book.cover,
                                        size: coverRect.width,
                                        radius: 8,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.book.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: bookTitle(
                                          theme.textTheme.titleSmall,
                                        ),
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
                                    tooltip: snap.data == true
                                        ? 'Pause'
                                        : 'Play',
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
                          _ProgressLine(player: player),
                        ],
                      ),
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

/// Where the player unfolds from: the card tells its page's player sheet where it is, steps
/// aside while the sheet is out (the sheet draws it then), and a finger pulling it up takes the
/// sheet up with it.
class _Unfolds extends StatefulWidget {
  const _Unfolds({required this.child});
  final Widget child;

  @override
  State<_Unfolds> createState() => _UnfoldsState();
}

class _UnfoldsState extends State<_Unfolds> {
  PlayerSheetState? _sheet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sheet = PlayerSheet.maybeOf(context)?..card = context;
  }

  @override
  void dispose() {
    if (_sheet?.card == context) _sheet!.card = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragStart: (_) => _sheet?.grab(),
    onVerticalDragUpdate: (d) => _sheet?.dragBy(d.primaryDelta ?? 0),
    onVerticalDragEnd: (d) => _sheet?.release(d.primaryVelocity ?? 0),
    onVerticalDragCancel: () => _sheet?.release(0),
    child: ValueListenableBuilder(
      valueListenable: playerExpansion,
      builder: (context, out, child) => Opacity(
        opacity: out > 0 ? 0 : 1,
        child: IgnorePointer(ignoring: out > 0, child: child),
      ),
      child: widget.child,
    ),
  );
}

/// The mini player's cover, made known to its page's player sheet, which moves a copy of it
/// between here and the player.
class _CoverSpot extends StatefulWidget {
  const _CoverSpot({required this.child});
  final Widget child;

  @override
  State<_CoverSpot> createState() => _CoverSpotState();
}

class _CoverSpotState extends State<_CoverSpot> {
  PlayerSheetState? _sheet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sheet = PlayerSheet.maybeOf(context)?..miniCover = context;
  }

  @override
  void dispose() {
    if (_sheet?.miniCover == context) _sheet!.miniCover = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.player});
  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: player.slowPositionStream,
        initialData: player.position,
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

/// Wide windows: every control at hand in one slim row, as in desktop music players, so
/// listening never needs the full-screen player. The book on the left opens it.
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
      // As tall as its contents, also in a page's bottom bar slot (which offers the whole
      // height): the column lets the row measure its children without that height.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Tooltip(
                    message: 'Open the player',
                    waitDuration: const Duration(milliseconds: 600),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => openPlayer(context),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Hero(
                              tag: playerCoverTag,
                              transitionOnUserGestures: true,
                              createRectTween: straightFlight,
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
                                    style: bookTitle(
                                      theme.textTheme.titleSmall,
                                    ),
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
                const SizedBox(width: 8),
                PlayerTransport(player: player, entry: entry, compact: true),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  // Repaints often; keep it from repainting the rest of the bar.
                  child: RepaintBoundary(
                    child: PlayerSeekBar(player: player, compact: true),
                  ),
                ),
                if (roomy) ...[
                  const SizedBox(width: 8),
                  PlayerExtras(player: player),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The phone card, swiped sideways to stop playback. It goes at once: stopping takes a moment,
/// and a swiped card left on screen in between is an error.
class _SwipeAway extends StatefulWidget {
  const _SwipeAway({super.key, required this.onGone, required this.child});
  final Future<void> Function() onGone;
  final Widget child;

  @override
  State<_SwipeAway> createState() => _SwipeAwayState();
}

class _SwipeAwayState extends State<_SwipeAway> {
  bool _gone = false;

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final stop = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.stop_circle_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Stop',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
    return Dismissible(
      key: const ValueKey('mini player'),
      background: Align(alignment: Alignment.centerLeft, child: stop),
      secondaryBackground: Align(alignment: Alignment.centerRight, child: stop),
      onDismissed: (_) {
        setState(() => _gone = true);
        widget.onGone();
      },
      child: widget.child,
    );
  }
}
