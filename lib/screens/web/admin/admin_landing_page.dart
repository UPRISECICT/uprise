import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../widgets/common/terms_and_conditions.dart';
import 'admin_login.dart';

// Full marketing-style landing page for the Admin portal: a light hero
// (soft gray/blue background, no dark navy backdrop) built around the real
// UPRISE logo, matching the light palette AdminLogin already uses. Gray/
// slate stays structural, blue carries the interactive CTA. Feature/steps
// sections, a CTA band, and a dark footer follow below. Navigation target
// (AdminLogin) is unchanged from earlier versions.

class AdminLandingPage extends StatefulWidget {
  const AdminLandingPage({super.key});

  @override
  State<AdminLandingPage> createState() => _AdminLandingPageState();
}

class _AdminLandingPageState extends State<AdminLandingPage>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF1E293B);
  static const Color _primaryDeep = Color(0xFF0B1120);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _blueDeep = Color(0xFF1E40AF);
  static const Color _navyDeep = Color(0xFF0B1120);
  static const Color _slateDark = Color(0xFF111827);
  static const Color _slateMid = Color(0xFF6B7280);
  static const Color _slateSoft = Color(0xFFAEB4C4);
  static const Color _lightBg = Color(0xFFF8FAFC);
  // Hero-specific light tones — a soft gray/blue background instead of a
  // dark navy backdrop.
  static const Color _heroBg = Color(0xFFFAFBFD);
  static const Color _heroBgDeep = Color(0xFFE9EFF8);

  late final AnimationController _introCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _featuresKey = GlobalKey();

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
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AdminLogin()),
    );
  }

  void _scrollToFeatures() {
    final ctx = _featuresKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TermsAndConditionsScreen(accent: _blueDeep),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightBg,
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        child: Column(
          // Column defaults to centering children at their intrinsic width —
          // without this, every section (including the dark hero) shrinks to
          // its content width instead of spanning the full browser viewport.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(context),
            _buildFeatures(context),
            _buildHowItWorks(context),
            _buildCtaBand(context),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  // ── HERO ──────────────────────────────────────────────────────────
  // Fills the full browser viewport on first load — a proper full-screen
  // hero, not a short strip that lets the next section peek in before the
  // user scrolls.
  Widget _buildHero(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(minHeight: viewportHeight),
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_heroBg, _heroBgDeep],
        ),
      ),
      child: Stack(
        children: [
          // Large soft glows — blue is the interactive accent, gray/slate
          // stays structural, matching the rest of the admin portal.
          Positioned(
            top: -160,
            right: -140,
            child: _heroGlow(560, _blue.withAlpha(55)),
          ),
          Positioned(
            bottom: -200,
            left: -180,
            child: _heroGlow(520, _primary.withAlpha(25)),
          ),
          // Faint decorative rings echoing the gear-ring shape of the real
          // logo — texture for the open space instead of a flat void.
          Positioned(top: 90, left: -60, child: _ringTexture(180)),
          Positioned(bottom: 40, right: 60, child: _ringTexture(120)),
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: viewportHeight,
              child: Column(
                children: [
                  _buildNavBar(context),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 24,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: LayoutBuilder(
                            builder: (_, c) {
                              final wide = c.maxWidth >= 900;
                              final headline = FadeTransition(
                                opacity: _fade,
                                child: SlideTransition(
                                  position: _slide,
                                  child: _buildHeroCopy(wide),
                                ),
                              );
                              final visual = FadeTransition(
                                opacity: _fade,
                                child: _buildHeroVisual(),
                              );
                              return wide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(flex: 6, child: headline),
                                        const SizedBox(width: 24),
                                        Expanded(flex: 5, child: visual),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroGlow(double size, Color color) {
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

  Widget _ringTexture(double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _blueDeep.withAlpha(22), width: 10),
        ),
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 38,
              height: 38,
              errorBuilder: (_, __, ___) => Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_primary, _primaryDeep],
                  ),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'UPRISE',
              style: GoogleFonts.beVietnamPro(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _slateDark,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _blueDeep.withAlpha(20),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'ADMIN PORTAL',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _blueDeep,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _scrollToFeatures,
              child: Text(
                'Features',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _slateMid,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _goToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blueDeep,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Admin Login',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCopy(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _blueDeep.withAlpha(20),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: _blueDeep.withAlpha(50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security_rounded, size: 13, color: _blueDeep),
              const SizedBox(width: 6),
              Text(
                'SYSTEM ADMINISTRATION FOR CICT',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _blueDeep,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'One console for the\nwhole CICT portal.',
          style: GoogleFonts.beVietnamPro(
            fontSize: wide ? 54 : 36,
            fontWeight: FontWeight.w800,
            color: _slateDark,
            height: 1.12,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Provision accounts, review organizations and events, oversee '
          'reports, and keep an audit trail of everything that happens '
          'across the student portal.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 16,
            color: _slateMid,
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
                gradient: const LinearGradient(colors: [_blueDeep, _blue]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _blue.withAlpha(90),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: TextButton(
                onPressed: _goToLogin,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
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
              onPressed: _scrollToFeatures,
              style: OutlinedButton.styleFrom(
                foregroundColor: _slateDark,
                side: BorderSide(color: _slateDark.withAlpha(60)),
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
          spacing: 22,
          runSpacing: 10,
          children: [
            for (final c in const [
              ('Bulacan State University · CICT', Icons.school_rounded),
              ('Firebase-Secured Accounts', Icons.verified_user_rounded),
              ('Full Audit Trail', Icons.fact_check_rounded),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.$2, size: 14, color: _blueDeep),
                  const SizedBox(width: 6),
                  Text(
                    c.$1,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _slateMid,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroVisual() {
    return SizedBox(
      height: 420,
      child: Center(
        child: SizedBox(
          width: 380,
          height: 380,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Soft glow behind everything
              Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_blue.withAlpha(55), Colors.transparent],
                    stops: const [0.0, 0.75],
                  ),
                ),
              ),
              // Decorative rings — echo the gear-ring shape of the real logo
              Container(
                width: 336,
                height: 336,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _blueDeep.withAlpha(40)),
                ),
              ),
              Container(
                width: 274,
                height: 274,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _blueDeep.withAlpha(26)),
                ),
              ),
              // Real UPRISE logo, glowing, on a white plate so it reads
              // clearly against the light background
              Container(
                width: 214,
                height: 214,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withAlpha(80),
                      blurRadius: 50,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withAlpha(18),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.shield_rounded,
                    size: 90,
                    color: _blueDeep,
                  ),
                ),
              ),
              // Orbit badges — a hint of what the console does, without the
              // clutter of stacked mockup cards
              const Positioned(
                top: 8,
                left: 30,
                child: _OrbitBadge(icon: Icons.group_work_rounded),
              ),
              Positioned(
                bottom: 20,
                right: 6,
                child: _OrbitBadge(
                  icon: Icons.fact_check_rounded,
                  accent: true,
                  accentDeep: _blueDeep,
                  accentColor: _blue,
                ),
              ),
              const Positioned(
                bottom: 64,
                left: -10,
                child: _OrbitBadge(icon: Icons.history_rounded),
              ),
              const Positioned(
                top: 60,
                right: -14,
                child: _OrbitBadge(icon: Icons.badge_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── FEATURES ──────────────────────────────────────────────────────
  Widget _buildFeatures(BuildContext context) {
    const features = [
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
      (
        Icons.summarize_rounded,
        'Reports Oversight',
        'Track financial and accomplishment report submissions against university deadlines.',
      ),
      (
        Icons.how_to_reg_rounded,
        'Guest & External Access',
        'Review guest applications and control who gets access to the platform from outside CICT.',
      ),
      (
        Icons.fact_check_rounded,
        'System Activity Logs',
        'Keep a full audit trail of significant actions taken across the entire portal.',
      ),
    ];

    return Container(
      key: _featuresKey,
      color: _lightBg,
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
                  color: _blueDeep,
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
                  color: _slateDark,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 40),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                alignment: WrapAlignment.center,
                children: [
                  for (final f in features)
                    _FeatureCard(
                      icon: f.$1,
                      title: f.$2,
                      subtitle: f.$3,
                      accent: _blueDeep,
                      accentBg: const Color(0xFFF1F5F9),
                      accentBorder: const Color(0xFFE2E8F0),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HOW IT WORKS ──────────────────────────────────────────────────
  Widget _buildHowItWorks(BuildContext context) {
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
                  color: _slateDark,
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
                        width: wide ? (c.maxWidth - 48) / 3 : double.infinity,
                        child: _StepCard(number: s.$1, title: s.$2, body: s.$3),
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
    );
  }

  // ── CTA BAND ──────────────────────────────────────────────────────
  Widget _buildCtaBand(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_blueDeep, _blue]),
      ),
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
                  onPressed: _goToLogin,
                  style: TextButton.styleFrom(
                    foregroundColor: _blueDeep,
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
    );
  }

  // ── FOOTER ────────────────────────────────────────────────────────
  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _navyDeep,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (_, c) {
              final wide = c.maxWidth >= 640;
              final brand = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 26,
                    height: 26,
                    errorBuilder: (_, __, ___) => Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [_primary, _primaryDeep],
                        ),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'UPRISE',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              );
              final links = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _openTerms,
                    style: TextButton.styleFrom(
                      foregroundColor: _slateSoft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      'Terms & Privacy',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
              final copyright = Text(
                '© ${DateTime.now().year} UPRISE · $kAppLegalEntity',
                textAlign: wide ? TextAlign.right : TextAlign.left,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11.5,
                  color: _slateSoft,
                  height: 1.5,
                ),
              );
              return wide
                  ? Row(
                      children: [
                        brand,
                        const SizedBox(width: 16),
                        links,
                        const Spacer(),
                        Flexible(child: copyright),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        brand,
                        const SizedBox(height: 12),
                        links,
                        const SizedBox(height: 12),
                        copyright,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _OrbitBadge extends StatelessWidget {
  final IconData icon;
  final bool accent;
  final Color accentDeep;
  final Color accentColor;
  final Color slateDark;

  const _OrbitBadge({
    required this.icon,
    this.accent = false,
    this.accentDeep = const Color(0xFF1E40AF),
    this.accentColor = const Color(0xFF2563EB),
    this.slateDark = const Color(0xFF111827),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: accent
              ? [accentDeep, accentColor]
              : [Colors.white, const Color(0xFFF3F4F6)],
        ),
        border: Border.all(color: Colors.white.withAlpha(140), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(90),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, size: 22, color: accent ? Colors.white : slateDark),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color accentBg;
  final Color accentBorder;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.accentBg,
    required this.accentBorder,
  });

  static const Color _slateDark = Color(0xFF111827);
  static const Color _slateMid = Color(0xFF6B7280);
  static const Color _cardBorder = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accentBg,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: accentBorder),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: _slateDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              color: _slateMid,
              height: 1.55,
            ),
          ),
        ],
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

  static const Color _slateDark = Color(0xFF111827);
  static const Color _slateMid = Color(0xFF6B7280);
  static const Color _blueDeep = Color(0xFF1E40AF);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: GoogleFonts.beVietnamPro(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _blueDeep.withAlpha(70),
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _slateDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12.5,
              color: _slateMid,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
