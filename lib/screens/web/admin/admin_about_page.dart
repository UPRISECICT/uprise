import '../landing/landing_motion.dart';
import '../landing/landing_palette.dart';
import '../landing/researchers_section.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_site_chrome.dart';

// About content — one continuous narrative (system → researchers → client
// → organizations), not a stack of uniform bordered cards: a dark
// full-bleed band for the team and a plain pull-quote for the client are
// the two deliberate visual breaks that give the page rhythm.
class AdminAboutContent extends StatefulWidget {
  final ValueChanged<AdminSiteSection> onSelect;
  final VoidCallback onTerms;

  const AdminAboutContent({
    required this.onSelect,
    required this.onTerms,
    super.key,
  });

  @override
  State<AdminAboutContent> createState() => _AdminAboutContentState();
}

class _AdminAboutContentState extends State<AdminAboutContent> {
  late final Future<List<_OrgSummary>> _orgsFuture = _loadOrgs();

  Future<List<_OrgSummary>> _loadOrgs() async {
    final snap = await FirebaseFirestore.instance
        .collection('organizations')
        .get();
    final orgs = snap.docs
        .map((d) {
          final data = d.data();
          final name =
              (data['orgName'] as String?) ??
              (data['name'] as String?) ??
              (data['shortName'] as String?) ??
              '';
          return _OrgSummary(
            name: name,
            shortName: data['shortName'] as String? ?? '',
            logoUrl: data['logoUrl'] as String? ?? '',
          );
        })
        .where((o) => o.name.isNotEmpty)
        .toList();
    orgs.sort((a, b) => a.name.compareTo(b.name));
    return orgs;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SectionSeam(from: Colors.white, to: AdminSiteColors.bg),
              _buildSystem(),
              const SectionSeam(from: AdminSiteColors.bg, to: Colors.white),
              _buildComparison(),
              const SectionSeam(from: Colors.white, to: AdminSiteColors.navy),
              _buildResearchers(),
              const SectionSeam(
                from: AdminSiteColors.navy,
                to: AdminSiteColors.bg,
              ),
              _buildClient(),
              const SectionSeam(from: AdminSiteColors.bg, to: Colors.white),
              _buildOrgWall(),
              const SectionSeam(from: Colors.white, to: AdminSiteColors.navy),
              AdminSiteFooter(
                onSelect: widget.onSelect,
                onTerms: widget.onTerms,
              ),
            ],
          ),
          const PageSpine(),
        ],
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      child: AbstractSectionBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Reveal(
                    dy: 10,
                    scaleFrom: 0.8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AdminSiteColors.primary.withAlpha(14),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: AdminSiteColors.border),
                      ),
                      child: Text(
                        'ABOUT UPRISE',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AdminSiteColors.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Reveal(
                    delay: Duration(milliseconds: 120),
                    dy: 34,
                    tiltFrom: 0.35,
                    child: Text(
                      'Built for CICT, from the ground up',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AdminSiteColors.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Reveal(
                    delay: Duration(milliseconds: 260),
                    dy: 20,
                    child: Text(
                      'One system, explained: what it replaces, who built it, '
                      'and who it serves.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 15,
                        color: AdminSiteColors.inkSoft,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── THE SYSTEM ────────────────────────────────────────────────────
  Widget _buildSystem() {
    const points = [
      (
        'One backend, three tailored front ends',
        'Admins and org officers get the web console; students and guests '
            'get the mobile app — all reading and writing the same live '
            'Firebase data, never out of sync.',
      ),
      (
        'Role-based access, enforced end to end',
        'Every account is routed and gated by its role the moment it '
            'signs in — no shared logins, no manual permission juggling.',
      ),
      (
        'Nothing happens off the record',
        'Approvals, account changes, and report submissions are all '
            'written to a permanent, admin-visible activity log.',
      ),
    ];

    return Container(
      color: AdminSiteColors.bg,
      child: AbstractSectionBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: LayoutBuilder(
                builder: (_, c) {
                  final wide = c.maxWidth >= 900;
                  final copy = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Reveal(
                        dx: -24,
                        dy: 0,
                        child: _eyebrow('01 · THE SYSTEM'),
                      ),
                      const SizedBox(height: 10),
                      Reveal(
                        delay: Duration(milliseconds: 100),
                        dy: 24,
                        child: Text(
                          'A system, not a spreadsheet',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AdminSiteColors.ink,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      for (var i = 0; i < points.length; i++)
                        Reveal(
                          delay: Duration(milliseconds: 200 + 130 * i),
                          dx: -40,
                          dy: 0,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 22),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '0${i + 1}',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AdminSiteColors.blue,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        points[i].$1,
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: AdminSiteColors.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        points[i].$2,
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12.5,
                                          color: AdminSiteColors.inkSoft,
                                          height: 1.55,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                  final diagram = Reveal(
                    delay: Duration(milliseconds: 180),
                    dy: 44,
                    scaleFrom: 0.94,
                    tiltFrom: 0.25,
                    child: PointerTilt(
                      builder: (context, t) => Transform(
                        alignment: Alignment.center,
                        transform: perspective3d()
                          ..rotateX(-t.dy * 0.07)
                          ..rotateY(t.dx * 0.07),
                        child: const _RoleDiagram(),
                      ),
                    ),
                  );
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: copy),
                            const SizedBox(width: 48),
                            Expanded(flex: 5, child: diagram),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [copy, const SizedBox(height: 36), diagram],
                        );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eyebrow(String text) {
    return Text(
      text,
      style: GoogleFonts.beVietnamPro(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AdminSiteColors.blue,
        letterSpacing: 1.4,
      ),
    );
  }

  // ── WHAT UPRISE REPLACES (plain spec-sheet list, no chip boxes) ────
  Widget _buildComparison() {
    const rows = [
      ('Paper event forms', 'In-app proposal → approval flow'),
      (
        'Scattered enrollment spreadsheets',
        'One roster, imported and provisioned in bulk',
      ),
      ('Email chains for status updates', 'Real-time in-app notifications'),
      ('No record of who did what', 'Full, timestamped activity log'),
    ];

    return Container(
      color: Colors.white,
      child: AbstractSectionBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Reveal(dx: -24, dy: 0, child: _eyebrow('WHAT IT REPLACES')),
                  const SizedBox(height: 10),
                  Reveal(
                    delay: Duration(milliseconds: 100),
                    dy: 24,
                    child: Text(
                      'Before → After',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AdminSiteColors.ink,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  for (var i = 0; i < rows.length; i++) ...[
                    LayoutBuilder(
                      builder: (_, c) {
                        final wide = c.maxWidth >= 480;
                        final before = Reveal(
                          delay: Duration(milliseconds: 160 + 120 * i),
                          dx: -48,
                          dy: 0,
                          child: Text(
                            rows[i].$1,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13.5,
                              color: AdminSiteColors.inkFaint,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: AdminSiteColors.inkFaint,
                            ),
                          ),
                        );
                        final after = Reveal(
                          delay: Duration(milliseconds: 300 + 120 * i),
                          dx: 48,
                          dy: 0,
                          child: Text(
                            rows[i].$2,
                            textAlign: wide ? TextAlign.right : TextAlign.left,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AdminSiteColors.ink,
                            ),
                          ),
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: wide
                              ? Row(
                                  children: [
                                    Expanded(child: before),
                                    Reveal(
                                      delay: Duration(
                                        milliseconds: 240 + 120 * i,
                                      ),
                                      dy: 0,
                                      scaleFrom: 0.3,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 16,
                                          color: AdminSiteColors.blue,
                                        ),
                                      ),
                                    ),
                                    Expanded(child: after),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    before,
                                    const SizedBox(height: 4),
                                    after,
                                  ],
                                ),
                        );
                      },
                    ),
                    if (i != rows.length - 1)
                      const Divider(height: 1, color: AdminSiteColors.border),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── THE RESEARCHERS — dark full-bleed band, the one visual break ──
  Widget _buildResearchers() {
    return ResearchersSection(
      palette: LandingPalette.admin,
      background: AdminSiteColors.navy,
      eyebrow: '02 · THE RESEARCHERS',
    );
  }

  // ── THE CLIENT — plain pull-quote, no card chrome ──────────────────
  Widget _buildClient() {
    return Container(
      color: AdminSiteColors.bg,
      child: AbstractSectionBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  // The client's own emblem, front and center — this section
                  // was pure text with nothing to visually anchor "the
                  // client" it's describing.
                  Reveal(
                    dy: 0,
                    scaleFrom: 0.6,
                    child: Floating(
                      child: Container(
                        width: 92,
                        height: 92,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AdminSiteColors.ink.withAlpha(20),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/cict_logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.school_rounded,
                            color: AdminSiteColors.blue,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Reveal(
                    delay: Duration(milliseconds: 120),
                    dy: 16,
                    child: Text(
                      '03 · THE CLIENT',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AdminSiteColors.blue,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Reveal(
                    delay: Duration(milliseconds: 220),
                    dy: 30,
                    tiltFrom: 0.3,
                    child: Text(
                      'One office, every organization.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AdminSiteColors.ink,
                        height: 1.3,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Reveal(
                    delay: Duration(milliseconds: 340),
                    dy: 22,
                    child: Text(
                      'Bulacan State University\'s College of Information and '
                      'Communications Technology is the client — a single '
                      'central admin account coordinating every recognized '
                      'student organization under one system, instead of each '
                      'one running independently.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14.5,
                        color: AdminSiteColors.inkSoft,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── ORGANIZATIONS — minimal logo strip, not a card grid ────────────
  Widget _buildOrgWall() {
    return Container(
      color: Colors.white,
      child: AbstractSectionBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                children: [
                  Reveal(
                    dy: 16,
                    child: Text(
                      '04 · ON UPRISE TODAY',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AdminSiteColors.blue,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Reveal(
                    delay: Duration(milliseconds: 100),
                    dy: 24,
                    child: Text(
                      'Organizations already on the system',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AdminSiteColors.ink,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  FutureBuilder<List<_OrgSummary>>(
                    future: _orgsFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(
                            color: AdminSiteColors.blue,
                          ),
                        );
                      }
                      final orgs = snap.data ?? const [];
                      if (orgs.isEmpty) {
                        return Text(
                          'No organizations are registered yet.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: AdminSiteColors.inkSoft,
                          ),
                        );
                      }
                      return Wrap(
                        spacing: 40,
                        runSpacing: 36,
                        alignment: WrapAlignment.center,
                        children: [
                          for (var i = 0; i < orgs.length; i++)
                            Reveal(
                              delay: Duration(
                                milliseconds: 70 * (i < 10 ? i : 10),
                              ),
                              dy: 30,
                              scaleFrom: 0.85,
                              child: _OrgBadge(org: orgs[i]),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrgSummary {
  final String name;
  final String shortName;
  final String logoUrl;

  const _OrgSummary({
    required this.name,
    required this.shortName,
    required this.logoUrl,
  });
}

// Minimal logo + name, stacked — no border/card, reads as a "trusted by"
// strip instead of another bordered box.
class _OrgBadge extends StatelessWidget {
  final _OrgSummary org;

  const _OrgBadge({required this.org});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        children: [
          _logo(),
          const SizedBox(height: 12),
          Text(
            org.shortName.isNotEmpty ? org.shortName : org.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AdminSiteColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logo() {
    const size = 92.0;
    if (org.logoUrl.isEmpty) return _placeholder();
    if (org.logoUrl.startsWith('data:')) {
      try {
        return ClipOval(
          child: Image.memory(
            base64Decode(org.logoUrl.split(',').last),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        );
      } catch (_) {
        return _placeholder();
      }
    }
    return ClipOval(
      child: Image.network(
        org.logoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    final trimmed = (org.shortName.isNotEmpty ? org.shortName : org.name)
        .trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: 92,
      height: 92,
      decoration: const BoxDecoration(
        color: AdminSiteColors.bg,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: AdminSiteColors.border),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.beVietnamPro(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: AdminSiteColors.primary,
        ),
      ),
    );
  }
}

// Visual echoing the college's real role split (admin/org web console vs.
// student/guest mobile app) converging on one Firebase backend.
class _RoleDiagram extends StatelessWidget {
  const _RoleDiagram();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminSiteColors.border),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              Reveal(
                delay: Duration(milliseconds: 360),
                dy: 26,
                scaleFrom: 0.88,
                child: Floating(
                  phase: 0.00,
                  amplitude: 5,
                  child: const _RoleNode(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'Admin',
                    sub: 'Web console',
                  ),
                ),
              ),
              Reveal(
                delay: Duration(milliseconds: 490),
                dy: 26,
                scaleFrom: 0.88,
                child: Floating(
                  phase: 0.33,
                  amplitude: 5,
                  child: const _RoleNode(
                    icon: Icons.groups_rounded,
                    label: 'Org Officers',
                    sub: 'Web console',
                  ),
                ),
              ),
              Reveal(
                delay: Duration(milliseconds: 620),
                dy: 26,
                scaleFrom: 0.88,
                child: Floating(
                  phase: 0.67,
                  amplitude: 5,
                  child: const _RoleNode(
                    icon: Icons.school_rounded,
                    label: 'Students & Guests',
                    sub: 'Mobile app',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Floating(
            amplitude: 4,
            period: Duration(milliseconds: 1600),
            child: const Icon(
              Icons.arrow_downward_rounded,
              size: 20,
              color: AdminSiteColors.inkFaint,
            ),
          ),
          const SizedBox(height: 10),
          Reveal(
            delay: Duration(milliseconds: 760),
            dy: 20,
            scaleFrom: 0.92,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: AdminSiteColors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.storage_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'One Firebase Backend — Auth · Firestore · Cloud Functions',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleNode extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;

  const _RoleNode({required this.icon, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: AdminSiteColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminSiteColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AdminSiteColors.primary),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AdminSiteColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10.5,
              color: AdminSiteColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
