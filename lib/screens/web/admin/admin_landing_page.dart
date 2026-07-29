import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_login.dart';

// Restyled to match the AdminLogin / OrganizationLogin visual language:
// campus photo backdrop + vignette, frosted-glass card. CICT professional
// scheme: gray is the structural primary, blue carries the interactive CTA,
// orange stays reserved for the login page's own wordmark accent.
// Navigation logic is unchanged.

class AdminLandingPage extends StatelessWidget {
  const AdminLandingPage({super.key});

  static const Color _primary = Color(0xFF1E293B);
  static const Color _primaryDeep = Color(0xFF0B1120);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _blueDeep = Color(0xFF1E40AF);
  static const Color _navy = Color(0xFF0F172A);
  static const Color _slateDark = Color(0xFF111827);
  static const Color _slateMid = Color(0xFF6B7280);
  static const Color _slateSoft = Color(0xFFAEB4C4);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/bg_pattern.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryDeep, _navy],
                ),
              ),
            ),
          ),
          // Vignette — darker at the edges so the centered card has contrast,
          // lighter in the middle so the campus photo still reads through.
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [
                  Color(0x660B1120),
                  Color(0xD91E293B),
                  Color(0xF00F172A),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(232),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withAlpha(90),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(120),
                              blurRadius: 60,
                              offset: const Offset(0, 24),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(36),
                          child: LayoutBuilder(
                            builder: (_, c) {
                              final narrow = c.maxWidth < 640;
                              final left = _buildLeft(context);
                              final right = _buildRight();
                              return narrow
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        left,
                                        const SizedBox(height: 24),
                                        right,
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(child: left),
                                        const SizedBox(width: 28),
                                        Expanded(child: right),
                                      ],
                                    );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeft(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primary, _primaryDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: _primary.withAlpha(90),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.shield_rounded,
            size: 36,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            'ADMIN ACCESS',
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _primaryDeep,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Admin Portal',
          style: GoogleFonts.beVietnamPro(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _slateDark,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Manage the system, review organizations, and keep the campus portal running smoothly.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 15,
            color: _slateMid,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 26),
        SizedBox(
          width: 260,
          height: 48,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_blueDeep, _blue]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _blue.withAlpha(80),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminLogin()),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Continue to Admin Login',
                style: GoogleFonts.beVietnamPro(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: _slateSoft),
            const SizedBox(width: 6),
            Text(
              'Secure access for administrators and system officers.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                color: _slateSoft,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRight() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FeatureTile(
            icon: Icons.group_work_rounded,
            title: 'Manage organizations',
            subtitle: 'Monitor org records and access levels.',
          ),
          const SizedBox(height: 14),
          _FeatureTile(
            icon: Icons.event_available_rounded,
            title: 'Review events',
            subtitle: 'Approve, track, and manage event activity.',
          ),
          const SizedBox(height: 14),
          _FeatureTile(
            icon: Icons.security_rounded,
            title: 'Control access',
            subtitle: 'Keep the system secure with admin-only tools.',
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  static const Color _primary = Color(0xFF334155);
  static const Color _slateDark = Color(0xFF111827);
  static const Color _slateMid = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Icon(icon, color: _primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _slateDark,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: GoogleFonts.beVietnamPro(fontSize: 13, color: _slateMid),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
