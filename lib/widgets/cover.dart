import 'package:flutter/material.dart';

import 'cover_image.dart';

/// Square cover art. Books without (or with a broken) cover get a generated one.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.title,
    this.url,
    this.size,
    this.radius = 10,
    this.decodeWidth,
  });

  final String title;
  final String? url;
  final double? size;
  final double radius;

  /// Decodes at this width whatever size it is drawn at (a cover in flight between two sizes
  /// would otherwise decode again on the way).
  final int? decodeWidth;

  @override
  Widget build(BuildContext context) {
    final fallback = _GeneratedCover(title: title);
    return SizedBox.square(
      dimension: size,
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: url == null
              ? fallback
              : LayoutBuilder(
                  builder: (context, box) {
                    final image = ResizeImage(
                      CoverImage(url!),
                      width:
                          decodeWidth ??
                          decodeWidthFor(
                            box.maxWidth *
                                MediaQuery.devicePixelRatioOf(context),
                          ),
                      policy: ResizeImagePolicy.fit,
                    );
                    return _CoverPicture(image: image, fallback: fallback);
                  },
                ),
        ),
      ),
    );
  }

  /// Decoding at display size saves most of a cover's memory; a few fixed sizes let covers
  /// shown at similar sizes share one decoded image.
  static int decodeWidthFor(double pixels) {
    for (final w in const [96, 192, 384, 768]) {
      if (pixels <= w) return w;
    }
    return 1024;
  }
}

/// The decoded cover: a square one drawn once; a book cover (taller than wide) shown whole over
/// a darkened, filled copy of itself, both from the one decoded image. [fallback] shows while it
/// loads and when it can't. A new size keeps the old picture until it is ready.
class _CoverPicture extends StatefulWidget {
  const _CoverPicture({required this.image, required this.fallback});

  final ImageProvider image;
  final Widget fallback;

  @override
  State<_CoverPicture> createState() => _CoverPictureState();
}

class _CoverPictureState extends State<_CoverPicture> {
  ImageStream? _stream;
  ImageInfo? _info;
  bool _failed = false;
  late final _listener = ImageStreamListener(_shown, onError: _broken);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_CoverPicture old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) _resolve();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _shown(ImageInfo info, bool _) => setState(() {
    _info?.dispose();
    _info = info;
    _failed = false;
  });

  void _broken(Object error, StackTrace? stack) =>
      setState(() => _failed = true);

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    if (image == null || _failed) return widget.fallback;
    RawImage draw(BoxFit fit) =>
        RawImage(image: image, fit: fit, filterQuality: FilterQuality.medium);
    if ((image.width / image.height - 1).abs() < 0.03) {
      return draw(BoxFit.cover);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        draw(BoxFit.cover),
        const ColoredBox(color: Color(0x8C000000)),
        draw(BoxFit.contain),
      ],
    );
  }
}

class _GeneratedCover extends StatelessWidget {
  const _GeneratedCover({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    // A stable hue per title so different books look different.
    final hue = (title.codeUnits.fold(0, (a, b) => a * 31 + b) % 360)
        .toDouble();
    final top = HSLColor.fromAHSL(1, hue, 0.35, 0.28).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.30, 0.12).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Too small for a readable title (mini player, list rows): just the mark.
          if (box.maxWidth < 72) {
            return Center(
              child: Icon(
                Icons.headphones,
                color: const Color(0xFFE8B04A),
                size: box.maxWidth * 0.45,
              ),
            );
          }
          final small = box.maxWidth < 90;
          final padding = small ? 6.0 : 12.0;
          final iconSize = small ? 14.0 : 22.0;
          final fontSize = small ? 9.0 : 15.0;
          // As many title lines as fit under the icon, at most five.
          final lines =
              ((box.maxHeight - 2 * padding - iconSize - 4) / (fontSize * 1.15))
                  .floor()
                  .clamp(1, 5);
          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.headphones,
                  color: const Color(0xFFE8B04A),
                  size: iconSize,
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFF4EFE6),
                    fontWeight: FontWeight.w700,
                    fontSize: fontSize,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
