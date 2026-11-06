import '../library/library_store.dart';
import 'addon_store.dart';
import 'backend.dart';
import 'models.dart';

/// Asks [addon] for chapter [index] of [entry]: the link, or "still downloading", and the
/// source it came from (the one the user picked, else a cached one, else the first).
Future<({Resolved link, String sourceId})> chapterLink(
  InstalledAddon addon,
  LibraryEntry entry,
  int index,
) async {
  final chapter = entry.book.chapters[index];
  final list = await addon.client.sources(entry.book.id, chapter.id);
  if (list.sources.isEmpty) {
    throw AddonException(
      list.message ?? 'The addon has no source for this chapter.',
    );
  }
  final source = _pickSource(list.sources, entry.sourceId);
  return (link: await addon.client.resolve(source), sourceId: source.id);
}

Source _pickSource(List<Source> sources, String? preferred) {
  for (final s in sources) {
    if (s.id == preferred) return s;
  }
  for (final s in sources) {
    if (s.cached == true) return s;
  }
  return sources.first;
}
