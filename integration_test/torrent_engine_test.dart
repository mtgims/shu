// The torrent engine against a real TorrServer (SHU_TORRSERVER, set by the dev shell) and the
// live network, with Debian's installer torrent: always well shared, and a free download.
import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/peer/torrent_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'temp_paths.dart';

const hash = '7acf8fb590b2060dd9c3146ef770169d593433b0';
const magnet =
    'magnet:?xt=urn:btih:$hash&tr=http%3A%2F%2Fbttracker.debian.org%3A6969%2Fannounce';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'streams part of a torrent, keeps it across restarts, deletes it',
    (tester) async {
      await tester.runAsync(() async {
        if (await TorrentEngine.findBinary() == null) {
          markTestSkipped('No TorrServer: set SHU_TORRSERVER');
          return;
        }
        final root = useTempAppStorage();
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final engine = TorrentEngine(prefs);
        const options = TorrentOptions(storageLimit: 1 << 30);

        final files = await engine.files(magnet, options);
        expect(files.single.path, endsWith('.iso'));
        final url = await engine.stream(magnet, files.single.index, options);
        expect(engine.hashOf(url), hash);
        final res = await http
            .get(Uri.parse(url), headers: {'range': 'bytes=0-262143'})
            .timeout(const Duration(seconds: 60));
        expect(res.statusCode, 206);
        expect(res.bodyBytes.length, 262144);
        engine.loaded(url, 'ext|book');

        final folder = Directory('${root.path}/support/torrents/$hash');
        expect(File('${folder.path}/.shu-download').existsSync(), isTrue);
        final pieces = folder.listSync().length;
        expect(pieces, greaterThan(1));

        // A new engine process keeps what was downloaded.
        await engine.stop();
        await engine.files(magnet, options);
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(folder.listSync().length, greaterThanOrEqualTo(pieces));

        engine.loaded(null, null);
        await engine.forget(hash);
        expect(folder.existsSync(), isFalse);
        final port = prefs.getInt('torrent.port')!;
        final listed = await http.post(
          Uri.parse('http://127.0.0.1:$port/torrents'),
          body: jsonEncode({'action': 'list'}),
        );
        expect(listed.body, isNot(contains(hash)));

        await engine.stop();
        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, port),
          throwsA(isA<SocketException>()),
          reason: 'the process is gone',
        );
        await root.delete(recursive: true);
      });
    },
  );
}
