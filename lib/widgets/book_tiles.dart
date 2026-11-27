import 'dart:math' show min;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../addons/addon_store.dart';
import '../app.dart' show PageBesideRail;
import '../addons/content_cache.dart';
import '../addons/models.dart';
import '../library/library_store.dart';
import '../screens/book_screen.dart';
import '../theme.dart';
import 'adaptive.dart';
import 'cover.dart';
import 'title_parts.dart';

void openBook(BuildContext context, InstalledAddon addon, BookSummary summary) {
  Navigator.of(context).push(
    PageBesideRail<void>(
      withSheet: true,
      builder: (_) => BookScreen(addon: addon, summary: summary),
    ),
  );
}

/// Opens a library book, keeping the look of the catalog book it was started from.
void openEntry(BuildContext context, InstalledAddon addon, LibraryEntry entry) {
  Navigator.of(context).push(
    PageBesideRail<void>(
      withSheet: true,
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
      borderRadius: BorderRadius.circular(12),
      onTapDown: (_) => ContentCache.book(addon, book.id),
      onTap: () => openBook(context, addon, book),
      child: Padding(
        // The list around it adds 8 more, so its highlight keeps off the window's edges.
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                    style: bookTitle(theme.textTheme.titleSmall),
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
    final (:title, :labels) = splitTitle(this.title);
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
              Stack(
                children: [
                  BookCover(title: title, url: cover),
                  if (labels.isNotEmpty)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [for (final l in labels) TitleLabel(l)],
                      ),
                    ),
                ],
              ),
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
                style: bookTitle(
                  theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
    this.height = 230,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // A compact "See all": a full-height button doubles the gap above the row.
              if (trailing case final trailing?)
                TextButtonTheme(
                  data: TextButtonThemeData(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  child: trailing,
                ),
            ],
          ),
        ),
        CardStrip(height: height, children: children),
      ],
    );
  }
}

/// A horizontal list of cards. In wide windows arrows at its ends page through it, and a mouse
/// can drag it: few mice scroll sideways, so otherwise the cards past the edge are out of reach.
class CardStrip extends StatefulWidget {
  const CardStrip({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.height = 230,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  /// Room for the cards: 230 fits a cover with two lines of title and one of byline.
  final double height;

  @override
  State<CardStrip> createState() => _CardStripState();
}

class _CardStripState extends State<CardStrip> {
  final _scroll = ScrollController();
  bool _canBack = false;
  bool _canForward = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollMetrics m) {
    final back = m.pixels > m.minScrollExtent + 1;
    final forward = m.pixels < m.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
    return false;
  }

  void _page(int direction) {
    final p = _scroll.position;
    _scroll.animateTo(
      (p.pixels + direction * p.viewportDimension * 0.8).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = SizedBox(
      height: widget.height,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: widget.padding,
        itemCount: widget.children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (_, i) => widget.children[i],
      ),
    );
    if (!isWide(context)) return list;
    // Over the covers' middle, or the middle of a lower strip.
    final arrowTop = min(48.0, (widget.height - 48) / 2);
    Widget arrow(int direction) => IconButton.filledTonal(
      tooltip: direction < 0 ? 'Back' : 'More',
      onPressed: () => _page(direction),
      icon: Icon(direction < 0 ? Icons.chevron_left : Icons.chevron_right),
    );
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onScroll(n.metrics),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) => _onScroll(n.metrics),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context)
              .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: Stack(
            children: [
              list,
              if (_canBack)
                Positioned(left: 4, top: arrowTop, child: arrow(-1)),
              if (_canForward)
                Positioned(right: 4, top: arrowTop, child: arrow(1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "4 h 12 min left" for a book under way at [speed]. Without every chapter's length it is
/// estimated from the book's length and how far along it is ("About 6 h left"). Null when
/// neither is known, or the book isn't started or is finished (those say so in words).
String? timeLeftText(LibraryEntry entry, double speed) {
  if (entry.finished || !entry.started) return null;
  final left = entry.timeLeftAt(entry.position);
  if (left != null) return '${formatLength(left * (1 / speed))} left';
  final minutes = entry.book.durationMinutes ?? 0;
  if (minutes <= 0) return null;
  final estimate = Duration(minutes: minutes) * ((1 - entry.progress) / speed);
  // Chapters are uneven: minutes would claim a precision the estimate doesn't have.
  final rounded = estimate.inMinutes >= 90
      ? Duration(hours: (estimate.inMinutes / 60).round())
      : estimate;
  return 'About ${formatLength(rounded)} left';
}

/// A length in words: "4 h 12 min", "38 min", "1 min" (never "0 min").
String formatLength(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '${m < 1 ? 1 : m} min';
  return m == 0 ? '$h h' : '$h h $m min';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// An edition note taken out of a title ("Part 1 of 2", "Full cast"), as a small tag on a cover.
class TitleLabel extends StatelessWidget {
  const TitleLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(text, style: theme.textTheme.labelSmall),
      ),
    );
  }
}
