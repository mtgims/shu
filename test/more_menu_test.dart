import 'package:audiobooks/theme.dart';
import 'package:audiobooks/widgets/more_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the ⋮ menu opens, runs an item and closes', (tester) async {
    var ran = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              MoreMenu(
                items: [
                  MenuItemButton(
                    onPressed: () => ran = true,
                    child: const Text('About Shu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About Shu'));
    await tester.pumpAndSettle();
    expect(ran, isTrue);
    expect(find.text('About Shu'), findsNothing);
  });
}
