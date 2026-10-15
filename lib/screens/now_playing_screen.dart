import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../widgets/adaptive.dart';
import '../widgets/book_tiles.dart';
import '../widgets/cover.dart';
import '../widgets/cover_colors.dart';
import '../widgets/marked_track.dart';
import '../widgets/more_menu.dart';
import 'marks.dart';
import 'player_extras.dart';

export 'player_extras.dart' show PlayerExtras;

/// The full player: cover, chapter, seek bar, transport, speed, sleep timer and bookmarks, in
/// the colours of the book's cover.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  static Route<void> route() => PlayerRoute();

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    // Rebuilt only for another book: chapters, bookmarks and the history are followed by the
    // parts that show them, not by the whole page and its colours.
    return _OnNewBook(
      current: player.current,
      builder: (context, entry) => CoverTheme(
        url: entry?.book.cover,
        child: Builder(builder: (context) => _page(context, player, entry)),
      ),
    );
  }

  Widget _page(
    BuildContext context,
    AudiobookPlayer player,
    LibraryEntry? entry,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // Wide windows show the chapters beside the player instead of in a sheet.
    final sidePane = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Close',
          icon: Icon(isWide(context) ? Icons.close : Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!sidePane && entry != null)
            IconButton(
              tooltip: 'Chapters and bookmarks',
              icon: const Icon(Icons.format_list_numbered),
              onPressed: () => _showMarks(context, player, entry),
            ),
          MoreMenu(
            items: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.tune),
                onPressed: () => showAudioSettings(context, player.settings),
                child: const Text('Playback settings'),
              ),
            ],
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CoverBackdrop(url: entry?.book.cover),
          if (entry == null)
            const Center(child: Text('Nothing is playing.'))
          else
            _body(context, player, entry, sidePane),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AudiobookPlayer player,
    LibraryEntry entry,
    bool sidePane,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final main = SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final coverSize = (box.maxHeight * 0.42).clamp(140.0, 380.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, kToolbarHeight, 24, 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.25),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Hero(
                        tag: playerCoverTag,
                        transitionOnUserGestures: true,
                        flightShuttleBuilder: smallCoverInFlight,
                        child: BookCover(
                          title: entry.book.title,
                          url: entry.book.cover,
                          size: coverSize.toDouble(),
                          radius: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListenableBuilder(
                      listenable: player.current,
                      builder: (_, _) => _Titles(entry: entry),
                    ),
                    const SizedBox(height: 12),
                    _StatusBanner(player: player),
                    // Repaints often; keep it from repainting the cover and text.
                    RepaintBoundary(child: PlayerSeekBar(player: player)),
                    ListenableBuilder(
                      listenable: player.current,
                      builder: (_, _) =>
                          PlayerTransport(player: player, entry: entry),
                    ),
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
        SizedBox(
          width: 380,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: kToolbarHeight),
              child: _AfterOpening(
                child: MarksPane(player: player, entry: entry),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static void _showMarks(
    BuildContext context,
    AudiobookPlayer player,
    LibraryEntry entry,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: MarksPane(
          player: player,
          entry: entry,
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
    this.onPicked,
  });

  final AudiobookPlayer player;
  final LibraryEntry entry;
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      // The current chapter moves while chapters inside one file play.
      listenable: player.current,
      builder: (context, _) => ListView.builder(
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

  /// The track with the chapter starts and bookmarks inside the open file ([max] ms long).
  MarkedTrackShape? _marks(ColorScheme scheme, double max) {
    final entry = widget.player.current.value;
    if (entry == null || max <= 0) return null;
    final chapters = entry.book.chapters;
    final here = chapters[entry.chapterIndex];
    bool inFile(int i) =>
        i == entry.chapterIndex || chapters[i].sharesFileWith(here);
    double at(Duration d) => (d.inMilliseconds / max).clamp(0.0, 1.0);
    return MarkedTrackShape(
      chapters: [
        for (final c in chapters)
          if (c.sharesFileWith(here) &&
              (c.start ?? Duration.zero) > Duration.zero)
            at(c.start!),
      ],
      bookmarks: [
        for (final m in entry.bookmarks)
          if (inFile(m.chapterIndex)) at(m.position),
      ],
      gapColor: scheme.surface,
      bookmarkColor: scheme.tertiary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      initialData: widget.player.position,
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
        final slider = SliderTheme(
          data: SliderTheme.of(context)
              .copyWith(trackShape: _marks(theme.colorScheme, max)),
          child: Slider(
            value: max > 0 ? value : 0,
            max: max > 0 ? max : 1,
            onChanged: max > 0 ? (v) => setState(() => _dragging = v) : null,
            onChangeEnd: (v) {
              widget.player.seek(Duration(milliseconds: v.round()));
              setState(() => _dragging = null);
            },
          ),
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

/// Builds [child] once the page has finished opening, fading it in: the first frame of the
/// opening has enough to build already.
class _AfterOpening extends StatefulWidget {
  const _AfterOpening({required this.child});
  final Widget child;

  @override
  State<_AfterOpening> createState() => _AfterOpeningState();
}

class _AfterOpeningState extends State<_AfterOpening> {
  Animation<double>? _opening;
  bool _open = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final opening = route?.animation;
    if (opening == _opening) return;
    _opening?.removeStatusListener(_check);
    _opening = opening;
    opening?.addStatusListener(_check);
    // Already open (rebuilt later, or no route animation): no waiting. A route is first built
    // offstage, for heroes to measure, and then looks finished: that build doesn't count.
    if (opening == null || (opening.isCompleted && route?.offstage != true)) {
      _open = true;
    }
  }

  void _check(AnimationStatus status) {
    if (_open || status != AnimationStatus.completed) return;
    if (mounted) setState(() => _open = true);
  }

  @override
  void dispose() {
    _opening?.removeStatusListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _open ? 1 : 0,
    duration: const Duration(milliseconds: 200),
    child: _open ? widget.child : const SizedBox.expand(),
  );
}

/// The cover that flies from the player bar into the player and back.
const playerCoverTag = 'player-cover';

/// The flying cover is the player bar's, already decoded, scaled: decoding bigger copies on the
/// way stalls frames and flashes the placeholder. The sharp cover takes over on landing.
Widget smallCoverInFlight(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHero,
  BuildContext toHero,
) {
  final bar = direction == HeroFlightDirection.push ? fromHero : toHero;
  final cover = (bar.widget as Hero).child as BookCover;
  return BookCover(
    title: cover.title,
    url: cover.url,
    radius: 12,
    decodeWidth: BookCover.decodeWidthFor(
      (cover.size ?? 56) * MediaQuery.devicePixelRatioOf(context),
    ),
  );
}

/// Builds with the open book, again only when another book is opened (a book that plays on is
/// the same object, with its chapter and marks changing inside).
class _OnNewBook extends StatefulWidget {
  const _OnNewBook({required this.current, required this.builder});

  final ValueListenable<LibraryEntry?> current;
  final Widget Function(BuildContext context, LibraryEntry? entry) builder;

  @override
  State<_OnNewBook> createState() => _OnNewBookState();
}

class _OnNewBookState extends State<_OnNewBook> {
  late LibraryEntry? _entry = widget.current.value;

  @override
  void initState() {
    super.initState();
    widget.current.addListener(_check);
  }

  @override
  void dispose() {
    widget.current.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!identical(widget.current.value, _entry)) {
      setState(() => _entry = widget.current.value);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _entry);
}

/// Opens the player: it rises from the player bar while the cover flies into place. On phones it
/// slides up from the bottom and a drag down puts it back.
class PlayerRoute extends PageRoute<void> {
  PlayerRoute() : super(fullscreenDialog: true);

  /// While the route moves, the page is drawn once and that picture moves: redrawing the whole
  /// player (cover, blurred background) on every frame stutters on big screens.
  final _snapshot = SnapshotController();

  @override
  void install() {
    super.install();
    animation!.addStatusListener(_snapshotWhileMoving);
  }

  void _snapshotWhileMoving(AnimationStatus status) =>
      _snapshot.allowSnapshotting = status.isAnimating && !_dragging;

  @override
  void dispose() {
    animation?.removeStatusListener(_snapshotWhileMoving);
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 450);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const NowPlayingScreen();

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final moving = SnapshotWidget(
      controller: _snapshot,
      mode: SnapshotMode.permissive,
      child: child,
    );
    final curved = CurvedAnimation(
      parent: animation,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Easing.emphasizedAccelerate,
    );
    if (isWide(context)) {
      // A window: the player rises a little and fades in where it will be.
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: moving,
        ),
      );
    }
    return SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: GestureDetector(
        onVerticalDragStart: (_) => _grab(),
        onVerticalDragUpdate: (d) => _drag(context, d.primaryDelta ?? 0),
        onVerticalDragEnd: (d) => _release(d.primaryVelocity ?? 0),
        onVerticalDragCancel: () => _release(0),
        child: moving,
      ),
    );
  }

  /// Whether a drag is under way: a tap also ends in a "cancel", with nothing to undo.
  bool _dragging = false;

  void _grab() {
    _dragging = true;
    // The finger moves the page itself: it stays live.
    _snapshot.allowSnapshotting = false;
    navigator?.didStartUserGesture();
  }

  /// Follows the finger down (and back up).
  void _drag(BuildContext context, double dy) {
    if (!_dragging) return;
    final height = MediaQuery.sizeOf(context).height;
    controller!.value -= dy / height;
  }

  /// Closes after a flick or past a third of the way down, otherwise springs back.
  void _release(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final close = velocity > 700 || controller!.value < 0.67;
    if (close) {
      navigator?.pop();
    } else {
      controller!.forward();
    }
    navigator?.didStopUserGesture();
  }
}
