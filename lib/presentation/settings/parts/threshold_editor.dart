part of '../settings_screen.dart';

const double _minThresholdSeparationCelsius = 1.0;

void _submitThreshold(
  BuildContext context,
  SettingsNotifier notifier, {
  required TemperatureThresholds current,
  required String rawValue,
  required bool isWarningField,
  required AppSettings Function(
    AppSettings settings,
    TemperatureThresholds updated,
  )
  apply,
}) {
  final value = double.tryParse(rawValue.trim());
  if (value == null) {
    _showThresholdError(context, 'Enter a numeric temperature.');
    return;
  }
  if (value <= 0 || !value.isFinite) {
    _showThresholdError(context, 'Threshold must be a positive temperature.');
    return;
  }

  final updated = isWarningField
      ? current.copyWith(warningCelsius: value)
      : current.copyWith(criticalCelsius: value);

  if (updated.criticalCelsius - updated.warningCelsius <
      _minThresholdSeparationCelsius) {
    _showThresholdError(
      context,
      'Critical threshold must be higher than warning threshold.',
    );
    return;
  }

  notifier.updateWith((s) => apply(s, updated));
}

const double _minStorageThresholdSeparationPercent = 1.0;

void _submitStorageThreshold(
  BuildContext context,
  SettingsNotifier notifier, {
  required StorageThresholds current,
  required String rawValue,
  required bool isWarningField,
}) {
  final value = double.tryParse(rawValue.trim());
  if (value == null) {
    _showThresholdError(context, 'Enter a numeric percentage.');
    return;
  }
  if (value <= 0 || value > 100 || !value.isFinite) {
    _showThresholdError(context, 'Threshold must be between 1 and 100.');
    return;
  }

  final updated = isWarningField
      ? current.copyWith(warningPercent: value)
      : current.copyWith(criticalPercent: value);

  if (updated.criticalPercent - updated.warningPercent <
      _minStorageThresholdSeparationPercent) {
    _showThresholdError(
      context,
      'Critical threshold must be higher than warning threshold.',
    );
    return;
  }

  notifier.updateWith((s) => s.copyWith(storageThresholds: updated));
}

void _submitRapidRiseDelta(
  BuildContext context,
  SettingsNotifier notifier,
  String rawValue,
) {
  final value = double.tryParse(rawValue.trim());
  if (value == null) {
    _showThresholdError(context, 'Enter a numeric temperature delta.');
    return;
  }
  if (value <= 0 || !value.isFinite) {
    _showThresholdError(context, 'Delta must be a positive temperature.');
    return;
  }
  notifier.updateWith((s) => s.copyWith(rapidRiseDeltaCelsius: value));
}

void _showThresholdError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.critical,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
}

typedef _DeviceOverrideResult = ({
  TemperatureThresholds temperature,
  StorageThresholds storage,
  double rapidRiseDelta,
});

Future<void> _editDeviceThresholds(
  BuildContext context,
  SettingsNotifier notifier, {
  required String deviceId,
  required AppSettings settings,
}) async {
  final result = await showDialog<_DeviceOverrideResult>(
    context: context,
    builder: (dialogContext) => _ThresholdEditorDialog(
      temperature: settings.thresholdsFor(deviceId),
      storage: settings.storageThresholdsFor(deviceId),
      rapidRiseDelta: settings.rapidRiseDeltaFor(deviceId),
    ),
  );

  if (result != null) {
    final temp = Map.of(settings.perDeviceThresholds)
      ..[deviceId] = result.temperature;
    final storage = Map.of(settings.perDeviceStorageThresholds)
      ..[deviceId] = result.storage;
    final rapidRise = Map.of(settings.perDeviceRapidRiseDelta)
      ..[deviceId] = result.rapidRiseDelta;
    await notifier.updateWith(
      (s) => s.copyWith(
        perDeviceThresholds: temp,
        perDeviceStorageThresholds: storage,
        perDeviceRapidRiseDelta: rapidRise,
      ),
    );
  }
}

class _ThresholdEditorDialog extends StatefulWidget {
  const _ThresholdEditorDialog({
    required this.temperature,
    required this.storage,
    required this.rapidRiseDelta,
  });

  final TemperatureThresholds temperature;
  final StorageThresholds storage;
  final double rapidRiseDelta;

  @override
  State<_ThresholdEditorDialog> createState() => _ThresholdEditorDialogState();
}

class _ThresholdEditorDialogState extends State<_ThresholdEditorDialog> {
  late final _warningController = TextEditingController(
    text: widget.temperature.warningCelsius.toStringAsFixed(0),
  );
  late final _criticalController = TextEditingController(
    text: widget.temperature.criticalCelsius.toStringAsFixed(0),
  );
  late final _storageWarningController = TextEditingController(
    text: widget.storage.warningPercent.toStringAsFixed(0),
  );
  late final _storageCriticalController = TextEditingController(
    text: widget.storage.criticalPercent.toStringAsFixed(0),
  );
  late final _rapidRiseController = TextEditingController(
    text: widget.rapidRiseDelta.toStringAsFixed(0),
  );

  @override
  void dispose() {
    _warningController.dispose();
    _criticalController.dispose();
    _storageWarningController.dispose();
    _storageCriticalController.dispose();
    _rapidRiseController.dispose();
    super.dispose();
  }

  void _save() {
    final warning = double.tryParse(_warningController.text.trim());
    final critical = double.tryParse(_criticalController.text.trim());
    if (warning == null || critical == null || warning <= 0 || critical <= 0) {
      _showThresholdError(context, 'Enter positive numeric temperatures.');
      return;
    }
    if (critical - warning < _minThresholdSeparationCelsius) {
      _showThresholdError(
        context,
        'Critical threshold must be higher than warning threshold.',
      );
      return;
    }

    final storageWarning = double.tryParse(
      _storageWarningController.text.trim(),
    );
    final storageCritical = double.tryParse(
      _storageCriticalController.text.trim(),
    );
    if (storageWarning == null ||
        storageCritical == null ||
        storageWarning <= 0 ||
        storageWarning > 100 ||
        storageCritical <= 0 ||
        storageCritical > 100) {
      _showThresholdError(context, 'Enter disk percentages between 1 and 100.');
      return;
    }
    if (storageCritical - storageWarning <
        _minStorageThresholdSeparationPercent) {
      _showThresholdError(
        context,
        'Disk critical threshold must be higher than warning threshold.',
      );
      return;
    }

    final rapidRise = double.tryParse(_rapidRiseController.text.trim());
    if (rapidRise == null || rapidRise <= 0) {
      _showThresholdError(context, 'Enter a positive rapid-rise delta.');
      return;
    }

    Navigator.of(context).pop((
      temperature: widget.temperature.copyWith(
        warningCelsius: warning,
        criticalCelsius: critical,
      ),
      storage: widget.storage.copyWith(
        warningPercent: storageWarning,
        criticalPercent: storageCritical,
      ),
      rapidRiseDelta: rapidRise,
    ));
  }

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
        'Device Thresholds',
        style: TextStyle(
          color: isDark ? AppColors.textPrimary : AppColors.lightText,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(title: 'Temperature', isDark: isDark),
            const SizedBox(height: AppSpacing.xs),
            _ThresholdEditorField(
              controller: _warningController,
              label: 'Warning',
              color: AppColors.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ThresholdEditorField(
              controller: _criticalController,
              label: 'Critical',
              color: AppColors.critical,
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionLabel(title: 'Disk usage', isDark: isDark),
            const SizedBox(height: AppSpacing.xs),
            _ThresholdEditorField(
              controller: _storageWarningController,
              label: 'Warning',
              color: AppColors.warning,
              suffixText: '%',
            ),
            const SizedBox(height: AppSpacing.sm),
            _ThresholdEditorField(
              controller: _storageCriticalController,
              label: 'Critical',
              color: AppColors.critical,
              suffixText: '%',
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionLabel(title: 'Rapid rise', isDark: isDark),
            const SizedBox(height: AppSpacing.xs),
            _ThresholdEditorField(
              controller: _rapidRiseController,
              label: 'Delta',
              color: AppColors.warning,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
      ),
    );
  }
}

class _ThresholdEditorField extends StatelessWidget {
  const _ThresholdEditorField({
    required this.controller,
    required this.label,
    required this.color,
    this.suffixText = 'C',
  });

  final TextEditingController controller;
  final String label;
  final Color color;
  final String suffixText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color),
        suffixText: suffixText,
        suffixStyle: TextStyle(color: color),
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
    );
  }
}
