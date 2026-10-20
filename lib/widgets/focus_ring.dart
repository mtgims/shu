import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// An outline around whatever has the keyboard focus, over the whole app: the same clear mark on
/// every control, which Material's faint focus tints are not. Shown after a key press, hidden
/// again by a click, as browsers do. Text fields and [ignore] (a page-wide node) get none.
///
/// The outline follows its control only in frames that are drawn anyway (scrolling, a page
/// sliding in), so it costs nothing while the app is idle.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.ignore, required this.child});

  final FocusNode ignore;
  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  final _rect = ValueNotifier<Rect?>(null);
  bool _keyboard = false;
  bool _listening = true;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_update);
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      // Frame callbacks can't be removed; this one goes quiet after dispose.
      if (_listening) _update();
    });
  }

  @override
  void dispose() {
    _listening = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.removeListener(_update);
    _rect.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && !_keyboard) {
      _keyboard = true;
      _update();
    }
    return false;
  }

  void _update() {
    final node = FocusManager.instance.primaryFocus;
    final context = node?.context;
    final show =
        _keyboard &&
        node != null &&
        context != null &&
        context.mounted &&
        node is! FocusScopeNode &&
        node != widget.ignore &&
        context.widget is! EditableText &&
        context.findAncestorWidgetOfExactType<EditableText>() == null;
    // A control that hasn't been laid out yet has no place; the next frame gives it one.
    final box = show ? context.findRenderObject() : null;
    final rect = box is RenderBox && box.attached && box.hasSize
        ? node!.rect
        : null;
    if (rect != _rect.value) _rect.value = rect;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      _keyboard = false;
      _update();
    },
    child: CustomPaint(
      foregroundPainter: _RingPainter(
        _rect,
        Theme.of(context).colorScheme.primary,
      ),
      child: widget.child,
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.rect, this.color) : super(repaint: rect);

  final ValueNotifier<Rect?> rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect.value;
    if (r == null || r.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(3), const Radius.circular(12)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.rect != rect || old.color != color;
}
