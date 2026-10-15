import 'dart:async';
import 'dart:isolate';

import '../addons/backend.dart';
import 'host.dart';
import 'js_engine.dart';

/// Runs one extension in its own background isolate, so its JavaScript and the host work it
/// asks for (parsing pages, matching results) never hold up the app's frames.
///
/// The isolate starts on the first call and exits after [idleTimeout] without calls, so an
/// installed but unused extension costs no memory. Messages only flow while calls do: nothing
/// polls.
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

  // shortcut: a call stuck in a synchronous JS loop keeps its isolate busy until the app exits
  // (Isolate.kill waits for native code to return); stopping it needs a QuickJS interrupt
  // handler, which flutter_js's prebuilt bridge doesn't set.
  static const _callTimeout = Duration(seconds: 60);

  final String id;
  final String code;

  /// The app's host: it keeps the extension's cache while the isolate comes and goes.
  final ExtensionHost host;
  final Duration idleTimeout;

  /// The user's settings, visible to the extension as `host.settings`.
  Map<String, Object?> settings;

  Future<SendPort>? _worker;
  ReceivePort? _inbox;
  final _calls = <int, Completer<Object?>>{};
  int _nextCall = 0;
  Timer? _idleTimer;

  bool get isRunning => _worker != null;

  /// Calls `extension[method](...args)` and waits for its (JSON) result.
  Future<Object?> call(String method, List<Object?> args) async {
    _idleTimer?.cancel();
    final id = _nextCall++;
    final done = Completer<Object?>();
    _calls[id] = done;
    try {
      (await _start()).send(('call', id, method, args));
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
    _worker?.then((port) => port.send(('settings', value)));
  }

  /// Reads an extension's manifest without starting an isolate (once, when installing).
  static Map<String, dynamic> readManifest(String code, ExtensionHost host) =>
      JsEngine.readManifest(code, host);

  Future<SendPort> _start() => _worker ??= () async {
    final inbox = _inbox = ReceivePort();
    final ready = Completer<SendPort>();
    inbox.listen((message) {
      switch (message) {
        case SendPort port:
          ready.complete(port);
        case ('cache', int ask, String op, List<Object?> args):
          final worker = _worker;
          unawaited(
            host
                .run(op, args)
                .then(
                  (value) async => (await worker)?.send(('cache', ask, value)),
                ),
          );
        case ('done', int id, bool ok, Object? value):
          final call = _calls[id];
          if (call == null || call.isCompleted) return;
          ok
              ? call.complete(value)
              : call.completeError(AddonException('$value'));
        case [String error, String? _]:
          // An uncaught error ended the isolate.
          _fail('The extension stopped: $error');
          _stop();
      }
    });
    await Isolate.spawn(
      _run,
      (inbox.sendPort, id, code, settings),
      onError: inbox.sendPort,
      debugName: 'extension $id',
    );
    return ready.future;
  }();

  void _scheduleIdle() {
    _idleTimer?.cancel();
    if (_calls.isNotEmpty) return;
    _idleTimer = Timer(idleTimeout, dispose);
  }

  void dispose() {
    _idleTimer?.cancel();
    _fail('The extension was stopped.');
    _stop();
  }

  void _fail(String message) {
    for (final c in _calls.values) {
      if (!c.isCompleted) c.completeError(AddonException(message));
    }
    _calls.clear();
  }

  void _stop() {
    final worker = _worker;
    _worker = null;
    worker?.then((port) => port.send(('stop',)));
    _inbox?.close();
    _inbox = null;
  }

  /// The isolate: one [JsEngine] with its own [ExtensionHost], answering calls.
  static Future<void> _run(
    (SendPort, String, String, Map<String, Object?>) start,
  ) async {
    final (reply, id, code, settings) = start;
    final inbox = ReceivePort();
    final asked = <int, Completer<Object?>>{};
    var nextAsk = 0;
    final host = ExtensionHost(
      sharedCache: (op, args) {
        final answer = Completer<Object?>();
        asked[nextAsk] = answer;
        reply.send(('cache', nextAsk++, op, args));
        return answer.future;
      },
    );
    final engine = JsEngine(id: id, code: code, host: host, settings: settings);
    reply.send(inbox.sendPort);
    await for (final message in inbox) {
      switch (message) {
        case ('call', int call, String method, List<Object?> args):
          unawaited(
            engine
                .call(method, args)
                .then(
                  (value) => reply.send(('done', call, true, value)),
                  onError: (Object e) => reply.send((
                    'done',
                    call,
                    false,
                    e is AddonException ? e.message : '$e',
                  )),
                ),
          );
        case ('cache', int ask, Object? value):
          asked.remove(ask)?.complete(value);
        case ('settings', Map<String, Object?> value):
          engine.updateSettings(value);
        case ('stop',):
          engine.dispose();
          // Ends the isolate with everything in it (open connections too).
          Isolate.exit();
      }
    }
  }
}
