import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../downloads/download_service.dart';
import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../theme.dart';
import '../widgets/cover_colors.dart';

/// For the car: one huge play/pause and a big "back 15 s", nothing else to hit by mistake. The
/// screen stays on while it shows (Android).
class DrivingScreen extends StatefulWidget {
  const DrivingScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const DrivingScreen(),
  );

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends State<DrivingScreen> {
  /// How long without a touch before the screen goes black.
  static const idle = Duration(seconds: 15);

  /// The backlight while black: what little is lit (nothing, on an OLED screen) uses less.
  static const dimmed = 0.05;

  // A one-shot timer, started again on each touch, only while driving mode shows.
  Timer? _idle;
  bool _black = false;

  @override
  void initState() {
    super.initState();
    DownloadService.keepScreenOn(true);
    _idle = Timer(idle, _sleep);
    HardwareKeyboard.instance.addHandler(_volumeKey);
  }

  /// While black, the volume keys work the player without looking: up plays or pauses, down goes
  /// back 15 s. They change the volume again once the controls show.
  bool _volumeKey(KeyEvent event) {
    if (!_black) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.audioVolumeUp &&
        key != LogicalKeyboardKey.audioVolumeDown) {
      return false;
    }
    // Held keys and key-ups are taken too, so the volume doesn't move.
    if (event is KeyDownEvent) {
      final player = AppScope.of(context).player;
      HapticFeedback.lightImpact();
      if (key == LogicalKeyboardKey.audioVolumeUp) {
        player.togglePlay();
      } else {
        player.rewind();
      }
    }
    return true;
  }

  @override
  void dispose() {
    _idle?.cancel();
    HardwareKeyboard.instance.removeHandler(_volumeKey);
    if (_black) _showSystemBars();
    DownloadService.screenBrightness(null);
    DownloadService.keepScreenOn(false);
    super.dispose();
  }

  void _sleep() {
    if (!mounted) return;
    setState(() => _black = true);
    // Nothing lit: the status and navigation bars go too.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    DownloadService.screenBrightness(dimmed);
  }

  void _touched() {
    _idle?.cancel();
    _idle = Timer(idle, _sleep);
  }

  void _wake() {
    setState(() => _black = false);
    _showSystemBars();
    DownloadService.screenBrightness(null);
    _touched();
  }

  static void _showSystemBars() => SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return Listener(
      // Any touch keeps the screen lit for another while.
      onPointerDown: (_) => _touched(),
      child: Stack(
        children: [
          ValueListenableBuilder<LibraryEntry?>(
            valueListenable: player.current,
            builder: (context, entry, _) => CoverTheme(
              url: entry?.book.cover,
              child: Builder(
                builder: (context) => _body(context, player, entry),
              ),
            ),
          ),
          // Black: the first tap only wakes the screen, so a blind tap can't pause or skip.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_black,
              child: AnimatedOpacity(
                opacity: _black ? 1 : 0,
                duration: const Duration(milliseconds: 600),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _wake,
                  child: const ColoredBox(
                    color: Colors.black,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AudiobookPlayer player,
    LibraryEntry? entry,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: entry == null
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: bookTitle(theme.textTheme.titleLarge),
                              ),
                              Text(
                                entry.book.chapters[entry.chapterIndex].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Exit'),
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size =
                        math.min(box.maxWidth, box.maxHeight - 140) * 0.8;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        StreamBuilder<bool>(
                          stream: player.playingStream,
                          initialData: player.playing,
                          builder: (context, snap) {
                            final playing = snap.data == true;
                            return SizedBox.square(
                              dimension: size,
                              child: IconButton.filled(
                                tooltip: playing ? 'Pause' : 'Play',
                                iconSize: size * 0.5,
                                style: IconButton.styleFrom(
                                  backgroundColor: colors.primary,
                                  foregroundColor: colors.onPrimary,
                                ),
                                onPressed: entry == null
                                    ? null
                                    : () {
                                        HapticFeedback.mediumImpact();
                                        player.togglePlay();
                                      },
                                icon: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: math.min(box.maxWidth, 420),
                          height: 80,
                          child: FilledButton.tonalIcon(
                            onPressed: entry == null
                                ? null
                                : () {
                                    HapticFeedback.lightImpact();
                                    player.rewind();
                                  },
                            icon: const Icon(Icons.replay, size: 36),
                            label: Text(
                              'Back 15 s',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Loading or a problem, in plain words.
                        ValueListenableBuilder<PlayerStatus>(
                          valueListenable: player.status,
                          builder: (context, status, _) => Text(
                            switch (status.phase) {
                              PlayerPhase.loading => 'Getting the audio…',
                              PlayerPhase.downloading =>
                                'Waiting for the download…',
                              PlayerPhase.error => status.message ?? '',
                              _ => '',
                            },
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: status.phase == PlayerPhase.error
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
