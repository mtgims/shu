import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../theme.dart';
import 'cover_image.dart';

/// The colours of book covers, so the player looks like the book playing. Worked out off the
/// UI thread from the small copy of the cover the lists already decode, and kept for the covers
/// seen lately.
abstract final class CoverColors {
  static final _seeds = <String, Future<Color?>>{};
  static final _known = <String, Color?>{};
  static final _themes = <(Color, Brightness), ThemeData>{};

  /// The small decode shared with the lists.
  static ImageProvider small(String url) =>
      ResizeImage(CoverImage(url), width: 96, policy: ResizeImagePolicy.fit);

  /// Starts working out the colour of the cover at [url] (null: it has none to speak of), so
  /// the player has it the moment it opens.
  static Future<Color?> seedOf(String url) {
    final known = _seeds.remove(url);
    if (known == null && _seeds.length >= 24) {
      _known.remove(_seeds.keys.first);
      _seeds.remove(_seeds.keys.first);
    }
    return _seeds[url] =
        known ??
        _extract(url).then((seed) => _known[url] = seed, onError: (_) => null);
  }

  /// The colour, when it has been worked out already.
  static Color? knownSeed(String url) => _known[url];
  static bool isKnown(String url) => _known.containsKey(url);

  /// The app's theme in the cover's colour; built once per colour.
  static ThemeData theme(Color seed, Brightness brightness) =>
      _themes[(seed, brightness)] ??= buildTheme(brightness, seed: seed);

  static Future<Color?> _extract(String url) async {
    final image = await _decode(small(url));
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final argb = await compute(dominantColor, data.buffer.asUint8List());
      return argb == null ? null : Color(argb);
    } finally {
      image.dispose();
    }
  }

  static final _blurred = <String, Future<ui.Image?>>{};

  /// The cover blurred once, small, for the player's background: stretched to fill the screen
  /// it stays smooth (nothing sharp is left to show pixels), and no frame pays for the blur.
  static Future<ui.Image?> blurredOf(String url) {
    final known = _blurred.remove(url);
    if (known == null && _blurred.length >= 6) {
      final oldest = _blurred.keys.first;
      _blurred.remove(oldest)!.then((image) => image?.dispose());
    }
    return _blurred[url] = known ?? _blur(url).catchError((Object _) => null);
  }

  static Future<ui.Image?> _blur(String url) async {
    final cover = await _decode(small(url));
    try {
      const width = 128.0;
      final height = width * cover.height / cover.width;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final source = Rect.fromLTWH(
        0,
        0,
        cover.width.toDouble(),
        cover.height.toDouble(),
      );
      canvas.drawImageRect(
        cover,
        source,
        const Offset(0, 0) & Size(width, height),
        Paint()
          ..filterQuality = FilterQuality.high
          // Clamped edges: the blur doesn't fade into dark borders.
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 6,
            sigmaY: 6,
            tileMode: TileMode.clamp,
          ),
      );
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(width.toInt(), height.round());
      } finally {
        picture.dispose();
      }
    } finally {
      cover.dispose();
    }
  }

  static Future<ui.Image> _decode(ImageProvider provider) {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        done.complete(info.image.clone());
        info.dispose();
      },
      onError: (e, stack) {
        stream.removeListener(listener);
        done.completeError(e, stack);
      },
    );
    stream.addListener(listener);
    return done.future;
  }
}

/// The colour most of a cover is (ARGB), from its RGBA bytes: the biggest cluster of colour,
/// helped a little by how colourful it is, so a small bright title doesn't win over the cover's
/// own colour. Greys count only when the cover is mostly grey. Null for an empty image.
Future<int?> dominantColor(Uint8List rgba) async {
  final pixels = <int>[
    for (var i = 0; i + 3 < rgba.length; i += 4)
      if (rgba[i + 3] > 128)
        0xFF000000 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2],
  ];
  if (pixels.isEmpty) return null;
  final clusters = (await QuantizerCelebi().quantize(pixels, 16)).colorToCount;
  final total = clusters.values.fold(0, (a, b) => a + b);
  bool colourful(int argb) => Hct.fromInt(argb).chroma >= 12;
  final colourfulShare =
      clusters.entries
          .where((e) => colourful(e.key))
          .fold(0, (a, e) => a + e.value) /
      total;
  int? best;
  var bestScore = 0.0;
  for (final MapEntry(key: argb, value: count) in clusters.entries) {
    final share = count / total;
    final double score;
    if (colourfulShare < 0.2) {
      score = share; // a black and white cover: its main grey
    } else if (!colourful(argb)) {
      continue;
    } else {
      score = share * (1 + min(Hct.fromInt(argb).chroma, 60) / 120);
    }
    if (score > bestScore) {
      best = argb;
      bestScore = score;
    }
  }
  return best;
}

/// Gives [child] the app's theme in the colours of the cover at [url]: at once when they are
/// known (see [CoverColors.seedOf]), otherwise easing into them when they are.
class CoverTheme extends StatelessWidget {
  const CoverTheme({super.key, required this.url, required this.child});

  final String? url;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = this.url;
    if (url == null) return child;
    // Localized like the theme Theme.of hands out, so the two blend without jumps in the text.
    final geometry = theme.typography.geometryThemeFor(
      MaterialLocalizations.of(context).scriptCategory,
    );
    ThemeData themed(Color? seed) => seed == null
        ? theme
        : ThemeData.localize(
            CoverColors.theme(seed, theme.brightness),
            geometry,
          );
    if (CoverColors.isKnown(url)) {
      return AnimatedTheme(
        data: themed(CoverColors.knownSeed(url)),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        child: child,
      );
    }
    return FutureBuilder<Color?>(
      future: CoverColors.seedOf(url),
      builder: (context, snap) => AnimatedTheme(
        data: themed(snap.data),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

/// The blurred cover from [CoverColors.blurredOf], filling its space (nothing until it's ready).
class _BlurredCover extends StatefulWidget {
  const _BlurredCover({required this.url});
  final String url;

  @override
  State<_BlurredCover> createState() => _BlurredCoverState();
}

class _BlurredCoverState extends State<_BlurredCover> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    CoverColors.blurredOf(widget.url).then((image) {
      // A copy of its own: the cache may let go of the original while this still shows it.
      if (image != null && mounted) setState(() => _image = image.clone());
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image == null
      ? const SizedBox.expand()
      : RawImage(
          image: _image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        );
}

/// The cover, blurred and darkened, filling the space behind the player; a new book's cover
/// fades in over the last one.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final url = this.url;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: url == null
            ? const SizedBox.expand()
            : Stack(
                key: ValueKey(url),
                fit: StackFit.expand,
                children: [
                  _BlurredCover(url: url),
                  // Keeps text and controls readable over any cover.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          surface.withValues(alpha: 0.45),
                          surface.withValues(alpha: 0.7),
                          surface.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
