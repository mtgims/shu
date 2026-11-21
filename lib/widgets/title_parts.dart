/// A book title without the edition notes stores add in brackets, and those notes as short
/// labels: "Red Rising (Part 1 of 2) (Dramatized Adaptation)" is "Red Rising" with "Part 1 of 2"
/// and "Full cast". Brackets it doesn't know stay in the title.
({String title, List<String> labels}) splitTitle(String raw) {
  var title = raw.trim();
  final labels = <String>[];
  while (true) {
    final m = _trailing.firstMatch(title);
    if (m == null) break;
    final note = m.group(1)!.trim();
    final label = _label(note);
    if (label == null) break;
    if (label.isNotEmpty) labels.insert(0, label);
    title = title.substring(0, m.start).trimRight();
  }
  // A title that is only notes keeps them.
  return title.isEmpty
      ? (title: raw, labels: const [])
      : (title: title, labels: labels);
}

final _trailing = RegExp(r'[\(\[]([^\(\)\[\]]+)[\)\]]$');

/// The label for a bracketed [note], '' for one not worth showing, null for one to keep.
String? _label(String note) {
  final lower = note.toLowerCase();
  final part = RegExp(
    r'^(part|book|vol\.?|volume)\s*(\d+)(?:\s*(?:of|/)\s*(\d+))?$',
  ).firstMatch(lower);
  if (part != null) {
    final word = part.group(1)!.startsWith('vol')
        ? 'Vol.'
        : part.group(1) == 'book'
        ? 'Book'
        : 'Part';
    final of = part.group(3);
    return of == null
        ? '$word ${part.group(2)}'
        : '$word ${part.group(2)} of $of';
  }
  if (RegExp(r'dramati[sz]|full[- ]cast|audio drama|radio drama')
      .hasMatch(lower)) {
    return 'Full cast';
  }
  if (lower == 'abridged') return 'Abridged';
  const dropped = {'unabridged', 'audiobook', 'audio book'};
  if (dropped.contains(lower)) return '';
  return null;
}
