import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../widgets/adaptive.dart';
import '../widgets/cover.dart';

/// The player's cover. It sits back a little while paused and comes forward while playing; a
/// tap plays or pauses. On phones a sideways swipe changes chapter: the cover follows the finger,
/// tilting, and past a third of its width a tick says letting go will skip.
class PlayerCover extends StatefulWidget {
  const PlayerCover({
    super.key,
    required this.player,
    required this.entry,
    required this.size,
    required this.heroTag,
    required this.flightShuttleBuilder,
    required this.overlay,
  });

  final AudiobookPlayer player;
  final LibraryEntry entry;
  final double size;
  final Object heroTag;
  final HeroFlightShuttleBuilder flightShuttleBuilder;

  /// Drawn over the cover's bottom (the loading and error messages).
  final Widget overlay;

  @override
  State<PlayerCover> createState() => _PlayerCoverState();
}

class _PlayerCoverState extends State<PlayerCover>
    with SingleTickerProviderStateMixin {
  /// How far the cover has been dragged sideways.
  double _dx = 0;

  /// Puts the cover back after a swipe.
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _from = 0;

  bool get _past => _dx.abs() > widget.size / 3;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails d) {
    final wasPast = _past;
    setState(() => _dx += d.delta.dx);
    if (_past != wasPast && _past) HapticFeedback.lightImpact();
  }

  void _release(DragEndDetails _) {
    if (_past) {
      _dx < 0 ? widget.player.skipToNext() : widget.player.skipToPrevious();
    }
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chapters = widget.entry.book.chapters.length;
    final swipes = chapters > 1 && !isWide(context);
    return StreamBuilder<bool>(
      stream: widget.player.playingStream,
      initialData: widget.player.playing,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        final turn = (_dx / widget.size).clamp(-1.0, 1.0);
        return GestureDetector(
          onTap: widget.player.togglePlay,
          onHorizontalDragUpdate: swipes ? _drag : null,
          onHorizontalDragEnd: swipes ? _release : null,
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Transform.rotate(
              angle: turn * 8 * math.pi / 180,
              child: Opacity(
                opacity: 1 - turn.abs() * 0.4,
                child: AnimatedScale(
                  scale: playing ? 1 : 0.9,
                  duration: const Duration(milliseconds: 450),
                  curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.shadow.withValues(
                                alpha: playing ? 0.3 : 0.15,
                              ),
                              blurRadius: playing ? 36 : 12,
                              offset: Offset(0, playing ? 14 : 4),
                            ),
                          ],
                        ),
                        child: Hero(
                          tag: widget.heroTag,
                          transitionOnUserGestures: true,
                          flightShuttleBuilder: widget.flightShuttleBuilder,
                          child: BookCover(
                            title: widget.entry.book.title,
                            url: widget.entry.book.cover,
                            size: widget.size,
                            radius: 16,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: widget.overlay,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
