import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../widgets/common/terms_and_conditions.dart';
import 'admin_about_page.dart';
import 'admin_help_page.dart';
import 'admin_login.dart';
import 'admin_site_chrome.dart';

// Single-page admin marketing site: one persistent Scaffold with a fixed
// nav bar, and Home/Features/About/Help as content that swaps in place
// (AnimatedSwitcher) below it — clicking a nav item never navigates to a
// new route, it just toggles which content is shown, same page throughout.
class AdminLandingPage extends StatefulWidget {
  const AdminLandingPage({super.key});

  @override
  State<AdminLandingPage> createState() => _AdminLandingPageState();
}

class _AdminLandingPageState extends State<AdminLandingPage>
    with SingleTickerProviderStateMixin {
  AdminSiteSection _section = AdminSiteSection.home;

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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminLogin()),
    );
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const TermsAndConditionsScreen(accent: AdminSiteColors.blue),
      ),
    );
  }

  void _select(AdminSiteSection s) {
    if (s == _section) return;
    setState(() => _section = s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminSiteColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            AdminSiteNavBar(
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
      case AdminSiteSection.home:
        return _HomeContent(
          onSelect: _select,
          onLogin: _goToLogin,
          onTerms: _openTerms,
          fade: _fade,
          slide: _slide,
          scrollTick: _scrollTick,
        );
      case AdminSiteSection.features:
        return _FeaturesContent(onSelect: _select, onTerms: _openTerms);
      case AdminSiteSection.about:
        return AdminAboutContent(onSelect: _select, onTerms: _openTerms);
      case AdminSiteSection.help:
        return AdminHelpContent(onSelect: _select, onTerms: _openTerms);
    }
  }
}

// ── HOME ────────────────────────────────────────────────────────────
class _HomeContent extends StatelessWidget {
  final ValueChanged<AdminSiteSection> onSelect;
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
        // The spine sits in a Stack alongside the section Column — a
        // separate widget outside any one section, so it visually threads
        // through every color band underneath it instead of being clipped
        // to whichever section happens to draw it.
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(context),
                const SectionSeam(from: AdminSiteColors.bg, to: Colors.white),
                _RevealOnVisible(tick: scrollTick, child: _buildStatStrip()),
                const SectionSeam(
                  from: Colors.white,
                  to: AdminSiteColors.primary,
                ),
                _RevealOnVisible(tick: scrollTick, child: _buildPullQuote()),
                const SectionSeam(
                  from: AdminSiteColors.primary,
                  to: AdminSiteColors.bg,
                ),
                _RevealOnVisible(
                  tick: scrollTick,
                  child: _buildFeaturesPreview(context),
                ),
                const SectionSeam(from: AdminSiteColors.bg, to: Colors.white),
                _RevealOnVisible(tick: scrollTick, child: _buildHowItWorks()),
                const SectionSeam(from: Colors.white, to: AdminSiteColors.blue),
                _RevealOnVisible(tick: scrollTick, child: _buildCtaBand()),
                const SectionSeam(
                  from: AdminSiteColors.blue,
                  to: AdminSiteColors.navy,
                ),
                AdminSiteFooter(onSelect: onSelect, onTerms: onTerms),
              ],
            ),
            const PageSpine(),
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
      // Container's clipBehavior assertion requires an explicit decoration,
      // not just `color` (which only becomes a decoration internally at
      // build time, after that assertion already runs) — this crashed the
      // whole page with "decoration != null || clipBehavior == Clip.none"
      // the moment clipBehavior was added below.
      decoration: const BoxDecoration(color: AdminSiteColors.bg),
      // The abstract diagonal streaks below are sized loosely (some run
      // past the corners on purpose, the way a poster bleeds off its own
      // edge) — clip them to the hero's own bounds so that never leaks
      // into the section above/below on a short viewport.
      clipBehavior: Clip.hardEdge,
      child: _MouseSpotlight(
        child: Stack(
          children: [
            // Abstract diagonal streaks, translated into the site's own
            // light palette (low-alpha blue/orange fading to transparent)
            // instead of copying a dark neon template wholesale — this is
            // what actually turns the flat dotted field into a background
            // with real motion and depth. The hero gets more of these than
            // any other section (6 vs. the standard 4 in
            // AbstractSectionBackdrop) since it's the one place meant to
            // make the strongest first impression.
            const Positioned(
              top: -40,
              right: 120,
              child: DiagonalStreak(
                width: 340,
                height: 34,
                angle: -0.55,
                colors: [Color(0x332563EB), Color(0x002563EB)],
              ),
            ),
            const Positioned(
              top: 90,
              right: -60,
              child: DiagonalStreak(
                width: 260,
                height: 26,
                angle: -0.55,
                colors: [Color(0x26F97316), Color(0x00F97316)],
              ),
            ),
            const Positioned(
              top: -20,
              right: 380,
              child: DiagonalStreak(
                width: 160,
                height: 16,
                angle: -0.55,
                colors: [Color(0x1F2563EB), Color(0x002563EB)],
              ),
            ),
            const Positioned(
              bottom: 40,
              left: -80,
              child: DiagonalStreak(
                width: 300,
                height: 30,
                angle: -0.5,
                colors: [Color(0x2A2563EB), Color(0x002563EB)],
              ),
            ),
            const Positioned(
              bottom: -30,
              left: 160,
              child: DiagonalStreak(
                width: 220,
                height: 22,
                angle: -0.5,
                colors: [Color(0x1FF97316), Color(0x00F97316)],
              ),
            ),
            const Positioned(
              bottom: 140,
              left: 40,
              child: DiagonalStreak(
                width: 140,
                height: 14,
                angle: -0.5,
                colors: [Color(0x182563EB), Color(0x002563EB)],
              ),
            ),
            const Positioned.fill(child: DotGridBackground()),
            // The right panel has its own warm glow behind the emblem —
            // the left column had nothing to match it, which is what read
            // as "empty" next to the much richer visual on the right.
            Positioned(
              top: -80,
              left: -120,
              child: IgnorePointer(
                child: Container(
                  width: 480,
                  height: 480,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AdminSiteColors.blue.withAlpha(20),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
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
                color: AdminSiteColors.primary.withAlpha(14),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AdminSiteColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.security_rounded,
                    size: 13,
                    color: AdminSiteColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SYSTEM ADMINISTRATION FOR CICT',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AdminSiteColors.primary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const LiveStatusBadge(),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'One console for the\nwhole CICT portal.',
          style: GoogleFonts.beVietnamPro(
            fontSize: wide ? 54 : 36,
            fontWeight: FontWeight.w800,
            color: AdminSiteColors.ink,
            height: 1.12,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 16),
        // Echoes the orange accent rule under the CICT emblem's name on
        // the right — a small, deliberate color rhyme tying the two
        // halves of the hero together instead of them reading as two
        // unrelated blocks side by side.
        Container(width: 44, height: 3, color: AdminSiteColors.orange),
        const SizedBox(height: 18),
        Text(
          'Provision accounts, review organizations and events, oversee '
          'reports, and keep an audit trail of everything that happens '
          'across the student portal.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 16,
            color: AdminSiteColors.inkSoft,
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
                    color: AdminSiteColors.blue.withAlpha(70),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: onLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminSiteColors.blue,
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
                      'Continue to Admin Login',
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
              onPressed: () => onSelect(AdminSiteSection.features),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminSiteColors.ink,
                side: BorderSide(color: AdminSiteColors.ink.withAlpha(60)),
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
        // Real chip cards instead of a thin row of plain text — that row
        // read as an afterthought and left the space beneath it looking
        // bare; these carry actual visual weight and fill the column the
        // way the CTA buttons above them do.
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in const [
              ('Bulacan State University · CICT', Icons.school_rounded),
              ('Firebase-Secured Accounts', Icons.verified_user_rounded),
              ('Full Audit Trail', Icons.fact_check_rounded),
            ])
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdminSiteColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AdminSiteColors.ink.withAlpha(8),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(c.$2, size: 14, color: AdminSiteColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      c.$1,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminSiteColors.inkSoft,
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

  // No campus/app-activity photo exists to put here, so rather than leave
  // a "photo goes here" stub forever, this panel makes CICT itself the
  // hero image — the college is the system's origin (every admin, org,
  // and event on UPRISE traces back to it), so its emblem earns center
  // stage instead of a generic screenshot.
  Widget _heroVisual() {
    return AspectRatio(
      // Was 4/5 — with the internal content now centered rather than
      // stretched across spaceBetween, that ratio left a visibly taller
      // panel than the (now more compact) content needed, and pushed the
      // bottom floating badge past typical viewport height.
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
                  colors: [AdminSiteColors.blueDeep, AdminSiteColors.navy],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AdminSiteColors.blue.withAlpha(60),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: const _CictEmblemPanel(),
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
          // The one deliberate spark of orange on this whole page.
          Positioned(
            bottom: 76,
            right: -16,
            child: _Bobbing(
              duration: const Duration(milliseconds: 2600),
              amplitude: 9,
              child: _FloatingBadge(
                icon: Icons.fact_check_rounded,
                label: '24/7 Activity Logs',
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
                icon: Icons.group_work_rounded,
                label: 'Every CICT Organization, One System',
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
      (Icons.groups_rounded, '3', '', 'Roles Managed', 'Admin · Org · Student'),
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
        'Every account, authenticated',
      ),
      (
        Icons.fact_check_rounded,
        null,
        '24/7',
        'Activity Logging',
        'Every action, on the record',
      ),
    ];

    return Container(
      color: Colors.white,
      child: AbstractSectionBackdrop(
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
  // A single, confident statement — a moment of visual quiet between the
  // stat strip and the feature grid, rather than uniform cards top to
  // bottom.
  Widget _buildPullQuote() {
    return Container(
      color: AdminSiteColors.primary,
      child: AbstractSectionBackdrop(
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
                    'every organization in the college.',
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
        Icons.group_work_rounded,
        'Organization Management',
        'Review, create, and manage every recognized CICT organization and its officer accounts.',
      ),
      (
        Icons.event_available_rounded,
        'Event Oversight',
        'Approve, reject, or archive event proposals submitted by organizations across the college.',
      ),
      (
        Icons.badge_rounded,
        'Student & Account Provisioning',
        'Create and manage student, guest, and officer accounts with temporary-password onboarding.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'FULL SYSTEM OVERSIGHT',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AdminSiteColors.blue,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'One console, every administrative task',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AdminSiteColors.ink,
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
                    onPressed: () => onSelect(AdminSiteSection.features),
                    style: TextButton.styleFrom(
                      foregroundColor: AdminSiteColors.blue,
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
        'Sign In Securely',
        'Access the console with your administrator credentials.',
      ),
      (
        '02',
        'Provision & Review',
        'Create accounts, review organizations, and approve pending event proposals.',
      ),
      (
        '03',
        'Oversee the System',
        'Track reports, monitor activity logs, and keep the whole portal running smoothly.',
      ),
    ];

    return Container(
      color: Colors.white,
      child: AbstractSectionBackdrop(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                children: [
                  Text(
                    'How administrators use UPRISE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AdminSiteColors.ink,
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
      color: AdminSiteColors.blue,
      child: AbstractSectionBackdrop(
        dark: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  Text(
                    'Ready to manage the system?',
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
                    'Sign in with your administrator credentials.',
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
                        foregroundColor: AdminSiteColors.blueDeep,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
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
  final ValueChanged<AdminSiteSection> onSelect;
  final VoidCallback onTerms;

  const _FeaturesContent({required this.onSelect, required this.onTerms});

  static const _features = [
    (
      Icons.group_work_rounded,
      'Organization Management',
      'Review, create, and manage every recognized CICT organization and '
          'its officer accounts.',
      [
        'Approve or archive organization records',
        'Assign advisers and track officer rosters',
        'One directory shared with every other module',
      ],
    ),
    (
      Icons.event_available_rounded,
      'Event Oversight',
      'Approve, reject, or archive event proposals submitted by '
          'organizations across the college.',
      [
        'Central queue for every pending proposal',
        'Organizations notified the moment a decision is made',
        'Published events feed straight into attendance & certificates',
      ],
    ),
    (
      Icons.badge_rounded,
      'Student & Account Provisioning',
      'Create and manage student, guest, and officer accounts with '
          'temporary-password onboarding.',
      [
        'Batch-import a whole class roster from one spreadsheet',
        'Temporary credentials emailed automatically',
        'Forced password change on first login',
      ],
    ),
    (
      Icons.summarize_rounded,
      'Reports Oversight',
      'Track financial and accomplishment report submissions against '
          'university deadlines.',
      [
        'One deadline calendar for every organization',
        'Submissions flagged the moment they\'re late',
        'Exportable for university records',
      ],
    ),
    (
      Icons.how_to_reg_rounded,
      'Guest & External Access',
      'Review guest applications and control who gets access to the '
          'platform from outside CICT.',
      [
        'Manual review before any guest account is created',
        'Scoped access — guests never see admin/org tooling',
        'Revocable at any time',
      ],
    ),
    (
      Icons.fact_check_rounded,
      'System Activity Logs',
      'Keep a full audit trail of significant actions taken across the '
          'entire portal.',
      [
        'Every approval, edit, and account change is logged',
        'Filterable by module, actor, and date',
        'Nothing happens off the record',
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
                child: AbstractSectionBackdrop(
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
                                color: AdminSiteColors.primary.withAlpha(14),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: AdminSiteColors.border,
                                ),
                              ),
                              child: Text(
                                'EVERYTHING IN THE CONSOLE',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AdminSiteColors.primary,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Six modules. One console.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: AdminSiteColors.ink,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Everything an admin needs to run CICT\'s student '
                              'portal, in detail.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 15,
                                color: AdminSiteColors.inkSoft,
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
              const SectionSeam(from: Colors.white, to: AdminSiteColors.bg),
              Container(
                color: AdminSiteColors.bg,
                child: AbstractSectionBackdrop(
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
              const SectionSeam(
                from: AdminSiteColors.bg,
                to: AdminSiteColors.navy,
              ),
              AdminSiteFooter(onSelect: onSelect, onTerms: onTerms),
            ],
          ),
          const PageSpine(),
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
        color: AdminSiteColors.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 38),
    );

    final copy = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            index.toString().padLeft(2, '0'),
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AdminSiteColors.blue,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AdminSiteColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13.5,
              color: AdminSiteColors.inkSoft,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AdminSiteColors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        color: AdminSiteColors.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminSiteColors.border),
      ),
      child: LayoutBuilder(
        builder: (_, c) {
          if (c.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [iconPanel, const SizedBox(height: 18), copy],
            );
          }
          final children = reversed
              ? [copy, const SizedBox(width: 32), iconPanel]
              : [iconPanel, const SizedBox(width: 32), copy];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
        },
      ),
    );
  }
}

// Small "floating chip overlapping a photo" card, the composition trick
// that carries the reference layout's energy — a pill of icon + label that
// sits half-off the photo edge instead of a plain decorative badge.
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
        color: accent ? AdminSiteColors.orange : Colors.white,
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
            color: accent ? Colors.white : AdminSiteColors.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent ? Colors.white : AdminSiteColors.ink,
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
                ? AdminSiteColors.blue.withAlpha(120)
                : AdminSiteColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovering
                  ? AdminSiteColors.blue.withAlpha(35)
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
                        ? AdminSiteColors.primary
                        : AdminSiteColors.bg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: _hovering
                          ? Colors.transparent
                          : AdminSiteColors.border,
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    color: _hovering ? Colors.white : AdminSiteColors.primary,
                    size: 22,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.index.toString().padLeft(2, '0'),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AdminSiteColors.border,
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
                color: AdminSiteColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                color: AdminSiteColors.inkSoft,
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
        color: AdminSiteColors.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminSiteColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: GoogleFonts.beVietnamPro(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AdminSiteColors.border,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AdminSiteColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              color: AdminSiteColors.inkSoft,
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
            color: AdminSiteColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminSiteColors.border),
          ),
          child: Icon(icon, size: 20, color: AdminSiteColors.primary),
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
                  color: AdminSiteColors.ink,
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
                          color: AdminSiteColors.ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                    )
                  : Text(
                      staticValue ?? '',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AdminSiteColors.ink,
                        letterSpacing: -0.5,
                      ),
                    ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: AdminSiteColors.inkSoft,
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

// Cursor-follow spotlight — a soft blue glow that tracks the pointer across
// the hero instead of sitting static, the signature "modern SaaS" touch
// (Linear/Vercel-style). Falls back to nothing (no pointer) on touch
// devices, which is fine — the hero still has the dot grid and CTA glows.
class _MouseSpotlight extends StatefulWidget {
  final Widget child;

  const _MouseSpotlight({required this.child});

  @override
  State<_MouseSpotlight> createState() => _MouseSpotlightState();
}

class _MouseSpotlightState extends State<_MouseSpotlight> {
  Offset? _pointer;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) => setState(() => _pointer = e.localPosition),
      onExit: (_) => setState(() => _pointer = null),
      child: Stack(
        children: [
          if (_pointer != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SpotlightPainter(center: _pointer!),
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Offset center;

  _SpotlightPainter({required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 280.0;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          AdminSiteColors.blue.withAlpha(55),
          AdminSiteColors.blue.withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.center != center;
}

// Continuous gentle up/down drift — makes the floating badges read as
// "alive" instead of static decoration.
// The hero visual's centerpiece — CICT's own emblem standing in for a
// campus/app photo that doesn't exist, dressed as a real designed panel
// (dot texture, radial glow, an expanding pulse ring behind the disc)
// rather than a bare logo dropped on a gradient.
class _CictEmblemPanel extends StatelessWidget {
  const _CictEmblemPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DotGridBackground(dotColor: Colors.white.withAlpha(18)),
        Center(
          child: Container(
            width: 300,
            height: 300,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x33F97316), Colors.transparent],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
          child: Column(
            // A naturally centered flow, not spaceBetween — that pattern
            // stretched three unrelated islands across the panel's full
            // height with dead gradient between them. There's also no
            // internal top label anymore (it used to sit right on top of
            // the "Firebase Secured" floating badge outside this panel,
            // reading as two competing pills instead of one clean corner).
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
                          padding: const EdgeInsets.all(17),
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
                            'assets/images/cict_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.school_rounded,
                              color: AdminSiteColors.blueDeep,
                              size: 46,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'COLLEGE OF INFORMATION AND\nCOMMUNICATIONS TECHNOLOGY',
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
                  Container(
                    width: 36,
                    height: 2,
                    color: AdminSiteColors.orange,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bulacan State University · Est. 2001',
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
              // What CICT "hands down to" — makes the emblem the root of a
              // small hierarchy instead of a logo floating with nothing
              // connected to it.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ONE COLLEGE, THREE PORTALS',
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
                      _PortalChip(
                        icon: Icons.admin_panel_settings_rounded,
                        label: 'Admin',
                      ),
                      const SizedBox(width: 10),
                      _PortalChip(
                        icon: Icons.groups_rounded,
                        label: 'Organizations',
                      ),
                      const SizedBox(width: 10),
                      _PortalChip(
                        icon: Icons.school_rounded,
                        label: 'Students',
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

// One node in the "hands down to" row under the CICT emblem.
class _PortalChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PortalChip({required this.icon, required this.label});

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

// A single expanding-and-fading ring, looped — reads as a soft radar
// pulse behind the emblem disc. Two instances staggered by `delay` (see
// _CictEmblemPanel) keep a ring perpetually mid-expansion instead of a
// visible reset gap between cycles.
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
      ..repeat();
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
      child: widget.child,
      builder: (_, child) {
        final dy = math.sin(_ctrl.value * 2 * math.pi) * widget.amplitude;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
    );
  }
}
