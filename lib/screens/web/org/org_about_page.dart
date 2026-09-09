import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'org_site_chrome.dart';

// Structural mirror of the admin portal's About page (admin_about_page.dart)
// — same one-continuous-narrative shape (system → researchers → institution
// → organizations), same dark full-bleed team band and plain pull-quote
// break. Only the palette and copy are org-specific.
class OrgAboutContent extends StatefulWidget {
  final ValueChanged<OrgSiteSection> onSelect;
  final VoidCallback onTerms;

  const OrgAboutContent({
    required this.onSelect,
    required this.onTerms,
    super.key,
  });

  @override
  State<OrgAboutContent> createState() => _OrgAboutContentState();
}

class _OrgAboutContentState extends State<OrgAboutContent> {
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
              const OrgSectionSeam(from: Colors.white, to: OrgSiteColors.bg),
              _buildSystem(),
              const OrgSectionSeam(from: OrgSiteColors.bg, to: Colors.white),
              _buildComparison(),
              const OrgSectionSeam(from: Colors.white, to: OrgSiteColors.navy),
              _buildResearchers(),
              const OrgSectionSeam(
                from: OrgSiteColors.navy,
                to: OrgSiteColors.bg,
              ),
              _buildInstitution(),
              const OrgSectionSeam(from: OrgSiteColors.bg, to: Colors.white),
              _buildOrgWall(),
              const OrgSectionSeam(from: Colors.white, to: OrgSiteColors.navy),
              OrgSiteFooter(onSelect: widget.onSelect, onTerms: widget.onTerms),
            ],
          ),
          const OrgPageSpine(),
        ],
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      child: OrgAbstractBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: OrgSiteColors.accentDeep.withAlpha(14),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: OrgSiteColors.border),
                    ),
                    child: Text(
                      'ABOUT UPRISE',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: OrgSiteColors.accentDeep,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Built for your organization, from the ground up',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: OrgSiteColors.ink,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'One system, explained: what it replaces, who built it, '
                    'and who it serves.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      color: OrgSiteColors.inkSoft,
                      height: 1.6,
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
        'Officers get this web console; your members and guests get the '
            'mobile app — all reading and writing the same live Firebase '
            'data, never out of sync.',
      ),
      (
        'Role-based access, enforced end to end',
        'Every account is routed and gated by its role the moment it '
            'signs in — no shared logins, no manual permission juggling.',
      ),
      (
        'Nothing happens off the record',
        'Every proposal, certificate, and report your organization '
            'submits is written to a permanent activity log.',
      ),
    ];

    return Container(
      color: OrgSiteColors.bg,
      child: OrgAbstractBackdrop(
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
                      _eyebrow('01 · THE SYSTEM'),
                      const SizedBox(height: 10),
                      Text(
                        'A system, not a spreadsheet',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: OrgSiteColors.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      for (var i = 0; i < points.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '0${i + 1}',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: OrgSiteColors.accentDeep,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      points[i].$1,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: OrgSiteColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      points[i].$2,
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 12.5,
                                        color: OrgSiteColors.inkSoft,
                                        height: 1.55,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                  const diagram = _RoleDiagram();
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
        color: OrgSiteColors.accentDeep,
        letterSpacing: 1.4,
      ),
    );
  }

  // ── WHAT UPRISE REPLACES ────────────────────────────────────────────
  Widget _buildComparison() {
    const rows = [
      ('Paper event forms', 'In-app proposal → approval flow'),
      (
        'Manual attendance sheets',
        'QR & webinar check-in with live rotating codes',
      ),
      (
        'Printed certificates, no proof',
        'Digital certificates, publicly verifiable',
      ),
      ('Emailed financial reports', 'In-app submission with deadline tracking'),
    ];

    return Container(
      color: Colors.white,
      child: OrgAbstractBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _eyebrow('WHAT IT REPLACES'),
                  const SizedBox(height: 10),
                  Text(
                    'Before → After',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: OrgSiteColors.ink,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  for (var i = 0; i < rows.length; i++) ...[
                    LayoutBuilder(
                      builder: (_, c) {
                        final wide = c.maxWidth >= 480;
                        final before = Text(
                          rows[i].$1,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13.5,
                            color: OrgSiteColors.inkFaint,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: OrgSiteColors.inkFaint,
                          ),
                        );
                        final after = Text(
                          rows[i].$2,
                          textAlign: wide ? TextAlign.right : TextAlign.left,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: OrgSiteColors.ink,
                          ),
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: wide
                              ? Row(
                                  children: [
                                    Expanded(child: before),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 16,
                                        color: OrgSiteColors.accentDeep,
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
                      const Divider(height: 1, color: OrgSiteColors.border),
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
    const team = [
      (
        'Claudine Joy San Jose',
        'Leader · Web Developer · Documentation',
        'assets/images/team/claudine.jpg',
      ),
      (
        'Jayson Labor',
        'Assistant Leader · Web Developer · Documentation',
        'assets/images/team/jayson.jpg',
      ),
      (
        'Paul Arvin Castro',
        'UI/UX · Mobile Developer',
        'assets/images/team/paul.jpg',
      ),
      (
        'Arvin Joseph De Honor',
        'UI/UX · Mobile Developer',
        'assets/images/team/arvin.jpg',
      ),
      (
        'Carl Adrian Rivera',
        'UI/UX · Mobile Developer',
        'assets/images/team/carl.jpg',
      ),
    ];

    return Container(
      width: double.infinity,
      color: OrgSiteColors.navy,
      child: OrgAbstractBackdrop(
        dark: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                children: [
                  Text(
                    '02 · THE RESEARCHERS',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: OrgSiteColors.accent,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Built by the team behind UPRISE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 44),
                  Wrap(
                    spacing: 32,
                    runSpacing: 32,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final t in team)
                        _ResearcherPhotoCard(
                          name: t.$1,
                          role: t.$2,
                          imagePath: t.$3,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── THE INSTITUTION — plain pull-quote, no card chrome ─────────────
  Widget _buildInstitution() {
    return Container(
      color: OrgSiteColors.bg,
      child: OrgAbstractBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: OrgSiteColors.ink.withAlpha(20),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/cict_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.school_rounded,
                        color: OrgSiteColors.accentDeep,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '03 · THE INSTITUTION',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: OrgSiteColors.accentDeep,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'One recognized organization among many.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: OrgSiteColors.ink,
                      height: 1.3,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Your organization operates under Bulacan State '
                    'University\'s College of Information and '
                    'Communications Technology — coordinated through a '
                    'single admin office alongside every other recognized '
                    'student organization on the system.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14.5,
                      color: OrgSiteColors.inkSoft,
                      height: 1.7,
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
      child: OrgAbstractBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                children: [
                  Text(
                    '04 · ON UPRISE TODAY',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: OrgSiteColors.accentDeep,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Organizations already on the system',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: OrgSiteColors.ink,
                      letterSpacing: -0.4,
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
                            color: OrgSiteColors.accentDeep,
                          ),
                        );
                      }
                      final orgs = snap.data ?? const [];
                      if (orgs.isEmpty) {
                        return Text(
                          'No organizations are registered yet.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: OrgSiteColors.inkSoft,
                          ),
                        );
                      }
                      return Wrap(
                        spacing: 40,
                        runSpacing: 36,
                        alignment: WrapAlignment.center,
                        children: [for (final org in orgs) _OrgBadge(org: org)],
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
              color: OrgSiteColors.ink,
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
        color: OrgSiteColors.bg,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: OrgSiteColors.border)),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.beVietnamPro(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: OrgSiteColors.accentDeep,
        ),
      ),
    );
  }
}

// Individual headshot placeholder + name/role — same team as the admin
// portal's About page (this is the same UPRISE, not a different product).
class _ResearcherPhotoCard extends StatelessWidget {
  final String name;
  final String role;
  final String imagePath;

  const _ResearcherPhotoCard({
    required this.name,
    required this.role,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: 108,
              height: 108,
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(14),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withAlpha(40)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 38,
                    color: Colors.white.withAlpha(110),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            role,
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10.5,
              color: Colors.white.withAlpha(150),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// Visual echoing the real role split (org officer web console vs.
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
        border: Border.all(color: OrgSiteColors.border),
      ),
      child: Column(
        children: [
          const Wrap(
            spacing: 12,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _RoleNode(
                icon: Icons.domain_rounded,
                label: 'Your Org',
                sub: 'Web console',
              ),
              _RoleNode(
                icon: Icons.admin_panel_settings_rounded,
                label: 'CICT Admin',
                sub: 'Web console',
              ),
              _RoleNode(
                icon: Icons.school_rounded,
                label: 'Members & Guests',
                sub: 'Mobile app',
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Icon(
            Icons.arrow_downward_rounded,
            size: 20,
            color: OrgSiteColors.inkFaint,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: OrgSiteColors.slateDark,
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
        color: OrgSiteColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OrgSiteColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: OrgSiteColors.accentDeep),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: OrgSiteColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10.5,
              color: OrgSiteColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
