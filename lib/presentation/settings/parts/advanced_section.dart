part of '../settings_screen.dart';

class _AdvancedSection extends ConsumerWidget {
  const _AdvancedSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final devices = ref.watch(devicesProvider);

    return _SectionGroup(
      isDark: isDark,
      children: [
        _SettingRow(
          label: 'Diagnostic logging',
          isDark: isDark,
          trailing: Switch(
            value: settings.diagnosticLoggingEnabled,
            onChanged: (v) => notifier.updateWith(
              (s) => s.copyWith(diagnosticLoggingEnabled: v),
            ),
          ),
        ),
        _SettingRow(
          label: 'Simulated devices',
          subtitle: 'Developer mode — use mock data instead of real drives',
          isDark: isDark,
          trailing: Switch(
            value: settings.mockBackendForced,
            onChanged: (v) =>
                notifier.updateWith((s) => s.copyWith(mockBackendForced: v)),
          ),
        ),
        _SettingRow(
          label: 'Rescan drives',
          isDark: isDark,
          onTap: () => ref.read(monitoringServiceProvider).rescan(),
        ),
        FutureBuilder(
          future: ref.read(storageMonitorProvider).getCapabilities(),
          builder: (context, snapshot) {
            final caps = snapshot.data;
            final backendText = caps != null
                ? 'Backend: ${caps.backendName}'
                : 'Backend: detecting…';
            final subtitleText = caps == null
                ? null
                : caps.missingTools.isEmpty
                ? 'All required tools available'
                : 'Missing: ${caps.missingTools.join(', ')}';
            return _SettingRow(
              label: backendText,
              subtitle: subtitleText,
              isDark: isDark,
              trailing: caps != null
                  ? Icon(
                      caps.missingTools.isEmpty
                          ? Icons.check_circle_outline_rounded
                          : Icons.warning_amber_rounded,
                      color: caps.missingTools.isEmpty
                          ? AppColors.normal
                          : AppColors.warning,
                      size: 18,
                    )
                  : null,
            );
          },
        ),
        _SettingRow(
          label: 'Export diagnostic report',
          subtitle: 'Copies OS, backend and device info to the clipboard',
          isDark: isDark,
          isLast: true,
          onTap: () async {
            final caps = await ref
                .read(storageMonitorProvider)
                .getCapabilities();
            final report = StringBuffer()
              ..writeln('DriveGuard diagnostic report')
              ..writeln('Backend: ${caps.backendName}')
              ..writeln('Can enumerate devices: ${caps.canEnumerateDevices}')
              ..writeln('Can read temperature: ${caps.canReadTemperature}')
              ..writeln('Can read health: ${caps.canReadHealth}')
              ..writeln(
                'Missing tools: ${caps.missingTools.isEmpty ? 'None' : caps.missingTools.join(', ')}',
              );
            if (caps.notes.isNotEmpty) {
              report.writeln('Notes:');
              for (final note in caps.notes) {
                report.writeln('  - $note');
              }
            }
            report.writeln('Devices:');
            for (final d in devices) {
              final capabilities = DeviceCapabilities.derive(d);
              report.writeln(
                '  - ${d.type.name}/${d.interfaceType.name} status=${d.monitoringStatus.name} sensor=${d.sensorAvailability.name}',
              );
              report.writeln(
                '      capabilities: ${capabilities.entries.map((e) => '${e.$1}=${e.$2 ? 'yes' : 'no'}').join(', ')}',
              );
            }
            report.writeln('--- Log ---');
            report.writeln(AppLogger.instance.exportAsText());
            if (context.mounted) {
              await showDialog<void>(
                context: context,
                builder: (ctx) => _DiagnosticDialog(report: report.toString()),
              );
            }
          },
        ),
      ],
    );
  }
}

class _ThresholdField extends StatelessWidget {
  const _ThresholdField({
    super.key,
    required this.value,
    required this.color,
    required this.onSubmit,
    this.suffixText = 'C',
  });

  final double value;
  final Color color;
  final ValueChanged<String> onSubmit;
  final String suffixText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: TextFormField(
        initialValue: value.toStringAsFixed(0),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        decoration: InputDecoration(
          suffixText: suffixText,
          suffixStyle: TextStyle(color: color, fontWeight: FontWeight.w500),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          filled: true,
          fillColor: color.withValues(alpha: 0.07),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: color, width: 1.5),
          ),
        ),
        onFieldSubmitted: onSubmit,
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    required this.isDark,
    this.useAccent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool useAccent;

  @override
  Widget build(BuildContext context) {
    final color = useAccent
        ? AppColors.accent
        : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _NativeDropdown<T> extends StatelessWidget {
  const _NativeDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDark,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        underline: const SizedBox.shrink(),
        isDense: true,
        dropdownColor: isDark ? AppColors.bg2 : AppColors.lightCard,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? AppColors.textPrimary : AppColors.lightText,
        ),
        icon: Icon(
          Icons.expand_more_rounded,
          size: 15,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}

class _SegmentedControl<T> extends StatelessWidget {
  const _SegmentedControl({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final (value, label) = opt;
          final isSelected = value == selected;
          return GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? AppColors.bg3 : AppColors.lightCard)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm - 1),
                border: isSelected
                    ? Border.all(
                        color: isDark
                            ? AppColors.border
                            : AppColors.lightBorder,
                      )
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? (isDark ? AppColors.textPrimary : AppColors.lightText)
                      : (isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DiagnosticDialog extends StatelessWidget {
  const _DiagnosticDialog({required this.report});
  final String report;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? AppColors.bg1 : AppColors.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      title: Text(
        'Diagnostic Report',
        style: TextStyle(
          color: isDark ? AppColors.textPrimary : AppColors.lightText,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
      content: SizedBox(
        width: 480,
        height: 380,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bg0 : AppColors.lightBg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.lightBorder,
            ),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              report,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: isDark
                    ? AppColors.textSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: isDark
                ? AppColors.textSecondary
                : AppColors.lightTextSecondary,
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
