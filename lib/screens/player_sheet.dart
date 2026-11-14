import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../app.dart';
import '../widgets/adaptive.dart';
import '../widgets/cover.dart';
import '../widgets/mini_player.dart' show MiniCard;
import 'now_playing_screen.dart';

/// How far the player is unfolded on a phone, 0 (only the mini player) to 1 (open): the mini
/// player steps aside for the sheet drawn out of it, and the navigation bar slides away.
final playerExpansion = ValueNotifier<double>(0);

/// Opens the player: on a phone the page's sheet ([sheet], or the one around [context]) unfolds;
/// in wide windows (or on a page without a sheet) the player's route opens.
void openPlayer(BuildContext context, [PlayerSheetState? sheet]) {
  sheet = isWide(context) ? null : sheet ?? PlayerSheet.maybeOf(context);
  if (sheet != null) {
    sheet.open();
  } else {
    Navigator.of(context).push(NowPlayingScreen.route());
  }
}

/// Closes the player that [context] is in.
void closePlayer(BuildContext context) {
  final sheet = PlayerSheet.maybeOf(context);
  if (sheet != null) {
    sheet.close();
  } else {
    Navigator.of(context).pop();
  }
}

/// On phones the player is a sheet over the page, folded into the mini player: a tap or a pull
/// on the mini player unfolds it, a drag down or Back folds it again. It is one surface: the mini
/// player's card stretches to the sheet's outline, its row fading out as it grows, then the
/// player fades in riding on the top edge while the cover moves from the card to its place; the
/// navigation bar slides away underneath. Folding plays it backwards and ends as the mini player.
///
/// Not a route: pushing one cancels the pointers on screen, and a finger must be able to hold the
/// sheet from the mini player all the way up. Back reaches it through a local history entry.
class PlayerSheet extends StatefulWidget {
  const PlayerSheet({super.key, required this.child});

  /// The page, with the mini player in it.
  final Widget child;

  static PlayerSheetState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<PlayerSheetState>();

  static final _unfolded = <PlayerSheetState>{};

  /// Folds every sheet at once: another page is about to cover them.
  static void foldAll() {
    for (final sheet in List.of(_unfolded)) {
      sheet._out.value = 0;
    }
  }

  @override
  State<PlayerSheet> createState() => PlayerSheetState();
}

class PlayerSheetState extends State<PlayerSheet>
    with SingleTickerProviderStateMixin {
  late final _out = AnimationController(vsync: this)..addListener(_moved);

  /// The mini player's card on this page (the mini player lists itself).
  BuildContext? card;

  /// Its cover, measured rather than assumed: the row centres it against the buttons.
  BuildContext? miniCover;

  final _pageKey = GlobalKey();
  final _coverKey = GlobalKey();
  final _coverAway = ValueNotifier(true);

  /// Built once: the sheet rebuilds on every frame of its movement, the player must not.
  late final _page = NowPlayingScreen(
    coverKey: _coverKey,
    coverAway: _coverAway,
  );

  ModalRoute<Object?>? _route;
  LocalHistoryEntry? _back;

  static const _ease = Easing.emphasizedDecelerate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    PlayerSheet._unfolded.remove(this);
    if (_out.value > 0) playerExpansion.value = 0;
    _out.dispose();
    _coverAway.dispose();
    super.dispose();
  }

  void open() => _run(1);

  void close() => _run(0);

  void _run(double to) {
    final ms = to == 1 ? 350 : 400;
    final duration = Duration(
      milliseconds: (ms * (to - _out.value).abs()).round(),
    );
    if (to == 1) {
      _out.animateTo(1, duration: duration, curve: _ease);
    } else {
      _out.animateBack(0, duration: duration, curve: _ease);
    }
  }

  void _moved() {
    final t = _out.value;
    playerExpansion.value = t;
    _coverAway.value = t < 1;
    if (t > 0 && _back == null) {
      PlayerSheet._unfolded.add(this);
      final back = _back = LocalHistoryEntry(
        // The page under it is not dismissed by Back: no back arrow in its app bar.
        impliesAppBarDismissal: false,
        onRemove: () {
          // Back: fold. (Removed after folding, it's no longer ours.)
          if (_back == null) return;
          _back = null;
          close();
        },
      );
      _route?.addLocalHistoryEntry(back);
    } else if (t == 0) {
      PlayerSheet._unfolded.remove(this);
      final back = _back;
      _back = null;
      if (back != null) _route?.removeLocalHistoryEntry(back);
    }
    setState(() {});
  }

  /// Whether a finger holds the sheet: a tap also ends in a "cancel", with nothing to undo.
  bool _dragging = false;

  /// Letting go below this folds it: a third of the way from where the finger took it.
  double _foldBelow = 0.67;

  /// A finger takes the sheet, open or from the mini player.
  void grab() {
    _dragging = true;
    _out.stop();
    _foldBelow = _out.value > 0.5 ? 0.67 : 0.33;
  }

  /// The sheet's top edge follows the finger, [dy] down (or up), over the way to the mini player.
  void dragBy(double dy) {
    final box = context.findRenderObject();
    if (!_dragging || box is! RenderBox) return;
    _out.value -= dy / _origin(box.size).top;
  }

  /// A flick decides; otherwise how far the finger took it.
  void release(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final fold = velocity > 700 || (velocity > -700 && _out.value < _foldBelow);
    fold ? close() : open();
  }

  /// [spot]'s box in the sheet's coordinates, while it is laid out.
  Rect? _measure(BuildContext? spot) {
    final box = spot != null && spot.mounted ? spot.findRenderObject() : null;
    final sheet = context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        sheet is! RenderBox) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: sheet) & box.size;
  }

  /// The mini player's card in the sheet's coordinates; without one, a line along the bottom.
  Rect _origin(Size size) =>
      _measure(card) ?? Rect.fromLTWH(0, size.height, size.width, 0);

  /// Where the player's cover rests in the player (as laid out on the last frame).
  Rect? _coverAtRest() {
    final cover = _coverKey.currentContext?.findRenderObject();
    final page = _pageKey.currentContext?.findRenderObject();
    if (cover is! RenderBox || page is! RenderBox || !cover.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      cover.getTransformTo(page),
      Offset.zero & cover.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _out.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (t > 0)
          LayoutBuilder(
            builder: (context, box) => _sheet(context, box.biggest, t),
          ),
      ],
    );
  }

  Widget _sheet(BuildContext context, Size size, double t) {
    final origin = _origin(size);
    final rect = Rect.lerp(origin, Offset.zero & size, t)!;
    final player = AppScope.of(context).player;
    final entry = player.current.value;
    final small =
        _measure(miniCover) ?? MiniCard.coverRect.shift(origin.topLeft);
    final cover = Rect.lerp(small, _coverAtRest() ?? small, t)!;
    return GestureDetector(
      onVerticalDragStart: (_) => grab(),
      onVerticalDragUpdate: (d) => dragBy(d.primaryDelta ?? 0),
      onVerticalDragEnd: (d) => release(d.primaryVelocity ?? 0),
      onVerticalDragCancel: () => release(0),
      child: ClipRRect(
        clipper: _Outline(
          RRect.fromRectAndRadius(rect, Radius.circular(14 * (1 - t))),
        ),
        clipBehavior: t < 1 ? Clip.antiAlias : Clip.none,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (entry != null && t < 1)
              Positioned.fromRect(
                rect: rect,
                child: MiniCard(
                  player: player,
                  entry: entry,
                  flying: true,
                  row: 1 - const Interval(0, 0.2).transform(t),
                  rowWidth: origin.width,
                ),
              ),
            Opacity(
              opacity: const Interval(0.3, 0.8).transform(t),
              child: Transform.translate(
                offset: Offset(0, rect.top),
                child: RepaintBoundary(key: _pageKey, child: _page),
              ),
            ),
            if (entry != null && t < 1)
              Positioned.fromRect(
                rect: cover,
                // The mini player's copy, already decoded: the player's sharp one takes over
                // where it rests.
                child: BookCover(
                  title: entry.book.title,
                  url: entry.book.cover,
                  radius: lerpDouble(8, 16, t)!,
                  decodeWidth: BookCover.decodeWidthFor(
                    MiniCard.coverRect.width *
                        MediaQuery.devicePixelRatioOf(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The sheet's outline while it grows out of the mini player.
class _Outline extends CustomClipper<RRect> {
  _Outline(this.outline);
  final RRect outline;

  @override
  RRect getClip(Size size) => outline;

  @override
  bool shouldReclip(_Outline old) => old.outline != outline;
}
