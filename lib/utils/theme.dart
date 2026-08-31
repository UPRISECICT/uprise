// lib/utils/theme.dart
//
// Mobile app-wide theme — now mirrors the web app's brand palette and font
// (lib/theme/app_theme.dart's UpriseColors/UpriseTheme, BeVietnamPro)
// instead of mobile's previous unrelated orange/Poppins scheme, so the
// student/guest mobile app looks like the same product as the web portal.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// Kept as aliases (rather than removed) since a handful of mobile screens
// import these names directly: profile_summary.dart, login_screen.dart,
// change_password_screen.dart, bottom_nav_bar.dart.
const Color primaryOrange = UpriseColors.primaryDark;
const Color secondaryOrange = UpriseColors.primaryLight;
const Color backgroundColor = UpriseColors.lightGray;
const Color textDark = UpriseColors.charcoal;

ThemeData appTheme = ThemeData(
  brightness: Brightness.light,
  primaryColor: UpriseColors.primaryDark,
  colorScheme: ColorScheme.light(
    primary: UpriseColors.primaryDark,
    secondary: UpriseColors.primaryLight,
    tertiary: UpriseColors.accent,
    surface: UpriseColors.white,
    error: UpriseColors.error,
  ),
  scaffoldBackgroundColor: UpriseColors.lightGray,
  fontFamily: GoogleFonts.beVietnamPro().fontFamily,
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: UpriseColors.charcoal,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: GoogleFonts.beVietnamPro(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: UpriseColors.charcoal,
    ),
  ),
  bottomNavigationBarTheme: BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: UpriseColors.primaryDark,
    unselectedItemColor: Colors.grey,
    type: BottomNavigationBarType.fixed,
    elevation: 8,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: UpriseColors.primaryDark, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: UpriseColors.primaryDark,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
);

// Applied only by the web Admin and Org routes in RoleRouter. Keeping this
// separate from [appTheme] preserves the existing mobile dialog UI.
final DialogThemeData upriseWebDialogTheme = DialogThemeData(
  alignment: Alignment.center,
  barrierColor: const Color(0x990F172A),
  backgroundColor: UpriseColors.white,
  surfaceTintColor: Colors.transparent,
  elevation: 18,
  shadowColor: const Color(0x330F172A),
  insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  titleTextStyle: GoogleFonts.beVietnamPro(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: UpriseColors.charcoal,
  ),
  contentTextStyle: GoogleFonts.beVietnamPro(
    fontSize: 14,
    height: 1.5,
    color: UpriseColors.darkGray,
  ),
);
