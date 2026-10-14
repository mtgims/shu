import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/content_cache.dart';
import '../addons/models.dart';
import '../widgets/cover.dart';

/// A playable version of a catalog book, found by a source extension.
class Version {
  const Version(this.addon, this.release);
  final InstalledAddon addon;
  final BookSummary release;

  /// Clearly the book: fine to play without asking. Sources that don't rate their matches are
  /// trusted, as before.
  bool get isGoodMatch => release.match == null || release.match == 'good';

  int get _rank => switch (release.match) {
    null || 'good' => 0,
    'fair' => 1,
    _ => 2,
  };
}

/// Which of [good] versions to play, in order: the first few are loaded and checked, and one
/// its source reports as cached goes first, since it starts at once. Versions that
/// fail to load are left out; the rest follow unchecked, to fall back on.
Future<List<({Version version, Book? book})>> playOrder(
  List<Version> good,
) async {
  const checked = 3;
  final probes = await Future.wait([
    for (final v in good.take(checked))
      () async {
        try {
          final book = await ContentCache.book(v.addon, v.release.id);
          if (book.chapters.isEmpty) return null;
          final list = await v.addon.client.sources(
            book.id,
            book.chapters.first.id,
          );
          if (list.sources.isEmpty) return null;
          final cached = list.sources.any((s) => s.cached == true);
          return (version: v, book: book, cached: cached);
        } on Object catch (e) {
          debugPrint('A version of ${v.release.id} is not playable: $e');
          return null;
        }
      }().timeout(const Duration(seconds: 15), onTimeout: () => null),
  ]);
  final ready = probes
      .whereType<({Version version, Book book, bool cached})>()
      .toList();
  return [
    for (final p in ready.where((p) => p.cached))
      (version: p.version, book: p.book),
    for (final p in ready.where((p) => !p.cached))
      (version: p.version, book: p.book),
    for (final v in good.skip(checked)) (version: v, book: null),
  ];
}

/// Lets the user pick a version when none clearly is the book.
Future<Version?> pickVersion(BuildContext context, List<Version> versions) {
  final theme = Theme.of(context);
  return showModalBottomSheet<Version>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Which version?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'None of these clearly matches this book. Pick the one to play.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final v in versions)
              _VersionTile(version: v, onTap: () => Navigator.pop(context, v)),
          ],
        ),
      ),
    ),
  );
}

/// Asks every source extension for versions of [work], all at once. A source that fails is
/// skipped; the others still answer. Clear matches come first.
Future<List<Version>> findVersions(AddonStore store, Book work) async {
  final sources = store.addons.where((a) => a.manifest.releases).toList();
  final results = await Future.wait([
    for (final addon in sources)
      addon.client
          .releases(work)
          .then(
            (found) => [for (final r in found) Version(addon, r)],
            onError: (Object e) {
              debugPrint('${addon.id} found no versions: $e');
              return <Version>[];
            },
          ),
  ]);
  final all = [for (final list in results) ...list];
  // Stable: within a level, each source keeps its own order.
  final order = all.indexed.toList()
    ..sort((a, b) {
      final byRank = a.$2._rank.compareTo(b.$2._rank);
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return [for (final (_, v) in order) v];
}

/// The versions list on a catalog book's page.
class VersionsList extends StatelessWidget {
  const VersionsList({
    super.key,
    required this.versions,
    required this.hasSources,
    required this.onOpen,
  });

  final Future<List<Version>>? versions;
  final bool hasSources;
  final void Function(Version) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (!hasSources) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.extension_outlined),
          title: Text(
            'Add a source extension to play books from this catalog.',
          ),
        ),
      );
    }
    return FutureBuilder<List<Version>>(
      future: versions,
      builder: (context, snap) {
        final list = snap.data;
        if (list == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No versions found.', style: muted),
          );
        }
        return Column(
          children: [
            for (final v in list)
              _VersionTile(
                version: v,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(v),
              ),
          ],
        );
      },
    );
  }
}

/// A version: its cover, name, and why it matches (or doesn't), with its size and source.
class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.version,
    required this.onTap,
    this.trailing,
  });

  final Version version;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final release = version.release;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: BookCover(
        title: release.title,
        url: release.cover,
        size: 44,
        radius: 6,
      ),
      title: Text(release.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [...release.tags, ?release.details].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
