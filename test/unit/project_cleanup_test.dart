import 'dart:io';

import 'package:driveguard/application/monitoring/metric_history_store.dart';
import 'package:driveguard/application/storage_sense/cleanup_service.dart';
import 'package:driveguard/application/storage_sense/project_scanner.dart';
import 'package:driveguard/application/storage_sense/size_measurer.dart';
import 'package:driveguard/domain/entities/cleanup_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('proj_test'));
  tearDown(() => root.deleteSync(recursive: true));

  Directory mk(String rel, {int bytes = 0}) {
    final d = Directory('${root.path}/$rel')..createSync(recursive: true);
    if (bytes > 0) {
      File('${d.path}/blob').writeAsBytesSync(List.filled(bytes, 1));
    }
    return d;
  }

  test('only recognises build folders that sit next to a project marker', () {
    mk('app/node_modules');
    File('${root.path}/app/package.json').writeAsStringSync('{}');
    mk('random/node_modules'); // no package.json
    mk('docs/build'); // no marker
    expect(isProjectArtifact('${root.path}/app/node_modules'), isTrue);
    expect(isProjectArtifact('${root.path}/random/node_modules'), isFalse);
    expect(isProjectArtifact('${root.path}/docs/build'), isFalse);
  });

  test(
    'scanner finds artifacts, groups by project, skips small ones',
    () async {
      mk('Projects/web/node_modules', bytes: 6 * 1024 * 1024);
      File('${root.path}/Projects/web/package.json').writeAsStringSync('{}');
      mk('Projects/app/build', bytes: 7 * 1024 * 1024);
      File(
        '${root.path}/Projects/app/pubspec.yaml',
      ).writeAsStringSync('name: a');
      mk('Projects/tiny/node_modules', bytes: 10);
      File('${root.path}/Projects/tiny/package.json').writeAsStringSync('{}');

      final items = await ProjectScanner(
        measurer: IsolateMeasurer(),
      ).scan(['${root.path}/Projects']);
      final byProject = {for (final i in items) i.project: i};
      expect(byProject.keys.toSet(), {'web', 'app'});
      expect(byProject['web']!.safety, CleanupSafety.safe);
      expect(byProject['app']!.safety, CleanupSafety.review); // build/
      expect(byProject['web']!.deleteContentsOnly, isFalse);
    },
  );

  test(
    'service deletes a project artifact but not an unmarked folder',
    () async {
      final nm = mk('code/web/node_modules', bytes: 100);
      File('${root.path}/code/web/package.json').writeAsStringSync('{}');
      final bad = mk('code/misc/node_modules', bytes: 100);
      final svc = CleanupService(targets: const [], projectRoots: [root.path]);

      CleanupItem item(String p) => CleanupItem(
        id: p,
        name: 'n',
        description: '',
        path: p,
        safety: CleanupSafety.safe,
        category: CleanupCategory.projects,
        sizeBytes: 100,
        deleteContentsOnly: false,
      );
      final r = await svc.delete([item(nm.path), item(bad.path)]);
      expect(nm.existsSync(), isFalse);
      expect(bad.existsSync(), isTrue);
      expect(r.failures.keys, contains(bad.path));
    },
  );

  test('capacity history restores older points without duplicating', () {
    final store = MetricHistoryStore(
      retention: const Duration(days: 14),
      minSampleInterval: Duration.zero,
    );
    final now = DateTime.now();
    store.record('d', 50, at: now);
    store.restore('d', [
      MetricPoint(now.subtract(const Duration(days: 2)), 40),
      MetricPoint(now.subtract(const Duration(days: 1)), 45),
      MetricPoint(now.add(const Duration(minutes: 1)), 99), // newer: ignored
      MetricPoint(now.subtract(const Duration(days: 30)), 1), // expired
    ]);
    final v = store.pointsFor('d').map((p) => p.value).toList();
    expect(v, [40, 45, 50]);
  });
}
