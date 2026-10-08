// End-to-end tour against example extensions served from this machine (no network): install a
// catalog and a source from a repository, browse Home, a full list and a genre, open a catalog
// book and its versions, play it, search, restart. Saves screenshots when SHOTS is set:
//   flutter test integration_test/tour_test.dart -d linux --dart-define=SHOTS=/tmp/shots
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audiobooks/main.dart';
import 'package:audiobooks/screens/catalog_screen.dart';
import 'package:audiobooks/widgets/book_tiles.dart';
import 'package:audiobooks/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'example_extensions.dart';

const shotsDir = String.fromEnvironment('SHOTS');

final rootKey = GlobalKey();

/// Waits for [finder] in real time.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  int seconds = 30,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      await shot(tester, 'timeout');
      fail('Timed out waiting for $finder');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// Lets images and animations finish, without pumpAndSettle (spinners never settle).
Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  if (shotsDir.isEmpty) return;
  await settle(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(rootKey),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  Directory(shotsDir).createSync(recursive: true);
  File('$shotsDir/$name.png').writeAsBytesSync(bytes!);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('tour', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final server = (await tester.runAsync(serveExampleRepository))!;
    final repository = 'http://127.0.0.1:${server.port}/index.json';
    final app = (await tester.runAsync(
      () => createApp(systemControls: false),
    ))!;
    await tester.pumpWidget(RepaintBoundary(key: rootKey, child: app));
    await tester.pump();
    await shot(tester, '01-empty');

    Future<void> install(String name, String setting) async {
      // The "Installed …" snack bar of the previous install would sit over the button.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tap(tester, find.text('Addons').last);
      await tap(tester, find.text('Add addon').last);
      await tester.enterText(find.byType(TextField), repository);
      await tap(tester, find.text('Install'));
      await waitFor(tester, find.text(name));
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(ListTile),
      );
      await tap(
        tester,
        find.descendant(of: row, matching: find.byType(FilledButton)),
      );
      await waitFor(tester, find.text(setting));
      await back(tester);
    }

    await install('Example Catalog', 'Language');
    await install('Example Source', 'Server');
    await waitFor(tester, find.textContaining('runs on this device'));
    await shot(tester, '02-addons');

    // Home: the catalog's rows and genres.
    await tap(tester, find.text('Home').last);
    await waitFor(tester, find.text('Popular'));
    await waitFor(tester, find.text('The Quiet Orchard'));
    expect(find.text('Browse by genre'), findsOneWidget);
    await shot(tester, '03-home');

    await tap(tester, find.text('See all').first);
    await waitFor(tester, find.byType(CatalogScreen));
    await waitFor(tester, find.text('Paper Comets'));
    await shot(tester, '04-see-all');
    await back(tester);

    await tap(tester, find.widgetWithText(ActionChip, 'Mystery'));
    await waitFor(tester, find.text('The Long Table'));
    expect(find.text('The Quiet Orchard'), findsNothing);
    await shot(tester, '05-genre');
    await back(tester);

    // A catalog book: details from the catalog, a version from the source.
    await tap(tester, find.text('The Quiet Orchard').first);
    await waitFor(tester, find.text('Versions'));
    await waitFor(tester, find.text('The Quiet Orchard (MP3)'));
    expect(find.textContaining('9 h 12 min'), findsOneWidget);
    await shot(tester, '06-book');

    // Play: the version starts, with the catalog's title on it.
    await tap(tester, find.widgetWithText(FilledButton, 'Play'));
    await waitFor(tester, find.byIcon(Icons.pause_rounded));
    expect(find.text('Part 1'), findsWidgets);
    await shot(tester, '07-player');
    await tap(tester, find.byTooltip('Pause'));
    await tap(tester, find.byTooltip('Close'));
    await back(tester);

    await tap(tester, find.text('Search').last);
    await tester.enterText(find.byType(TextField), 'orchard');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(tester, find.byType(BookListTile));
    await shot(tester, '08-search');

    // "Restart": a fresh app on the same storage shows Home at once, the book in Continue
    // listening and in the mini player.
    final restarted = (await tester.runAsync(
      () => createApp(systemControls: false),
    ))!;
    await tester.pumpWidget(
      RepaintBoundary(key: GlobalKey(), child: const SizedBox()),
    );
    await tester.pumpWidget(RepaintBoundary(key: rootKey, child: restarted));
    await waitFor(tester, find.text('Continue listening'));
    await waitFor(tester, find.byType(MiniPlayer));
    await shot(tester, '09-restart');

    await tester.runAsync(() => server.close(force: true));
  });
}
