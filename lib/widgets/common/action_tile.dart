// lib/widgets/common/action_tile.dart
//
// The settings-style row and its supporting card/label/badge helpers.
//
// Extracted from student_profile_screen.dart, where they sat at file scope
// inside a 2400-line screen — which is the only reason the guest settings and
// profile screens couldn't reach them and grew near-identical `_SettingsTile`
// and `_MenuItemData` copies instead. Same motivation as bottom_nav_bar.dart:
// the component was already shared in spirit, just not importable.
//
// kActionTile's icon color now defaults to AppColors.primaryDark rather than
// student_profile_screen's file-local `kOrange` — the same value, but reachable
// from anywhere.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';

/// White rounded card with the soft drop shadow used by every profile and
/// settings surface.
BoxDecoration kCardDecoration({double radius = 16}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: Colors.grey.withAlpha(15),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

/// Uppercase grey group heading that separates runs of [kActionTile]s.
Widget kSectionLabel(String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Colors.grey[500],
      ),
    ),
  );
}

/// Tinted rounded square behind a leading icon.
Widget kIconBadge(
  IconData icon, {
  Color color = AppColors.primaryDark,
  double size = 20,
}) {
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withAlpha(31),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, color: color, size: size),
  );
}

/// The one settings-style row shared by the student and guest Settings
/// screens and by both profile pages' action lists.
///
/// Carries its own horizontal margin, so the parent scroll view should supply
/// vertical padding only — a parent that also pads horizontally double-insets
/// the tile.
Widget kActionTile({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  Color? iconColor,
  Widget? trailing,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withAlpha(10),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.primaryDark).withAlpha(31),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.primaryDark, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
      trailing:
          trailing ??
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    ),
  );
}
