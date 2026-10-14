import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points the app's storage at a fresh temporary folder, so a test never touches the real
/// app data. Returns the folder; delete it when done.
Directory useTempAppStorage() {
  final root = Directory.systemTemp.createTempSync('shu-test-');
  PathProviderPlatform.instance = _TempPaths(root.path);
  return root;
}

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}
