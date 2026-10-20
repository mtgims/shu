import 'package:audiobooks/extensions/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const magnet = 'magnet:?xt=urn:btih:0f54898dc1b8e49d96e32827377f651ea6c935af';
  final check = ExtensionEngine.checkTorrentFolder;

  test('a torrent folder the user picked is kept', () {
    final args = [
      magnet,
      {'folder': ' /media/books ', 'shareAfter': true},
    ];
    expect(check('torrentFiles', args, ['/media/books']), args);
  });

  test('any other folder is left out; the other options stay', () {
    expect(
      check(
        'torrentStream',
        [
          magnet,
          3,
          {'folder': '/home/someone', 'shareAfter': true},
        ],
        ['/media/books'],
      ),
      [
        magnet,
        3,
        {'shareAfter': true},
      ],
    );
    expect(
      check('torrentFiles', [
        magnet,
        {'folder': '/etc'},
      ], const []),
      [magnet, <String, Object?>{}],
    );
  });

  test('calls without a folder, and other calls, pass unchanged', () {
    final noFolder = [magnet, <String, Object?>{}];
    expect(check('torrentFiles', noFolder, const []), noFolder);
    final fetch = [
      'https://example.org',
      {'folder': '/etc'},
    ];
    expect(check('fetch', fetch, const []), fetch);
  });
}
