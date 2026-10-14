import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/sources/local_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('shu_local'));
  tearDown(() => dir.delete(recursive: true));

  test('a broken book is dropped, the others are kept', () async {
    await File('${dir.path}/books.json').writeAsString(
      jsonEncode([
        {'id': 'bad'},
        {
          'id': 'good',
          'title': 'Dune',
          'authors': ['Frank Herbert'],
          'files': [
            {'path': '/books/dune.m4b', 'title': 'Dune'},
          ],
        },
      ]),
    );
    final library = await LocalLibrary.load(dir);
    expect(library.books.map((b) => b.id), ['good']);
  });

  test(
    'an unreadable list is kept aside before anything overwrites it',
    () async {
      await File('${dir.path}/books.json').writeAsString('[{"id": "cut off');
      final library = await LocalLibrary.load(dir);
      expect(library.books, isEmpty);
      expect(
        await File('${dir.path}/books.json.bad').readAsString(),
        '[{"id": "cut off',
      );
    },
  );
}
