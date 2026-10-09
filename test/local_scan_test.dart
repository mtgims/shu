import 'dart:io';

import 'package:audiobooks/sources/local_scan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('scan-'));
  tearDown(() => root.delete(recursive: true));

  Future<void> touch(String path) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([0]);
  }

  test(
    'finds a book per folder, joining disc folders and splitting M4Bs',
    () async {
      await touch('Author/Long Book/CD 1/01.mp3');
      await touch('Author/Long Book/CD 1/02.mp3');
      await touch('Author/Long Book/CD 2/01.mp3');
      await touch('Author/Long Book/cover.jpg');
      await touch('Singles/First.m4b');
      await touch('Singles/Second.m4b');
      await touch('Singles/notes.txt');

      final books = await scanFolder(root.path, '${root.path}/covers');
      expect(books.map((b) => b.title), ['First', 'Long Book', 'Second']);
      final long = books[1];
      expect(long.files.map((f) => f.path.substring(root.path.length)), [
        '/Author/Long Book/CD 1/01.mp3',
        '/Author/Long Book/CD 1/02.mp3',
        '/Author/Long Book/CD 2/01.mp3',
      ]);
      expect(long.cover, '${root.path}/Author/Long Book/cover.jpg');
    },
  );

  test('picked files of one folder are one book, in natural order', () async {
    for (final name in ['Part 10.mp3', 'Part 2.mp3', 'Part 1.mp3']) {
      await touch('Book/$name');
    }
    final books = await scanFiles([
      for (final name in ['Part 10.mp3', 'Part 2.mp3', 'Part 1.mp3'])
        '${root.path}/Book/$name',
    ], '${root.path}/covers');
    expect(books.single.title, 'Book');
    expect(books.single.files.map((f) => f.title), [
      'Part 1',
      'Part 2',
      'Part 10',
    ]);
  });
}
