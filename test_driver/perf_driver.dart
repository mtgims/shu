import 'package:integration_test/integration_test_driver.dart';

/// Saves the frame timings integration_test/perf_test.dart reports to build/perf.json.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) =>
      writeResponseData(data, testOutputFilename: 'perf'),
);
