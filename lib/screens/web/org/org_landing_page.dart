import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../widgets/common/terms_and_conditions.dart';
import 'org_about_page.dart';
import 'org_help_page.dart';
import 'org_login.dart';
import 'org_site_chrome.dart';

// Structural mirror of the admin portal's marketing site
// (admin_landing_page.dart) — same persistent nav bar, same
// Home/Features/About/Help section-switcher (AnimatedSwitcher in place,
// never a route push), same hero/stat-strip/pull-quote/features-preview/
// how-it-works/CTA/footer layout. Only the palette (warm orange/cream
// instead of admin's cool slate/blue) and every word of copy differ — this
// page is about the organization, not the college admin office.
class OrgLandingPage extends StatefulWidget {
  const OrgLandingPage({super.key});

  @override
  State<OrgLandingPage> createState() => _OrgLandingPageState();
}

class _OrgLandingPageState extends State<OrgLandingPage>
    with SingleTickerProviderStateMixin {
  OrgSiteSection _section = OrgSiteSection.home;

  late final AnimationController _introCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  final ValueNotifier<int> _scrollTick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fade = CurvedAnimation(parent: _introCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(_fade);
    _introCtrl.forward();
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _scrollTick.dispose();
    super.dispose();
  }

  void _goToLogin() {
    // A plain push (not pushReplacement) so this landing page stays on the
    // stack underneath — the login page's own "Back" returns here with a
    // normal Navigator.pop() instead of jumping to the portal selector.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OrganizationLogin()),
    );
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const TermsAndConditionsScreen(accent: OrgSiteColors.accentDeep),
      ),
    );
  }

  void _select(OrgSiteSection s) {
    if (s == _section) return;
    setState(() => _section = s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OrgSiteColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            OrgSiteNavBar(
              current: _section,
              onSelect: _select,
              onLogin: _goToLogin,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_section),
                  child: _buildSection(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    switch (_section) {
      case OrgSiteSection.home:
        return _HomeContent(
          onSelect: _select,
          onLogin: _goToLogin,
          onTerms: _openTerms,
          fade: _fade,
          slide: _slide,
          scrollTick: _scrollTick,
        );
      case OrgSiteSection.features:
        return _FeaturesContent(onSelect: _select, onTerms: _openTerms);
      case OrgSiteSection.about:
        return OrgAboutContent(onSelect: _select, onTerms: _openTerms);
      case OrgSiteSection.help:
        return OrgHelpContent(onSelect: _select, onTerms: _openTerms);
    }
  }
}

// ── HOME ────────────────────────────────────────────────────────────
class _HomeContent extends StatelessWidget {
  final ValueChanged<OrgSiteSection> onSelect;
  final VoidCallback onLogin;
  final VoidCallback onTerms;
  final Animation<double> fade;
  final Animation<Offset> slide;
  final ValueNotifier<int> scrollTick;

  const _HomeContent({
    required this.onSelect,
    required this.onLogin,
    required this.onTerms,
    required this.fade,
    required this.slide,
    required this.scrollTick,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        scrollTick.value++;
        return false;
      },
      child: SingleChildScrollView(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(context),
                const OrgSectionSeam(
                  from: Color(0xFFFDF0E4),
                  to: OrgSiteColors.bg,
                ),
                _RevealOnVisible(tick: scrollTick, child: _buildStatStrip()),
                const OrgSectionSeam(from: OrgSiteColors.bg, to: Colors.white),
                _RevealOnVisible(tick: scrollTick, child: _buildPullQuote()),
                const OrgSectionSeam(
                  from: OrgSiteColors.slateDark,
                  to: OrgSiteColors.bg,
                ),
                _RevealOnVisible(
                  tick: scrollTick,
                  child: _buildFeaturesPreview(context),
                ),
                const OrgSectionSeam(from: OrgSiteColors.bg, to: Colors.white),
                _RevealOnVisible(tick: scrollTick, child: _buildHowItWorks()),
                const OrgSectionSeam(
                  from: Colors.white,
                  to: OrgSiteColors.accentDeep,
                ),
                _RevealOnVisible(tick: scrollTick, child: _buildCtaBand()),
                const OrgSectionSeam(
                  from: OrgSiteColors.accent,
                  to: OrgSiteColors.navy,
                ),
                OrgSiteFooter(onSelect: onSelect, onTerms: onTerms),
              ],
            ),
            const OrgPageSpine(),
          ],
        ),
      ),
    );
  }

  // ── HERO ──────────────────────────────────────────────────────────
  Widget _buildHero(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(minHeight: viewportHeight * 0.78),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF7), Color(0xFFFDF0E4)],
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          const Positioned(
            top: -160,
            right: -140,
            child: _HeroGlow(size: 560, color: Color(0x46F97316)),
          ),
          const Positioned(
            bottom: -200,
            left: -180,
            child: _HeroGlow(size: 520, color: Color(0x28EA580C)),
          ),
          const Positioned.fill(
            child: OrgDotGridBackground(dotColor: Color(0x14EA580C)),
          ),
          const Positioned(
            top: -40,
            right: 120,
            child: OrgDiagonalStreak(
              width: 340,
              height: 34,
              angle: -0.55,
              colors: [Color(0x33F97316), Color(0x00F97316)],
            ),
          ),
          const Positioned(
            top: 90,
            right: -60,
            child: OrgDiagonalStreak(
              width: 260,
              height: 26,
              angle: -0.55,
              colors: [Color(0x26EA580C), Color(0x00EA580C)],
            ),
          ),
          const Positioned(
            bottom: 40,
            left: -80,
            child: OrgDiagonalStreak(
              width: 300,
              height: 30,
              angle: -0.5,
              colors: [Color(0x2AF97316), Color(0x00F97316)],
            ),
          ),
          const Positioned(
            bottom: -30,
            left: 160,
            child: OrgDiagonalStreak(
              width: 220,
              height: 22,
              angle: -0.5,
              colors: [Color(0x1FEA580C), Color(0x00EA580C)],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: LayoutBuilder(
                  builder: (_, c) {
                    final wide = c.maxWidth >= 900;
                    final headline = FadeTransition(
                      opacity: fade,
                      child: SlideTransition(
                        position: slide,
                        child: _heroCopy(wide),
                      ),
                    );
                    final visual = FadeTransition(
                      opacity: fade,
                      child: _heroVisual(),
                    );
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 6, child: headline),
                              const SizedBox(width: 24),
                              Expanded(flex: 5, child: visual),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              headline,
                              const SizedBox(height: 36),
                              visual,
                            ],
                          );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCopy(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: OrgSiteColors.accentDeep.withAlpha(14),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: OrgSiteColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.domain_rounded,
                    size: 13,
                    color: OrgSiteColors.accentDeep,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ORGANIZATION MANAGEMENT PORTAL',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: OrgSiteColors.accentDeep,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const OrgLiveStatusBadge(),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'One workspace for your\nwhole organization.',
          style: GoogleFonts.beVietnamPro(
            fontSize: wide ? 54 : 36,
            fontWeight: FontWeight.w800,
            color: OrgSiteColors.ink,
            height: 1.12,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 16),
        Container(width: 44, height: 3, color: OrgSiteColors.accentDeep),
        const SizedBox(height: 18),
        Text(
          'Plan events, run attendance, issue certificates, and keep your '
          'members and reports organized — all under one login.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 16,
            color: OrgSiteColors.inkSoft,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: OrgSiteColors.accentDeep.withAlpha(70),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: onLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: OrgSiteColors.accentDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Continue to Org Login',
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () => onSelect(OrgSiteSection.features),
              style: OutlinedButton.styleFrom(
                foregroundColor: OrgSiteColors.ink,
                side: BorderSide(color: OrgSiteColors.ink.withAlpha(60)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'See what\'s inside',
                style: GoogleFonts.beVietnamPro(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in const [
              ('CICT-Recognized Organization', Icons.verified_rounded),
              ('Firebase-Secured Accounts', Icons.verified_user_rounded),
              ('Real-Time Everywhere', Icons.bolt_rounded),
            ])
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: OrgSiteColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: OrgSiteColors.ink.withAlpha(8),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(c.$2, size: 14, color: OrgSiteColors.accentDeep),
                    const SizedBox(width: 8),
                    Text(
                      c.$1,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: OrgSiteColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // No single "client" logo represents an organization the way CICT's
  // emblem represents the admin office, so the hero's centerpiece here is
  // the app itself — UPRISE is the shared workspace every org's officers
  // actually log into, cascading down to the three things an org spends
  // most of its time on.
  Widget _heroVisual() {
    return AspectRatio(
      aspectRatio: 4 / 4.3,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [OrgSiteColors.accentDeep, OrgSiteColors.navy],
                ),
                boxShadow: [
                  BoxShadow(
                    color: OrgSiteColors.accentDeep.withAlpha(60),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: const _OrgEmblemPanel(),
              ),
            ),
          ),
          Positioned(
            top: 20,
            left: -18,
            child: _Bobbing(
              duration: const Duration(milliseconds: 3200),
              amplitude: 7,
              child: _FloatingBadge(
                icon: Icons.verified_user_rounded,
                label: 'Firebase Secured',
              ),
            ),
          ),
          Positioned(
            bottom: 76,
            right: -16,
            child: _Bobbing(
              duration: const Duration(milliseconds: 2600),
              amplitude: 9,
              child: _FloatingBadge(
                icon: Icons.qr_code_scanner_rounded,
                label: 'Live QR Attendance',
                accent: true,
              ),
            ),
          ),
          Positioned(
            bottom: -18,
            left: 24,
            right: 24,
            child: _Bobbing(
              duration: const Duration(milliseconds: 3800),
              amplitude: 5,
              child: _FloatingBadge(
                icon: Icons.workspace_premium_rounded,
                label: 'Certificates, Verified Instantly',
                wide: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STAT STRIP ────────────────────────────────────────────────────
  Widget _buildStatStrip() {
    const stats = [
      (
        Icons.event_note_rounded,
        '6',
        '',
        'Core Modules',
        'Proposals · Attendance · Certificates',
      ),
      (
        Icons.bolt_rounded,
        null,
        'Real-Time',
        'Data Sync',
        'Firestore-backed, live everywhere',
      ),
      (
        Icons.lock_rounded,
        '100',
        '%',
        'Firebase Secured',
        'Every officer account, authenticated',
      ),
      (
        Icons.fact_check_rounded,
        null,
        '24/7',
        'Activity Logging',
        'Every submission, on the record',
      ),
    ];

    return Container(
      color: Colors.white,
      child: OrgAbstractBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 24,
                children: [
                  for (final s in stats)
                    SizedBox(
                      width: 260,
                      child: _StatCard(
                        icon: s.$1,
                        numericValue: s.$2 == null ? null : int.parse(s.$2!),
                        staticValue: s.$2 == null ? s.$3 : null,
                        suffix: s.$2 == null ? '' : s.$3,
                        label: s.$4,
                        sub: s.$5,
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

  // ── PULL QUOTE ────────────────────────────────────────────────────
  Widget _buildPullQuote() {
    return Container(
      color: OrgSiteColors.slateDark,
      child: OrgAbstractBackdrop(
        dark: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                children: [
                  Icon(
                    Icons.format_quote_rounded,
                    color: Colors.white.withAlpha(90),
                    size: 32,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Built to replace paper event forms and scattered '
                    'spreadsheets with a single system of record — for '
                    'your organization and everyone in it.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.5,
                      letterSpacing: -0.2,
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

  // ── FEATURES PREVIEW ─────────────────────────────────────────────
  Widget _buildFeaturesPreview(BuildContext context) {
    const preview = [
      (
        Icons.event_available_rounded,
        'Event Proposals & Approval',
        'Submit event proposals and track their status through admin review, all in one thread.',
      ),
      (
        Icons.qr_code_scanner_rounded,
        'QR & Webinar Attendance',
        'Run check-in/check-out with live rotating codes for both on-site and online sessions.',
      ),
      (
        Icons.workspace_premium_rounded,
        'Certificates & Verification',
        'Issue certificates after attendance and feedback are verified, each with a public code.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'EVERYTHING YOUR ORG NEEDS',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: OrgSiteColors.accentDeep,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'One dashboard, every organizational task',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: OrgSiteColors.ink,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < preview.length; i++)
                        _FeatureCard(
                          index: i + 1,
                          icon: preview[i].$1,
                          title: preview[i].$2,
                          subtitle: preview[i].$3,
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  TextButton(
                    onPressed: () => onSelect(OrgSiteSection.features),
                    style: TextButton.styleFrom(
                      foregroundColor: OrgSiteColors.accentDeep,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See all 6 features',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
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

  // ── HOW IT WORKS ──────────────────────────────────────────────────
  Widget _buildHowItWorks() {
    const steps = [
      (
        '01',
        'Get Provisioned',
        'The CICT Admin creates your officer account and hands you a temporary password.',
      ),
      (
        '02',
        'Set Up Your Org',
        'Log in, set your permanent password, and complete your organization\'s profile.',
      ),
      (
        '03',
        'Run Everything',
        'Plan events, track attendance, issue certificates, and submit reports — all in one place.',
      ),
    ];

    return Container(
      color: Colors.white,
      child: OrgAbstractBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                children: [
                  Text(
                    'Up and running in three steps',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: OrgSiteColors.ink,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 36),
                  LayoutBuilder(
                    builder: (_, c) {
                      final wide = c.maxWidth >= 800;
                      final cards = [
                        for (final s in steps)
                          SizedBox(
                            width: wide
                                ? (c.maxWidth - 48) / 3
                                : double.infinity,
                            child: _StepCard(
                              number: s.$1,
                              title: s.$2,
                              body: s.$3,
                            ),
                          ),
                      ];
                      return wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: cards,
                            )
                          : Column(
                              children: [
                                for (final card in cards) ...[
                                  card,
                                  const SizedBox(height: 16),
                                ],
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

  // ── CTA BAND ──────────────────────────────────────────────────────
  Widget _buildCtaBand() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [OrgSiteColors.accentDeep, OrgSiteColors.accent],
        ),
      ),
      child: OrgAbstractBackdrop(
        dark: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  Text(
                    'Ready to manage your organization?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sign in with the credentials issued by your CICT Admin.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      color: Colors.white.withAlpha(230),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(40),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: TextButton(
                      onPressed: onLogin,
                      style: TextButton.styleFrom(
                        foregroundColor: OrgSiteColors.accentDeep,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Continue to Org Login',
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
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
}

// ── FEATURES (dedicated section) ───────────────────────────────────
class _FeaturesContent extends StatelessWidget {
  final ValueChanged<OrgSiteSection> onSelect;
  final VoidCallback onTerms;

  const _FeaturesContent({required this.onSelect, required this.onTerms});

  static const _features = [
    (
      Icons.event_available_rounded,
      'Event Proposals & Approval',
      'Submit event proposals and track their status through admin review, '
          'all in one thread.',
      [
        'Draft a proposal with date, venue, and target audience',
        'Track approval status in real time — no more email chains',
        'Approved proposals feed straight into Events & Schedules',
      ],
    ),
    (
      Icons.qr_code_scanner_rounded,
      'QR & Webinar Attendance',
      'Run check-in/check-out with live rotating codes for both on-site '
          'and online sessions.',
      [
        'Rotating QR codes prevent screenshot sharing between attendees',
        'Webinar mode tracks join/leave time for online sessions',
        'Late-arrival logic applied automatically from your own settings',
      ],
    ),
    (
      Icons.workspace_premium_rounded,
      'Certificates & Verification',
      'Issue certificates after attendance and feedback are verified, each '
          'with a public verification code.',
      [
        'Gated on attendance + feedback — no certificate without both',
        'Bulk-send to every eligible attendee in one action',
        'Each certificate carries a publicly verifiable code',
      ],
    ),
    (
      Icons.receipt_long_rounded,
      'Financial & Accomplishment Reports',
      'Submit and track financial and accomplishment reports against '
          'university deadlines.',
      [
        'One deadline calendar tied to each finished event',
        'Submissions flagged the moment they\'re overdue',
        'Full history kept for university audit records',
      ],
    ),
    (
      Icons.campaign_rounded,
      'Announcements & Broadcast',
      'Reach your members with announcements and one-way broadcast '
          'messages.',
      [
        'Post announcements visible to your members\' mobile app',
        'One-way broadcast messaging, no reply-all clutter',
        'Pin important announcements to keep them on top',
      ],
    ),
    (
      Icons.groups_2_rounded,
      'Member & Officer Tools',
      'Keep your organization\'s roster, events, and activity organized in '
          'one workspace.',
      [
        'Officer roster shared across every module automatically',
        'Every action logged — nothing happens off the record',
        'One profile for your organization, used everywhere',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
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
                                'EVERYTHING IN THE WORKSPACE',
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
                              'Six modules. One workspace.',
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
                              'Everything your organization needs to run '
                              'events, attendance, and reporting, in detail.',
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
              ),
              const OrgSectionSeam(from: Colors.white, to: OrgSiteColors.bg),
              Container(
                color: OrgSiteColors.bg,
                child: OrgAbstractBackdrop(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          children: [
                            for (var i = 0; i < _features.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: _FeatureDetailRow(
                                  index: i + 1,
                                  icon: _features[i].$1,
                                  title: _features[i].$2,
                                  description: _features[i].$3,
                                  bullets: _features[i].$4,
                                  reversed: i.isOdd,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const OrgSectionSeam(
                from: OrgSiteColors.bg,
                to: OrgSiteColors.navy,
              ),
              OrgSiteFooter(onSelect: onSelect, onTerms: onTerms),
            ],
          ),
          const OrgPageSpine(),
        ],
      ),
    );
  }
}

class _FeatureDetailRow extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String description;
  final List<String> bullets;
  final bool reversed;

  const _FeatureDetailRow({
    required this.index,
    required this.icon,
    required this.title,
    required this.description,
    required this.bullets,
    required this.reversed,
  });

  @override
  Widget build(BuildContext context) {
    final iconPanel = Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: OrgSiteColors.accentDeep,
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 38),
    );

    final copy = Expanded(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OrgSiteColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  index.toString().padLeft(2, '0'),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: OrgSiteColors.accentDeep,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: OrgSiteColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                color: OrgSiteColors.inkSoft,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            for (final b in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: OrgSiteColors.accentDeep,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: OrgSiteColors.ink,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (_, c) {
        final wide = c.maxWidth >= 640;
        if (!wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [iconPanel, const SizedBox(width: 20), copy],
          );
        }
        final children = reversed
            ? [copy, const SizedBox(width: 28), iconPanel]
            : [iconPanel, const SizedBox(width: 28), copy];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}

// ── Small shared widgets — same visual family as admin's, org copy ──

class _HeroGlow extends StatelessWidget {
  final double size;
  final Color color;
  const _HeroGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      ),
    );
  }
}

class _FloatingBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final bool wide;

  const _FloatingBadge({
    required this.icon,
    required this.label,
    this.accent = false,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent ? OrgSiteColors.accentDeep : Colors.white,
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: accent ? Colors.white : OrgSiteColors.accentDeep,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent ? Colors.white : OrgSiteColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final int index;
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 340,
        padding: const EdgeInsets.all(22),
        transform: Matrix4.translationValues(0, _hovering ? -6 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hovering
                ? OrgSiteColors.accentDeep.withAlpha(120)
                : OrgSiteColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovering
                  ? OrgSiteColors.accentDeep.withAlpha(35)
                  : Colors.black.withAlpha(8),
              blurRadius: _hovering ? 26 : 14,
              offset: Offset(0, _hovering ? 12 : 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _hovering
                        ? OrgSiteColors.accentDeep
                        : OrgSiteColors.bg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: _hovering
                          ? Colors.transparent
                          : OrgSiteColors.border,
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    color: _hovering ? Colors.white : OrgSiteColors.accentDeep,
                    size: 22,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.index.toString().padLeft(2, '0'),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: OrgSiteColors.border,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: GoogleFonts.beVietnamPro(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: OrgSiteColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                color: OrgSiteColors.inkSoft,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: OrgSiteColors.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OrgSiteColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: GoogleFonts.beVietnamPro(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: OrgSiteColors.border,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: OrgSiteColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              color: OrgSiteColors.inkSoft,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final int? numericValue;
  final String? staticValue;
  final String suffix;
  final String label;
  final String sub;

  const _StatCard({
    required this.icon,
    this.numericValue,
    this.staticValue,
    this.suffix = '',
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: OrgSiteColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: OrgSiteColors.border),
          ),
          child: Icon(icon, size: 20, color: OrgSiteColors.accentDeep),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: OrgSiteColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              numericValue != null
                  ? TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: numericValue),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, __) => Text(
                        '$value$suffix',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: OrgSiteColors.ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                    )
                  : Text(
                      staticValue ?? '',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: OrgSiteColors.ink,
                        letterSpacing: -0.5,
                      ),
                    ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: OrgSiteColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Fades + slides a section in the first time it scrolls within reach of the
// viewport, then leaves it alone.
class _RevealOnVisible extends StatefulWidget {
  final Widget child;
  final ValueListenable<int> tick;

  const _RevealOnVisible({required this.child, required this.tick});

  @override
  State<_RevealOnVisible> createState() => _RevealOnVisibleState();
}

class _RevealOnVisibleState extends State<_RevealOnVisible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(_fade);
    widget.tick.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_triggered || !mounted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final position = renderObject.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    if (position.dy < screenHeight * 0.85) {
      _triggered = true;
      widget.tick.removeListener(_check);
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    widget.tick.removeListener(_check);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _Bobbing extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double amplitude;

  const _Bobbing({
    required this.child,
    required this.duration,
    required this.amplitude,
  });

  @override
  State<_Bobbing> createState() => _BobbingState();
}

class _BobbingState extends State<_Bobbing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        return Transform.translate(
          offset: Offset(0, (_ctrl.value - 0.5) * 2 * widget.amplitude),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// The hero visual's centerpiece — UPRISE's own app mark standing in for a
// campus/app photo, since no single logo represents "an organization" the
// way CICT's emblem represents the admin office. Reinforces that this is
// the one shared system every org's officers actually use, cascading down
// to the three things an org spends most of its time on.
class _OrgEmblemPanel extends StatelessWidget {
  const _OrgEmblemPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        OrgDotGridBackground(dotColor: Colors.white.withAlpha(18)),
        Center(
          child: Container(
            width: 300,
            height: 300,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x33FFFFFF), Colors.transparent],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _PulseRing(
                          size: 170,
                          color: Colors.white.withAlpha(60),
                        ),
                        _PulseRing(
                          size: 170,
                          color: Colors.white.withAlpha(60),
                          delay: const Duration(milliseconds: 1000),
                        ),
                        Container(
                          width: 124,
                          height: 124,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(70),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.domain_rounded,
                              color: OrgSiteColors.accentDeep,
                              size: 46,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'YOUR ORGANIZATION\'S\nWORKSPACE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.5,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(width: 36, height: 2, color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    'One login, everything connected',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withAlpha(160),
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'EVERYTHING YOUR TEAM RUNS',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withAlpha(130),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PillarChip(
                        icon: Icons.event_note_rounded,
                        label: 'Events',
                      ),
                      SizedBox(width: 10),
                      _PillarChip(icon: Icons.groups_rounded, label: 'Members'),
                      SizedBox(width: 10),
                      _PillarChip(
                        icon: Icons.receipt_long_rounded,
                        label: 'Reports',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PillarChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PillarChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white.withAlpha(220)),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(190),
            ),
          ),
        ],
      ),
    );
  }
}

// A single expanding-and-fading ring, looped — reads as a soft radar pulse
// behind the emblem disc.
class _PulseRing extends StatefulWidget {
  final double size;
  final Color color;
  final Duration delay;
  const _PulseRing({
    required this.size,
    required this.color,
    this.delay = Duration.zero,
  });

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Container(
            width: widget.size * (0.7 + t * 0.4),
            height: widget.size * (0.7 + t * 0.4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: widget.color, width: 1.5),
            ),
          ),
        );
      },
    );
  }
}
