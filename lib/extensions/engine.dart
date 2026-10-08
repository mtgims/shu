import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';

import '../addons/backend.dart';
import 'host.dart';

/// Runs one extension's JavaScript. The engine starts on the first call and shuts down after
/// [idleTimeout] without calls, so an installed but unused extension costs no memory.
///
/// Calls are event driven: JS asks for host work with `sendMessage`, Dart does it and hands the
/// result back, then runs the engine's pending jobs. Nothing polls.
class ExtensionEngine {
  ExtensionEngine({
    required this.id,
    required this.code,
    required this.host,
    this.settings = const {},
    Duration? idleTimeout,
  }) : idleTimeout = idleTimeout ?? defaultIdleTimeout;

  /// How long an engine stays up after its last call (tests shorten it).
  static Duration defaultIdleTimeout = const Duration(minutes: 2);

  final String id;
  final String code;
  final ExtensionHost host;
  final Duration idleTimeout;

  /// The user's settings, visible to the extension as `host.settings`.
  Map<String, Object?> settings;

  static const _callTimeout = Duration(seconds: 60);

  JavascriptRuntime? _rt;
  final _calls = <int, Completer<Object?>>{};
  int _nextCall = 0;
  Timer? _idleTimer;

  bool get isRunning => _rt != null;

  /// Calls `extension[method](...args)` and waits for its (JSON) result.
  Future<Object?> call(String method, List<Object?> args) async {
    _idleTimer?.cancel();
    final rt = _start();
    final id = _nextCall++;
    final done = Completer<Object?>();
    _calls[id] = done;
    final r = rt.evaluate(
      '__atb.call($id, ${jsonEncode(method)}, ${jsonEncode(jsonEncode(args))})',
    );
    if (r.isError) {
      _calls.remove(id);
      _scheduleIdle();
      throw AddonException('Extension error: ${r.stringResult}');
    }
    rt.executePendingJob();
    try {
      return await done.future.timeout(_callTimeout);
    } on TimeoutException {
      throw AddonException('The extension took too long to answer.');
    } finally {
      _calls.remove(id);
      _scheduleIdle();
    }
  }

  /// Pushes new settings into a running engine (a stopped one gets them when it starts).
  void updateSettings(Map<String, Object?> value) {
    settings = value;
    _rt?.evaluate('host.settings = ${jsonEncode(value)}');
  }

  /// Reads an extension's manifest without keeping the engine.
  static Map<String, dynamic> readManifest(String code, ExtensionHost host) {
    final engine = ExtensionEngine(id: '_probe', code: code, host: host);
    try {
      final rt = engine._start();
      final r = rt.evaluate(
        'JSON.stringify(typeof extension === "object" && extension ? extension.manifest : null)',
      );
      final manifest = r.isError ? null : jsonDecode(r.stringResult);
      if (manifest is! Map<String, dynamic>) {
        throw AddonException('This file is not an audiobook extension.');
      }
      return manifest;
    } finally {
      engine.dispose();
    }
  }

  /// flutter_js opens its QuickJS library by bare name, which Linux does not look for next to
  /// the app. Opening it once by full path makes later lookups by name find it.
  static bool _preloaded = false;
  static void _preloadQuickJs() {
    if (_preloaded || !Platform.isLinux) return;
    _preloaded = true;
    final lib = File(
      '${File(Platform.resolvedExecutable).parent.path}/lib/libquickjs_c_bridge_plugin.so',
    );
    if (lib.existsSync()) DynamicLibrary.open(lib.path);
  }

  JavascriptRuntime _start() {
    final existing = _rt;
    if (existing != null) return existing;
    _preloadQuickJs();
    final rt = Platform.isIOS || Platform.isMacOS
        ? JavascriptCoreRuntime()
        // No memory limit: the prebuilt QuickJS for Linux and Windows lacks jsSetMemoryLimit.
        : QuickJsRuntime2();
    rt.onMessage('atb.op', (args) {
      // Runs inside JS; the work starts after the current evaluation returns.
      scheduleMicrotask(() => _hostOp(rt, args as Map));
      return null;
    });
    rt.onMessage('atb.done', (args) {
      final m = args as Map;
      final call = _calls[(m['id'] as num).toInt()];
      if (call == null || call.isCompleted) return null;
      if (m['ok'] == true) {
        call.complete(m['value']);
      } else {
        call.completeError(AddonException('${m['value']}'));
      }
      return null;
    });
    rt.onMessage('atb.log', (args) {
      debugPrint('[$id] ${(args as List).join(' ')}');
      return null;
    });
    for (final script in [
      _prelude,
      'host.settings = ${jsonEncode(settings)}',
      code,
    ]) {
      final r = rt.evaluate(script);
      if (r.isError) {
        _dispose(rt);
        throw AddonException('The extension failed to load: ${r.stringResult}');
      }
    }
    rt.executePendingJob();
    _rt = rt;
    return rt;
  }

  Future<void> _hostOp(
    JavascriptRuntime rt,
    Map<Object?, Object?> message,
  ) async {
    final callId = message['id'];
    final op = message['op'] as String;
    var args = (message['args'] as List?)?.cast<Object?>() ?? const [];
    // Each extension gets its own cache namespace.
    if (op == 'cacheGet' || op == 'cacheSet') {
      args = ['$id:${args[0]}', ...args.skip(1)];
    }
    bool ok;
    Object? value;
    try {
      value = await host.run(op, args);
      ok = true;
    } on Object catch (e) {
      value = e is AddonException ? e.message : '$op failed: $e';
      ok = false;
    }
    if (!identical(rt, _rt)) return; // the engine was shut down meanwhile
    rt.evaluate('__atb.settle($callId, $ok, ${jsonEncode(jsonEncode(value))})');
    rt.executePendingJob();
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    if (_calls.isNotEmpty) return;
    _idleTimer = Timer(idleTimeout, dispose);
  }

  void dispose() {
    _idleTimer?.cancel();
    final rt = _rt;
    _rt = null;
    if (rt != null) _dispose(rt);
    for (final c in _calls.values) {
      if (!c.isCompleted) {
        c.completeError(AddonException('The extension was stopped.'));
      }
    }
    _calls.clear();
    host.trim();
  }

  static void _dispose(JavascriptRuntime rt) {
    JavascriptRuntime.channelFunctionsRegistered.remove(
      rt.getEngineInstanceId(),
    );
    rt.dispose();
  }

  /// Sets up `host` and the call/answer plumbing before the extension's own code runs.
  static const _prelude = r'''
var __atb = (function () {
  var waiting = {};
  var next = 0;
  function op(name, args) {
    return new Promise(function (resolve, reject) {
      var id = next++;
      waiting[id] = [resolve, reject];
      sendMessage('atb.op', JSON.stringify({ id: id, op: name, args: args }));
    });
  }
  globalThis.host = {
    settings: {},
    fetch: function (url, options) {
      return op('fetch', [url, options || {}]).then(function (r) {
        r.ok = r.status >= 200 && r.status < 300;
        return r;
      });
    },
    select: function (html, selector, fields) {
      return op('select', fields ? [html, selector, fields] : [html, selector]);
    },
    cache: {
      get: function (key) { return op('cacheGet', [key]); },
      set: function (key, value, seconds) { return op('cacheSet', [key, value, seconds || 600]); },
    },
    sleep: function (ms) { return op('sleep', [ms]); },
    log: function () {
      sendMessage('atb.log', JSON.stringify(Array.prototype.map.call(arguments, String)));
    },
  };
  function report(id, ok, value) {
    sendMessage('atb.done', JSON.stringify({ id: id, ok: ok, value: value === undefined ? null : value }));
  }
  return {
    settle: function (id, ok, json) {
      var w = waiting[id];
      delete waiting[id];
      if (!w) return;
      var value = JSON.parse(json);
      if (ok) w[0](value); else w[1](new Error(value));
    },
    call: function (id, method, argsJson) {
      var args = JSON.parse(argsJson);
      Promise.resolve()
        .then(function () {
          var ext = globalThis.extension;
          if (!ext || typeof ext[method] !== 'function') throw new Error('The extension has no ' + method + '()');
          return ext[method].apply(ext, args);
        })
        .then(
          function (value) { report(id, true, value); },
          function (e) { report(id, false, String((e && e.message) || e)); }
        );
    },
  };
})();
''';
}
