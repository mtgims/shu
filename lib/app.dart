import 'dart:math' show max;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'addons/addon_store.dart';
import 'downloads/download_store.dart';
import 'library/library_store.dart';
import 'player/audiobook_player.dart';
import 'screens/addons_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart' show PlayerRoute, openNextInSeries;
import 'screens/player_sheet.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';
import 'updates/updater.dart';
import 'widgets/adaptive.dart';
import 'widgets/desktop_input.dart';
import 'widgets/mini_player.dart';
import 'widgets/mini_window.dart';
import 'widgets/sidebar.dart';

/// Gives every screen access to the app's long-lived objects.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.addons,
    required this.library,
    required this.player,
    required this.downloads,
    required this.updater,
    required super.child,
  });

  final AddonStore addons;
  final LibraryStore library;
  final AudiobookPlayer player;
  final DownloadStore downloads;
  final Updater updater;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

/// Let code outside the widget tree (startup tasks) show snack bars and dialogs.
final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();
final homeShellKey = GlobalKey<HomeShellState>();

/// The main screen's tab. The side rail, which in wide windows sits beside the pages rather
/// than on the main screen, changes it too.
final currentTab = ValueNotifier<int>(0);

/// [updates]: the tab carries a dot while extension updates wait ([UpdatesBadge]).
const List<SidebarTab> _tabs = [
  (
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    updates: false,
  ),
  (
    label: 'Search',
    icon: Icons.search,
    selectedIcon: Icons.search,
    updates: false,
  ),
  (
    label: 'Library',
    icon: Icons.headphones_outlined,
    selectedIcon: Icons.headphones,
    updates: false,
  ),
  (
    label: 'Addons',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
    updates: true,
  ),
  (
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    updates: false,
  ),
];

/// The phone's bottom bar: the tabs in this order, Search in the middle under the thumb. The
/// desktop sidebar keeps [_tabs]' order (and Ctrl+1–5 with it).
const _barOrder = [0, 2, 1, 3, 4];

/// Back to the main screen, on tab [index]. Not while a dialog is open: it may be busy, and
/// closing it under its feet would make it close the page beneath when it ends.
bool goToTab(int index) {
  if (_dialogs.open.value != null) return false;
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
  currentTab.value = index;
  return true;
}

final _dialogs = _DialogObserver();

final _player = _PlayerObserver();

/// Whether the full player is open, so the side rail beside the pages can make way for it.
class _PlayerObserver extends NavigatorObserver {
  /// How far the full player is open, while it is on screen (opening, open or closing).
  final opening = ValueNotifier<Animation<double>?>(null);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PlayerRoute) return;
    final animation = route.animation!;
    opening.value = animation;
    animation.addStatusListener((status) {
      if (status.isDismissed && opening.value == animation) {
        opening.value = null;
      }
    });
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PlayerRoute && opening.value == route.animation) {
      opening.value = null;
    }
  }
}

/// Follows the dialogs and menus over the pages, so the side rail beside them can dim and stop
/// taking clicks the way the pages under a dialog's barrier do.
class _DialogObserver extends NavigatorObserver {
  final _popups = <PopupRoute<dynamic>>[];

  /// The barrier colour of the top dialog, or null when none is open.
  final open = ValueNotifier<Color?>(null);

  void _changed() => open.value = _popups.isEmpty
      ? null
      : _popups.last.barrierColor ?? Colors.transparent;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _popups.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _popups.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _popups.remove(route);
    _changed();
  }
}

class AudiobooksApp extends StatelessWidget {
  const AudiobooksApp({
    super.key,
    required this.addons,
    required this.library,
    required this.player,
    required this.downloads,
    required this.updater,
  });

  final AddonStore addons;
  final LibraryStore library;
  final AudiobookPlayer player;
  final DownloadStore downloads;
  final Updater updater;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      addons: addons,
      library: library,
      player: player,
      downloads: downloads,
      updater: updater,
      // Rebuilt when a setting changes, for the chosen theme (rare, and its themes are cached).
      child: ListenableBuilder(
        listenable: player.settings,
        builder: (context, _) => MaterialApp(
          title: 'Shu',
          scaffoldMessengerKey: messengerKey,
          navigatorKey: navigatorKey,
          navigatorObservers: [_dialogs, _player],
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light, player.settings.accent),
          darkTheme: appTheme(
            Brightness.dark,
            player.settings.accent,
            pureBlack: player.settings.pureBlack,
          ),
          themeMode: player.settings.themeMode,
          home: RailInset(child: HomeShell(key: homeShellKey)),
          // The pages and rail read the full window size even while the mini window shows.
          builder: (context, child) => MiniWindowFrame(
            child: Builder(
              builder: (context) => DesktopInput(
                player: player,
                navigator: navigatorKey,
                onSearch: () {
                  if (goToTab(1)) homeShellKey.currentState?.focusSearch();
                },
                onTab: goToTab,
                // Wide windows keep the rail beside every page, not only the main screen. The pages
                // span the whole window and leave the rail's width free ([RailInset]), so the
                // full player can take the whole window without anything changing size: the rail fades
                // out over it as it opens. (Shrinking the pages' area stretched the cover in flight.)
                child: Stack(
                  children: [
                    // Pages leave the rail's width empty: while the rail fades for the full player,
                    // this shows there instead of the window behind the app.
                    Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                    Positioned.fill(child: child!),
                    if (isWide(context))
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: ValueListenableBuilder(
                          valueListenable: _player.opening,
                          builder: (context, opening, rail) => opening == null
                              ? rail!
                              : IgnorePointer(
                                  child: FadeTransition(
                                    // Gone by halfway, so it never shows through the player.
                                    opacity: ReverseAnimation(
                                      CurvedAnimation(
                                        parent: opening,
                                        curve: const Interval(0, 0.5),
                                      ),
                                    ),
                                    child: rail,
                                  ),
                                ),
                          child: const Row(
                            children: [_SideRail(), VerticalDivider(width: 1)],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wide windows: the tabs down the side, with labels beside the icons or icons only.
class _SideRail extends StatefulWidget {
  const _SideRail();

  @override
  State<_SideRail> createState() => _SideRailState();
}

class _SideRailState extends State<_SideRail> {
  // The rail sits beside the navigator, so its tooltips need an overlay of their own.
  // Goes with its overlay when the window gets narrow (nothing else holds it).
  final _entry = OverlayEntry(builder: (_) => const _RailBody());

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).player.settings;
    return ValueListenableBuilder(
      valueListenable: _dialogs.open,
      builder: (context, barrier, rail) => AbsorbPointer(
        absorbing: barrier != null,
        child: Stack(
          children: [
            rail!,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  color: barrier ?? Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
      // An overlay takes all the width it is offered: give it the rail's, growing with it.
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => AnimatedContainer(
          duration: kThemeAnimationDuration,
          width: railWidthOf(context) - 1,
          child: Overlay(initialEntries: [_entry]),
        ),
      ),
    );
  }
}

/// Labels beside the icons only where the pages keep enough room, and when chosen.
bool _roomyForRail(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 1100;

bool _extended(BuildContext context) =>
    _roomyForRail(context) && AppScope.of(context).player.settings.railExtended;

/// The room the side rail takes at the left of the window, its divider included: none when
/// the window is too narrow for one.
double railWidthOf(BuildContext context) =>
    isWide(context) ? (_extended(context) ? 240 : 80) + 1 : 0;

/// Room for the side rail at the left of a page: the rail is drawn over the pages, not beside
/// them, so the full player can take the whole window with nothing changing size. It sits inside
/// the page, where hero flights measure from (around it, in the transition, they landed off by
/// the rail's width).
class RailInset extends StatelessWidget {
  const RailInset({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Follows the rail as it widens or narrows, in step with it.
    listenable: AppScope.of(context).player.settings,
    builder: (context, page) => AnimatedPadding(
      duration: kThemeAnimationDuration,
      padding: EdgeInsets.only(left: railWidthOf(context)),
      child: page,
    ),
    child: child,
  );
}

/// A page beside the side rail: every page opens as one, except the full player.
class PageBesideRail<T> extends MaterialPageRoute<T> {
  PageBesideRail({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Widget buildContent(BuildContext context) =>
      RailInset(child: super.buildContent(context));
}

class _RailBody extends StatelessWidget {
  const _RailBody();

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).player.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final extended = _extended(context);
        // Labels only once the rail has grown wide enough for them: they overflowed while it
        // widened (the expand button, a tablet turned on its side).
        return LayoutBuilder(
          builder: (context, box) => Sidebar(
            tabs: _tabs,
            extended: extended && box.maxWidth >= 200,
            onToggle: _roomyForRail(context)
                ? () => settings.railExtended = !extended
                : null,
          ),
        );
      },
    );
  }
}

/// Bottom navigation on phones (the side rail is beside the pages), the mini player above the
/// content.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  final _searchFocus = FocusNode(debugLabel: 'Search field');

  /// The cursor into the search field once the Search tab shows (Ctrl+F).
  void focusSearch() {
    // A hidden tab can't take the focus: ask once Search is the tab shown.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  /// Saves the listening position whenever the app leaves the screen; the OS may end it there.
  /// Closing a desktop window ends the app without hiding it first, so that saves too.
  late final _lifecycle = AppLifecycleListener(
    onHide: () => AppScope.of(context).player.saveNow(),
    onExitRequested: () async {
      final app = AppScope.of(context);
      await app.player.saveNow();
      // The torrent engine is a separate process: it must not outlive the window.
      await app.addons.host.torrents?.stop();
      return AppExitResponse.exit;
    },
  );

  /// How far a page pushed over the main screen covers it (follows a back gesture too).
  Animation<double>? get _covered => ModalRoute.of(context)?.secondaryAnimation;

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  /// Undoes the listener that announces the next book of a series once a book has ended.
  VoidCallback? _stopSuggesting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stopSuggesting != null) return;
    final next = AppScope.of(context).player.nextInSeries;
    void suggest() {
      final n = next.value;
      if (n == null) return;
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Next in the series: ${n.book.title}'),
          persist: false,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => openNextInSeries(n.addon, n.book),
          ),
        ),
      );
    }

    next.addListener(suggest);
    _stopSuggesting = () => next.removeListener(suggest);
  }

  @override
  void dispose() {
    _stopSuggesting?.call();
    _lifecycle.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  late final _pages = [
    const HomeScreen(),
    SearchScreen(focus: _searchFocus),
    const LibraryScreen(),
    const AddonsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: currentTab,
    builder: (context, tab, _) {
      final body = Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [
                for (final (i, page) in _pages.indexed)
                  // Hidden tabs keep their state but not their animations: a spinner on a
                  // hidden tab would keep the app drawing frames.
                  TickerMode(enabled: i == tab, child: page),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
      );
      // Android back: from another tab, go Home first instead of leaving the app. While the
      // player is out, Back folds it (its sheet's local history entry) wherever the tab.
      return ValueListenableBuilder(
        valueListenable: playerExpansion,
        builder: (context, out, page) => PopScope(
          canPop: tab == 0 || out > 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && playerExpansion.value == 0) currentTab.value = 0;
          },
          child: page!,
        ),
        child: PlayerSheet(
          child: Scaffold(
            body: body,
            bottomNavigationBar: isWide(context)
                ? null
                // Slides away while the player unfolds over it, or a page covers this one
                // (the mini player glides down to that page's edge), and back.
                : ListenableBuilder(
                    listenable: Listenable.merge([playerExpansion, _covered]),
                    builder: (context, bar) => FractionalTranslation(
                      translation: Offset(
                        0,
                        max(playerExpansion.value, _covered?.value ?? 0),
                      ),
                      child: bar,
                    ),
                    child: NavigationBar(
                      // A phone on its side: icons only (labels stay as tooltips), more page.
                      height: isShort(context) ? 56 : null,
                      labelBehavior: isShort(context)
                          ? NavigationDestinationLabelBehavior.alwaysHide
                          : null,
                      selectedIndex: _barOrder.indexOf(tab),
                      onDestinationSelected: (i) =>
                          currentTab.value = _barOrder[i],
                      destinations: [
                        for (final t in _barOrder.map((i) => _tabs[i]))
                          NavigationDestination(
                            icon: t.updates
                                ? UpdatesBadge(child: Icon(t.icon))
                                : Icon(t.icon),
                            selectedIcon: t.updates
                                ? UpdatesBadge(child: Icon(t.selectedIcon))
                                : Icon(t.selectedIcon),
                            label: t.label,
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
