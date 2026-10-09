import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Audio files the app can import. Everything mpv and Android's player read.
const audioExtensions = {
  'mp3',
  'm4b',
  'm4a',
  'mp4',
  'aac',
  'ogg',
  'oga',
  'opus',
  'flac',
  'wav',
  'wma', //
};

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};
const _mp4 = {'m4b', 'm4a', 'mp4'};

String extensionOf(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

String _baseName(String path) => path.split(Platform.pathSeparator).last;

String _parent(String path) =>
    path.substring(0, path.lastIndexOf(Platform.pathSeparator));

String _withoutExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// One audio file of a scanned book.
class ScannedFile {
  ScannedFile({
    required this.path,
    required this.title,
    this.size,
    this.duration,
    this.chapters = const [],
  });

  final String path;
  final String title;
  final int? size;
  final Duration? duration;

  /// Chapters inside the file (M4B), when it has more than one.
  final List<({Duration start, String title})> chapters;
}

/// A book found on disk, before it gets an id.
class ScannedBook {
  ScannedBook({
    required this.title,
    required this.files,
    this.authors = const [],
    this.narrators = const [],
    this.year,
    this.cover,
  });

  final String title;
  final List<String> authors;
  final List<String> narrators;
  final String? year;

  /// An image file: next to the audio, or the embedded cover saved to [coverDir].
  final String? cover;
  final List<ScannedFile> files;
}

/// Finds the books in a folder: every folder holding audio files is a book, and disc folders
/// ("CD 1", "Disc 2") count as part of the book above them. Runs off the UI thread.
Future<List<ScannedBook>> scanFolder(String root, String coverDir) =>
    Isolate.run(() {
      final files = Directory(root)
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => audioExtensions.contains(extensionOf(p)))
          .toList();
      return _books(files, coverDir);
    });

/// Turns picked files into books (a folder's files are one book, M4B files are a book each).
Future<List<ScannedBook>> scanFiles(List<String> paths, String coverDir) =>
    Isolate.run(() => _books(paths, coverDir));

final _discFolder = RegExp(r'^(cd|dis[ck]|part)\s*\d+$', caseSensitive: false);

List<ScannedBook> _books(List<String> paths, String coverDir) {
  // Files by the folder of the book they belong to.
  final byFolder = <String, List<String>>{};
  for (final path in paths) {
    var folder = _parent(path);
    if (_discFolder.hasMatch(_baseName(folder))) folder = _parent(folder);
    byFolder.putIfAbsent(folder, () => []).add(path);
  }
  final books = <ScannedBook>[];
  for (final MapEntry(key: folder, value: files) in byFolder.entries) {
    final tagged = [for (final path in files) (path: path, tags: _tags(path))];
    // Within a folder, files that name different albums are different books, and so are M4Bs
    // without an album name.
    final groups = <String, List<({String path, AudioMetadata? tags})>>{};
    for (final f in tagged) {
      final album = f.tags?.album?.trim() ?? '';
      final key = album.isNotEmpty
          ? 'album:$album'
          : extensionOf(f.path) == 'm4b'
          ? 'file:${f.path}'
          : '';
      groups.putIfAbsent(key, () => []).add(f);
    }
    for (final group in groups.values) {
      books.add(_book(folder, group, coverDir));
    }
  }
  books.sort((a, b) => _naturalCompare(a.title, b.title));
  return books;
}

AudioMetadata? _tags(String path) {
  try {
    return readMetadata(File(path), getImage: false);
  } on Object {
    return null;
  }
}

ScannedBook _book(
  String folder,
  List<({String path, AudioMetadata? tags})> group,
  String coverDir,
) {
  group.sort((a, b) {
    final disc = (a.tags?.discNumber ?? 0).compareTo(b.tags?.discNumber ?? 0);
    if (disc != 0) return disc;
    final track = (a.tags?.trackNumber ?? 0).compareTo(
      b.tags?.trackNumber ?? 0,
    );
    if (track != 0) return track;
    return _naturalCompare(a.path, b.path);
  });
  final first = group.first.tags;
  final single = group.length == 1;
  String? text(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  final title =
      text(first?.album) ??
      (single ? text(first?.title) : null) ??
      (single
          ? _withoutExtension(_baseName(group.first.path))
          : _baseName(folder));
  final author = text(first?.albumArtist) ?? text(first?.artist);
  final narrator = first?.performers
      .map(text)
      .whereType<String>()
      .where((p) => p != author)
      .firstOrNull;

  final files = [
    for (final f in group)
      ScannedFile(
        path: f.path,
        title: text(f.tags?.title) ?? _withoutExtension(_baseName(f.path)),
        size: _size(f.path),
        // MP4 files state their length; for other formats it is a guess, often far off.
        duration: _mp4.contains(extensionOf(f.path)) ? f.tags?.duration : null,
        chapters: (f.tags?.chapters.length ?? 0) > 1
            ? [
                for (final c in f.tags!.chapters)
                  (start: c.start, title: c.title),
              ]
            : const [],
      ),
  ];
  return ScannedBook(
    title: title,
    authors: [?author],
    narrators: [?narrator],
    year: switch (first?.year?.year) {
      final y? when y > 0 => '$y',
      _ => null,
    },
    cover: _cover(folder, group.first.path, coverDir),
    files: files,
  );
}

int? _size(String path) {
  try {
    return File(path).lengthSync();
  } on Object {
    return null;
  }
}

/// An image in the book's folder (cover.jpg, folder.jpg, or the only one), else the picture
/// embedded in the first file, saved next to the library.
String? _cover(String folder, String firstFile, String coverDir) {
  try {
    final images =
        Directory(folder)
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => _imageExtensions.contains(extensionOf(p)))
            .toList()
          ..sort(_naturalCompare);
    for (final name in ['cover', 'folder', 'front']) {
      for (final image in images) {
        if (_withoutExtension(_baseName(image)).toLowerCase() == name) {
          return image;
        }
      }
    }
    if (images.length == 1) return images.single;
  } on Object {
    // An unreadable folder: try the embedded picture.
  }
  try {
    final pictures = readMetadata(File(firstFile), getImage: true).pictures;
    if (pictures.isEmpty) return null;
    final picture =
        pictures
            .where((p) => p.pictureType == PictureType.coverFront)
            .firstOrNull ??
        pictures.first;
    final ext = picture.mimetype.contains('png') ? 'png' : 'jpg';
    Directory(coverDir).createSync(recursive: true);
    final file = File('$coverDir/${DateTime.now().microsecondsSinceEpoch}.$ext')
      ..writeAsBytesSync(picture.bytes);
    return file.path;
  } on Object {
    return null;
  }
}

/// Orders "Part 2" before "Part 10".
int _naturalCompare(String a, String b) {
  final chunks = RegExp(r'\d+|\D+');
  final x = chunks.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final y = chunks.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final m = int.tryParse(x[i]), n = int.tryParse(y[i]);
    final c = m != null && n != null ? m.compareTo(n) : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}
