// lib/widgets/common/section_header.dart
//
// "Title  ·  View all ›" row above a home-feed section.
//
// Student and guest each had a private `_SectionHeader` that rendered almost
// the same thing. This is the student one, promoted: its action is a
// TextButton with a 44x44 minimum tap target, where guest's was a bare
// GestureDetector around 13px text — below the accessible touch-target floor.
//
// Deliberately carries no padding or background of its own (guest's copy
// baked in `fromLTRB(16, 20, 12, 10)` and an opaque fill). Call sites wrap it,
// which is what lets one section sit tight under a card and the next breathe.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';

class SectionHeader extends StatelessWidget {
  final String title;

  /// Both null on a section with nothing to navigate to — the row then
  /// renders as a plain heading.
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 11,
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
