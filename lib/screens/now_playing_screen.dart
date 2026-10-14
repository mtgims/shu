import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../widgets/adaptive.dart';
import '../widgets/book_tiles.dart';
import '../widgets/cover.dart';

/// The full player: cover, chapter, seek bar, transport, speed and sleep timer.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const NowPlayingScreen(),
  );

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    // Wide windows show the chapters beside the player instead of in a sheet.
    final sidePane = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: Icon(isWide(context) ? Icons.close : Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!sidePane)
            IconButton(
              tooltip: 'Chapters',
              icon: const Icon(Icons.format_list_numbered),
              onPressed: () => _showChapters(context, player),
            ),
        ],
      ),
      body: ValueListenableBuilder<LibraryEntry?>(
        valueListenable: player.current,
        builder: (context, entry, _) {
          if (entry == null) {
            return const Center(child: Text('Nothing is playing.'));
          }
          final main = SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final coverSize = (box.maxHeight * 0.42).clamp(140.0, 380.0);
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        children: [
                          BookCover(
                            title: entry.book.title,
                            url: entry.book.cover,
                            size: coverSize.toDouble(),
                            radius: 16,
                          ),
                          const SizedBox(height: 20),
                          _Titles(entry: entry),
                          const SizedBox(height: 12),
                          _StatusBanner(player: player),
                          // Repaints often; keep it from repainting the cover and text.
                          RepaintBoundary(child: PlayerSeekBar(player: player)),
                          PlayerTransport(player: player, entry: entry),
                          const SizedBox(height: 8),
                          PlayerExtras(player: player),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
          if (!sidePane) return main;
          return Row(
            children: [
              Expanded(child: main),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 380,
                child: ChapterList(player: player, entry: entry),
              ),
            ],
          );
        },
      ),
    );
  }

  static void _showChapters(BuildContext context, AudiobookPlayer player) {
    final entry = player.current.value;
    if (entry == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ChapterList(
          player: player,
          entry: entry,
          controller: scroll,
          onPicked: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// The book's chapters, the current one marked; picking one plays it.
class ChapterList extends StatelessWidget {
  const ChapterList({
    super.key,
    required this.player,
    required this.entry,
    this.controller,
    this.onPicked,
  });

  final AudiobookPlayer player;
  final LibraryEntry entry;
  final ScrollController? controller;
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      // The current chapter moves while chapters inside one file play.
      listenable: player.current,
      builder: (context, _) => ListView.builder(
        controller: controller,
        itemCount: entry.book.chapters.length,
        itemBuilder: (context, i) {
          final here = i == entry.chapterIndex;
          return ListTile(
            selected: here,
            leading: SizedBox(
              width: 32,
              child: here
                  ? Icon(Icons.graphic_eq, color: primary)
                  : Text('${i + 1}', textAlign: TextAlign.center),
            ),
            title: Text(
              entry.book.chapters[i].title,
              style: here ? const TextStyle(fontWeight: FontWeight.w600) : null,
            ),
            onTap: () {
              onPicked?.call();
              player.playChapter(i);
            },
          );
        },
      ),
    );
  }
}

class _Titles extends StatelessWidget {
  const _Titles({required this.entry});
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapters = entry.book.chapters;
    return Column(
      children: [
        Text(
          chapters[entry.chapterIndex].title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          [
            entry.book.title,
            if (entry.book.byline.isNotEmpty) entry.book.byline,
          ].join(' · '),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (chapters.length > 1)
          Text(
            'Chapter ${entry.chapterIndex + 1} of ${chapters.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }
}

/// Loading, "still downloading" and error states, with a retry button.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.player});
  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<PlayerStatus>(
      valueListenable: player.status,
      builder: (context, status, _) {
        return switch (status.phase) {
          PlayerPhase.loading => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              status.message ?? 'Getting the audio…',
              textAlign: TextAlign.center,
            ),
          ),
          PlayerPhase.downloading || PlayerPhase.error => Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    status.message ?? '',
                    style: status.phase == PlayerPhase.error
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
                  ),
                  if (status.phase == PlayerPhase.downloading) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: status.progress),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: player.retry,
                      child: const Text('Try now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ => const SizedBox(height: 8),
        };
      },
    );
  }
}

class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({super.key, required this.player, this.compact = false});
  final AudiobookPlayer player;

  /// One line, times beside the slider (the desktop player bar).
  final bool compact;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  /// Where the thumb is while dragging; null otherwise.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (context, snap) {
        final total = widget.player.duration ?? Duration.zero;
        final position = snap.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        final value = (_dragging ?? position.inMilliseconds.toDouble()).clamp(
          0.0,
          max,
        );
        final shown = Duration(milliseconds: value.round());
        final speed = widget.player.speed;
        final left = total - shown;
        final remaining = total == Duration.zero
            ? '--:--'
            : '-${formatDuration(Duration(milliseconds: (left.inMilliseconds / speed).round()))}';
        final slider = Slider(
          value: max > 0 ? value : 0,
          max: max > 0 ? max : 1,
          onChanged: max > 0 ? (v) => setState(() => _dragging = v) : null,
          onChangeEnd: (v) {
            widget.player.seek(Duration(milliseconds: v.round()));
            setState(() => _dragging = null);
          },
        );
        if (widget.compact) {
          return Row(
            children: [
              Text(formatDuration(shown), style: muted),
              Expanded(child: slider),
              Text(remaining, style: muted),
            ],
          );
        }
        return Column(
          children: [
            slider,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(formatDuration(shown), style: muted),
                  const Spacer(),
                  Text(remaining, style: muted),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class PlayerTransport extends StatelessWidget {
  const PlayerTransport({
    super.key,
    required this.player,
    required this.entry,
    this.compact = false,
  });
  final AudiobookPlayer player;
  final LibraryEntry entry;

  /// Smaller buttons, packed together (the desktop player bar).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = compact ? 0.7 : 1.0;
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Previous chapter',
          iconSize: 30 * k,
          onPressed: player.skipToPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton(
          tooltip: 'Back 15 seconds (←)',
          iconSize: 34 * k,
          onPressed: player.rewind,
          icon: const Icon(Icons.replay),
        ),
        StreamBuilder<bool>(
          stream: player.playingStream,
          initialData: player.playing,
          builder: (_, snap) => IconButton.filled(
            tooltip: snap.data == true ? 'Pause (Space)' : 'Play (Space)',
            iconSize: 44 * k,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              minimumSize: Size.square(76 * k),
            ),
            onPressed: player.togglePlay,
            icon: Icon(
              snap.data == true
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Forward 30 seconds (→)',
          iconSize: 34 * k,
          onPressed: player.fastForward,
          icon: const Icon(Icons.forward_30),
        ),
        IconButton(
          tooltip: 'Next chapter',
          iconSize: 30 * k,
          onPressed: entry.chapterIndex + 1 < entry.book.chapters.length
              ? player.skipToNext
              : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

class PlayerExtras extends StatelessWidget {
  const PlayerExtras({super.key, required this.player});
  final AudiobookPlayer player;

  static const speeds = [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5];

  /// 1.0 → "1×", 1.25 → "1.25×", 1.5 → "1.5×".
  static String _speedLabel(double s) =>
      '${s.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}×';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StreamBuilder<double>(
          stream: player.speedStream,
          initialData: player.speed,
          builder: (context, snap) => TextButton.icon(
            onPressed: () => _pickSpeed(context, snap.data ?? 1),
            icon: const Icon(Icons.speed),
            label: Text(_speedLabel(snap.data ?? 1)),
          ),
        ),
        const SizedBox(width: 16),
        ValueListenableBuilder<SleepTimer?>(
          valueListenable: player.sleepTimer,
          builder: (context, timer, _) => TextButton.icon(
            onPressed: () => _pickSleep(context),
            icon: Icon(timer == null ? Icons.bedtime_outlined : Icons.bedtime),
            label: Text(
              timer == null
                  ? 'Sleep timer'
                  : timer.endOfChapter
                  ? 'End of chapter'
                  : 'Until ${TimeOfDay.fromDateTime(timer.endsAt!).format(context)}',
            ),
          ),
        ),
      ],
    );
  }

  void _pickSpeed(BuildContext context, double current) {
    showPanel<void>(
      context,
      builder: (context) => SafeArea(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in speeds)
              ChoiceChip(
                label: Text(_speedLabel(s)),
                selected: (s - current).abs() < 0.01,
                onSelected: (_) {
                  player.setSpeed(s);
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(width: double.infinity, height: 16),
          ],
        ),
      ),
    );
  }

  void _pickSleep(BuildContext context) {
    void choose(VoidCallback action) {
      action();
      Navigator.of(context).pop();
    }

    showPanel<void>(
      context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final minutes in [10, 15, 30, 45, 60])
              ListTile(
                title: Text('$minutes minutes'),
                onTap: () => choose(
                  () => player.setSleepTimer(Duration(minutes: minutes)),
                ),
              ),
            ListTile(
              title: const Text('End of chapter'),
              onTap: () => choose(player.setSleepAtChapterEnd),
            ),
            if (player.sleepTimer.value != null)
              ListTile(
                title: const Text('Turn off'),
                onTap: () => choose(player.cancelSleepTimer),
              ),
          ],
        ),
      ),
    );
  }
}
