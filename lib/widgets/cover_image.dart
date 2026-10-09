import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Cover art that is downloaded once and then read from disk. Paired with [ResizeImage] (see
/// BookCover), covers are also decoded at the size they are shown, not at full resolution.
class CoverImage extends ImageProvider<CoverImage> {
  const CoverImage(this.url);

  final String url;

  static final _http = http.Client();
  static Future<Directory>? _dir;

  /// Kept below this by [trim]; roughly a thousand covers.
  static const maxCacheBytes = 60 << 20;

  static Future<Directory> _cacheDir() => _dir ??= () async {
    final dir = Directory(
      '${(await getApplicationCacheDirectory()).path}/covers',
    );
    await dir.create(recursive: true);
    return dir;
  }();

  /// A short stable file name for a URL (FNV-1a).
  static String _fileName(String url) {
    var hash = 0xcbf29ce484222325;
    for (final unit in url.codeUnits) {
      hash = ((hash ^ unit) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  @override
  Future<CoverImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CoverImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    // Covers of books on this device are read where they are.
    final local = url.startsWith('file:')
        ? File(Uri.parse(url).toFilePath())
        : null;
    final file = local ?? File('${(await _cacheDir()).path}/${_fileName(url)}');
    Uint8List bytes;
    if (local != null || await file.exists()) {
      bytes = await file.readAsBytes();
    } else {
      final res = await _http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        throw StateError('Cover download failed (HTTP ${res.statusCode})');
      }
      bytes = res.bodyBytes;
      unawaited(file.writeAsBytes(bytes, flush: false).catchError((_) => file));
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  /// Deletes the least recently written covers until the cache fits [maxCacheBytes].
  static Future<void> trim() async {
    final dir = await _cacheDir();
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      files.add((entity, stat));
      total += stat.size;
    }
    if (total <= maxCacheBytes) return;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (total <= maxCacheBytes * 0.8) break;
      await file.delete().catchError((_) => file);
      total -= stat.size;
    }
  }

  @override
  bool operator ==(Object other) => other is CoverImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
