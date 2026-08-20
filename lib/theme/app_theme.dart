import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

export 'app_colors.dart';
export 'theme_controller.dart';

class AppTheme {
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData get light => _build(AppPalette.light, Brightness.light);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    const onMint = AppColors.mintDark;
    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: palette.background,
      colorScheme: base.colorScheme.copyWith(
        brightness: brightness,
        primary: AppColors.mint,
        secondary: AppColors.coral,
        surface: palette.surface,
        onSurface: palette.textPrimary,
        onPrimary: onMint,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineSmall: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        titleLarge: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(color: palette.textSecondary),
        bodySmall: GoogleFonts.inter(color: palette.textMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        iconTheme: IconThemeData(color: palette.textPrimary, size: 22),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.mint,
          foregroundColor: onMint,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
          minimumSize: const Size(0, AppSpacing.minTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textSecondary,
          side: BorderSide(color: palette.border),
          minimumSize: const Size(0, AppSpacing.minTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedItemColor: AppColors.mint,
        unselectedItemColor: palette.textFaint,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.mint),
        ),
        hintStyle: GoogleFonts.inter(color: palette.textFaint),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.hero),
          side: BorderSide(color: palette.border),
        ),
      ),
      dividerColor: palette.divider,
      listTileTheme: ListTileThemeData(
        iconColor: palette.textSecondary,
        textColor: palette.textPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return onMint;
          return palette.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.mint;
          return palette.border;
        }),
      ),
    );
  }
}
