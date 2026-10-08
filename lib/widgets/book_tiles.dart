import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../addons/content_cache.dart';
import '../addons/models.dart';
import '../library/library_store.dart';
import '../screens/book_screen.dart';
import 'cover.dart';

void openBook(BuildContext context, InstalledAddon addon, BookSummary summary) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BookScreen(addon: addon, summary: summary),
    ),
  );
}

/// Opens a library book, keeping the look of the catalog book it was started from.
void openEntry(BuildContext context, InstalledAddon addon, LibraryEntry entry) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BookScreen(
        addon: addon,
        summary: entry.book,
        look: entry.workKey == null ? null : entry.book,
        workKey: entry.workKey,
      ),
    ),
  );
}

/// A row in search results: cover, title, author, and the release details.
class BookListTile extends StatelessWidget {
  const BookListTile({super.key, required this.addon, required this.book});

  final InstalledAddon addon;
  final BookSummary book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return InkWell(
      onTapDown: (_) => ContentCache.book(addon, book.id),
      onTap: () => openBook(context, addon, book),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(title: book.title, url: book.cover, size: 64, radius: 8),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (book.byline.isNotEmpty)
                    Text(
                      book.byline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    [...book.tags, ?book.details].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A cover card for horizontal rows on the home screen.
class BookCard extends StatelessWidget {
  const BookCard({
    super.key,
    required this.title,
    this.subtitle,
    this.cover,
    this.progress,
    required this.onTap,
    this.onTapDown,
    this.width = rowWidth,
  });

  /// Width in horizontal rows; grids pass their own.
  static const rowWidth = 140.0;

  final double width;

  final String title;
  final String? subtitle;
  final String? cover;
  final double? progress;
  final VoidCallback onTap;

  /// Called as soon as a finger touches the card, to start loading early.
  final VoidCallback? onTapDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onTapDown: onTapDown == null ? null : (_) => onTapDown!(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(title: title, url: cover),
              if (progress != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled horizontal list of cards.
class CardRow extends StatelessWidget {
  const CardRow({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ],
    );
  }
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
