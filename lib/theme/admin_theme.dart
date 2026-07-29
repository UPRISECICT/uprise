// lib/theme/admin_theme.dart
//
// Admin-only color palette — deliberately separate from UpriseColors
// (theme/app_theme.dart), which the org-side web screens also import.
// Editing UpriseColors directly would recolor the org portal too; this file
// lets the admin section move to its own CICT-inspired scheme (gray as the
// structural primary, blue for interactive/actionable elements, orange as a
// sparing accent) without touching org or mobile screens at all.
//
// Field names mirror UpriseColors on purpose so admin files can swap their
// import and `UpriseColors.` references for `AdminColors.` with no other
// changes needed.
import 'package:flutter/material.dart';

class AdminColors {
  // Deepened from slate-700 to slate-800 for a richer, more premium primary
  // that reads more distinctly against blue/orange instead of sitting in the
  // same tonal weight as them.
  static const Color primaryDark = Color(0xFF1E293B);
  static const Color primaryLight = Color(0xFF475569);
  static const Color accent = Color(0xFFF97316);
  static const Color info = Color(0xFF2563EB);
  static const Color white = Color(0xFFFFFFFF);

  static const Color charcoal = Color(0xFF1F2937);
  static const Color darkText = Color(0xFF1F2937);
  static const Color darkGray = Color(0xFF6B7280);
  static const Color greyText = Color(0xFF6B7280);
  static const Color mediumGray = Color(0xFFE5E7EB);
  static const Color lightGray = Color(0xFFF9FAFB);

  // Semantic — unchanged from UpriseColors; these carry meaning
  // (success/warning/error) independent of brand color.
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
}
