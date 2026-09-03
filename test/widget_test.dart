// Smoke test: the dashboard renders against the mock backend without a
// real monitoring service running, and shows the empty state correctly
// before any device is discovered.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driveguard/application/providers.dart';
import 'package:driveguard/infrastructure/storage/mock_storage_monitor.dart';
import 'package:driveguard/presentation/dashboard/dashboard_screen.dart';

import 'mocks/fake_notification_service.dart';

void main() {
  testWidgets('Dashboard shows the app bar and title', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageMonitorProvider.overrideWithValue(MockStorageMonitor()),
          notificationServiceProvider.overrideWithValue(FakeNotificationService()),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );

    expect(find.text('DriveGuard'), findsOneWidget);
    // No devices are discovered yet because the monitoring service was
    // never started in this test - the empty state must render, not a
    // crash or a blank screen.
    expect(find.textContaining('Scanning for storage devices'), findsOneWidget);
  });
}
