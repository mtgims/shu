import 'package:audiobooks/addons/addon_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'extensions update on their own only over https or from this device',
    () {
      expect(updatesSafely('https://example.org/ext.js'), isTrue);
      expect(updatesSafely('file:///home/me/ext/index.json'), isTrue);
      expect(updatesSafely('http://localhost:8080/ext.js'), isTrue);
      expect(updatesSafely('http://[::1]:8080/ext.js'), isTrue);
      expect(updatesSafely('http://192.168.1.20:8080/ext.js'), isFalse);
      expect(updatesSafely('http://example.org/ext.js'), isFalse);
    },
  );
}
