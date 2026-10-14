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

  test(
    'a copy from the local network follows the address its manifest gives',
    () {
      const github = 'https://example.org/ext.js';
      expect(updateSource('http://192.168.1.20:8080/ext.js', github), github);
      // Safe sources keep their own address: a local working copy stays local.
      expect(
        updateSource('file:///home/me/ext.js', github),
        'file:///home/me/ext.js',
      );
      expect(
        updateSource('https://mirror.org/ext.js', github),
        'https://mirror.org/ext.js',
      );
      // Nothing safe to follow: as before.
      expect(
        updateSource('http://192.168.1.20/ext.js', 'http://other/ext.js'),
        'http://192.168.1.20/ext.js',
      );
      expect(updateSource(null, github), isNull);
    },
  );
}
