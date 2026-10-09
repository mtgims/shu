import 'package:flutter/material.dart';

import 'addons/addon_store.dart';
import 'library/library_store.dart';
import 'player/audiobook_player.dart';
import 'screens/addons_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'theme.dart';
import 'widgets/mini_player.dart';

/// Gives every screen access to the app's long-lived objects.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.addons,
    required this.library,
    required this.player,
    required super.child,
  });

  final AddonStore addons;
  final LibraryStore library;
  final AudiobookPlayer player;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

/// Lets code outside the widget tree (startup tasks) show snack bars.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

class AudiobooksApp extends StatelessWidget {
  const AudiobooksApp({
    super.key,
    required this.addons,
    required this.library,
    required this.player,
  });

  final AddonStore addons;
  final LibraryStore library;
  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      addons: addons,
      library: library,
      player: player,
      child: MaterialApp(
        title: 'Shu',
        scaffoldMessengerKey: messengerKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeShell(),
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
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Saves the listening position whenever the app leaves the screen; the OS may end it there.
  late final _lifecycle = AppLifecycleListener(
    onHide: () => AppScope.of(context).player.saveNow(),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  late final _destinations = [
    _Destination('Home', Icons.home_outlined, Icons.home, const HomeScreen()),
    const _Destination('Search', Icons.search, Icons.search, SearchScreen()),
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
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [for (final d in _destinations) d.page],
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
              onDestinationSelected: (i) => setState(() => _index = i),
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
          onDestinationSelected: (i) => setState(() => _index = i),
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
        if (!didPop) setState(() => _index = 0);
      },
      child: scaffold,
    );
  }
}
