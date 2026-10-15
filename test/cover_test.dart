import 'dart:io';
import 'dart:ui' as ui;

import 'package:audiobooks/widgets/cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A PNG file of [width]×[height] in [dir], as a file: URL.
Future<String> png(Directory dir, int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/${width}x$height.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return Uri.file(file.path).toString();
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('covers'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Shows the cover and gives it real time to read and decode the file.
  Future<void> show(WidgetTester tester, String url) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: BookCover(title: 'A Book', url: url, size: 120),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
        if (find.byType(RawImage).evaluate().isNotEmpty) break;
      }
    });
    await tester.pump();
  }

  testWidgets('a square cover is drawn once', (tester) async {
    await show(tester, (await tester.runAsync(() => png(dir, 300, 300)))!);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('a book cover is shown whole over a filled copy', (tester) async {
    await show(tester, (await tester.runAsync(() => png(dir, 200, 300)))!);
    expect(find.byType(RawImage), findsNWidgets(2));
  });

  testWidgets('a cover that cannot be read gets the generated one', (
    tester,
  ) async {
    await show(tester, Uri.file('${dir.path}/missing.png').toString());
    expect(find.byType(RawImage), findsNothing);
    expect(find.text('A Book'), findsOneWidget);
  });
}
