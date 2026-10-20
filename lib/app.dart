import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'addons/addon_store.dart';
import 'library/library_store.dart';
import 'player/audiobook_player.dart';
import 'screens/addons_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'theme.dart';
import 'updates/updater.dart';
import 'widgets/adaptive.dart';
import 'widgets/desktop_input.dart';
import 'widgets/mini_player.dart';

/// Gives every screen access to the app's long-lived objects.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.addons,
    required this.library,
    required this.player,
    required this.updater,
    required super.child,
  });

  final AddonStore addons;
  final LibraryStore library;
  final AudiobookPlayer player;
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

const _tabs = [
  (label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
  (label: 'Search', icon: Icons.search, selectedIcon: Icons.search),
  (
    label: 'Library',
    icon: Icons.headphones_outlined,
    selectedIcon: Icons.headphones,
  ),
  (
    label: 'Addons',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
  ),
];

/// Back to the main screen, on tab [index]. Not while a dialog is open: it may be busy, and
/// closing it under its feet would make it close the page beneath when it ends.
bool goToTab(int index) {
  if (_dialogs.open.value != null) return false;
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
  currentTab.value = index;
  return true;
}

final _dialogs = _DialogObserver();

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
    required this.updater,
  });

  final AddonStore addons;
  final LibraryStore library;
  final AudiobookPlayer player;
  final Updater updater;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      addons: addons,
      library: library,
      player: player,
      updater: updater,
      child: MaterialApp(
        title: 'Shu',
        scaffoldMessengerKey: messengerKey,
        navigatorKey: navigatorKey,
        navigatorObservers: [_dialogs],
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: HomeShell(key: homeShellKey),
        builder: (context, child) => DesktopInput(
          player: player,
          navigator: navigatorKey,
          onSearch: () {
            if (goToTab(1)) homeShellKey.currentState?.focusSearch();
          },
          onTab: goToTab,
          // Wide windows keep the rail beside every page, not only the main screen. The key
          // keeps the pages when the window crosses the width.
          child: Row(
            children: [
              if (isWide(context)) ...[
                const _SideRail(),
                const VerticalDivider(width: 1),
              ],
              Expanded(key: const ValueKey('pages'), child: child!),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
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
    child: ValueListenableBuilder(
      valueListenable: currentTab,
      builder: (context, tab, _) => NavigationRail(
        selectedIndex: tab,
        onDestinationSelected: goToTab,
        labelType: NavigationRailLabelType.all,
        destinations: [
          for (final t in _tabs)
            NavigationRailDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: Text(t.label),
            ),
        ],
      ),
    ),
  );
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

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  late final _pages = [
    const HomeScreen(),
    SearchScreen(focus: _searchFocus),
    const LibraryScreen(),
    const AddonsScreen(),
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
      // Android back: from another tab, go Home first instead of leaving the app.
      return PopScope(
        canPop: tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) currentTab.value = 0;
        },
        child: Scaffold(
          body: body,
          bottomNavigationBar: isWide(context)
              ? null
              : NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => currentTab.value = i,
                  destinations: [
                    for (final t in _tabs)
                      NavigationDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.selectedIcon),
                        label: t.label,
                      ),
                  ],
                ),
        ),
      );
    },
  );
}
