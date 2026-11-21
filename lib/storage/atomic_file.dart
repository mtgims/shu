import 'dart:io';

var _written = 0;

/// Replaces [file]'s contents in one step: the new text goes to a temporary file beside it,
/// reaches the disk, then is renamed over [file]. Killing the app or a power cut at any moment
/// leaves either the old file or the new one, never an empty or half-written file.
Future<void> writeAtomically(File file, String text) async {
  // Each write has its own temporary file, so two writes at once can't mix.
  final tmp = File('${file.path}.$pid-${_written++}.tmp');
  try {
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  } on Object {
    await tmp.delete().catchError((Object _) => tmp);
    rethrow;
  }
}
