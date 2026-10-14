import 'dart:io';

import 'package:audiobooks/screens/about.dart';
import 'package:audiobooks/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the newest changelog section, wrapped entries joined', () {
    const changelog = '''
# Changelog

## 1.1.0 - 2026-10-14

### New
- A thing that takes
  two lines
- Another

### Fixed
- A bug

## 1.0.0 - 2026-10-01

- Old
''';
    final release = latestRelease(changelog)!;
    expect(release.title, '1.1.0 - 2026-10-14');
    expect(release.lines, [
      (heading: true, text: 'New'),
      (heading: false, text: 'A thing that takes two lines'),
      (heading: false, text: 'Another'),
      (heading: true, text: 'Fixed'),
      (heading: false, text: 'A bug'),
    ]);
    expect(latestRelease('# Changelog\n'), isNull);
  });

  test("About shows this version's changes", () {
    final release = latestRelease(File('CHANGELOG.md').readAsStringSync())!;
    expect(release.title, startsWith('$appVersion '));
    expect(release.lines, isNotEmpty);
  });
}
