import 'package:flutter/material.dart';

import '../../domain/enums/storage_enums.dart';

// Design Tokens

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
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const Radius mdRadius = Radius.circular(md);
  static const Radius lgRadius = Radius.circular(lg);
}

class AppDurations {
  const AppDurations._();
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration verySlow = Duration(milliseconds: 800);
}

// Neutral palette: graphite-dark surfaces, single calm blue accent, status
// colors carry all semantic meaning.

class AppColors {
  const AppColors._();

  // Dark surfaces
  static const Color bg0 = Color(0xFF1C1C1E); // macOS-style dark background
  static const Color bg1 = Color(0xFF2C2C2E); // card
  static const Color bg2 = Color(0xFF3A3A3C); // elevated / hover
  static const Color bg3 = Color(0xFF48484A); // selected

  // Single restrained accent: calm steel blue
  static const Color accent = Color(0xFF3E7BFA);
  static const Color accentDim = Color(0xFF2B5ED6);

  // Status colors: semantic only, not decorative
  static const Color normal = Color(0xFF30D158); // green
  static const Color normalDim = Color(0xFF248A3D);
  static const Color warm = Color(0xFF7ED321); // yellow-green
  static const Color warning = Color(0xFFFF9F0A); // amber
  static const Color warningDim = Color(0xFFB97000);
  static const Color critical = Color(0xFFFF453A); // red
  static const Color criticalDim = Color(0xFFBF3228);

  // Dark text
  static const Color textPrimary = Color(0xFFEEEEF0);
  static const Color textSecondary = Color(0xFF98989D);
  static const Color textMuted = Color(0xFF636366);
  static const Color divider = Color(0xFF38383A);
  static const Color border = Color(0xFF3A3A3C);

  // Light surfaces
  static const Color lightBg = Color(0xFFF2F2F7); // macOS sidebar-like
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSurfaceMuted = Color(0xFFEFEFF4);
  static const Color lightBorder = Color(0xFFD1D1D6);
  static const Color lightText = Color(0xFF1C1C1E);
  static const Color lightTextSecondary = Color(0xFF6C6C70);
  static const Color lightShadow = Color(0x0C000000);
}

// Severity styling: no glow, no glassColor — just clean color+icon+label.

class SeverityStyle {
  const SeverityStyle({
    required this.color,
    required this.dimColor,
    required this.label,
    required this.icon,
  });

  final Color color;
  final Color dimColor;
  final String label;
  final IconData icon;

  static SeverityStyle of(TemperatureSeverity severity, BuildContext context) {
    switch (severity) {
      case TemperatureSeverity.normal:
        return const SeverityStyle(
          color: AppColors.normal,
          dimColor: AppColors.normalDim,
          label: 'Normal',
          icon: Icons.check_circle_outline_rounded,
        );
      case TemperatureSeverity.warm:
        return const SeverityStyle(
          color: AppColors.warm,
          dimColor: AppColors.normalDim,
          label: 'Normal',
          icon: Icons.check_circle_outline_rounded,
        );
      case TemperatureSeverity.warning:
        return const SeverityStyle(
          color: AppColors.warning,
          dimColor: AppColors.warningDim,
          label: 'Warning',
          icon: Icons.warning_amber_rounded,
        );
      case TemperatureSeverity.critical:
        return const SeverityStyle(
          color: AppColors.critical,
          dimColor: AppColors.criticalDim,
          label: 'Critical',
          icon: Icons.error_outline_rounded,
        );
      case TemperatureSeverity.unavailable:
        return SeverityStyle(
          color: Theme.of(context).colorScheme.outline,
          dimColor: Theme.of(context).colorScheme.outlineVariant,
          label: 'Unavailable',
          icon: Icons.help_outline_rounded,
        );
    }
  }
}

// Theme builder

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _buildLight();
  static ThemeData dark() => _buildDark();

  static ThemeData _buildDark() {
    const seed = Color(0xFF3E7BFA);
    final scheme =
        ColorScheme.fromSeed(
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
          primary: AppColors.accent,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          onSecondary: Colors.white,
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
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.textSecondary),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        space: 1,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      textTheme: _buildTextTheme(
        AppColors.textPrimary,
        AppColors.textSecondary,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.bg3,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bg2,
        selectedColor: AppColors.accent,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: const BorderSide(color: AppColors.border),
      ),
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
    );
  }

  static ThemeData _buildLight() {
    const seed = Color(0xFF3E7BFA);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ).copyWith(
          surface: AppColors.lightCard,
          primary: AppColors.accent,
          onPrimary: Colors.white,
          outline: AppColors.lightTextSecondary,
          outlineVariant: AppColors.lightBorder,
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
        shadowColor: AppColors.lightShadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.lightText,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.lightTextSecondary),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        space: 1,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.lightTextSecondary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.lightBorder,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightSurfaceMuted,
        selectedColor: AppColors.accent,
        labelStyle: const TextStyle(
          color: AppColors.lightTextSecondary,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: const BorderSide(color: AppColors.lightBorder),
      ),
      textTheme: _buildTextTheme(
        AppColors.lightText,
        AppColors.lightTextSecondary,
      ),
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
    );
  }

  static String? _fontFamily() => null; // system font

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: TextStyle(
        color: primary,
        fontSize: 57,
        fontWeight: FontWeight.w700,
      ),
      displayMedium: TextStyle(
        color: primary,
        fontSize: 45,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: TextStyle(
        color: primary,
        fontSize: 32,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: TextStyle(
        color: primary,
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: TextStyle(
        color: primary,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: primary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: primary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: primary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: primary,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: secondary,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: secondary,
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        color: primary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: secondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        color: secondary,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// Shared decoration helpers

class AppDecorations {
  const AppDecorations._();

  static BoxDecoration card({
    Color? color,
    double radius = AppRadius.lg,
    bool showBorder = true,
    bool isDark = true,
  }) => BoxDecoration(
    color: color ?? (isDark ? AppColors.bg1 : AppColors.lightCard),
    borderRadius: BorderRadius.circular(radius),
    border: showBorder
        ? Border.all(
            color: isDark ? AppColors.border : AppColors.lightBorder,
            width: 1,
          )
        : null,
  );

  static BoxDecoration statusHighlight({
    required Color color,
    double radius = AppRadius.lg,
  }) => BoxDecoration(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
  );
}
