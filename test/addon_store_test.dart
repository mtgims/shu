import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/addons/addon_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/temp_paths.dart';

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

  test('versions compare as semver orders them', () {
    expect(compareVersions('1.10.0', '1.9.2'), 1);
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('0.5.1+12', '0.5.1'), 0);
    expect(compareVersions('1.0.0', '1.0.0-beta.1'), 1);
    expect(compareVersions('1.0.0-rc1', '1.0.0'), -1);
    expect(compareVersions('1.0.0-beta.2', '1.0.0-beta.1'), 1);
    expect(compareVersions('1.0.0-beta.10', '1.0.0-beta.9'), 1);
    expect(compareVersions('1.0.0-beta', '1.0.0-rc'), -1);
    expect(compareVersions('1.0.0-beta', '1.0.0-beta.1'), -1);
    expect(compareVersions('1.0.0-1', '1.0.0-alpha'), -1);
    expect(compareVersions('1.0.1-beta', '1.0.0'), 1);
  });

  group('saved addons', () {
    late Directory root;
    setUp(() => root = useTempAppStorage());
    tearDown(() => root.delete(recursive: true));

    Map<String, Object?> remote(String base) => {
      'kind': 'remote',
      'base': base,
      'manifest': {
        'protocol': 1,
        'id': 'test.remote',
        'name': 'Remote',
        'version': '1.0.0',
        'catalogs': <Object>[],
      },
    };
    // An extension whose code file is gone.
    const lost = {
      'kind': 'extension',
      'manifest': {
        'protocol': 1,
        'id': 'test.lost',
        'name': 'Lost',
        'version': '1.0.0',
        'catalogs': <Object>[],
      },
    };

    test('one this version can\'t read is kept on the next save', () async {
      SharedPreferences.setMockInitialValues({
        'addons': jsonEncode([lost, remote('http://127.0.0.1:1')]),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = await AddonStore.load(prefs);
      final added = store.byId('test.remote')!;
      expect(store.byId('test.lost'), isNull);
      await store.remove(added);
      expect(jsonDecode(prefs.getString('addons')!), [lost]);
    });

    test('a later copy of the same addon wins', () async {
      SharedPreferences.setMockInitialValues({
        'addons': jsonEncode([
          remote('http://127.0.0.1:1'),
          remote('http://127.0.0.1:2'),
        ]),
      });
      final store = await AddonStore.load(
        await SharedPreferences.getInstance(),
      );
      final copies = store.addons.where((a) => a.id == 'test.remote');
      expect(copies.map((a) => a.base), ['http://127.0.0.1:2']);
    });

    test('a damaged list is set aside, not lost', () async {
      SharedPreferences.setMockInitialValues({'addons': '[{"kind":'});
      final prefs = await SharedPreferences.getInstance();
      final store = await AddonStore.load(prefs);
      expect(store.addons.where((a) => !a.isLocal), isEmpty);
      expect(prefs.getString('addons.bad'), '[{"kind":');
    });
  });
}
