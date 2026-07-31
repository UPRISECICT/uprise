// lib/widgets/student/app_colors.dart
//
// Single shared color palette for the student mobile app — now mirroring
// the web app's actual brand palette (lib/theme/app_theme.dart's
// UpriseColors: primaryDark 0xFFBE4700, primaryLight 0xFFD47A00, accent
// 0xFFDA6937) instead of mobile's old, unrelated Colors.orange/0xFFFF9800
// scheme, so mobile and web look like the same product.
//
// primaryDark is a MaterialColor (full 50-900 shade ramp generated from
// the brand hue) rather than a plain Color, on purpose: dozens of mobile
// screens reference `Colors.orange.shade300` etc. for gradients/badges.
// Keeping primaryDark shade-able lets every one of those call sites swap
// to the brand color via a plain find/replace without breaking `.shade*`.

import 'package:flutter/material.dart';

class AppColors {
  static const MaterialColor primaryDark =
      MaterialColor(0xFFBE4700, <int, Color>{
        50: Color(0xFFDB9A73),
        100: Color(0xFFD89166),
        200: Color(0xFFD27E4D),
        300: Color(0xFFCB6C33),
        400: Color(0xFFC5591A),
        500: Color(0xFFBE4700),
        600: Color(0xFFAB4000),
        700: Color(0xFF983900),
        800: Color(0xFF853200),
        900: Color(0xFF722B00),
      });
  static const Color primaryLight = Color(0xFFD47A00);
  static const Color accent = Color(0xFFDA6937);
  static const Color background = Color(0xFFF5F5F5);

  // Text scale — added so screens stop each inventing their own near-black
  // ("Colors.black87", "Colors.black", a private _UiTokens.headingText,
  // etc.) and instead share one consistent hierarchy across the app.
  static const Color textPrimary = Color(0xFF1B1B1D);
  static const Color textSecondary = Color(0xFF4B4B50);
  static const Color textMuted = Color(0xFF8A8A90);
  static const Color divider = Color(0xFFE7E7E9);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color surfaceTint = Color(0xFFFAF6F2);
}
