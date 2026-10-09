import 'package:flutter/material.dart';

import '../app.dart';
import '../sources/local_library.dart';

/// The book page's menu for a book on this device: fix its details, or remove it.
class LocalBookMenu extends StatelessWidget {
  const LocalBookMenu({
    super.key,
    required this.bookId,
    required this.onChanged,
  });

  final String bookId;

  /// Called after the details changed, so the page shows them.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final book = AppScope.of(context).addons.local.byId(bookId);
    if (book == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (action) => switch (action) {
        'edit' => _edit(context, book),
        _ => _remove(context, book),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit details')),
        PopupMenuItem(
          value: 'remove',
          child: Text(
            'Remove from Shu',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, LocalBook book) async {
    final scope = AppScope.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditDialog(book: book),
    );
    if (saved != true) return;
    // The library keeps a copy of the book; refresh it unless it is playing right now.
    final entry = scope.library.find(LocalBackend.id, book.id);
    if (entry != null && scope.player.current.value?.key != entry.key) {
      await scope.library.save(
        scope.library.entryFor(LocalBackend.id, book.book),
      );
    }
    onChanged();
  }

  Future<void> _remove(BuildContext context, LocalBook book) async {
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${book.title}?'),
        content: Text(
          book.owned
              ? 'Its files are deleted from Shu, along with where you stopped.'
              : 'Your files stay where they are; Shu forgets the book and where you stopped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final entry = scope.library.find(LocalBackend.id, book.id);
    if (entry != null) {
      if (scope.player.current.value?.key == entry.key) {
        await scope.player.stop();
      }
      await scope.library.remove(entry);
    }
    await scope.addons.local.remove(book);
    navigator.pop();
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.book});
  final LocalBook book;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _title = TextEditingController(text: widget.book.title);
  late final _authors = TextEditingController(
    text: widget.book.authors.join(', '),
  );
  late final _narrators = TextEditingController(
    text: widget.book.narrators.join(', '),
  );

  @override
  void dispose() {
    _title.dispose();
    _authors.dispose();
    _narrators.dispose();
    super.dispose();
  }

  static List<String> _names(String text) => [
    for (final name in text.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ];

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final navigator = Navigator.of(context);
    await AppScope.of(context).addons.local.update(
      widget.book,
      title: title,
      authors: _names(_authors.text),
      narrators: _names(_narrators.text),
    );
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit details'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _authors,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Author',
                helperText: 'Separate several with commas',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _narrators,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'Narrator'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
