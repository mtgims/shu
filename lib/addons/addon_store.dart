import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../extensions/engine.dart';
import '../extensions/extension_backend.dart';
import '../extensions/host.dart';
import '../sources/local_library.dart';
import '../sources/server.dart';
import 'backend.dart';
import 'client.dart';
import 'models.dart';

enum AddonKind { remote, extension, local, server }

class InstalledAddon {
  InstalledAddon.remote({required String this.base, required this.manifest})
    : kind = AddonKind.remote,
      client = AddonClient(base),
      updateUrl = null,
      engine = null;

  /// Part of the app: books on this device, or a media server the user signed in to.
  InstalledAddon.builtin({
    required this.kind,
    required this.manifest,
    required this.client,
  }) : base = null,
       updateUrl = null,
       engine = null;

  InstalledAddon.extension({
    required this.manifest,
    required ExtensionEngine this.engine,
    this.updateUrl,
  }) : kind = AddonKind.extension,
       base = null,
       client = ExtensionBackend(engine);

  final AddonKind kind;
  final Manifest manifest;
  final AddonBackend client;

  /// Remote addons: base URL; may hold the user's settings (API keys), never show it in full.
  final String? base;

  /// Extensions: where updates come from, and the engine running the code.
  final String? updateUrl;
  final ExtensionEngine? engine;

  String get id => manifest.id;
  bool get isExtension => kind == AddonKind.extension;
  bool get isLocal => kind == AddonKind.local;

  /// The media server behind a server addon.
  ServerBackend? get server =>
      client is ServerBackend ? client as ServerBackend : null;
}

/// An extension offered by a repository index (docs/EXTENSIONS.md).
class RepoEntry {
  const RepoEntry({
    this.id,
    required this.name,
    required this.url,
    this.version,
    this.description,
  });
  final String? id;
  final String name;
  final String url;
  final String? version;
  final String? description;
}

/// What a pasted URL turned out to be.
sealed class InstallResult {
  const InstallResult();
}

/// The user declined an extension's notice: nothing was installed.
class InstallCancelled extends AddonException {
  InstallCancelled() : super('Not installed.');
}

class Installed extends InstallResult {
  const Installed(this.addon);
  final InstalledAddon addon;
}

class Repository extends InstallResult {
  const Repository(this.name, this.entries);
  final String name;
  final List<RepoEntry> entries;
}

/// Installed remote addons, extensions and servers, and the books on this device. The list and
/// settings live in shared preferences, extension code in files.
class AddonStore extends ChangeNotifier {
  AddonStore._(this._prefs, this._dir, this.host, this.local);

  static Future<AddonStore> load(
    SharedPreferences prefs, {
    ExtensionHost? host,
  }) async {
    final support = (await getApplicationSupportDirectory()).path;
    final store = AddonStore._(
      prefs,
      Directory('$support/extensions'),
      host ?? ExtensionHost(),
      await LocalLibrary.load(Directory('$support/local')),
    );
    store._addons.add(
      InstalledAddon.builtin(
        kind: AddonKind.local,
        manifest: LocalBackend.manifest,
        client: LocalBackend(store.local),
      ),
    );
    await store._restore();
    return store;
  }

  /// Audiobooks added from this device.
  final LocalLibrary local;

  static const _key = 'addons';
  static const _updateEvery = Duration(hours: 24);

  final SharedPreferences _prefs;
  final Directory _dir;
  final ExtensionHost host;
  final List<InstalledAddon> _addons = [];
  final http.Client _http = http.Client();

  List<InstalledAddon> get addons => List.unmodifiable(_addons);

  InstalledAddon? byId(String id) {
    for (final a in _addons) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _restore() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    final List<Object?> items;
    try {
      items = jsonDecode(raw) as List;
    } on Object catch (e) {
      // Set aside rather than lost: the logins and extensions in it can be recovered.
      debugPrint('Unreadable addon list, kept as $_key.bad: $e');
      await _prefs.setString('$_key.bad', raw);
      return;
    }
    // A later copy of the same addon (reinstalled after its entry became unreadable) wins.
    void add(InstalledAddon addon) => _addons
      ..removeWhere((a) => a.id == addon.id)
      ..add(addon);
    // Extension code files are read all at once, not one after another.
    final codes = await Future.wait([for (final item in items) _codeOf(item)]);
    for (final (i, item) in items.indexed) {
      try {
        final json = item as Map<String, dynamic>;
        if (json['kind'] == 'server') {
          add(
            _serverAddon(
              ServerBackend.fromJson(json['server'] as Map<String, dynamic>),
            ),
          );
          continue;
        }
        final manifest = Manifest.fromJson(
          json['manifest'] as Map<String, dynamic>,
        );
        if (json['kind'] == 'extension') {
          final code =
              codes[i] ?? (throw StateError('No code for ${manifest.id}'));
          add(_extension(manifest, code, json['updateUrl'] as String?));
        } else {
          add(
            InstalledAddon.remote(
              base: json['base'] as String,
              manifest: manifest,
            ),
          );
        }
      } on Object catch (e) {
        debugPrint('Keeping an unreadable addon as it is: $e');
        _unreadable.add(item);
      }
    }
  }

  /// Saved addons this version can't read (an extension whose code file is gone, say),
  /// written back unchanged and first, so a readable copy of the same addon wins.
  final List<Object?> _unreadable = [];

  /// The code of a saved extension entry, or null (not an extension, or unreadable).
  Future<String?> _codeOf(Object? item) async {
    try {
      final json = item as Map<String, dynamic>;
      if (json['kind'] != 'extension') return null;
      final manifest = json['manifest'] as Map<String, dynamic>;
      return await _codeFile(manifest['id'] as String).readAsString();
    } on Object {
      return null;
    }
  }

  InstalledAddon _extension(
    Manifest manifest,
    String code,
    String? updateUrl,
  ) => InstalledAddon.extension(
    manifest: manifest,
    updateUrl: updateUrl,
    engine: ExtensionEngine(
      id: manifest.id,
      code: code,
      host: host,
      settings: settingsOf(manifest),
    ),
  );

  InstalledAddon _serverAddon(ServerBackend server) {
    // Renewed tokens must survive a restart.
    server.onLoginChanged = _save;
    return InstalledAddon.builtin(
      kind: AddonKind.server,
      manifest: server.manifest,
      client: server,
    );
  }

  /// Adds a server the user signed in to (signing in again to one replaces it).
  Future<InstalledAddon> addServer(ServerBackend server) async {
    final addon = _serverAddon(server);
    await _put(addon);
    return addon;
  }

  File _codeFile(String id) =>
      File('${_dir.path}/${id.replaceAll(RegExp(r'[^\w.-]'), '_')}.js');

  /// Installs whatever [input] points at: a remote addon, an extension (.js), or a repository
  /// index (returned so the user can pick). Same id as an installed one replaces it.
  /// Installs from [input]. [accept] is asked when an extension carries a notice the user has
  /// not accepted yet; declining throws [InstallCancelled].
  Future<InstallResult> install(
    String input, {
    Future<bool> Function(Manifest manifest)? accept,
  }) async {
    final text = input.trim();
    // A file on this device (desktop): an extension or repository not published yet.
    final uri = text.startsWith('/') || RegExp(r'^[A-Za-z]:\\').hasMatch(text)
        ? Uri.file(text)
        : Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null || (uri.host.isEmpty && !uri.isScheme('file'))) {
      throw AddonException('That is not a web address or file.');
    }

    final (body, etag) = await _download(uri).onError<Object>((e, _) async {
      if (uri.isScheme('file')) throw e;
      // A remote addon's base URL (without /manifest.json) is common to paste.
      final normalized = normalizeAddonUrl(text);
      if (normalized.manifest == uri) throw e;
      return _download(normalized.manifest);
    });
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{')) {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      if (json['extensions'] is List) return _repository(uri, json);
      if (json['protocol'] == 1) {
        final normalized = normalizeAddonUrl(uri.toString());
        final addon = InstalledAddon.remote(
          base: normalized.base,
          manifest: Manifest.fromJson(json),
        );
        await _put(addon);
        return Installed(addon);
      }
      throw AddonException(
        'That address is not an addon, extension or repository.',
      );
    }
    return Installed(
      await installExtension(
        body,
        updateUrl: uri.toString(),
        etag: etag,
        accept: accept,
      ),
    );
  }

  Future<InstalledAddon> installExtension(
    String code, {
    String? updateUrl,
    String? etag,
    Future<bool> Function(Manifest manifest)? accept,
  }) async {
    final json = ExtensionEngine.readManifest(code);
    final manifest = Manifest.fromExtensionJson(json);
    if (!await _noticeAccepted(manifest, accept)) throw InstallCancelled();
    await _dir.create(recursive: true);
    await _codeFile(manifest.id).writeAsString(code);
    final source = updateSource(updateUrl, json['updateUrl']);
    final addon = _extension(manifest, code, source);
    final etagKey = 'ext.etag.${manifest.id}';
    if (source != updateUrl) {
      await _prefs.remove(etagKey);
    } else if (etag != null) {
      await _prefs.setString(etagKey, etag);
    }
    await _prefs.setString(
      'ext.checked.${manifest.id}',
      DateTime.now().toIso8601String(),
    );
    await _put(addon);
    return addon;
  }

  /// Whether the user accepted [manifest]'s notice, asking through [accept] when the text is
  /// new to them. Updates install without asking only while the notice stays the same.
  Future<bool> _noticeAccepted(
    Manifest manifest,
    Future<bool> Function(Manifest manifest)? accept,
  ) async {
    final notice = manifest.notice;
    if (notice == null) return true;
    final key = 'ext.notice.${manifest.id}';
    if (_prefs.getString(key) == notice) return true;
    if (accept == null || !await accept(manifest)) return false;
    await _prefs.setString(key, notice);
    return true;
  }

  Repository _repository(Uri index, Map<String, dynamic> json) =>
      Repository(json['name'] as String? ?? index.host, [
        for (final e
            in (json['extensions'] as List).whereType<Map<String, dynamic>>())
          if (e['url'] is String)
            RepoEntry(
              id: e['id'] as String?,
              name: e['name'] as String? ?? e['id'] as String? ?? '?',
              url: index.resolve(e['url'] as String).toString(),
              version: e['version'] as String?,
              description: e['description'] as String?,
            ),
      ]);

  Future<(String, String?)> _download(Uri uri, {String? etag}) async {
    if (uri.isScheme('file')) {
      final file = File(uri.toFilePath());
      if (!await file.exists()) {
        throw AddonException('No file at ${file.path}.');
      }
      return (await file.readAsString(), null);
    }
    final http.Response res;
    try {
      res = await _http
          .get(uri, headers: {'if-none-match': ?etag})
          .timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      throw AddonException('Could not reach ${uri.host}: $e');
    }
    if (res.statusCode == 304) return ('', etag);
    if (res.statusCode >= 400) {
      throw AddonException('${uri.host} answered HTTP ${res.statusCode}.');
    }
    return (
      utf8.decode(res.bodyBytes, allowMalformed: true),
      res.headers['etag'],
    );
  }

  Future<void> _put(InstalledAddon addon) async {
    final at = _addons.indexWhere((a) => a.id == addon.id);
    if (at >= 0) {
      if (!identical(_addons[at].client, addon.client)) {
        _addons[at].client.dispose();
      }
      _addons[at] = addon;
    } else {
      _addons.add(addon);
    }
    await _save();
  }

  Future<void> remove(InstalledAddon addon) async {
    if (addon.isLocal) return;
    _addons.removeWhere((a) => a.id == addon.id);
    addon.client.dispose();
    if (addon.isExtension) {
      final file = _codeFile(addon.id);
      if (await file.exists()) await file.delete();
      // Installing it again asks for its notice again.
      for (final key in [
        'ext.settings.',
        'ext.etag.',
        'ext.checked.',
        'ext.notice.',
      ]) {
        await _prefs.remove('$key${addon.id}');
      }
    }
    if (addon.server != null) await _prefs.remove('server.checked.${addon.id}');
    await _save();
  }

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode([
        ..._unreadable,
        for (final a in _addons)
          if (a.server case final server?)
            {'kind': 'server', 'server': server.toJson()}
          else if (!a.isLocal)
            {
              'kind': a.kind.name,
              'manifest': a.manifest.toJson(),
              'base': ?a.base,
              'updateUrl': ?a.updateUrl,
            },
      ]),
    );
    notifyListeners();
  }

  /// Saved settings over the manifest's defaults.
  Map<String, Object?> settingsOf(Manifest manifest) {
    final raw = _prefs.getString('ext.settings.${manifest.id}');
    return {
      ...manifest.defaultSettings,
      if (raw != null) ...jsonDecode(raw) as Map<String, dynamic>,
    };
  }

  Future<void> saveSettings(
    InstalledAddon addon,
    Map<String, Object?> settings,
  ) async {
    await _prefs.setString('ext.settings.${addon.id}', jsonEncode(settings));
    addon.engine?.updateSettings(settingsOf(addon.manifest));
    notifyListeners();
  }

  /// Libraries added or renamed on a server show up as rows: checked at most once a day.
  Future<void> _refreshServers({required bool force}) async {
    for (final addon in [..._addons.where((a) => a.server != null)]) {
      final key = 'server.checked.${addon.id}';
      final checked = DateTime.tryParse(_prefs.getString(key) ?? '');
      if (!force &&
          checked != null &&
          DateTime.now().difference(checked) < _updateEvery) {
        continue;
      }
      try {
        final server = addon.server!;
        await server.refreshLibraries();
        await _prefs.setString(key, DateTime.now().toIso8601String());
        await _put(_serverAddon(server));
      } on Object catch (e) {
        debugPrint('Library check for ${addon.manifest.name} failed: $e');
      }
    }
  }

  /// Updates extensions whose last check is older than a day. A check without changes costs one
  /// small request (the server answers 304 to the stored ETag). Returns the updated names.
  Future<List<String>> checkUpdates({bool force = false}) async {
    await _refreshServers(force: force);
    final updated = <String>[];
    for (final addon in [
      ..._addons.where(
        (a) =>
            a.isExtension && a.updateUrl != null && updatesSafely(a.updateUrl!),
      ),
    ]) {
      final checkedKey = 'ext.checked.${addon.id}';
      final checked = DateTime.tryParse(_prefs.getString(checkedKey) ?? '');
      if (!force &&
          checked != null &&
          DateTime.now().difference(checked) < _updateEvery) {
        continue;
      }
      try {
        final (code, etag) = await _download(
          Uri.parse(addon.updateUrl!),
          etag: _prefs.getString('ext.etag.${addon.id}'),
        );
        await _prefs.setString(checkedKey, DateTime.now().toIso8601String());
        if (code.isEmpty) continue;
        final manifest = Manifest.fromExtensionJson(
          ExtensionEngine.readManifest(code),
        );
        if (manifest.id != addon.id ||
            compareVersions(manifest.version, addon.manifest.version) <= 0) {
          continue;
        }
        await installExtension(code, updateUrl: addon.updateUrl, etag: etag);
        updated.add('${manifest.name} ${manifest.version}');
      } on Object catch (e) {
        debugPrint('Update check for ${addon.id} failed: $e');
      }
    }
    return updated;
  }
}

/// Whether new code may be fetched from [url] on its own. Over plain http anyone on the same
/// network could swap in code that reads the extension's API keys; this device itself is fine.
bool updatesSafely(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.isScheme('https') ||
      uri.isScheme('file') ||
      (uri.isScheme('http') &&
          (uri.host == 'localhost' ||
              uri.host == '127.0.0.1' ||
              uri.host == '::1'));
}

/// Where an extension installed from [installedFrom] gets its updates. A copy from where they
/// can't safely come (plain http on a local network) follows the address the extension gives
/// for itself in its manifest ([declared]), so it keeps updating, and keeps its settings.
String? updateSource(String? installedFrom, Object? declared) =>
    installedFrom != null &&
        !updatesSafely(installedFrom) &&
        declared is String &&
        updatesSafely(declared)
    ? declared
    : installedFrom;

/// Compares dotted versions numerically ("1.10.0" > "1.9.2"), as semver orders them: a
/// pre-release comes before its release ("1.0.0-beta.2" < "1.0.0"), a build ("+12") counts
/// for nothing.
int compareVersions(String a, String b) {
  (List<int>, List<String>?) parse(String v) {
    final core = v.split('+').first;
    final dash = core.indexOf('-');
    final numbers = (dash < 0 ? core : core.substring(0, dash)).split('.');
    return (
      [for (final n in numbers) int.tryParse(n) ?? 0],
      dash < 0 ? null : core.substring(dash + 1).split('.'),
    );
  }

  final (x, xPre) = parse(a);
  final (y, yPre) = parse(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  if (xPre == null || yPre == null) {
    return xPre == yPre ? 0 : (xPre == null ? 1 : -1);
  }
  for (var i = 0; i < xPre.length && i < yPre.length; i++) {
    final (p, q) = (int.tryParse(xPre[i]), int.tryParse(yPre[i]));
    final d = p != null && q != null
        ? p - q
        : p != null
        ? -1 // Numbers come before words.
        : q != null
        ? 1
        : xPre[i].compareTo(yPre[i]);
    if (d != 0) return d.sign;
  }
  return (xPre.length - yPre.length).sign;
}
