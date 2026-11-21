import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:audiobooks/updates/desktop_install.dart';
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
      'shu-linux-x86_64.AppImage',
      'shu-windows-x64.zip',
    ])
      {'name': name, 'browser_download_url': 'https://dl.example/$tag/$name'},
  ],
};

void main() {
  test('each build installs its own release file', () {
    expect(
      Updater.assetFor(abi: Abi.androidArm64),
      'shu-android-arm64-v8a.apk',
    );
    expect(
      Updater.assetFor(abi: Abi.androidArm),
      'shu-android-armeabi-v7a.apk',
    );
    expect(Updater.assetFor(abi: Abi.linuxX64), 'shu-linux-x64.tar.gz');
    expect(
      Updater.assetFor(abi: Abi.linuxX64, appImage: true),
      'shu-linux-x86_64.AppImage',
    );
    expect(Updater.assetFor(abi: Abi.windowsX64), 'shu-windows-x64.zip');
    expect(Updater.assetFor(abi: Abi.macosArm64), isNull);
  });

  test('a newer release offers the file for this build', () {
    final update = Updater.parseRelease(
      release('v0.5.0'),
      current: '0.4.0',
      asset: 'shu-windows-x64.zip',
    )!;
    expect(update.version, '0.5.0');
    expect(update.file.toString(), endsWith('/v0.5.0/shu-windows-x64.zip'));
  });

  test('a build that can not replace itself gets the release page', () {
    final update = Updater.parseRelease(release('v0.5.0'), current: '0.4.0')!;
    expect(update.file, isNull);
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

  group('desktop install', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('shu'));
    tearDown(() => root.delete(recursive: true));

    Future<void> write(String path, String text) async {
      final file = File('${root.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    }

    String read(String path) => File('${root.path}/$path').readAsStringSync();

    test(
      'the archive replaces the app, the old files wait to be tidied',
      () async {
        await write('app/shu', 'old');
        await write('app/lib/libapp.so', 'old');
        await write('app/books.txt', 'mine');
        await write('new/shu/shu', 'new');
        await write('new/shu/lib/libapp.so', 'new');
        await write('new/shu/lib/libextra.so', 'new');
        final archive = File('${root.path}/app/.shu-update/shu.tar.gz');
        await archive.parent.create();
        final tar = await Process.run('tar', [
          '-czf',
          archive.path,
          '-C',
          '${root.path}/new',
          'shu',
        ]);
        expect(tar.exitCode, 0);

        await DesktopInstall.unpack(archive, Directory('${root.path}/app'));
        expect(read('app/shu'), 'new');
        expect(read('app/lib/libapp.so'), 'new');
        expect(read('app/lib/libextra.so'), 'new');
        expect(read('app/books.txt'), 'mine');
        final old = Directory('${root.path}/app')
            .listSync()
            .whereType<Directory>()
            .singleWhere((d) => d.path.contains('.shu-old-'));
        expect(File('${old.path}/shu').readAsStringSync(), 'old');
      },
    );

    test('a failed move puts everything back', () async {
      await write('app/a', 'old');
      await write('new/a', 'new');
      await write('new/b', 'new');
      // A folder where the file "b" should go makes its move fail.
      await Directory('${root.path}/app/b/x').create(recursive: true);
      await expectLater(
        DesktopInstall.swapIn(
          Directory('${root.path}/new'),
          Directory('${root.path}/app'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(read('app/a'), 'old');
    });
  });
}
