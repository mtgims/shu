import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../screens/now_playing_screen.dart' show PlayerTransport;
import '../theme.dart';
import 'cover.dart';
import 'mini_player.dart' show MiniPlayerTheme, ProgressLine, StatusLine;

/// Desktop: the window shrinks to a small player card that stays above other windows, like a
/// video's picture-in-picture. Same window and same player, so nothing needs handing over.
///
/// Wayland lets no app keep itself on top or place itself: there the window manager decides, and
/// it can recognise the mini player by its window title ([title]).
class MiniWindow {
  static final active = ValueNotifier(false);

  /// What window managers can match to float and pin it (the README says so).
  static const title = 'Shu mini player';
  static const size = Size(360, 128);

  /// Smaller than this, even the phone layout has no room.
  static const _minimum = Size(360, 520);

  static bool get available => Platform.isLinux || Platform.isWindows;

  /// The window before it shrank, to put it back.
  static Rect? _before;
  static bool _wasMaximized = false;

  /// The pages' size before it shrank: they keep it while hidden.
  static Size? fullSize;

  static Size get _viewSize {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.physicalSize / view.devicePixelRatio;
  }

  static Future<void> setUp() async {
    if (!available) return;
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(_minimum);
  }

  static Future<void> enter() async {
    if (active.value) return;
    _wasMaximized = await windowManager.isMaximized();
    if (_wasMaximized) await windowManager.unmaximize();
    _before = await windowManager.getBounds();
    fullSize = _viewSize;
    // The button's tooltip would stay open in the hidden pages.
    Tooltip.dismissAllToolTips();
    active.value = true;
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setMinimumSize(size);
    await windowManager.setSize(size);
    await windowManager.setAlwaysOnTop(true);
    // Last: a window manager matching the title then sees the window already small.
    await windowManager.setTitle(title);
  }

  static Future<void> leave() async {
    if (!active.value) return;
    await windowManager.setTitle('Shu');
    await windowManager.setAlwaysOnTop(false);
    // Before the size: GTK counts its sizes without the title bar, so the window gets its old
    // size back only with the title bar already there.
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(_minimum);
    if (_before != null) await windowManager.setBounds(_before);
    if (_wasMaximized) await windowManager.maximize();
    // Window managers resize in their own time: wait for it, a second at most, so the pages
    // never lay out in the small window.
    for (var i = 0; i < 60 && _viewSize.height < _minimum.height; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    Tooltip.dismissAllToolTips();
    active.value = false;
  }
}

/// Shows [child] (the whole app) or, in the mini window, the player card. The app stays built
/// meanwhile under the card, at its full size, out of keyboard reach and with its animations
/// stopped, so it comes back as it was.
class MiniWindowFrame extends StatelessWidget {
  const MiniWindowFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: MiniWindow.active,
      builder: (context, mini, app) {
        final full = mini ? MiniWindow.fullSize : null;
        final media = MediaQuery.of(context);
        // The same widgets either way: a change in shape would rebuild the app from scratch.
        // Offstage, IgnorePointer or ExcludeSemantics would hide the app better, but switching
        // any of them broke the semantics tree (an assertion a few frames later). Under the
        // small card there is little to draw anyway.
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: mini,
              child: TickerMode(
                enabled: !mini,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: full?.width,
                  maxWidth: full?.width,
                  minHeight: full?.height,
                  maxHeight: full?.height,
                  child: MediaQuery(
                    data: full == null ? media : media.copyWith(size: full),
                    child: app!,
                  ),
                ),
              ),
            ),
            // Covers the app and takes every click. Above the navigator: its tooltips need an
            // overlay of their own.
            if (mini)
              Overlay.wrap(
                // Cut off, never squeezed, while the title bar is back and the window not yet
                // grown.
                child: LayoutBuilder(
                  builder: (context, box) {
                    final height = max(box.maxHeight, MiniWindow.size.height);
                    return ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: height,
                        maxHeight: height,
                        child: const _MiniCard(),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
      child: child,
    );
  }
}

/// The mini window's contents: cover, title and chapter, the controls, the chapter's progress
/// along the bottom. Dragging it anywhere moves the window.
class _MiniCard extends StatelessWidget {
  const _MiniCard();

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    final back = IconButton(
      tooltip: 'Back to the full window',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: MiniWindow.leave,
      icon: const Icon(Icons.open_in_full),
    );
    return ValueListenableBuilder<LibraryEntry?>(
      valueListenable: player.current,
      builder: (context, entry, _) => entry == null
          ? Material(child: Center(child: back))
          : MiniPlayerTheme(
              url: entry.book.cover,
              child: Builder(
                builder: (context) {
                  final theme = Theme.of(context);
                  return Material(
                    color: Color.alphaBlend(
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      theme.colorScheme.surfaceContainerHigh,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => windowManager.startDragging(),
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
                              child: Row(
                                children: [
                                  BookCover(
                                    title: entry.book.title,
                                    url: entry.book.cover,
                                    size: 100,
                                    radius: 8,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    entry.book.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: bookTitle(
                                                      theme
                                                          .textTheme
                                                          .titleSmall,
                                                    ),
                                                  ),
                                                  StatusLine(
                                                    player: player,
                                                    entry: entry,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            back,
                                          ],
                                        ),
                                        FittedBox(
                                          child: PlayerTransport(
                                            player: player,
                                            entry: entry,
                                            compact: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ProgressLine(player: player),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
