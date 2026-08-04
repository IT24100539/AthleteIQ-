import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors pulled directly from the AthleteIQ wireframe.
class AppColors {
  static const background = Color(0xFF0B0D0C);
  static const surface = Color(0xFF1C1F1D);
  static const surfaceAlt = Color(0xFF121412);
  static const border = Color(0xFF2A2E2B);
  static const divider = Color(0xFF1C1F1D);

  static const textPrimary = Color(0xFFEDEFEC);
  static const textSecondary = Color(0xFFB4B8B5);
  static const textMuted = Color(0xFF6E736F);
  static const textFaint = Color(0xFF4E524F);

  static const mint = Color(0xFF2FE6B8);
  static const mintDark = Color(0xFF06231C);
  static const coral = Color(0xFFFF6A4D);
  static const amber = Color(0xFFE6A83B);

  // Risk chip backgrounds
  static const riskHighBg = Color(0xFF2A1810);
  static const riskMedBg = Color(0xFF241C10);
  static const riskLowBg = Color(0xFF10201C);

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

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.mint,
        secondary: AppColors.coral,
        surface: AppColors.surface,
        background: AppColors.background,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineSmall: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(color: AppColors.textSecondary),
        bodySmall: GoogleFonts.inter(color: AppColors.textMuted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.mint,
          foregroundColor: AppColors.mintDark,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.mint),
        ),
        hintStyle: GoogleFonts.inter(color: AppColors.textFaint),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerColor: AppColors.divider,
    );
  }
}
