// A catalog page in a large window: pages that don't fill it load on their own, and a page
// that only repeats books already shown doesn't stop the loading.

import 'package:audiobooks/app.dart';
import 'package:audiobooks/main.dart';
import 'package:audiobooks/screens/catalog_screen.dart';
import 'package:audiobooks/widgets/book_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'temp_paths.dart';

// 24 entries in pages of 4: the second page repeats the first, so 20 different books.
const _catalog = '''
var list = [];
for (var i = 0; i < 24; i++) {
  var n = i >= 4 ? i - 4 : i;
  list.push({ id: 'b' + n, title: 'Book ' + n });
}
extension = {
  manifest: { id: 'org.example.pages', name: 'Pages', version: '1.0.0',
    catalogs: [{ id: 'all', name: 'All' }] },
  async catalog(id, o) {
    var skip = o.skip || 0;
    return { books: list.slice(skip, skip + 4), hasMore: skip + 4 < list.length };
  },
  async book(id) { return { id: id, title: id, chapters: [] }; },
};
''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('a catalog fills a large window by itself', (tester) async {
    final root = useTempAppStorage();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.reset();
      root.deleteSync(recursive: true);
    });

    final app = (await tester.runAsync(
      () => createApp(systemControls: false),
    ))!;
    final addon = (await tester.runAsync(
      () => app.addons.installExtension(_catalog),
    ))!;
    await tester.pumpWidget(app);
    await tester.pump();
    navigatorKey.currentState!.push(
      CatalogScreen.route(addon, addon.manifest.catalogs.single),
    );

    // No scrolling at all: every page has to come by itself.
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.byType(BookCard).evaluate().length == 20) break;
    }
    expect(find.byType(BookCard), findsNWidgets(20));
    expect(find.text('Book 19'), findsWidgets);
  });
}
