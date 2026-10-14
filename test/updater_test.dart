import 'dart:ffi' show Abi;

import 'package:audiobooks/updates/updater.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> release(String tag) => {
  'tag_name': tag,
  'html_url': 'https://github.com/mtgims/shu/releases/tag/$tag',
  'assets': [
    for (final name in [
      'shu-android-arm64-v8a.apk',
      'shu-android-armeabi-v7a.apk',
      'shu-linux-x64.tar.gz',
    ])
      {'name': name, 'browser_download_url': 'https://dl.example/$tag/$name'},
  ],
};

void main() {
  test('a newer release offers the APK for this phone', () {
    final update = Updater.parseRelease(
      release('v0.5.0'),
      current: '0.4.0',
      android: true,
      abi: Abi.androidArm64,
    )!;
    expect(update.version, '0.5.0');
    expect(update.apk.toString(), endsWith('/shu-android-arm64-v8a.apk'));

    final old = Updater.parseRelease(
      release('v0.5.0'),
      current: '0.4.0',
      android: true,
      abi: Abi.androidArm,
    )!;
    expect(old.apk.toString(), endsWith('/shu-android-armeabi-v7a.apk'));
  });

  test('desktop gets the release page, not a file', () {
    final update = Updater.parseRelease(
      release('v0.5.0'),
      current: '0.4.0',
      abi: Abi.linuxX64,
    )!;
    expect(update.apk, isNull);
    expect(update.page.path, '/mtgims/shu/releases/tag/v0.5.0');
  });

  test('the same, older or skipped versions are not offered', () {
    expect(Updater.parseRelease(release('v0.4.0'), current: '0.4.0'), isNull);
    expect(Updater.parseRelease(release('v0.3.1'), current: '0.4.0'), isNull);
    expect(
      Updater.parseRelease(
        release('v0.5.0'),
        current: '0.4.0',
        skipped: '0.5.0',
      ),
      isNull,
    );
    expect(
      Updater.parseRelease(release('v0.10.0'), current: '0.9.2'),
      isNotNull,
    );
  });
}
