import 'package:audiobooks/widgets/keyboard_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final navigator = GlobalKey<NavigatorState>();
  final hidden = ScrollController();
  final shown = ScrollController();
  var enabled = true;

  Widget list(ScrollController c) => ListView.builder(
    controller: c,
    itemCount: 100,
    itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
  );

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      builder: (_, child) => Focus(
        autofocus: true,
        child: KeyboardScroll(
          navigator: navigator,
          enabled: () => enabled,
          child: child!,
        ),
      ),
      // The hidden tab comes first, as Home does before Search.
      home: Scaffold(
        body: IndexedStack(index: 1, children: [list(hidden), list(shown)]),
      ),
    ),
  );

  testWidgets('keys scroll the list on screen, not a hidden one', (
    tester,
  ) async {
    enabled = true;
    await pumpApp(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(shown.offset, 64);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(shown.offset, shown.position.maxScrollExtent);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(
      shown.offset,
      shown.position.maxScrollExtent - shown.position.viewportDimension * 0.8,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(shown.offset, 0);
    expect(hidden.offset, 0);
  });

  testWidgets('keys do nothing while something else has the focus', (
    tester,
  ) async {
    enabled = false;
    await pumpApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(shown.offset, 0);
  });
}
