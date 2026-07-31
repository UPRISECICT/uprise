// lib/theme/org_theme.dart
// Org-side brand palette: orange (primary), gray, white, blue (links/info
// accents only) — kept in its own file, separate from theme/app_theme.dart,
// so the org portal reads visually distinct from admin's amber palette.
// Same member names as the shared UpriseColors so it's a drop-in import
// swap for any org screen that used to pull its colors from app_theme.dart.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class UpriseColors {
  static const Color primaryDark = Color(0xFFEA580C); // true orange – primary
  static const Color primaryLight = Color(
    0xFFF97316,
  ); // lighter orange – hover/emphasis
  static const Color accent = Color(0xFFF97316); // secondary accent
  static const Color info = Color(0xFF2563EB); // blue – links/info accents only
  static const Color white = Color(0xFFFFFFFF);

  // Neutral gray scale
  static const Color charcoal = Color(0xFF1A202C);
  static const Color darkText = Color(0xFF1A202C);
  static const Color darkGray = Color(0xFF64748B);
  static const Color greyText = Color(0xFF64748B);
  static const Color mediumGray = Color(0xFFE8ECF0);
  static const Color lightGray = Color(0xFFF8F9FB);

  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
}

class UpriseTheme {
  static ThemeData lightTheme = ThemeData(
    primaryColor: UpriseColors.primaryDark,
    fontFamily: GoogleFonts.beVietnamPro().fontFamily,
    scaffoldBackgroundColor: UpriseColors.lightGray,
    appBarTheme: AppBarTheme(
      backgroundColor: UpriseColors.white,
      elevation: 0,
      titleTextStyle: GoogleFonts.beVietnamPro(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: UpriseColors.charcoal,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: UpriseColors.primaryDark),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: UpriseColors.primaryDark,
        foregroundColor: UpriseColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: UpriseColors.primaryDark),
    ),
    colorScheme: ColorScheme.light(
      primary: UpriseColors.primaryDark,
      secondary: UpriseColors.primaryLight,
      tertiary: UpriseColors.accent,
      surface: UpriseColors.white,
      error: UpriseColors.error,
    ),
  );
}
