import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DashboardOverviewLabel extends StatelessWidget {
  final String subtitle;

  const DashboardOverviewLabel({super.key, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Overview',
          style: GoogleFonts.beVietnamPro(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12.5,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
