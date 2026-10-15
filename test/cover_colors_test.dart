import 'dart:typed_data';

import 'package:audiobooks/widgets/cover_colors.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// RGBA bytes of a 100-pixel cover made of [parts]: (share in percent, colour).
Uint8List cover(List<(int, Color)> parts) => Uint8List.fromList([
  for (final (share, c) in parts)
    for (var i = 0; i < share; i++) ...[
      (c.r * 255).round(),
      (c.g * 255).round(),
      (c.b * 255).round(),
      255,
    ],
]);

void main() {
  test('the colour most of the cover is, not a small bright title', () async {
    final argb = await dominantColor(
      cover([(88, const Color(0xFF1E3C8C)), (12, const Color(0xFFFF2020))]),
    );
    final c = Color(argb!);
    expect(c.b, greaterThan(c.r), reason: 'blue, not the red title');
  });

  test('a cream cover with dark text and an orange logo stays cream', () async {
    final c = Color(
      (await dominantColor(
        cover([
          (85, const Color(0xFFF5EBD7)),
          (10, const Color(0xFF1E1E1E)),
          (5, const Color(0xFFFF6A00)),
        ]),
      ))!,
    );
    expect(c.computeLuminance(), greaterThan(0.6));
  });

  test('black and white covers give their main grey', () async {
    final c = Color(
      (await dominantColor(
        cover([(70, const Color(0xFF101010)), (30, const Color(0xFFF0F0F0))]),
      ))!,
    );
    expect(c.computeLuminance(), lessThan(0.05));
  });

  test('nothing to see: no colour', () async {
    expect(await dominantColor(Uint8List(0)), isNull);
  });
}
