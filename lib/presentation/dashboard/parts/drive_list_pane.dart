part of '../dashboard_screen.dart';

class _DriveListPane extends StatelessWidget {
  const _DriveListPane({
    required this.settings,
    required this.isDark,
    required this.onOpenDevice,
    required this.onToggleCompactView,
  });

  final dynamic settings;
  final bool isDark;
  final ValueChanged<String> onOpenDevice;
  final ValueChanged<bool> onToggleCompactView;

  /// "4 drives · all normal · avg 38°C" — replaces a row of stat tiles.
  String _summary(List<StorageDevice> devices) {
    if (devices.isEmpty) return 'Looking for drives…';
    var warning = 0;
    var critical = 0;
    var tempSum = 0.0;
    var tempCount = 0;
    for (final d in devices) {
      final p = DevicePresentation.of(
        d,
        settings.thresholdsFor(d.id),
        settings.temperatureUnit,
      );
      if (p.severity == TemperatureSeverity.critical) critical++;
      if (p.severity == TemperatureSeverity.warning) warning++;
      if (p.tempCelsius != null) {
        tempSum += p.tempCelsius!;
        tempCount++;
      }
    }
    final parts = <String>[
      '${devices.length} drive${devices.length == 1 ? '' : 's'}',
      if (critical > 0)
        '$critical critical'
      else if (warning > 0)
        '$warning need attention'
      else
        'all normal',
      if (tempCount > 0)
        'avg ${TemperatureUtils.format(tempSum / tempCount, settings.temperatureUnit)}',
    ];
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final compactView = settings.dashboardCompactView as bool;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Consumer(
          builder: (context, ref, _) => _DriveListToolbar(
            summary: _summary(ref.watch(devicesProvider)),
            compactView: compactView,
            isDark: isDark,
            onToggleCompactView: onToggleCompactView,
          ),
        ),
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              final ids = ref.watch(deviceIdsProvider);
              if (ids.isEmpty) return const _EmptyState();
              return _DriveScrollBody(
                ids: ids,
                settings: settings,
                isDark: isDark,
                compactView: compactView,
                onOpenDevice: onOpenDevice,
              );
            },
          ),
        ),
      ],
    );
  }
}
