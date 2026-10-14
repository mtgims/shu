// Home on a phone: after scrolling down past many rows, scrolling back up reaches the top
// again. Uses a catalog with a dozen rows served from this machine.

import 'package:audiobooks/main.dart';
import 'package:audiobooks/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'temp_paths.dart';

const _rows = 12;

const _catalog =
    '''
var rows = [];
for (var i = 1; i <= $_rows; i++) rows.push({ id: 'row' + i, name: 'Row ' + i });
extension = {
  manifest: { id: 'org.example.rows', name: 'Rows', version: '1.0.0', catalogs: rows },
  async catalog(id) {
    var books = [];
    for (var i = 0; i < 8; i++) books.push({ id: id + ':' + i, title: id + ' book ' + i });
    return { books: books, hasMore: false };
  },
  async book(id) { return { id: id, title: id, chapters: [] }; },
};
''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Home scrolls back to the top on a phone', (tester) async {
    final root = useTempAppStorage();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412 * 2.6, 915 * 2.6);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(() {
      tester.view.reset();
      root.deleteSync(recursive: true);
    });

    final app = (await tester.runAsync(
      () => createApp(systemControls: false),
    ))!;
    await tester.runAsync(() => app.addons.installExtension(_catalog));
    await tester.pumpWidget(app);

    Future<void> settle([int ms = 800]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }

    await settle(2000);
    final list = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    ScrollPosition position() => tester.state<ScrollableState>(list).position;
    expect(find.text('Row 1'), findsOneWidget);

    // Down to the last row, then back up, the way a thumb does it.
    for (var i = 0; i < 8; i++) {
      await tester.fling(list, const Offset(0, -900), 2500);
      await settle(600);
    }
    expect(position().pixels, greaterThan(1000));
    for (var i = 0; i < 12; i++) {
      await tester.fling(list, const Offset(0, 900), 2500);
      await settle(600);
      if (position().pixels == 0) break;
    }
    expect(
      position().pixels,
      0,
      reason: 'Home should scroll back to its first row',
    );
    expect(find.text('Row 1'), findsOneWidget);
  });
}
