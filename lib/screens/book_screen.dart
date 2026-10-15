import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../addons/addon_store.dart';
import '../addons/content_cache.dart';
import '../addons/models.dart';
import '../app.dart';
import '../library/library_store.dart';
import '../widgets/book_tiles.dart';
import '../widgets/cover.dart';
import '../widgets/mini_player.dart';
import 'local_book_menu.dart';
import 'now_playing_screen.dart';
import 'versions.dart';

/// A book's page. Catalog books (no chapters) list the versions sources found and play the
/// best one; versions and other books show their chapters and where they play from.
class BookScreen extends StatefulWidget {
  const BookScreen({
    super.key,
    required this.addon,
    required this.summary,
    this.look,
    this.workKey,
  });

  final InstalledAddon addon;
  final BookSummary summary;

  /// For a version of a catalog book: that book, whose title, cover and credits it shows.
  final Book? look;

  /// For a version of a catalog book: `addonId|bookId` of that book, kept in the library.
  final String? workKey;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  late Future<Book> _book = _load();
  Future<SourceList>? _sources;
  Future<List<Version>>? _versions;
  Future<List<BookSummary>>? _series;
  String? _sourceId;
  bool _expanded = false;
  bool _starting = false;

  /// A book from the library comes complete: shown at once, refreshed in the background.
  Book? get _stored => widget.summary is Book ? widget.summary as Book : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stored = _stored;
    if (stored != null && _sources == null && _versions == null) {
      _prepare(stored);
    }
  }

  /// What the page needs next: versions for a catalog book, sources for a playable one.
  void _prepare(Book book) {
    if (book.isWork) {
      _versions = findVersions(AppScope.of(context).addons, book);
      if (book.series != null) {
        _series = widget.addon.client.series(book.id).catchError((Object e) {
          debugPrint('No series row for ${book.id}: $e');
          return <BookSummary>[];
        });
      }
      return;
    }
    final entry = AppScope.of(context).library.find(widget.addon.id, book.id);
    _sourceId ??= entry?.sourceId;
    final at = (entry?.chapterIndex ?? 0).clamp(0, book.chapters.length - 1);
    _sources = widget.addon.client.sources(book.id, book.chapters[at].id);
  }

  Future<Book> _load() async {
    var book = await ContentCache.book(widget.addon, widget.summary.id);
    final look = widget.look;
    if (look != null && !book.isWork) book = book.withLookOf(look);
    if (mounted && _sources == null && _versions == null) {
      setState(() => _prepare(book));
    }
    return book;
  }

  String get _workKey => LibraryEntry.keyOf(widget.addon.id, widget.summary.id);

  Future<void> _play(Book book, {int? chapter}) async {
    final player = AppScope.of(context).player;
    final navigator = Navigator.of(context);
    // The player opens at once and shows progress; getting the link can take seconds.
    unawaited(
      player.openBook(
        widget.addon,
        book,
        chapterIndex: chapter,
        sourceId: _sourceId,
        workKey: widget.workKey,
      ),
    );
    await navigator.push(NowPlayingScreen.route());
  }

  /// Play on a catalog book: the version listened to before, or the best one found.
  Future<void> _playWork(Book work) async {
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final earlier = scope.library.findByWork(widget.addon.id, work.id);
    if (earlier != null && !earlier.finished) {
      unawaited(scope.player.resume(earlier));
      await navigator.push(NowPlayingScreen.route());
      return;
    }
    setState(() => _starting = true);
    try {
      final versions = await (_versions ?? findVersions(scope.addons, work));
      if (versions.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No versions found to play.')),
        );
        return;
      }
      final good = versions.where((v) => v.isGoodMatch).toList();
      // When no version is clearly this book, the user decides instead of a guess.
      if (good.isEmpty) {
        if (!mounted) return;
        final picked = await pickVersion(context, versions);
        if (picked == null) return;
        final release = await ContentCache.book(
          picked.addon,
          picked.release.id,
        );
        unawaited(
          scope.player.openBook(
            picked.addon,
            release.withLookOf(work),
            workKey: _workKey,
            look: work,
          ),
        );
        await navigator.push(NowPlayingScreen.route());
        return;
      }
      // The first good version that is ready at once, the others to fall back on.
      final order = await playOrder(good);
      if (order.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('None of the versions can be played.')),
        );
        return;
      }
      final first = order.first;
      final release =
          first.book ??
          await ContentCache.book(
            first.version.addon,
            first.version.release.id,
          );
      unawaited(
        scope.player.openBook(
          first.version.addon,
          release.withLookOf(work),
          workKey: _workKey,
          look: work,
          alternatives: [
            for (final o in order.skip(1))
              (
                addon: o.version.addon,
                bookId: o.version.release.id,
                book: o.book,
              ),
          ],
        ),
      );
      await navigator.push(NowPlayingScreen.route());
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _openVersion(Book work, Version v) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookScreen(
          addon: v.addon,
          summary: v.release,
          look: work,
          workKey: _workKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Playback stays at hand on pages opened over the main screen.
      bottomNavigationBar: const MiniPlayer(),
      appBar: AppBar(
        actions: [
          if (widget.addon.isLocal)
            LocalBookMenu(
              bookId: widget.summary.id,
              onChanged: () => setState(() {
                ContentCache.forgetBook(widget.addon, widget.summary.id);
                _book = _load();
              }),
            ),
        ],
      ),
      body: FutureBuilder<Book>(
        future: _book,
        initialData: _stored,
        builder: (context, snap) {
          if (snap.hasError && _stored != null) {
            return _content(context, _stored);
          }
          if (snap.hasError) {
            return _Problem(
              message: '${snap.error}',
              onRetry: () => setState(() {
                _book = _load();
              }),
            );
          }
          return _content(context, snap.data);
        },
      ),
    );
  }

  Widget _content(BuildContext context, Book? book) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    // Until the version loads, show the catalog book it belongs to.
    final summary = book ?? widget.look ?? widget.summary;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final facts = [
      if ((book?.durationMinutes ?? 0) > 0) _duration(book!.durationMinutes!),
      if (book?.rating != null) '★ ${book!.rating!.toStringAsFixed(1)}',
      ?book?.year,
    ];

    final cover = BookCover(
      title: summary.title,
      url: summary.cover,
      size: wide ? 220 : 180,
      radius: 14,
    );
    final info = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          summary.title,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        if (summary.byline.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(summary.byline, style: theme.textTheme.titleMedium),
        ],
        if (summary.narrators.isNotEmpty)
          Text(
            'Read by ${summary.narrators.join(', ')}',
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        if (book?.series != null)
          Text(
            book!.series!,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(facts.join(' · '), style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            for (final tag in summary.tags)
              Chip(label: Text(tag), visualDensity: VisualDensity.compact),
            if (book != null && !book.isWork)
              Chip(
                label: Text(
                  book.chapters.length == 1
                      ? '1 file'
                      : '${book.chapters.length} chapters',
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (summary.details != null && book?.isWork != true) ...[
          const SizedBox(height: 8),
          Text(
            summary.details!,
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    // Side by side on wide screens, stacked on phones.
    final header = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 24),
              Expanded(child: info),
            ],
          )
        : Column(children: [cover, const SizedBox(height: 16), info]);

    // Only what shows the player's place follows it (each pause, chapter or bookmark); the
    // rest is built once per load. Chapters are built as they scroll into view.
    final moves = Listenable.merge([scope.library, scope.player.current]);
    final chapters = book != null && !book.isWork ? book.chapters : null;
    return LayoutBuilder(
      builder: (context, box) {
        // A readable column of at most 860 px, centred.
        final side = math.max(16.0, (box.maxWidth - 860) / 2);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: side),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 20),
                    if (book == null)
                      const LinearProgressIndicator()
                    else if (book.isWork)
                      ListenableBuilder(
                        listenable: moves,
                        builder: (_, _) => _workPlayButton(book),
                      )
                    else ...[
                      ListenableBuilder(
                        listenable: moves,
                        builder: (_, _) {
                          final (entry, isCurrent) = _place(book);
                          return _playButton(book, entry, isCurrent);
                        },
                      ),
                      const SizedBox(height: 12),
                      _sourcePicker(),
                    ],
                    if (book?.description != null) ...[
                      const SizedBox(height: 20),
                      Text('About', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Text(
                          book!.description!,
                          maxLines: _expanded ? null : 6,
                          overflow: _expanded ? null : TextOverflow.fade,
                        ),
                      ),
                    ],
                    if (book != null && book.genres.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final g in book.genres)
                            Chip(
                              label: Text(g),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    if (book != null && book.isWork) ...[
                      const SizedBox(height: 20),
                      Text('Versions', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      VersionsList(
                        versions: _versions,
                        hasSources: scope.addons.addons.any(
                          (a) => a.manifest.releases,
                        ),
                        onOpen: (v) => _openVersion(book, v),
                      ),
                      _SeriesRow(addon: widget.addon, books: _series),
                    ],
                    if (chapters != null) ...[
                      const SizedBox(height: 20),
                      Text('Chapters', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
            ),
            if (chapters != null)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: side),
                sliver: ListenableBuilder(
                  listenable: moves,
                  builder: (_, _) {
                    final (entry, isCurrent) = _place(book!);
                    return SliverList.builder(
                      itemCount: chapters.length,
                      itemBuilder: (_, i) =>
                          _chapterTile(book, i, chapters[i], entry, isCurrent),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }

  /// The library entry of a playable [book], and whether it is the one in the player.
  (LibraryEntry?, bool) _place(Book book) {
    final scope = AppScope.of(context);
    final entry = scope.library.find(widget.addon.id, book.id);
    return (
      entry,
      entry != null && scope.player.current.value?.key == entry.key,
    );
  }

  static String _duration(int minutes) =>
      minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';

  Widget _workPlayButton(Book work) {
    final scope = AppScope.of(context);
    final earlier = scope.library.findByWork(widget.addon.id, work.id);
    final playing =
        earlier != null && scope.player.current.value?.key == earlier.key;
    final label = playing
        ? 'Open player'
        : earlier != null && !earlier.finished
        ? 'Resume'
        : _starting
        ? 'Finding a version…'
        : 'Play';
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: _starting
          ? null
          : () => playing
                ? Navigator.of(context).push(NowPlayingScreen.route())
                : _playWork(work),
      icon: _starting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(playing ? Icons.graphic_eq : Icons.play_arrow_rounded),
      label: Text(label),
    );
  }

  Widget _playButton(Book book, LibraryEntry? entry, bool isCurrent) {
    final resuming = entry != null && !entry.finished;
    final label = isCurrent
        ? 'Open player'
        : resuming
        ? 'Resume · chapter ${entry.chapterIndex + 1}'
        : entry?.finished == true
        ? 'Listen again'
        : 'Play';
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: () => isCurrent
          ? Navigator.of(context).push(NowPlayingScreen.route())
          : _play(book),
      icon: Icon(isCurrent ? Icons.graphic_eq : Icons.play_arrow_rounded),
      label: Text(label),
    );
  }

  Widget _sourcePicker() {
    final theme = Theme.of(context);
    return FutureBuilder<SourceList>(
      future: _sources,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            'Could not check sources: ${snap.error}',
            style: TextStyle(color: theme.colorScheme.error),
          );
        }
        final list = snap.data;
        if (list == null) return const SizedBox(height: 4);
        if (list.sources.isEmpty) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(
                list.message ?? 'This addon has no way to play this book.',
              ),
              trailing: widget.addon.manifest.configureUrl == null
                  ? null
                  : TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(widget.addon.manifest.configureUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Settings'),
                    ),
            ),
          );
        }
        final selected = list.sources.any((s) => s.id == _sourceId)
            ? _sourceId!
            : (list.sources.where((s) => s.cached == true).firstOrNull ??
                      list.sources.first)
                  .id;
        if (list.sources.length == 1) {
          final s = list.sources.first;
          return Text(
            'Plays from ${s.name}${s.description == null ? '' : ' · ${s.description}'}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return DropdownMenu<String>(
          expandedInsets: EdgeInsets.zero,
          initialSelection: selected,
          label: const Text('Play from'),
          onSelected: (id) => setState(() => _sourceId = id),
          dropdownMenuEntries: [
            for (final s in list.sources)
              DropdownMenuEntry(
                value: s.id,
                label: s.name,
                labelWidget: Text(
                  s.description == null
                      ? s.name
                      : '${s.name} · ${s.description}',
                ),
                leadingIcon: Icon(
                  s.cached == true ? Icons.bolt : Icons.cloud_download_outlined,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _chapterTile(
    Book book,
    int i,
    Chapter chapter,
    LibraryEntry? entry,
    bool isCurrent,
  ) {
    final theme = Theme.of(context);
    final here = entry != null && entry.chapterIndex == i && !entry.finished;
    final size = chapter.size == null
        ? null
        : '${(chapter.size! / 1048576).round()} MB';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 32,
        child: here
            ? Icon(
                isCurrent ? Icons.graphic_eq : Icons.bookmark,
                color: theme.colorScheme.primary,
              )
            : Text(
                '${i + 1}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
      ),
      title: Text(
        chapter.title,
        style: here
            ? TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      trailing: size == null
          ? null
          : Text(size, style: theme.textTheme.bodySmall),
      onTap: () => isCurrent
          ? AppScope.of(context).player.playChapter(i)
          : _play(book, chapter: i),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// The other books of the series, shown once the catalog found them; nothing before or without.
class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.addon, required this.books});

  final InstalledAddon addon;
  final Future<List<BookSummary>>? books;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BookSummary>>(
      future: books,
      builder: (context, snap) {
        final list = snap.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              'In this series',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            CardStrip(
              padding: EdgeInsets.zero,
              children: [
                for (final book in list)
                  BookCard(
                    title: book.title,
                    subtitle: book.details ?? book.byline,
                    cover: book.cover,
                    onTapDown: () => ContentCache.book(addon, book.id),
                    onTap: () => openBook(context, addon, book),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
