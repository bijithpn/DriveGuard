import 'dart:io';

import 'package:driveguard/application/protection/privileged_runner.dart';
import 'package:driveguard/application/storage_sense/cleanup_catalog.dart';
import 'package:driveguard/application/storage_sense/cleanup_scanner.dart';
import 'package:driveguard/application/storage_sense/cleanup_service.dart';
import 'package:driveguard/application/storage_sense/size_measurer.dart';
import 'package:driveguard/domain/entities/cleanup_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late Directory cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sense_test');
    cache = Directory('${tmp.path}/cache')..createSync();
    File('${cache.path}/a.bin').writeAsBytesSync(List.filled(2048, 1));
    Directory('${cache.path}/sub').createSync();
    File('${cache.path}/sub/b.bin').writeAsBytesSync(List.filled(1024, 1));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  CleanupTarget target(String path) => CleanupTarget(
    id: 't',
    name: 'Test cache',
    description: 'd',
    path: path,
    safety: CleanupSafety.safe,
    category: CleanupCategory.systemCaches,
  );

  test('scanner measures sizes', () async {
    final items = await CleanupScanner(
      measurer: IsolateMeasurer(),
    ).scan([target(cache.path)]);
    expect(items, hasLength(1));
    expect(items.single.sizeBytes, 3072);
  });

  test('safe delete empties the folder but keeps it', () async {
    final t = target(cache.path);
    final svc = CleanupService(targets: [t]);
    final item = (await CleanupScanner(
      measurer: IsolateMeasurer(),
    ).scan([t])).single;
    final r = await svc.delete([item]);
    expect(r.freedBytes, 3072);
    expect(r.failures, isEmpty);
    expect(cache.existsSync(), isTrue);
    expect(cache.listSync(), isEmpty);
  });

  test('refuses paths outside the catalog roots', () async {
    final outside = Directory('${tmp.path}/precious')..createSync();
    File('${outside.path}/keep.txt').writeAsStringSync('keep');
    final svc = CleanupService(targets: [target(cache.path)]);
    final r = await svc.delete([
      CleanupItem(
        id: 'x',
        name: 'x',
        description: '',
        path: outside.path,
        safety: CleanupSafety.safe,
        category: CleanupCategory.logs,
        sizeBytes: 4,
      ),
    ]);
    expect(r.failures.keys, contains('x'));
    expect(File('${outside.path}/keep.txt').existsSync(), isTrue);
  });

  test('refuses a symlink that points outside the root', () async {
    final outside = Directory('${tmp.path}/elsewhere')..createSync();
    File('${outside.path}/keep.txt').writeAsStringSync('keep');
    Link('${cache.path}/escape').createSync(outside.path);
    final svc = CleanupService(targets: [target(cache.path)]);
    expect(svc.isAllowed('${cache.path}/escape'), isFalse);
    // Emptying the cache must unlink the symlink, never follow it.
    await svc.delete([
      CleanupItem(
        id: 'c',
        name: 'c',
        description: '',
        path: cache.path,
        safety: CleanupSafety.safe,
        category: CleanupCategory.logs,
      ),
    ]);
    expect(File('${outside.path}/keep.txt').existsSync(), isTrue);
  });

  test('refuses the home directory itself', () {
    final svc = CleanupService(targets: [target(cache.path)]);
    expect(svc.isAllowed(CleanupCatalog.home), isFalse);
    expect(svc.isAllowed('/'), isFalse);
  });

  test('review items go to Trash, never deleted if trash fails', () async {
    final t = target(cache.path);
    final item = (await CleanupScanner(
      measurer: IsolateMeasurer(),
    ).scan([t])).single;
    final review = CleanupItem(
      id: item.id,
      name: item.name,
      description: '',
      path: item.path,
      safety: CleanupSafety.review,
      category: item.category,
      sizeBytes: item.sizeBytes,
    );
    final failing = CleanupService(targets: [t], trash: (_) async => false);
    final r1 = await failing.delete([review]);
    expect(r1.failures, isNotEmpty);
    expect(cache.listSync(), isNotEmpty);

    final trashed = <String>[];
    final ok = CleanupService(
      targets: [t],
      trash: (p) async {
        trashed.add(p);
        return true;
      },
    );
    final r2 = await ok.delete([review]);
    expect(r2.trashedBytes, 3072);
    expect(trashed, [cache.path]);
  });

  test('catalog only lists locations under the home/temp dirs', () {
    final targets = CleanupCatalog.forPlatform(
      homeDir: '/Users/x',
      os: 'macos',
      env: const {},
    );
    expect(targets, isNotEmpty);
    for (final t in targets.where((t) => !t.requiresAdmin)) {
      expect(t.path.startsWith('/Users/x/'), isTrue, reason: t.path);
    }
    // System-owned locations are flagged so the UI asks for consent.
    expect(targets.where((t) => t.requiresAdmin), isNotEmpty);
    for (final t in targets.where((t) => t.requiresAdmin)) {
      expect(t.safety, CleanupSafety.safe);
    }
    // Personal data is never "safe".
    expect(
      targets.firstWhere((t) => t.id == 'downloads').safety,
      CleanupSafety.manual,
    );
  });

  scannerTests();

  group('administrator cleanup', () {
    CleanupItem adminItem() => CleanupItem(
      id: 'sys',
      name: 'System cache',
      description: '',
      path: cache.path,
      safety: CleanupSafety.safe,
      category: CleanupCategory.systemCaches,
      sizeBytes: 3072,
      requiresAdmin: true,
    );

    test('is never attempted without the user consenting', () async {
      final priv = _FakePriv();
      final svc = CleanupService(
        targets: [target(cache.path)],
        privileged: priv,
      );
      final r = await svc.delete([adminItem()]);
      expect(priv.calls, isEmpty);
      expect(r.failures['sys'], contains('administrator'));
      expect(cache.listSync(), isNotEmpty);
    });

    test(
      'uses ONE prompt for all admin items and verifies the result',
      () async {
        final other = Directory('${tmp.path}/other')..createSync();
        File('${other.path}/x').writeAsBytesSync([1]);
        final priv = _FakePriv(
          onRun: (script) {
            // Pretend the privileged shell emptied both folders.
            for (final d in [cache, other]) {
              for (final e in d.listSync()) {
                e.deleteSync(recursive: true);
              }
            }
          },
        );
        final svc = CleanupService(
          targets: [target(cache.path), target(other.path)],
          privileged: priv,
        );
        final second = CleanupItem(
          id: 'sys2',
          name: 's2',
          description: '',
          path: other.path,
          safety: CleanupSafety.safe,
          category: CleanupCategory.logs,
          sizeBytes: 1,
          requiresAdmin: true,
        );
        final r = await svc.delete([adminItem(), second], allowAdmin: true);
        expect(priv.calls, hasLength(1));
        expect(priv.calls.single, contains(cache.path));
        expect(priv.calls.single, contains(other.path));
        expect(priv.calls.single, contains('-mindepth 1'));
        expect(r.failures, isEmpty);
        expect(r.freedBytes, 3073);
      },
    );

    test('reports a declined prompt honestly and deletes nothing', () async {
      final priv = _FakePriv(result: false);
      final svc = CleanupService(
        targets: [target(cache.path)],
        privileged: priv,
      );
      final r = await svc.delete([adminItem()], allowAdmin: true);
      expect(r.failures['sys'], contains('not granted'));
      expect(r.freedBytes, 0);
      expect(cache.listSync(), isNotEmpty);
    });

    test('never elevates for a path outside the catalog roots', () async {
      final priv = _FakePriv();
      final outside = Directory('${tmp.path}/outside')..createSync();
      final svc = CleanupService(
        targets: [target(cache.path)],
        privileged: priv,
      );
      final r = await svc.delete([
        CleanupItem(
          id: 'bad',
          name: 'bad',
          description: '',
          path: outside.path,
          safety: CleanupSafety.safe,
          category: CleanupCategory.logs,
          requiresAdmin: true,
        ),
      ], allowAdmin: true);
      expect(priv.calls, isEmpty);
      expect(r.failures.keys, contains('bad'));
    });
  });
}

class _FakePriv implements PrivilegedRunner {
  _FakePriv({this.result = true, this.onRun});
  final bool result;
  final void Function(String script)? onRun;
  final calls = <String>[];

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<bool> run(
    String executable,
    List<String> args, {
    required String reason,
  }) async {
    final script = args.join(' ');
    calls.add(script);
    if (result) onRun?.call(script);
    return result;
  }
}

void scannerTests() {
  group('CleanupScanner progress, splitting and cancel', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('scan_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    CleanupTarget t(String path, {bool expand = false}) => CleanupTarget(
      id: 't${path.hashCode}',
      name: 'T',
      description: 'd',
      path: path,
      safety: CleanupSafety.safe,
      category: CleanupCategory.systemCaches,
      expandChildren: expand,
    );

    Directory tree() {
      final d = Directory('${tmp.path}/big')..createSync();
      for (var i = 0; i < 6; i++) {
        final sub = Directory('${d.path}/sub$i')..createSync();
        File('${sub.path}/f').writeAsBytesSync(List.filled(1000 * (i + 1), 1));
        Directory('${sub.path}/deep').createSync();
        File('${sub.path}/deep/g').writeAsBytesSync(List.filled(500, 1));
      }
      File('${d.path}/loose').writeAsBytesSync(List.filled(777, 1));
      return d;
    }

    test('a split target totals exactly what an unsplit scan gives', () async {
      final d = tree();
      final whole = await CleanupScanner(
        measurer: IsolateMeasurer(),
        splitDepth: 0,
      ).scan([t(d.path)]);
      final split = await CleanupScanner(
        measurer: IsolateMeasurer(),
        splitDepth: 2,
      ).scan([t(d.path)]);
      expect(split.single.sizeBytes, whole.single.sizeBytes);
      expect(split.single.sizeBytes, 1000 * 21 + 500 * 6 + 777);
    });

    test(
      'progress is monotonic, ends complete, and items stream out',
      () async {
        final d = tree();
        final seen = <ScanProgress>[];
        final streamed = <CleanupItem>[];
        await CleanupScanner(measurer: IsolateMeasurer()).scan(
          [t(d.path), t(d.path, expand: true)],
          onProgress: seen.add,
          onItems: streamed.addAll,
        );
        expect(seen, isNotEmpty);
        var last = 0;
        for (final p in seen) {
          expect(p.done, greaterThanOrEqualTo(last));
          last = p.done;
        }
        expect(seen.last.done, seen.last.total);
        expect(streamed, isNotEmpty);
        expect(
          seen.last.foundBytes,
          streamed.fold<int>(0, (s, i) => s + i.sizeBytes),
        );
      },
    );

    test('cancel stops measuring', () async {
      final d = tree();
      var calls = 0;
      final items = await CleanupScanner(
        measurer: IsolateMeasurer(concurrency: 1),
      ).scan([t(d.path, expand: true)], isCancelled: () => ++calls > 2);
      expect(items.length, lessThan(6));
    });

    test(
      'native du agrees with the Dart walk to within block rounding',
      () async {
        if (Platform.isWindows || !await DuMeasurer.available()) return;
        final d = tree();
        final du = await DuMeasurer().measure(d.path);
        final dart = await IsolateMeasurer().measure(d.path);
        // du reports allocated blocks, so it is >= the apparent size.
        expect(du.bytes, greaterThanOrEqualTo(dart.bytes));
        expect(du.bytes, lessThan(dart.bytes + 64 * 1024));
      },
    );
  });
}
