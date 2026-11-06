import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's side of downloads: a foreground service (with its notification) that keeps Shu
/// running with the screen off, and whether the network costs money. Elsewhere it does nothing.
class DownloadService {
  DownloadService({required this.onCancel, required this.onNetwork}) {
    if (Platform.isAndroid) _channel.setMethodCallHandler(_called);
  }

  static const _channel = MethodChannel('io.player.shu/downloads');

  /// The notification's Cancel button.
  final VoidCallback onCancel;

  /// The network changed while [watchNetwork] was on.
  final VoidCallback onNetwork;

  Future<void> _called(MethodCall call) async {
    switch (call.method) {
      case 'cancel':
        onCancel();
      case 'network':
        onNetwork();
    }
  }

  /// Shows [text] (and [detail] under it) in the notification, starting the service when it
  /// isn't running.
  Future<void> show(String text, {int? percent, String? detail}) =>
      _call('show', {'text': text, 'percent': percent, 'detail': detail});

  Future<void> stop() => _call('stop');

  /// Asks for the notification permission on Android 13+ (once per run; Android itself shows the
  /// prompt only until it is answered). The playback controls on the lock screen need it too, so
  /// the player calls this as well: this channel is the app's way to the system, not only for
  /// downloads.
  static Future<void> askForNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('askForNotifications');
    } on PlatformException catch (e) {
      debugPrint('Notification permission: ${e.message}');
    }
  }

  /// Keeps the screen from turning off while [on] (driving mode). Android only.
  static Future<void> keepScreenOn(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('keepScreenOn', on);
    } on PlatformException catch (e) {
      debugPrint('Keep screen on: ${e.message}');
    }
  }

  /// Sets the screen's brightness for this app's window, 0 to 1, or the system's again with null
  /// (driving mode's black screen). Android only.
  static Future<void> screenBrightness(double? value) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('screenBrightness', value);
    } on PlatformException catch (e) {
      debugPrint('Screen brightness: ${e.message}');
    }
  }

  /// Whether the network in use is metered (mobile data); false off Android.
  Future<bool> metered() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('metered') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Calls [onNetwork] on network changes while [on]; used only while a download waits.
  Future<void> watchNetwork(bool on) => _call('watchNetwork', on);

  Future<void> _call(String method, [Object? arguments]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (e) {
      // Downloads go on without the notification (Android may refuse a service from the
      // background).
      debugPrint('Download service: ${e.message}');
    }
  }
}
