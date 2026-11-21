import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'atomic_file.dart';

/// Shu's settings, library and progress on Linux and Windows, in the same
/// `shared_preferences.json` the stock plugins use. Those empty the file and then write it, so
/// a kill in between left an empty file, read back as "no settings" and saved over for good.
/// This store replaces the file in one step ([writeAtomically]).
class DesktopPrefs extends SharedPreferencesStorePlatform {
  DesktopPrefs({Future<Directory> Function()? folder})
    : _folder = folder ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _folder;
  Map<String, Object>? _values;
  File? _file;

  /// The write on its way to the disk, and the callers waiting for the one after it.
  Future<void>? _writing;
  Completer<void>? _next;

  /// Puts this store in place of the plugin's, before the first `SharedPreferences.getInstance`.
  static void use() {
    if (Platform.isLinux || Platform.isWindows) {
      SharedPreferencesStorePlatform.instance = DesktopPrefs();
    }
  }

  Future<Map<String, Object>> _read() async {
    if (_values case final values?) return values;
    final file = _file = File(
      '${(await _folder()).path}${Platform.pathSeparator}shared_preferences.json',
    );
    // On a first start the folder doesn't exist yet; saves create it.
    await file.parent.create(recursive: true);
    // A save cut short by a kill leaves its temporary file; the real one is untouched.
    await for (final left in file.parent.list()) {
      final name = left.path.split(Platform.pathSeparator).last;
      if (name.startsWith('shared_preferences.json.') &&
          name.endsWith('.tmp')) {
        await left.delete();
      }
    }
    var values = <String, Object>{};
    if (await file.exists()) {
      try {
        final text = await file.readAsString();
        // An empty file never comes from this store; the plugin left one when it was killed.
        values = (jsonDecode(text) as Map).cast<String, Object>();
      } on Object catch (e) {
        // Kept for recovery: the next save would otherwise write over it.
        final aside =
            '${file.path}.bad-${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('Settings file unreadable ($e), kept as $aside');
        await file.rename(aside);
      }
    }
    return _values ??= values;
  }

  /// Saves everything as it is now; done once a write that includes this change is on disk.
  /// Writes run one at a time, each a full copy, so the file always ends at the latest state.
  Future<bool> _save() async {
    final next = _next ??= Completer<void>();
    _writing ??= _flush();
    try {
      await next.future;
      return true;
    } on Object catch (e) {
      debugPrint('Could not save settings: $e');
      return false;
    }
  }

  /// Writes until nothing is waiting. Changes made during a write share the next one: a burst
  /// of changes costs two writes, not one each.
  Future<void> _flush() async {
    for (var done = _next; done != null; done = _next) {
      _next = null;
      try {
        await writeAtomically(_file!, jsonEncode(_values));
        done.complete();
      } on Object catch (e) {
        done.completeError(e);
      }
    }
    _writing = null;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    (await _read())[key] = value;
    return _save();
  }

  @override
  Future<bool> remove(String key) async {
    (await _read()).remove(key);
    return _save();
  }

  @override
  Future<bool> clear() => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final filter = parameters.filter;
    (await _read()).removeWhere(
      (key, _) =>
          key.startsWith(filter.prefix) &&
          (filter.allowList?.contains(key) ?? true),
    );
    return _save();
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final filter = parameters.filter;
    return {
      for (final MapEntry(:key, :value) in (await _read()).entries)
        if (key.startsWith(filter.prefix) &&
            (filter.allowList?.contains(key) ?? true))
          key: value,
    };
  }
}
