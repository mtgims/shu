import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/audiobook_player.dart';

/// Keys and mouse buttons that work on every page, as in desktop players: Space plays or pauses,
/// ← and → skip back 15 s and forward 30 s, Esc, Alt+← and the mouse's back button go back,
/// Ctrl+F searches.
///
/// Space and the arrows act only when nothing in particular has the focus: in a text field they
/// type and move the cursor, and on a control reached with Tab, Space presses it.
class DesktopInput extends StatefulWidget {
  const DesktopInput({
    super.key,
    required this.player,
    required this.navigator,
    required this.onSearch,
    required this.child,
  });

  final AudiobookPlayer player;
  final GlobalKey<NavigatorState> navigator;
  final VoidCallback onSearch;
  final Widget child;

  @override
  State<DesktopInput> createState() => _DesktopInputState();
}

class _DesktopInputState extends State<DesktopInput> {
  final _focus = FocusNode(debugLabel: 'DesktopInput');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Nothing in particular has the focus: a page or dialog as a whole, or this widget.
  bool get _free {
    final f = FocusManager.instance.primaryFocus;
    return f == null || f is FocusScopeNode || f == _focus;
  }

  void _back() {
    final f = FocusManager.instance.primaryFocus;
    // Leaving a text field comes first, so the keys above work again.
    if (f != null && !_free) {
      f.unfocus();
      return;
    }
    widget.navigator.currentState?.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) {
          widget.navigator.currentState?.maybePop();
        }
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): _PlayPause(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _Rewind(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _Forward(),
          SingleActivator(LogicalKeyboardKey.escape): _Back(),
          SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _Back(),
          SingleActivator(LogicalKeyboardKey.keyF, control: true): _Search(),
        },
        child: Actions(
          actions: {
            _PlayPause: _KeyAction<_PlayPause>(
              () => _free,
              () => player.togglePlay(),
            ),
            _Rewind: _KeyAction<_Rewind>(() => _free, () => player.rewind()),
            _Forward: _KeyAction<_Forward>(
              () => _free,
              () => player.fastForward(),
            ),
            _Back: _KeyAction<_Back>(() => true, _back),
            _Search: _KeyAction<_Search>(() => true, widget.onSearch),
          },
          child: Focus(focusNode: _focus, autofocus: true, child: widget.child),
        ),
      ),
    );
  }
}

class _PlayPause extends Intent {
  const _PlayPause();
}

class _Rewind extends Intent {
  const _Rewind();
}

class _Forward extends Intent {
  const _Forward();
}

class _Back extends Intent {
  const _Back();
}

class _Search extends Intent {
  const _Search();
}

/// Runs [run] when [enabled]; otherwise the key goes on to whatever else wants it.
class _KeyAction<T extends Intent> extends Action<T> {
  _KeyAction(this.enabled, this.run);

  final bool Function() enabled;
  final VoidCallback run;

  @override
  bool isEnabled(T intent) => enabled();

  @override
  Object? invoke(T intent) {
    run();
    return null;
  }
}
