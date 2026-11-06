import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../player/audiobook_player.dart';
import '../widgets/book_tiles.dart';
import 'player_extras.dart';

/// The whole book under the player: one segment per chapter (as long as the chapter, when the
/// lengths are known), filled up to where the listener is, with "34 % read" and the time left
/// at the current speed. Only for books with more than one chapter: with one, the seek bar
/// already spans the book.
class BookProgress extends StatelessWidget {
  const BookProgress({super.key, required this.player, required this.entry});

  final AudiobookPlayer player;
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final chapters = entry.book.chapters;
    final known = chapters.every((c) => c.duration != null);
    final weights = [
      for (final c in chapters) known ? c.duration!.toDouble() : 1.0,
    ];
    final digits = theme.textTheme.labelMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: player.slowPositionStream,
        initialData: player.position,
        builder: (context, snap) {
          final at = snap.data ?? Duration.zero;
          final here = chapters[entry.chapterIndex];
          final length = here.duration != null
              ? Duration(seconds: here.duration!)
              : here.file == null
              ? player.duration
              : null;
          final into = at - (here.start ?? Duration.zero);
          final part = length == null || length <= Duration.zero
              ? 0.0
              : (into.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
          final percent = (entry.progressAt(at, chapterLength: length) * 100)
              .floor();
          final left = entry.timeLeftAt(at);
          final speed = player.speed;
          final speedText = (speed - 1).abs() < 0.01
              ? ''
              : ' at ${PlayerExtras.speedLabel(speed)}';
          return Semantics(
            label: 'Book progress',
            value: '$percent percent',
            child: Column(
              children: [
                SizedBox(
                  height: 8,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _Segments(
                      weights: weights,
                      current: entry.chapterIndex,
                      part: part,
                      done: primary,
                      track: primary.withValues(alpha: 0.18),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '$percent % read',
                      style: digits?.copyWith(color: primary),
                    ),
                    const Spacer(),
                    if (entry.finished || left != null)
                      Text(
                        entry.finished
                            ? 'Finished'
                            : '${formatLength(left! * (1 / speed))} left$speedText',
                        style: digits?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Rounded segments with small gaps; those before [current] full, [current] filled to [part].
class _Segments extends CustomPainter {
  _Segments({
    required this.weights,
    required this.current,
    required this.part,
    required this.done,
    required this.track,
  });

  final List<double> weights;
  final int current;
  final double part;
  final Color done;
  final Color track;

  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final total = weights.fold(0.0, (a, b) => a + b);
    // Hundreds of short chapters would be all gap: then they run together.
    final gap = weights.length * 4 > size.width ? 0.0 : _gap;
    final room = size.width - gap * (weights.length - 1);
    final radius = Radius.circular(size.height / 2);
    final paint = Paint();
    var x = 0.0;
    for (var i = 0; i < weights.length; i++) {
      final w = total > 0 ? room * weights[i] / total : 0.0;
      final rect = RRect.fromLTRBR(x, 0, x + w, size.height, radius);
      paint.color = i < current ? done : track;
      canvas.drawRRect(rect, paint);
      if (i == current && part > 0) {
        canvas.save();
        canvas.clipRRect(rect);
        canvas.drawRect(
          Rect.fromLTWH(x, 0, w * part, size.height),
          paint..color = done,
        );
        canvas.restore();
      }
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(_Segments old) =>
      old.part != part ||
      old.current != current ||
      old.done != done ||
      old.weights != weights;
}
