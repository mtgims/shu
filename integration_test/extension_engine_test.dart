// Runs a small extension in the real JS engine: host.fetch, host.select, host.cache, settings,
// errors, timeouts of nothing (event-driven), and shutdown when idle.
import 'dart:convert';
import 'dart:io';

import 'package:audiobooks/addons/addon_store.dart';
import 'package:audiobooks/addons/backend.dart';
import 'package:audiobooks/addons/models.dart';
import 'package:audiobooks/extensions/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const page = '''
<html><body>
  <div class="book"><a href="/b/1">First Book</a><img src="/c/1.jpg"></div>
  <div class="book"><a href="/b/2">Second Book</a></div>
</body></html>''';

String extensionCode(String base) =>
    '''
var fetches = 0;
extension = {
  manifest: {
    id: 'test.engine', name: 'Engine test', version: '1.0.0',
    catalogs: [{ id: 'all', name: 'All' }],
    settings: [{ key: 'greeting', label: 'Greeting', type: 'text', default: 'hello' }],
  },
  async catalog(id, opts) {
    var cached = await host.cache.get('page');
    if (!cached) {
      fetches++;
      var res = await host.fetch('$base/list', { query: { q: opts.search || '' } });
      cached = res.text;
      await host.cache.set('page', cached, 60);
    }
    var books = [];
    for (var el of await host.select(cached, 'div.book')) {
      var link = (await host.select(el.html, 'a'))[0];
      var img = (await host.select(el.html, 'img'))[0];
      books.push({ id: link.attrs.href, title: link.text, cover: img ? img.attrs.src : undefined,
        details: host.settings.greeting + ' #' + fetches });
    }
    return { books: books, hasMore: false };
  },
  async book(id) { return { id: id, title: 'T', chapters: [{ id: '0', title: 'One' }] }; },
  async sources(bookId, chapterId) {
    var res = await host.fetch('$base/echo', { form: { a: [1, 2], b: 'x y' } });
    return { sources: [{ id: 's', name: 'S', resolve: { token: res.text } }] };
  },
  async resolve(data) {
    if (data.token === 'fail') throw new Error('nope');
    return { url: 'https://cdn.test/' + data.token };
  },
};
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('extension engine', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.uri.path == '/echo') {
          req.response.write(await utf8.decoder.bind(req).join());
        } else {
          req.response.headers.contentType = ContentType.html;
          req.response.write(page);
        }
        await req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      ExtensionEngine.defaultIdleTimeout = const Duration(milliseconds: 500);

      final store = await AddonStore.load(
        await SharedPreferences.getInstance(),
      );
      // Installed the way a user would from a file on the computer.
      final file = File('${Directory.systemTemp.createTempSync().path}/test.js')
        ..writeAsStringSync(extensionCode(base));
      final addon = ((await store.install(file.path)) as Installed).addon;
      expect(addon.updateUrl, Uri.file(file.path).toString());
      expect(addon.manifest.settings.single.key, 'greeting');

      final first = await addon.client.catalog('all', search: 'x');
      expect(first.books.map((b) => b.title), ['First Book', 'Second Book']);
      expect(first.books.first.cover, '/c/1.jpg');
      expect(first.books.first.details, 'hello #1');

      // Settings reach the running engine; the cache spares a second download.
      await store.saveSettings(addon, {'greeting': 'hi'});
      expect((await addon.client.catalog('all')).books.first.details, 'hi #1');

      final sources = await addon.client.sources('b', '0');
      expect(sources.sources.single.resolve, {'token': 'a=1&a=2&b=x+y'});
      final resolved = await addon.client.resolve(sources.sources.single);
      expect((resolved as Playable).url, 'https://cdn.test/a=1&a=2&b=x+y');

      await expectLater(
        addon.client.resolve(
          const Source(id: 's', name: 'S', resolve: {'token': 'fail'}),
        ),
        throwsA(
          isA<AddonException>().having((e) => e.message, 'message', 'nope'),
        ),
      );

      // Idle engines shut down; the next call starts a fresh one (globals reset, cache kept).
      expect(addon.engine!.isRunning, isTrue);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(addon.engine!.isRunning, isFalse);
      expect((await addon.client.catalog('all')).books.first.details, 'hi #0');

      // Many calls at once.
      final many = await Future.wait([
        for (var i = 0; i < 20; i++)
          addon.client.resolve(
            Source(id: 's', name: 'S', resolve: {'token': '$i'}),
          ),
      ]);
      expect(many.whereType<Playable>().length, 20);

      await server.close(force: true);
    });
  });
}
