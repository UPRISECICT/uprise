// lib/widgets/common/info_tile.dart
//
// The two metadata rows an event/product detail screen is built from.
//
// These look like a duplicate pair across the two sides but aren't — they do
// different jobs, so both survive:
//
//   InfoRow   (from student's _InfoRow)  — one line: icon + text. For a run of
//                                          compact meta lines under a title.
//   InfoTile  (from guest's _InfoTile)   — two lines: tinted icon square, with
//                                          a small label above a bold value.
//                                          For a labelled field ("WHEN", "WHERE").
//
// LocationCard is guest's, kept because the student side has no boxed variant.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';

/// Single-line `icon + text` metadata row.
///
/// Passing [color] both tints the row and bolds it — that's how the student
/// detail screen marks the one row that needs attention (a cancelled date, a
/// changed venue) without a separate widget.
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const InfoRow({super.key, required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: color ?? Colors.black87,
              fontWeight: color != null ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Labelled field: tinted icon square, small grey label, bold value.
class InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const InfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = AppColors.primaryDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withAlpha(26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Boxed venue row — a bordered surface around a single location line.
class LocationCard extends StatelessWidget {
  final String location;

  const LocationCard({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                location,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
