import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../sources/local_library.dart';
import '../sources/local_scan.dart';
import '../widgets/book_tiles.dart';

/// Lets the user pick audiobooks on this device and adds them. On desktop a folder can be
/// picked (every folder of audio files in it is a book) and files stay where they are; Android
/// hands the app temporary copies, which are moved into the app.
Future<void> addBooksFromDevice(BuildContext context) async {
  final scope = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  final how = desktop
      ? await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Choose a folder'),
                  subtitle: const Text(
                    'Every folder of audio files inside becomes a book',
                  ),
                  onTap: () => Navigator.pop(context, 'folder'),
                ),
                ListTile(
                  leading: const Icon(Icons.audio_file_outlined),
                  title: const Text('Choose files'),
                  subtitle: const Text('The files of one book, or M4B files'),
                  onTap: () => Navigator.pop(context, 'files'),
                ),
              ],
            ),
          ),
        )
      : 'files';
  if (how == null) return;

  final library = scope.addons.local;
  // Reading the tags of many files, or Android copying big ones, takes a while.
  var busy = false;
  void showBusy() {
    if (busy) return;
    busy = true;
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Adding audiobooks…')),
            ],
          ),
        ),
      ),
    );
  }

  final List<LocalBook> added;
  try {
    if (how == 'folder') {
      final folder = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose a folder of audiobooks',
      );
      if (folder == null) return;
      showBusy();
      added = await library.addFolder(folder);
    } else {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Choose audiobook files',
        type: desktop ? FileType.custom : FileType.audio,
        allowedExtensions: desktop ? audioExtensions.toList() : null,
        onFileLoading: (status) {
          if (status == FilePickerStatus.picking && !desktop) showBusy();
        },
      );
      final paths = [for (final f in picked) ?f.path];
      if (paths.isEmpty) return;
      showBusy();
      added = await library.addFiles(paths, copy: !desktop);
    }
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
    return;
  } finally {
    if (busy) navigator.pop();
  }

  final local = scope.addons.byId(LocalBackend.id);
  messenger.showSnackBar(
    SnackBar(
      content: Text(switch (added.length) {
        0 => 'No audio files found there.',
        1 => 'Added ${added.single.title}',
        final n => 'Added $n books',
      }),
      action: added.length == 1 && local != null
          ? SnackBarAction(
              label: 'Open',
              onPressed: () =>
                  openBook(navigator.context, local, added.single.summary),
            )
          : null,
    ),
  );
}
