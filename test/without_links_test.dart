import 'package:audiobooks/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('errors are logged without their links', () {
    expect(
      withoutLinks(
        Exception(
          'Could not reach https://api.example.org/x?apikey=SECRET and '
          'magnet:?xt=urn:btih:abc, nor HTTP://Host:8080/a',
        ),
      ),
      'Exception: Could not reach <link> and magnet:?xt=urn:btih:abc, nor <link>',
    );
    expect(withoutLinks('Plain text'), 'Plain text');
  });
}
