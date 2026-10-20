import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../addons/addon_store.dart' show compareVersions;
import '../version.dart';

/// A newer release on GitHub. [apk] is the download for this phone; desktop builds get the
/// release page instead.
class AppUpdate {
  const AppUpdate({required this.version, required this.page, this.apk});

  final String version;
  final Uri page;
  final Uri? apk;
}

/// Looks for a newer release on GitHub at most once a day, and on Android installs it.
class Updater {
  Updater(this._prefs, {http.Client? client}) : _http = client ?? http.Client();

  final SharedPreferences _prefs;
  final http.Client _http;

  static const repo = 'mtgims/shu';

  /// Builds that are updated another way (the Nix package) leave the check out.
  static const enabled = bool.fromEnvironment(
    'UPDATE_CHECK',
    defaultValue: true,
  );

  static const _checkedKey = 'update.checked';
  static const _skippedKey = 'update.skipped';
  static const _every = Duration(hours: 24);

  /// The newer release, or null. [force] checks now and also shows a version marked "later".
  Future<AppUpdate?> check({bool force = false}) async {
    if (!enabled ||
        !(Platform.isAndroid || Platform.isLinux || Platform.isWindows)) {
      return null;
    }
    final checked = DateTime.tryParse(_prefs.getString(_checkedKey) ?? '');
    if (!force &&
        checked != null &&
        DateTime.now().difference(checked) < _every) {
      return null;
    }
    final res = await _http
        .get(
          Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
          headers: {'accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 20));
    await _prefs.setString(_checkedKey, DateTime.now().toIso8601String());
    if (res.statusCode != 200) return null;
    return parseRelease(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      skipped: force ? null : _prefs.getString(_skippedKey),
    );
  }

  /// The update in GitHub's release JSON, when it is newer than this build and not [skipped].
  static AppUpdate? parseRelease(
    Map<String, dynamic> release, {
    String? skipped,
    String current = appVersion,
    bool android = false,
    Abi? abi,
  }) {
    final version = (release['tag_name'] as String? ?? '').replaceFirst(
      RegExp('^v'),
      '',
    );
    if (version.isEmpty ||
        compareVersions(version, current) <= 0 ||
        version == skipped) {
      return null;
    }
    final assets = <String, String>{
      for (final a in (release['assets'] as List? ?? const []))
        if (a is Map &&
            a['name'] is String &&
            a['browser_download_url'] is String)
          a['name'] as String: a['browser_download_url'] as String,
    };
    final apkName = switch (abi ?? Abi.current()) {
      Abi.androidArm64 => 'shu-android-arm64-v8a.apk',
      Abi.androidArm => 'shu-android-armeabi-v7a.apk',
      _ => null,
    };
    final apk = (android || Platform.isAndroid) && apkName != null
        ? assets[apkName]
        : null;
    return AppUpdate(
      version: version,
      page: Uri.parse(
        release['html_url'] as String? ??
            'https://github.com/$repo/releases/latest',
      ),
      apk: apk == null ? null : Uri.parse(apk),
    );
  }

  /// "Later": this version isn't offered again on its own.
  Future<void> skip(AppUpdate update) =>
      _prefs.setString(_skippedKey, update.version);

  /// Downloads the APK into the app's cache and opens the system installer. Answers
  /// "permission" when Android first needs the user to allow installs from Shu.
  Future<String> install(
    AppUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = Directory(
      '${(await getApplicationCacheDirectory()).path}/updates',
    );
    // Only the update being installed is kept.
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}/shu-${update.version}.apk');
    final res = await _http
        .send(http.Request('GET', update.apk!))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw HttpException('The download failed (HTTP ${res.statusCode}).');
    }
    final total = res.contentLength;
    var received = 0;
    final sink = file.openWrite();
    try {
      // A download that stops sending fails instead of hanging.
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) onProgress?.call(received / total);
      }
    } on Object {
      await sink.close().catchError((Object _) {});
      // Half an APK is no use, and the next try starts over.
      await file.delete().catchError((Object _) => file);
      rethrow;
    }
    await sink.close();
    return await const MethodChannel('io.player.shu/update')
            .invokeMethod<String>('install', file.path) ??
        'started';
  }
}
