import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/shutdown_incident.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';
import '../theme/app_theme.dart';

part 'parts/report_body.dart';
part 'parts/header_card.dart';
part 'parts/bsod_banner.dart';
part 'parts/timeline_chart.dart';
part 'parts/event_rows.dart';

class IncidentReportScreen extends ConsumerWidget {
  const IncidentReportScreen({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(incidentDetailProvider(incidentId));

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      appBar: AppBar(
        title: const Text('Incident Report'),
        backgroundColor: isDark ? AppColors.bg1 : AppColors.lightCard,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load incident: $e')),
        data: (incident) {
          if (incident == null) {
            return const Center(child: Text('Incident not found'));
          }
          return _ReportBody(incident: incident, isDark: isDark);
        },
      ),
    );
  }
}
