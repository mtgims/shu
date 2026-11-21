// A jump far into a streamed MP3 must ask the server for that part, not read up to it. MP3s
// without a seek table that carry a cover picture (most audiobook rips) were searched frame by
// frame from the start on the desktop: an hour in meant downloading the whole hour first, the
// player silent meanwhile. The backend's fastseek makes mpv jump to the byte instead.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// One frame of silence: MPEG-1 Layer III, 32 kbps (4000 bytes a second), 32 kHz, mono.
final _frame = base64Decode(
  '//sYxMIDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV'
  'VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV'
  'VVVVVVVMQU1FNC4wVVVVVVVVVVVVVVVV',
);

/// An ID3v2.3 tag with a small front cover picture, as audiobook files carry (written by
/// ffmpeg). The picture is what makes mpv treat the file as one it must search frame by frame.
final _tag = base64Decode(
  'SUQzAwAAAAAIX1RTU0UAAAAOAAAATGF2ZjYzLjEuMTAyAEFQSUMAAAQzAAAAaW1hZ2UvanBlZwAAQWxi'
  'dW0gY292ZXIA/9j/4AAQSkZJRgABAgAAAQABAAD//gAPTGF2YzYzLjEuMTAyAP/bAEMACAQEBAQEBQUF'
  'BQUFBgYGBgYGBgYGBgYGBgcHBwgICAcHBwYGBwcICAgICQkJCAgICAkJCgoKDAwLCw4ODhERFP/EAE0A'
  'AQEAAAAAAAAAAAAAAAAAAAAGAQEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAA'
  'AAAAAAAAAAAAAAAAAAD/wAARCAHCASwDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLASbfwAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAH//ZAAAAAAAAAAAAAA==',
);

/// Where the player's requests started, and the bytes sent.
final _starts = <int>[];
var _sent = 0;

/// An hour of silence (~14 MB) after the tag, served with ranges at ~256 KB/s like a real host.
Future<HttpServer> _serveHour() async {
  const frames = 100000;
  final tag = _tag;
  final file = Uint8List(tag.length + frames * _frame.length)..setAll(0, tag);
  for (var i = 0; i < frames; i++) {
    file.setAll(tag.length + i * _frame.length, _frame);
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final res = req.response;
    res.headers.contentType = ContentType('audio', 'mpeg');
    res.headers.set('accept-ranges', 'bytes');
    final range = RegExp(r'bytes=(\d+)-')
        .firstMatch(req.headers.value('range') ?? '');
    final start = range == null ? 0 : int.parse(range.group(1)!);
    _starts.add(start);
    if (range != null) {
      res.statusCode = 206;
      res.headers.set(
        'content-range',
        'bytes $start-${file.length - 1}/${file.length}',
      );
    }
    res.contentLength = file.length - start;
    try {
      for (var at = start; at < file.length; at += 16384) {
        final chunk = file.sublist(at, (at + 16384).clamp(0, file.length));
        res.add(chunk);
        _sent += chunk.length;
        await res.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await res.close();
    } on Object {
      // The player hung up: it jumped elsewhere.
    }
  });
  return server;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();

  for (final opening in [false, true]) {
    final how = opening ? 'opening at 55 min (a resume)' : 'a jump to 55 min';
    testWidgets('$how asks for that part of the file', (tester) async {
      await tester.runAsync(() async {
        _starts.clear();
        _sent = 0;
        final server = await _serveHour();
        final player = AudioPlayer();
        final url = 'http://127.0.0.1:${server.port}/hour.mp3';
        const target = Duration(minutes: 55);
        if (opening) {
          await player.setUrl(url, initialPosition: target);
        } else {
          await player.setUrl(url);
          await player.seek(target);
        }
        unawaited(player.play());
        // The position proves nothing: it shows the target at once. What counts is a request
        // past 50 minutes (4000 bytes a second) before most of the file was read.
        const far = 50 * 60 * 4000;
        final end = DateTime.now().add(const Duration(seconds: 15));
        while (!_starts.any((s) => s > far)) {
          if (DateTime.now().isAfter(end)) {
            fail(
              'No request near 55 min after 15 s; ${_sent ~/ 1024} KB read from the start',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(_sent, lessThan(4 << 20), reason: 'read most of the file first');
        await player.dispose();
        await server.close(force: true);
      });
    });
  }
}
