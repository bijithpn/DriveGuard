import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart'
    show Display, screenRetriever;

import '../../application/providers.dart';
import '../../application/settings/app_settings.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/device_capabilities.dart';
import '../../domain/entities/storage_thresholds.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/enums/ui_enums.dart';
import '../app_root.dart' show edgeDockActiveProvider, widgetModeActiveProvider;
import '../theme/app_theme.dart';
import '../widget/edge_dock_view.dart' show resolveAccent;

part 'parts/basic_sections.dart';
part 'parts/widget_section.dart';
part 'parts/advanced_section.dart';
part 'parts/threshold_editor.dart';

enum _Section {
  general,
  monitoring,
  alerts,
  protection,
  thresholds,
  appearance,
  widget,
  advanced;

  String get label => switch (this) {
    _Section.general => 'General',
    _Section.monitoring => 'Monitoring',
    _Section.alerts => 'Alerts',
    _Section.protection => 'Protection',
    _Section.thresholds => 'Thresholds',
    _Section.appearance => 'Appearance',
    _Section.widget => 'Widget',
    _Section.advanced => 'Advanced',
  };

  IconData get icon => switch (this) {
    _Section.general => Icons.tune_rounded,
    _Section.monitoring => Icons.monitor_heart_outlined,
    _Section.alerts => Icons.notifications_outlined,
    _Section.protection => Icons.shield_outlined,
    _Section.thresholds => Icons.device_thermostat_rounded,
    _Section.appearance => Icons.palette_outlined,
    _Section.widget => Icons.widgets_outlined,
    _Section.advanced => Icons.build_outlined,
  };
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _Section _selectedSection = _Section.general;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      body: Row(
        children: [
          _SettingsSidebar(
            selected: _selectedSection,
            isDark: isDark,
            onSelect: (s) => setState(() => _selectedSection = s),
          ),

          Expanded(
            child: _ContentPanel(section: _selectedSection, isDark: isDark),
          ),
        ],
      ),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.selected,
    required this.isDark,
    required this.onSelect,
  });

  final _Section selected;
  final bool isDark;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.border : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sidebarPad,
                AppSpacing.md,
                AppSpacing.sidebarPad,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  _SidebarBackButton(isDark: isDark),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? AppColors.divider : AppColors.lightBorder,
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                children: _Section.values.map((s) {
                  return _SidebarNavItem(
                    section: s,
                    isSelected: s == selected,
                    isDark: isDark,
                    onTap: () => onSelect(s),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBackButton extends StatelessWidget {
  const _SidebarBackButton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.lightBorder,
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 14,
            color: isDark
                ? AppColors.textSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.section,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final _Section section;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isDark = widget.isDark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sidebarPad,
            vertical: 9,
          ),
          decoration: isSelected
              ? AppDecorations.sidebarItem(selected: true, isDark: isDark)
              : BoxDecoration(
                  color: _hovered
                      ? (isDark
                            ? AppColors.bg2.withValues(alpha: 0.6)
                            : AppColors.lightSurfaceMuted.withValues(
                                alpha: 0.7,
                              ))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
          child: Row(
            children: [
              Icon(
                widget.section.icon,
                size: 15,
                color: isSelected
                    ? AppColors.accent
                    : (isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.section.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? (isDark ? AppColors.textPrimary : AppColors.lightText)
                      : (isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentPanel extends ConsumerWidget {
  const _ContentPanel({required this.section, required this.isDark});

  final _Section section;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: isDark ? AppColors.bg0 : AppColors.lightBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? AppColors.divider : AppColors.lightBorder,
                    width: 1,
                  ),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                section.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textPrimary : AppColors.lightText,
                ),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _buildSection(context, ref, section),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, WidgetRef ref, _Section section) {
    return switch (section) {
      _Section.general => _GeneralSection(isDark: isDark),
      _Section.monitoring => _MonitoringSection(isDark: isDark),
      _Section.alerts => _AlertsSection(isDark: isDark),
      _Section.protection => _ProtectionSection(isDark: isDark),
      _Section.thresholds => _ThresholdsSection(isDark: isDark),
      _Section.appearance => _AppearanceSection(isDark: isDark),
      _Section.widget => _WidgetSection(isDark: isDark),
      _Section.advanced => _AdvancedSection(isDark: isDark),
    };
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.isDark,
    this.subtitle,
    this.trailing,
    this.isLast = false,
    this.onTap,
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final bool isDark;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.divider : AppColors.lightBorder,
                  width: 1,
                ),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
          if (onTap != null && trailing == null)
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: isDark
                  ? AppColors.textMuted
                  : AppColors.lightTextSecondary,
            ),
        ],
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      );
    }

    return content;
  }
}

class _SectionGroup extends StatelessWidget {
  const _SectionGroup({required this.children, required this.isDark});

  final List<Widget> children;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? AppColors.shadowDark : AppColors.lightShadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(children.length, (i) {
          return children[i];
        }),
      ),
    );
  }
}
