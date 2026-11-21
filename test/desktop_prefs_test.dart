import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/storage/desktop_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('prefs'));
  tearDown(() => dir.delete(recursive: true));

  DesktopPrefs store() => DesktopPrefs(folder: () async => dir);
  File file() => File('${dir.path}/shared_preferences.json');

  test('saves reach the file and the next start reads them', () async {
    final first = store();
    await first.setValue('String', 'flutter.library', '[1]');
    for (var i = 0; i < 50; i++) {
      // Not awaited, as the app's quick saves often aren't: the file still ends at the last.
      first.setValue('Int', 'flutter.n', i);
    }
    await first.remove('flutter.gone');
    expect(jsonDecode(file().readAsStringSync()), {
      'flutter.library': '[1]',
      'flutter.n': 49,
    });
    expect(dir.listSync().length, 1, reason: 'no temporary files left');
    File('${dir.path}/shared_preferences.json.1-0.tmp').writeAsStringSync('{');
    expect(await store().getAll(), hasLength(2));
    expect(dir.listSync().length, 1, reason: 'a killed save is cleaned up');
    expect(await store().getAll(), {'flutter.library': '[1]', 'flutter.n': 49});
  });

  test('a first start, with no folder yet, saves', () async {
    final prefs = DesktopPrefs(
      folder: () async => Directory('${dir.path}/new/support'),
    );
    expect(await prefs.getAll(), isEmpty);
    await prefs.setValue('Bool', 'flutter.x', true);
    expect(
      File('${dir.path}/new/support/shared_preferences.json')
          .readAsStringSync(),
      '{"flutter.x":true}',
    );
  });

  test('an unreadable file is kept, not saved over', () async {
    file().writeAsStringSync('{"flutter.library": "[1, 2');
    final prefs = store();
    expect(await prefs.getAll(), isEmpty);
    await prefs.setValue('Bool', 'flutter.x', true);
    final kept = dir.listSync().whereType<File>().singleWhere(
      (f) => f.path.contains('.bad-'),
    );
    expect(kept.readAsStringSync(), '{"flutter.library": "[1, 2');
  });
}
