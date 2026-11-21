import 'dart:io';

/// Puts a downloaded Linux or Windows release in place of the running one. Files being replaced
/// are moved aside into `.shu-old-*` first: Windows can't overwrite a running program or its
/// libraries, but it can move them. [tidy] deletes them at the next start.
abstract final class DesktopInstall {
  static const _old = '.shu-old-';
  static const _work = '.shu-update';

  /// The running AppImage file, when Shu runs from one.
  static String? get appImage => Platform.environment['APPIMAGE'];

  /// The folder holding the running program and its `lib/`, `data/`.
  static Directory get bundle => File(Platform.resolvedExecutable).parent;

  /// What to start once the update is in place.
  static String get relaunchPath => appImage ?? Platform.resolvedExecutable;

  /// Whether Shu can change [dir] (not so under /opt or in the Nix store).
  static bool writable(Directory dir) {
    final probe = File('${dir.path}${Platform.pathSeparator}.shu-write-test');
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Where the download goes: beside its destination, so moving it there is a rename.
  static File downloadFile(String asset) => appImage != null
      ? File('$appImage.download')
      : File(_join(bundle.path, '$_work/$asset'));

  /// Puts [download] in place: the new AppImage over the old one, or the archive's files over
  /// the bundle's.
  static Future<void> apply(File download) async {
    final image = appImage;
    if (image != null) {
      await _run('chmod', ['+x', download.path]);
      // The running copy keeps its open file; the next start reads the new one.
      await download.rename(image);
      return;
    }
    await unpack(download, bundle);
  }

  /// Extracts [archive] (a tar.gz or zip with one top folder) and moves its files into [into].
  static Future<void> unpack(File archive, Directory into) async {
    final out = Directory(_join(archive.parent.path, 'files'));
    if (await out.exists()) await out.delete(recursive: true);
    await out.create(recursive: true);
    // Windows 10 and later ship bsdtar, which reads zip files too. Git's tar on the PATH can't.
    final tar = Platform.isWindows
        ? '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\tar.exe'
        : 'tar';
    await _run(tar, ['-xf', archive.path, '-C', out.path]);
    final top = await out.list().toList();
    final root = top.length == 1 && top.single is Directory
        ? top.single as Directory
        : out;
    await swapIn(root, into);
  }

  /// Moves every file under [from] to the same place under [into]. If one fails, everything
  /// moved so far goes back, so a half-updated app never starts.
  static Future<void> swapIn(Directory from, Directory into) async {
    final old = _join(
      into.path,
      '$_old${DateTime.now().millisecondsSinceEpoch}',
    );
    final added = <String>[];
    final replaced = <(String, String)>[]; // (place, where its old file went)
    try {
      await for (final entry in from.list(recursive: true)) {
        if (entry is! File) continue;
        final rel = entry.path.substring(from.path.length + 1);
        final target = File(_join(into.path, rel));
        await target.parent.create(recursive: true);
        if (await target.exists()) {
          final aside = File(_join(old, rel));
          await aside.parent.create(recursive: true);
          await target.rename(aside.path);
          replaced.add((target.path, aside.path));
        } else {
          added.add(target.path);
        }
        await entry.rename(target.path);
      }
    } on Object {
      for (final path in added) {
        await File(path).delete().catchError((Object _) => File(path));
      }
      for (final (place, aside) in replaced.reversed) {
        final file = File(place);
        if (await file.exists()) await file.delete();
        await File(aside).rename(place);
      }
      rethrow;
    }
  }

  /// Deletes what an update left behind: old files, the download and its unpacked copy.
  static Future<void> tidy() async {
    final image = appImage;
    if (image != null) {
      final left = File('$image.download');
      if (await left.exists()) await left.delete();
      return;
    }
    await for (final entry in bundle.list()) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (entry is Directory && (name.startsWith(_old) || name == _work)) {
        await entry.delete(recursive: true);
      }
    }
  }

  static String _join(String dir, String rel) =>
      [dir, ...rel.split('/')].join(Platform.pathSeparator);

  static Future<void> _run(String program, List<String> args) async {
    final result = await Process.run(program, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        program,
        args,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }
}
