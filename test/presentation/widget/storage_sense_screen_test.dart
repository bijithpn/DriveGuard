import 'package:driveguard/application/providers.dart';
import 'package:driveguard/application/storage_sense/storage_sense_controller.dart';
import 'package:driveguard/domain/entities/cleanup_item.dart';
import 'package:driveguard/domain/entities/storage_device.dart';
import 'package:driveguard/presentation/storage_sense/storage_sense_screen.dart';
import 'package:driveguard/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _gb = 1024 * 1024 * 1024;

class _SeededSense extends StorageSenseController {
  final List<String> deleted = [];
  @override
  StorageSenseState build() => StorageSenseState(
    status: SenseStatus.ready,
    hasScanned: true,
    items: [
      CleanupItem(
        id: 'a',
        name: 'Xcode DerivedData',
        description: 'Build products and indexes.',
        path: '/x/a',
        safety: CleanupSafety.safe,
        category: CleanupCategory.developer,
        sizeBytes: 14 * _gb,
        lastModified: DateTime.now().subtract(const Duration(days: 90)),
      ),
      const CleanupItem(
        id: 'b',
        name: 'iOS Simulators',
        description: 'Deleting resets them.',
        path: '/x/b',
        safety: CleanupSafety.review,
        category: CleanupCategory.developer,
        sizeBytes: 5 * _gb,
      ),
      const CleanupItem(
        id: 'c',
        name: 'movie.mkv',
        description: 'Personal file in Downloads.',
        path: '/x/c',
        safety: CleanupSafety.manual,
        category: CleanupCategory.downloads,
        sizeBytes: 2 * _gb,
      ),
    ],
  );

  @override
  Future<void> deleteItems(Set<String> ids) async => deleted.addAll(ids);
}

class _NoDevices extends DevicesNotifier {
  @override
  List<StorageDevice> build() => const [];
}

void main() {
  for (final size in const [Size(1000, 900), Size(720, 480)]) {
    testWidgets('renders without overflow at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sense = _SeededSense();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageSenseProvider.overrideWith(() => sense),
            devicesProvider.overrideWith(_NoDevices.new),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const StorageSenseScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Storage Sense'), findsOneWidget);
      expect(find.text('Select safe'), findsOneWidget);
      if (size.height > 600) {
        expect(find.text('Developer tools'), findsOneWidget);
        expect(find.text('14.0 GB'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('delete asks for confirmation before removing', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sense = _SeededSense();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageSenseProvider.overrideWith(() => sense),
          devicesProvider.overrideWith(_NoDevices.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const StorageSenseScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('deleted permanently'), findsOneWidget);
    expect(sense.deleted, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sense.deleted, isEmpty);

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clean'));
    await tester.pumpAndSettle();
    expect(sense.deleted, hasLength(1));
  });
}
