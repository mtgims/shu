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
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: HomeShell(key: homeShellKey),
        builder: (context, child) => DesktopInput(
          player: player,
          navigator: navigatorKey,
          onSearch: () {
            navigatorKey.currentState?.popUntil((route) => route.isFirst);
            homeShellKey.currentState?.openSearch();
          },
          child: child!,
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.page);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// Bottom navigation on phones, a side rail on wide windows, the mini player above the content.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _searchFocus = FocusNode(debugLabel: 'Search field');

  void _select(int index) => setState(() => _index = index);

  /// The Search tab with the cursor in its field (Ctrl+F).
  void openSearch() {
    _select(1);
    _searchFocus.requestFocus();
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

  late final _destinations = [
    _Destination('Home', Icons.home_outlined, Icons.home, const HomeScreen()),
    _Destination(
      'Search',
      Icons.search,
      Icons.search,
      SearchScreen(focus: _searchFocus),
    ),
    const _Destination(
      'Library',
      Icons.headphones_outlined,
      Icons.headphones,
      LibraryScreen(),
    ),
    const _Destination(
      'Addons',
      Icons.extension_outlined,
      Icons.extension,
      AddonsScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final body = Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              for (final (i, d) in _destinations.indexed)
                // Hidden tabs keep their state but not their animations: a spinner on a hidden
                // tab would keep the app drawing frames.
                TickerMode(enabled: i == _index, child: d.page),
            ],
          ),
        ),
        const MiniPlayer(),
      ],
    );

    final Widget scaffold;
    if (wide) {
      scaffold = Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    } else {
      scaffold = Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }
    // Android back: from another tab, go Home first instead of leaving the app.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: scaffold,
    );
  }
}
