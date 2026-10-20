import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ↑ ↓, Page Up/Down, Home and End scroll the page, as in a browser, while [enabled] (nothing in
/// particular has the focus). When it isn't, or the page doesn't scroll, the key goes on to
/// Flutter's own handling (moving the focus with the arrows).
class KeyboardScroll extends StatelessWidget {
  const KeyboardScroll({
    super.key,
    required this.navigator,
    required this.enabled,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigator;
  final bool Function() enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.arrowUp): _Scroll(_Step.lineUp),
      SingleActivator(LogicalKeyboardKey.arrowDown): _Scroll(_Step.lineDown),
      SingleActivator(LogicalKeyboardKey.pageUp): _Scroll(_Step.pageUp),
      SingleActivator(LogicalKeyboardKey.pageDown): _Scroll(_Step.pageDown),
      SingleActivator(LogicalKeyboardKey.home): _Scroll(_Step.top),
      SingleActivator(LogicalKeyboardKey.end): _Scroll(_Step.bottom),
    },
    child: Actions(actions: {_Scroll: _ScrollAction(this)}, child: child),
  );

  /// The vertical list that fills most of what is on screen: the page's own, not one in a
  /// hidden tab, under another page or behind a dialog. Those are told apart by hit testing
  /// the list's middle, which needs no listeners and makes no list rebuild.
  ScrollPosition? _target() {
    final root = navigator.currentContext;
    if (root == null) return null;
    final view = View.of(root).viewId;
    ScrollPosition? best;
    var bestArea = 0.0;
    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        final position = (e.state as ScrollableState).position;
        final box = e.findRenderObject();
        if (position.axis == Axis.vertical &&
            position.hasContentDimensions &&
            position.maxScrollExtent > position.minScrollExtent &&
            box is RenderBox &&
            box.attached &&
            box.hasSize) {
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(
            hit,
            box.localToGlobal(box.size.center(Offset.zero)),
            view,
          );
          final area = box.size.width * box.size.height;
          if (area > bestArea && hit.path.any((h) => h.target == box)) {
            best = position;
            bestArea = area;
          }
        }
      }
      e.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    return best;
  }
}

enum _Step { lineUp, lineDown, pageUp, pageDown, top, bottom }

class _Scroll extends Intent {
  const _Scroll(this.step);
  final _Step step;
}

class _ScrollAction extends Action<_Scroll> {
  _ScrollAction(this.widget);

  final KeyboardScroll widget;
  ScrollPosition? _position;

  @override
  bool isEnabled(_Scroll intent) =>
      widget.enabled() && (_position = widget._target()) != null;

  @override
  Object? invoke(_Scroll intent) {
    final p = _position!;
    final page = p.viewportDimension * 0.8;
    final to = switch (intent.step) {
      _Step.lineUp => p.pixels - 64,
      _Step.lineDown => p.pixels + 64,
      _Step.pageUp => p.pixels - page,
      _Step.pageDown => p.pixels + page,
      _Step.top => p.minScrollExtent,
      _Step.bottom => p.maxScrollExtent,
    };
    p.animateTo(
      to.clamp(p.minScrollExtent, p.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
    return null;
  }
}
