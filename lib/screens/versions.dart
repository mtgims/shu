import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/models.dart';
import '../widgets/cover.dart';

/// A playable version of a catalog book, found by a source extension.
class Version {
  const Version(this.addon, this.release);
  final InstalledAddon addon;
  final BookSummary release;
}

/// Asks every source extension for versions of [work], all at once. A source that fails is
/// skipped; the others still answer.
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
  return [for (final list in results) ...list];
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
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: BookCover(
                  title: v.release.title,
                  url: v.release.cover,
                  size: 44,
                  radius: 6,
                ),
                title: Text(
                  v.release.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [...v.release.tags, ?v.release.details].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(v),
              ),
          ],
        );
      },
    );
  }
}
