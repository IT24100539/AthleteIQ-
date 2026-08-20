import 'package:flutter/material.dart';

/// Surface / text tokens for one brightness. Accents (mint, coral, amber)
/// stay the same in both modes.
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.textTertiary,
    required this.mintTint,
    required this.mintBorder,
    required this.calendarRest,
    required this.heroGradientStart,
    required this.heroGradientEnd,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;
  final Color textTertiary;
  final Color mintTint;
  final Color mintBorder;
  final Color calendarRest;
  final Color heroGradientStart;
  final Color heroGradientEnd;

  static const dark = AppPalette(
    background: Color(0xFF0B0D0C),
    surface: Color(0xFF1C1F1D),
    surfaceAlt: Color(0xFF121412),
    border: Color(0xFF2A2E2B),
    divider: Color(0xFF1C1F1D),
    textPrimary: Color(0xFFEDEFEC),
    textSecondary: Color(0xFFB4B8B5),
    textMuted: Color(0xFF6E736F),
    textFaint: Color(0xFF4E524F),
    textTertiary: Color(0xFF8A8F8C),
    mintTint: Color(0xFF153A30),
    mintBorder: Color(0xFF1F5B49),
    calendarRest: Color(0xFF17191A),
    heroGradientStart: Color(0xFF153A30),
    heroGradientEnd: Color(0xFF0F2A22),
  );

  static const light = AppPalette(
    background: Color(0xFFF3F6F4),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE8EDE9),
    border: Color(0xFFD0D7D2),
    divider: Color(0xFFE2E8E4),
    textPrimary: Color(0xFF121614),
    textSecondary: Color(0xFF3F4743),
    textMuted: Color(0xFF5C6560),
    textFaint: Color(0xFF8B938E),
    textTertiary: Color(0xFF6A736E),
    mintTint: Color(0xFFD8F6ED),
    mintBorder: Color(0xFF8ED9C4),
    calendarRest: Color(0xFFEEF2F0),
    heroGradientStart: Color(0xFF153A30),
    heroGradientEnd: Color(0xFF0F2A22),
  );
}

/// Design tokens pulled from `docs/wireframe.html.html` (top of `<style>` block).
/// Surface/text colors follow the active [AppPalette] (dark by default).
/// Accents stay constant so existing `const` mint/coral usages still compile.
class AppColors {
  static AppPalette _palette = AppPalette.dark;

  static bool get isDark => identical(_palette, AppPalette.dark);

  /// Called when [ThemeMode] changes so screens using `AppColors.textPrimary`
  /// (etc.) pick up light/dark without rewriting every widget.
  static void bind(bool dark) {
    _palette = dark ? AppPalette.dark : AppPalette.light;
  }

  static Color get background => _palette.background;
  static Color get surface => _palette.surface;
  static Color get surfaceAlt => _palette.surfaceAlt;
  static Color get border => _palette.border;
  static Color get divider => _palette.divider;

  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get textMuted => _palette.textMuted;
  static Color get textFaint => _palette.textFaint;
  static Color get textTertiary => _palette.textTertiary;

  static Color get mintTint => _palette.mintTint;
  static Color get mintBorder => _palette.mintBorder;
  static Color get calendarRest => _palette.calendarRest;
  static Color get heroGradientStart => _palette.heroGradientStart;
  static Color get heroGradientEnd => _palette.heroGradientEnd;

  // ── Accents (same in both modes) ──────────────────────────────────────────
  static const mint = Color(0xFF2FE6B8);
  static const mintDark = Color(0xFF06231C);
  static const coral = Color(0xFFFF6A4D);
  static const amber = Color(0xFFE6A83B);

  // Risk chips stay on dark tints so contrast holds in both modes.
  static const riskHighBg = Color(0xFF2A1810);
  static const riskMedBg = Color(0xFF241C10);
  static const riskLowBg = Color(0xFF10201C);

  /// Text on mint / coral fills (`.btn-mint`, selected chips).
  static const onAccent = mintDark;

  static Color forRisk(String level) {
    switch (level.toUpperCase()) {
      case 'HIGH':
        return coral;
      case 'MEDIUM':
        return amber;
      default:
        return mint;
    }
  }

  static Color bgForRisk(String level) {
    switch (level.toUpperCase()) {
      case 'HIGH':
        return riskHighBg;
      case 'MEDIUM':
        return riskMedBg;
      default:
        return riskLowBg;
    }
  }
}

/// Border radii used across wireframe phone mockups.
class AppRadius {
  static const phone = 28.0;
  static const hero = 10.0;
  static const chip = 10.0;
  static const card = 8.0;
  static const cardSmall = 7.0;
  static const button = 8.0;
  static const buttonWireframe = 6.0;
  static const emptyIcon = 10.0;
  static const input = 8.0;
}

/// Spacing scale derived from wireframe padding / gap values.
class AppSpacing {
  static const screenEdge = 14.0;
  static const screenPadding = 16.0;
  static const cardPadding = 14.0;
  static const cardPaddingCompact = 8.0;
  static const sectionGap = 24.0;
  static const itemGap = 8.0;
  static const statGap = 6.0;
  static const labelBottom = 12.0;

  /// Material / WCAG minimum tap target.
  static const minTapTarget = 48.0;
}
