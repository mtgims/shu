import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Flutter keeps a snack bar with an action on screen until it is dismissed, unless it says
  // `persist: false`. Shu's actions are all shortcuts to something found elsewhere too, so a
  // snack bar that never goes away is always a mistake.
  test('every snack bar with an action goes away on its own', () {
    final stuck = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final code = file.readAsStringSync();
      for (final m in RegExp(r'SnackBarAction\(').allMatches(code)) {
        final bar = code.lastIndexOf('SnackBar(', m.start);
        if (bar < 0 ||
            !code.substring(bar, m.start).contains('persist: false')) {
          final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
          stuck.add('${file.path}:$line');
        }
      }
    }
    expect(stuck, isEmpty);
  });
}
