import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/content_cache.dart';
import '../addons/models.dart';
import '../app.dart';
import '../library/library_store.dart';
import '../widgets/book_tiles.dart';
import '../widgets/title_parts.dart';

/// The next book of each series the user has finished a book of, unless already started:
/// "Up next in your series". Only books started from a catalog know their series.
class UpNextRow extends StatefulWidget {
  const UpNextRow({super.key});

  @override
  State<UpNextRow> createState() => _UpNextRowState();
}

typedef _Next = ({InstalledAddon addon, BookSummary book, String after});

class _UpNextRowState extends State<UpNextRow> {
  /// The finished books asked about last: asked again only when that list changes.
  String _asked = '';
  List<_Next> _next = const [];

  /// At most this many finished books are asked about, newest first: one request each.
  static const _recent = 8;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final finished = scope.library.entries
            .where((e) => e.finished && e.workKey != null)
            .take(_recent)
            .toList();
        final asked = finished.map((e) => e.workKey).join(',');
        if (asked != _asked) {
          _asked = asked;
          _load(scope.addons, finished, asked);
        }
        final library = scope.library;
        // Started since: no longer "next".
        final next = [
          for (final n in _next)
            if (library.findByWork(n.addon.id, n.book.id) == null) n,
        ];
        if (next.isEmpty) return const SizedBox.shrink();
        return CardRow(
          title: 'Up next in your series',
          children: [
            for (final n in next)
              BookCard(
                title: n.book.title,
                subtitle: 'After ${n.after}',
                cover: n.book.cover,
                onTapDown: () => ContentCache.book(n.addon, n.book.id),
                onTap: () => openBook(context, n.addon, n.book),
              ),
          ],
        );
      },
    );
  }

  Future<void> _load(
    AddonStore addons,
    List<LibraryEntry> finished,
    String asked,
  ) async {
    final found = await Future.wait(finished.map((e) => _nextOf(addons, e)));
    if (!mounted || asked != _asked) return;
    final seen = <String>{};
    setState(() {
      _next = [
        for (final n in found)
          if (n != null && seen.add('${n.addon.id}|${n.book.id}')) n,
      ];
    });
  }

  Future<_Next?> _nextOf(AddonStore addons, LibraryEntry entry) async {
    final work = entry.workKey!;
    final bar = work.indexOf('|');
    final addon = bar < 0 ? null : addons.byId(work.substring(0, bar));
    if (addon == null) return null;
    try {
      final series = await addon.client.series(work.substring(bar + 1));
      final at = series.at;
      if (at == null || at >= series.books.length) return null;
      return (
        addon: addon,
        book: series.books[at],
        after: splitTitle(entry.book.title).title,
      );
    } on Object catch (e) {
      // Only the type: an extension's error can carry a link with an API key.
      debugPrint('No next book in the series (${e.runtimeType})');
      return null;
    }
  }
}
