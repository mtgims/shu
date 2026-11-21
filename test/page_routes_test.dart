import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // On desktop the side rail is drawn over the pages, which leave its width free. A page
  // opened as a plain MaterialPageRoute would sit under the rail; PageBesideRail leaves room.
  test('pages open beside the rail', () {
    final plain = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (line.contains('MaterialPageRoute') &&
            !line.contains('extends MaterialPageRoute')) {
          plain.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(plain, isEmpty);
  });
}
