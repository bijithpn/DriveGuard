import 'dart:async';
import 'dart:io';

import 'package:driveguard/application/storage_sense/cleanup_scanner.dart';
import 'package:driveguard/application/storage_sense/project_scanner.dart';
import 'package:driveguard/application/storage_sense/size_measurer.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMeasurer implements SizeMeasurer {
  @override
  int get concurrency => 1;

  @override
  Future<SizeResult> measure(
    String path, {
    Duration budget = const Duration(seconds: 5),
  }) async => const SizeResult(10 * 1024 * 1024, 0, null, false);
}

void main() {
  test('scan works when callbacks capture unsendable objects', () async {
    final dir = Directory.systemTemp.createTempSync('scan_isolate');
    addTearDown(() => dir.deleteSync(recursive: true));
    // A project with a node_modules artifact.
    File('${dir.path}/proj/package.json').createSync(recursive: true);
    File('${dir.path}/proj/node_modules/x/a.bin')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(1024, 1));

    // A StreamController / Zone-bound closure cannot be sent to an isolate.
    final controller = StreamController<int>();
    // close() only completes once a listener has drained the stream.
    controller.stream.listen((_) {});
    addTearDown(controller.close);
    final scanner = ProjectScanner(minBytes: 0, measurer: _FakeMeasurer());
    await scanner.scan(
      [dir.path],
      onProgress: (d, t, c) => controller.add(d),
      onItems: (_) => controller.add(-1),
      isCancelled: () => controller.isClosed,
    );
  });
}
