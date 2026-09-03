import 'package:flutter/material.dart';

import '../../domain/enums/storage_enums.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design Tokens
// ─────────────────────────────────────────────────────────────────────────────

class AppSpacing {
  const AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppRadius {
  const AppRadius._();
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const Radius mdRadius = Radius.circular(md);
  static const Radius lgRadius = Radius.circular(lg);
}

class AppDurations {
  const AppDurations._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 600);
  static const Duration verySlow = Duration(milliseconds: 900);
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand Palette
// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  const AppColors._();

  // Dark background layers
  static const Color bg0 = Color(0xFF0D0B1A); // deepest
  static const Color bg1 = Color(0xFF13112B); // card bg
  static const Color bg2 = Color(0xFF1A1740); // elevated card
  static const Color bg3 = Color(0xFF201E4D); // hover/selected

  // Purple brand
  static const Color purpleDeep = Color(0xFF3D2D9E);
  static const Color purpleMid = Color(0xFF5B3FCE);
  static const Color purpleLight = Color(0xFF7E5FF0);
  static const Color purpleAccent = Color(0xFFA57BFF);

  // Cyan accent
  static const Color cyan = Color(0xFF3EEAFF);
  static const Color cyanDim = Color(0xFF1DBBD0);

  // State colors — temperature severity
  static const Color normal = Color(0xFF3DD68C);
  static const Color normalDim = Color(0xFF2BAE70);
  static const Color warm = Color(0xFF8AE04B);
  static const Color warning = Color(0xFFFFBC42);
  static const Color warningDim = Color(0xFFCF8B0A);
  static const Color critical = Color(0xFFFF4D4D);
  static const Color criticalDim = Color(0xFFD1453B);

  // Neutral
  static const Color textPrimary = Color(0xFFE8E3FF);
  static const Color textSecondary = Color(0xFF9990CC);
  static const Color textMuted = Color(0xFF5E587A);
  static const Color divider = Color(0xFF2A2550);
  static const Color border = Color(0xFF2E2A5A);

  // Glass overlay
  static const Color glassSurface = Color(0x1AFFFFFF);
  static const Color glassHighlight = Color(0x0DFFFFFF);

  // Gradient
  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purpleMid, purpleDeep],
  );

  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF14103A), Color(0xFF0A0817)],
  );

  // Light theme
  static const Color lightBg = Color(0xFFF5F3FF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE0DAFF);
  static const Color lightText = Color(0xFF1A1240);
  static const Color lightTextSecondary = Color(0xFF6B5EA8);
}

// ─────────────────────────────────────────────────────────────────────────────
// Severity Styling
// ─────────────────────────────────────────────────────────────────────────────

class SeverityStyle {
  const SeverityStyle({
    required this.color,
    required this.dimColor,
    required this.label,
    required this.icon,
    required this.glowColor,
  });

  final Color color;
  final Color dimColor;
  final String label;
  final IconData icon;
  final Color glowColor;

  static SeverityStyle of(TemperatureSeverity severity, BuildContext context) {
    switch (severity) {
      case TemperatureSeverity.normal:
        return const SeverityStyle(
          color: AppColors.normal,
          dimColor: AppColors.normalDim,
          label: 'Normal',
          icon: Icons.check_circle_rounded,
          glowColor: Color(0x553DD68C),
        );
      case TemperatureSeverity.warm:
        return const SeverityStyle(
          color: AppColors.warm,
          dimColor: AppColors.normalDim,
          label: 'Normal',
          icon: Icons.check_circle_rounded,
          glowColor: Color(0x558AE04B),
        );
      case TemperatureSeverity.warning:
        return const SeverityStyle(
          color: AppColors.warning,
          dimColor: AppColors.warningDim,
          label: 'Warning',
          icon: Icons.warning_amber_rounded,
          glowColor: Color(0x55FFBC42),
        );
      case TemperatureSeverity.critical:
        return const SeverityStyle(
          color: AppColors.critical,
          dimColor: AppColors.criticalDim,
          label: 'Critical',
          icon: Icons.error_rounded,
          glowColor: Color(0x55FF4D4D),
        );
      case TemperatureSeverity.unavailable:
        return SeverityStyle(
          color: Theme.of(context).colorScheme.outline,
          dimColor: Theme.of(context).colorScheme.outlineVariant,
          label: 'Unavailable',
          icon: Icons.help_outline_rounded,
          glowColor: Colors.transparent,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Builder
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _buildLight();
  static ThemeData dark() => _buildDark();

  static ThemeData _buildDark() {
    const seed = Color(0xFF5B3FCE);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.bg0,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: AppColors.bg0,
      surfaceContainerLow: AppColors.bg1,
      surfaceContainer: AppColors.bg1,
      surfaceContainerHigh: AppColors.bg2,
      surfaceContainerHighest: AppColors.bg3,
      primary: AppColors.purpleLight,
      onPrimary: Colors.white,
      secondary: AppColors.cyan,
      onSecondary: AppColors.bg0,
      outline: AppColors.textMuted,
      outlineVariant: AppColors.divider,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg0,
      fontFamily: _fontFamily(),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.bg1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.textSecondary),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        space: 1,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      textTheme: _buildTextTheme(AppColors.textPrimary, AppColors.textSecondary),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.purpleLight : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.purpleLight.withValues(alpha: 0.3)
                : AppColors.bg3),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bg2,
        selectedColor: AppColors.purpleMid,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        side: const BorderSide(color: AppColors.border),
      ),
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static ThemeData _buildLight() {
    const seed = Color(0xFF5B3FCE);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.lightBg,
      fontFamily: _fontFamily(),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.lightText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      textTheme: _buildTextTheme(AppColors.lightText, AppColors.lightTextSecondary),
      dividerTheme: DividerThemeData(
        color: AppColors.lightBorder,
        space: 1,
        thickness: 1,
      ),
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static String? _fontFamily() => null; // System font by default

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: TextStyle(
        color: primary,
        fontSize: 57,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
      ),
      displayMedium: TextStyle(
        color: primary,
        fontSize: 45,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
      ),
      headlineLarge: TextStyle(
        color: primary,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        color: primary,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        color: primary,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: primary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: primary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: primary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      bodyLarge: TextStyle(
        color: primary,
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: secondary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: secondary,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
      ),
      labelLarge: TextStyle(
        color: primary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        color: secondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
      labelSmall: TextStyle(
        color: secondary,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Decoration Helpers
// ─────────────────────────────────────────────────────────────────────────────

class AppDecorations {
  const AppDecorations._();

  static BoxDecoration glassCard({
    Color? color,
    double radius = AppRadius.lg,
    bool showBorder = true,
  }) =>
      BoxDecoration(
        color: color ?? AppColors.bg1,
        borderRadius: BorderRadius.circular(radius),
        border: showBorder
            ? Border.all(color: AppColors.border, width: 1)
            : null,
      );

  static BoxDecoration gradientCard({
    List<Color>? colors,
    double radius = AppRadius.lg,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? [AppColors.bg2, AppColors.bg1],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border, width: 1),
      );

  static BoxDecoration highlightCard({
    required Color color,
    double radius = AppRadius.lg,
    double opacity = 0.08,
  }) =>
      BoxDecoration(
        color: color.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      );
}
