import 'package:flutter/material.dart';

/// The slider's usual track with small marks on it: chapter starts and bookmarks.
class MarkedTrackShape extends RoundedRectSliderTrackShape {
  const MarkedTrackShape({
    required this.chapters,
    required this.bookmarks,
    required this.gapColor,
    required this.bookmarkColor,
  });

  /// Places along the track, from 0 to 1.
  final List<double> chapters;
  final List<double> bookmarks;

  /// Chapter starts are cut out of the track in the background colour.
  final Color gapColor;
  final Color bookmarkColor;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    if (chapters.isEmpty && bookmarks.isEmpty) return;
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    double x(double at) => textDirection == TextDirection.ltr
        ? track.left + at * track.width
        : track.right - at * track.width;
    final canvas = context.canvas;
    final gap = Paint()..color = gapColor;
    final dot = Paint()..color = bookmarkColor;
    for (final at in chapters) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x(at), track.center.dy),
          width: 2,
          height: track.height + 6,
        ),
        gap,
      );
    }
    // Bookmarks sit just above the track.
    for (final at in bookmarks) {
      canvas.drawCircle(Offset(x(at), track.top - 5), 2.5, dot);
    }
  }
}
