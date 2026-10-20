import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/audiobook_player.dart';
import 'focus_ring.dart';
import 'keyboard_scroll.dart';

/// Keys and mouse buttons that work on every page, as in desktop players: Space plays or pauses,
/// ← and → skip back 15 s and forward 30 s, ↑ ↓ Page Up/Down Home End scroll ([KeyboardScroll]),
/// Esc, Alt+← and the mouse's back button go back,
/// Ctrl+F searches, Ctrl+1 to Ctrl+4 open the tabs, and the keyboard's media keys play, pause and
/// skip chapters.
///
/// Space and the arrows act only when nothing in particular has the focus: in a text field they
/// type and move the cursor, and on a control reached with Tab, Space presses it.
class DesktopInput extends StatefulWidget {
  const DesktopInput({
    super.key,
    required this.player,
    required this.navigator,
    required this.onSearch,
    required this.onTab,
    required this.child,
  });

  final AudiobookPlayer player;
  final GlobalKey<NavigatorState> navigator;
  final VoidCallback onSearch;

  /// Ctrl+1 to Ctrl+4: the main screen's tabs.
  final void Function(int index) onTab;
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
          SingleActivator(LogicalKeyboardKey.digit1, control: true): _Tab(0),
          SingleActivator(LogicalKeyboardKey.digit2, control: true): _Tab(1),
          SingleActivator(LogicalKeyboardKey.digit3, control: true): _Tab(2),
          SingleActivator(LogicalKeyboardKey.digit4, control: true): _Tab(3),
          // Media keys work everywhere: no text field uses them.
          SingleActivator(LogicalKeyboardKey.mediaPlayPause): _Media(
            _Key.toggle,
          ),
          SingleActivator(LogicalKeyboardKey.mediaPlay): _Media(_Key.play),
          SingleActivator(LogicalKeyboardKey.mediaPause): _Media(_Key.pause),
          SingleActivator(LogicalKeyboardKey.mediaTrackNext): _Media(_Key.next),
          SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): _Media(
            _Key.previous,
          ),
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
            _Tab: CallbackAction<_Tab>(
              onInvoke: (intent) => widget.onTab(intent.index),
            ),
            _Media: CallbackAction<_Media>(
              onInvoke: (intent) => switch (intent.key) {
                _Key.toggle => player.togglePlay(),
                _Key.play => player.play(),
                _Key.pause => player.pause(),
                _Key.next => player.skipToNext(),
                _Key.previous => player.skipToPrevious(),
              },
            ),
          },
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            child: KeyboardScroll(
              navigator: widget.navigator,
              enabled: () => _free,
              child: FocusRing(ignore: _focus, child: widget.child),
            ),
          ),
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

enum _Key { toggle, play, pause, next, previous }

class _Media extends Intent {
  const _Media(this.key);
  final _Key key;
}

class _Tab extends Intent {
  const _Tab(this.index);
  final int index;
}
