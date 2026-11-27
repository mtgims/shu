import 'package:flutter/material.dart';

import '../app.dart';
import '../library/library_store.dart';
import '../screens/addons_screen.dart' show UpdatesBadge;
import '../screens/player_sheet.dart';
import '../theme.dart';
import 'book_tiles.dart';
import 'cover.dart';
import 'title_parts.dart';

typedef SidebarTab = ({
  String label,
  IconData icon,
  IconData selectedIcon,
  bool updates,
});

/// The desktop sidebar: the tabs as full-width rows, then the books in progress, one click to go
/// on with one. [extended] shows labels and titles; otherwise icons and covers only, with tooltips.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.tabs,
    required this.extended,
    required this.onToggle,
  });

  final List<SidebarTab> tabs;
  final bool extended;

  /// Collapses or widens the sidebar; null where the window has no room for it wide.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // A Material: the rows' ink needs one.
    return Material(
      color: colors.surface,
      // Clear of a tablet's status bar and home indicator (none on desktop).
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: currentTab,
                builder: (context, _) => Column(
                  children: [
                    for (final (i, tab) in tabs.indexed)
                      _TabRow(
                        tab: tab,
                        selected: currentTab.value == i,
                        extended: extended,
                        onTap: () => goToTab(i),
                      ),
                  ],
                ),
              ),
              Expanded(child: _InProgress(extended: extended)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final logo = Text(
      // The app's icon is this character.
      extended ? '书  Shu' : '书',
      style: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
    final toggle = onToggle == null
        ? null
        : IconButton(
            tooltip: extended ? 'Collapse' : 'Expand',
            icon: Icon(extended ? Icons.menu_open : Icons.menu),
            onPressed: onToggle,
          );
    if (extended) {
      return SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(child: logo),
            ?toggle,
          ],
        ),
      );
    }
    return Column(
      children: [
        SizedBox(height: 48, child: Center(child: logo)),
        ?toggle,
      ],
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tab,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final SidebarTab tab;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ink = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    Widget icon = Icon(selected ? tab.selectedIcon : tab.icon, color: ink);
    if (tab.updates) icon = UpdatesBadge(child: icon);
    final row = Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: extended
              ? Row(
                  children: [
                    const SizedBox(width: 14),
                    icon,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        tab.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: selected ? ink : colors.onSurface,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                )
              : Center(child: icon),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: selected,
        button: true,
        label: extended ? null : tab.label,
        child: extended ? row : Tooltip(message: tab.label, child: row),
      ),
    );
  }
}

/// The books under way, newest first; the one playing opens the player, the others go on.
class _InProgress extends StatelessWidget {
  const _InProgress({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.library, scope.player.current]),
      builder: (context, _) {
        final entries = scope.library.entries
            .where((e) => !e.finished && e.started)
            .toList();
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            if (extended)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'In progress',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final entry in entries)
                    _BookRow(entry: entry, extended: extended),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.entry, required this.extended});
  final LibraryEntry entry;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final playing = scope.player.current.value?.key == entry.key;
    final title = splitTitle(entry.book.title).title;
    final status = playing
        ? 'Playing'
        : timeLeftText(entry, scope.player.settings.speed) ??
              '${(entry.progress * 100).floor()} % read';
    void open() {
      if (playing) {
        final nav = navigatorKey.currentContext;
        if (nav != null) openPlayer(nav);
      } else {
        scope.player.resume(entry);
      }
    }

    final cover = BookCover(
      title: entry.book.title,
      url: entry.book.cover,
      size: 40,
      radius: 6,
    );
    final row = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: extended
            ? Row(
                children: [
                  cover,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bookTitle(
                            theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: playing ? colors.primary : null,
                            ),
                          ),
                        ),
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: playing
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Center(child: cover),
      ),
    );
    return Semantics(
      button: true,
      label: playing ? '$title, playing: open the player' : 'Go on with $title',
      child: Tooltip(
        message: playing ? 'Open the player' : '$title · $status',
        waitDuration: const Duration(milliseconds: 500),
        child: row,
      ),
    );
  }
}
