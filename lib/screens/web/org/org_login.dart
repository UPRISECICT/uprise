// lib/screens/web/org/org_login.dart
//
// Split-card layout matching admin_login.dart's structure (floating white
// card, sign-in form on one side, illustrated showcase carousel on the
// other) but themed with the org side's own orange/gray/white/blue palette
// (theme/org_theme.dart) instead of admin's amber/gray scheme, so the two
// portals stay visually distinct at a glance.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../auth_service.dart';
import '../../../theme/org_theme.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/change_password_screen.dart';
import 'org_dashboard.dart';
import 'org_forgot_password.dart';
import 'org_landing_page.dart';

class OrganizationLogin extends StatefulWidget {
  const OrganizationLogin({super.key});
  @override
  State<OrganizationLogin> createState() => _OrganizationLoginState();
}

class _OrganizationLoginState extends State<OrganizationLogin>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  // After 3 straight failed attempts, nudge toward resetting the password
  // instead of letting the org keep guessing indefinitely — same rule as
  // the admin login flow.
  int _failedAttempts = 0;
  static const int _maxAttemptsBeforePrompt = 3;
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  final AuthService _auth = AuthService();

  // Showcase carousel — swipeable, auto-advancing every 5s, with the active
  // indicator dot filling like a progress bar, mirroring admin_login.dart.
  final PageController _showcaseController = PageController();
  int _showcasePage = 0;
  static const int _showcaseSlideCount = 3;
  late final AnimationController _showcaseProgress;

  // ── Palette — the org side's own theme (org_theme.dart): orange is the
  //    primary brand color, blue carries links/interactive accents, gray
  //    and white make up the neutral structure. ───────────────────────────
  static const Color _primary = UpriseColors.primaryDark;
  static const Color _blue = UpriseColors.info;
  static const Color _orange = UpriseColors.accent;
  static const Color _slateDark = UpriseColors.charcoal;
  static const Color _slateMid = UpriseColors.darkGray;
  static const Color _slateSoft = Color(0xFFC9B8AC);
  static const Color _fieldFill = UpriseColors.lightGray;
  static const Color _fieldBorder = UpriseColors.mediumGray;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    _loadSavedEmail();

    _showcaseProgress =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _advanceShowcase();
          })
          ..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _showcaseController.dispose();
    _showcaseProgress.dispose();
    super.dispose();
  }

  void _advanceShowcase() {
    final next = (_showcasePage + 1) % _showcaseSlideCount;
    _showcaseController.animateToPage(
      next,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _onShowcasePageChanged(int index) {
    setState(() => _showcasePage = index);
    _showcaseProgress
      ..stop()
      ..reset()
      ..forward();
  }

  Future<SharedPreferences?> _getPrefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    final saved = prefs.getString('org_email');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _emailController.text = saved;
        _rememberMe = true;
      });
    }
  }

  Future<void> _saveEmail(String email) async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (_rememberMe && email.isNotEmpty) {
      await prefs.setString('org_email', email);
    } else {
      await prefs.remove('org_email');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    try {
      final user = await _auth.loginWithEmail(email, password);
      if (user == null) {
        _registerFailedAttempt('Invalid email or password');
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final role = await _auth.getUserRole(user.uid) ?? '';
      if (role != 'org') {
        await FirebaseAuth.instance.signOut();
        _registerFailedAttempt(
          'This account is not authorized for the Organization Portal',
        );
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      _failedAttempts = 0;
      AuthService.cacheRole(user.uid, role);
      await _saveEmail(email);
      final needsChange = await _auth.needsPasswordChange(user.uid);

      Widget destination() => needsChange
          ? ChangePasswordScreen(userId: user.uid, isFirstLogin: true)
          : OrgDashboard();

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => destination()));
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found with this email';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Incorrect email or password';
          break;
        case 'invalid-email':
          msg = 'Please enter a valid email address';
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Try again later';
          break;
        default:
          msg = e.message ?? 'Login failed';
      }
      _registerFailedAttempt(msg);
      if (mounted) setState(() => _isLoading = false);
    } on FirebaseException catch (e) {
      await FirebaseAuth.instance.signOut();
      _registerFailedAttempt('Database error: ${e.message ?? e.code}');
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      _registerFailedAttempt('Login failed: ${e.toString()}');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Not infinite tries — after 3 straight failures, nudge toward resetting
  // the password instead of just repeating the same generic error forever.
  void _registerFailedAttempt(String message) {
    _failedAttempts++;
    if (!mounted) return;
    if (_failedAttempts >= _maxAttemptsBeforePrompt) {
      _failedAttempts = 0;
      AppToast.warning(
        context,
        "Still can't sign in after several tries. Let's reset your password.",
      );
      _openForgotPassword();
    } else {
      AppToast.error(context, message);
    }
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrgForgotPassword(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F0EA),
      body: Stack(
        children: [
          Positioned(
            top: -160,
            left: -160,
            child: _softGlow(380, _primary.withAlpha(24)),
          ),
          Positioned(
            bottom: -180,
            right: -140,
            child: _softGlow(420, _blue.withAlpha(16)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: FadeTransition(
                opacity: _fadeIn,
                child: SlideTransition(
                  position: _slideUp,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(35),
                            blurRadius: 60,
                            offset: const Offset(0, 24),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (layoutContext, c) {
                          final wide = c.maxWidth > 760;
                          if (!wide) {
                            return ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    MediaQuery.of(layoutContext).size.height *
                                    0.75,
                              ),
                              child: _buildFormSide(compact: true),
                            );
                          }
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildFormSide(compact: false),
                                ),
                                Expanded(flex: 5, child: _buildShowcaseSide()),
                              ],
                            ),
                          );
                        },
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

  Widget _softGlow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
      ),
    );
  }

  // ── Left: the sign-in form ───────────────────────────────────────────────

  Widget _buildFormSide({required bool compact}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 32 : 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _fieldBorder, width: 1.5),
                  ),
                  padding: const EdgeInsets.all(7),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.business_outlined,
                      size: 38,
                      color: _primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'UPRISE',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: _slateDark,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 32 : 48),
            Text(
              'Welcome back',
              style: GoogleFonts.beVietnamPro(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: _slateDark,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in to access the organization portal.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: _slateMid,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),

            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildField(
                    controller: _emailController,
                    label: 'Email Address *',
                    hint: 'org@uprise.org',
                    icon: Icons.mail_outline_rounded,
                    type: TextInputType.emailAddress,
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty) {
                        return 'Please enter your email address';
                      }
                      if (!RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(value)) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 13),

                  _buildField(
                    controller: _passwordController,
                    label: 'Password *',
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscurePassword,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _slateSoft,
                        size: 18,
                      ),
                      tooltip: _obscurePassword
                          ? 'Show Password'
                          : 'Hide Password',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    onSubmit: (_) => _login(),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Please enter your password'
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),

            Row(
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _rememberMe = !_rememberMe);
                      if (!_rememberMe) _saveEmail('');
                    },
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 17,
                          height: 17,
                          decoration: BoxDecoration(
                            color: _rememberMe ? _blue : Colors.white,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: _rememberMe
                                  ? _blue
                                  : const Color(0xFFC7CDD6),
                              width: 1.5,
                            ),
                          ),
                          child: _rememberMe
                              ? const Icon(
                                  Icons.check,
                                  size: 11,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Remember me',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            color: _slateMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _openForgotPassword,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Forgot password?',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: _blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            AnimatedOpacity(
              opacity: _isLoading ? 0.7 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: double.infinity,
                height: 46,
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withAlpha(70),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: TextButton(
                  onPressed: _isLoading ? null : _login,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Sign In to Organization Portal',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: Divider(color: const Color(0xFFE2E8F0), thickness: 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      color: _slateSoft,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: const Color(0xFFE2E8F0), thickness: 1),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Don't have an organization account?",
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: _slateSoft,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Contact CICT Administrator',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: _slateDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      // Ordinary back — returns to the Organization landing
                      // page this login screen was pushed from. Only falls
                      // back to opening that landing page fresh if there's
                      // nothing to pop to (e.g. reached directly as the
                      // app's root route, with no prior screen at all).
                      final nav = Navigator.of(context);
                      if (nav.canPop()) {
                        nav.pop();
                      } else {
                        nav.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const OrgLandingPage(),
                          ),
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 10.5,
                      color: _blue,
                    ),
                    label: Text(
                      'Back',
                      style: GoogleFonts.beVietnamPro(
                        color: _blue,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Right: illustrated showcase panel ───────────────────────────────────

  Widget _buildShowcaseSide() {
    final slides = [
      (
        visual: _buildMockProposals(),
        title: 'Submit & Track Event Proposals',
        subtitle:
            'Propose events, follow their approval status, and\npublish them to students the moment they\'re\ngreenlit — all from one place.',
      ),
      (
        visual: _buildMockMembers(),
        title: 'Manage Officers & Members',
        subtitle:
            'Keep your org chart, officer roles, and member\nroster up to date so the right people always\nhave access.',
      ),
      (
        visual: _buildMockFinanceChart(),
        title: 'Track Finance & Reports',
        subtitle:
            'Log income and expenses, and stay ahead of\nfinancial and accomplishment report deadlines\nbefore they become overdue.',
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primary, _orange],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -60,
            right: -60,
            child: _softGlow(220, _blue.withAlpha(60)),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: _softGlow(240, Colors.white.withAlpha(12)),
          ),
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 320,
                  child: PageView.builder(
                    controller: _showcaseController,
                    itemCount: slides.length,
                    onPageChanged: _onShowcasePageChanged,
                    itemBuilder: (context, i) {
                      final slide = slides[i];
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          slide.visual,
                          const SizedBox(height: 28),
                          Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            slide.subtitle,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12.5,
                              color: Colors.white.withAlpha(200),
                              height: 1.6,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < slides.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _showcaseController.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOut,
                          ),
                          child: _pageDot(active: i == _showcasePage),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageDot({required bool active}) {
    if (!active) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(60),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _showcaseProgress,
      builder: (context, _) {
        return Container(
          width: 22,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(35),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _showcaseProgress.value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: _orange,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMockProposals() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(90),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _mockDot(const Color(0xFFEF4444)),
              const SizedBox(width: 4),
              _mockDot(const Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              _mockDot(const Color(0xFF10B981)),
              const Spacer(),
              Text(
                'Proposals',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 9,
                  color: _slateSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _mockStat(_primary)),
              const SizedBox(width: 6),
              Expanded(child: _mockStat(_orange)),
              const SizedBox(width: 6),
              Expanded(child: _mockStat(_blue)),
            ],
          ),
          const SizedBox(height: 10),
          for (final w in [1.0, 0.8, 0.9])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _fieldFill,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: w,
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: _fieldFill,
                          borderRadius: BorderRadius.circular(4),
                        ),
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

  Widget _buildMockMembers() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(90),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _mockDot(const Color(0xFFEF4444)),
              const SizedBox(width: 4),
              _mockDot(const Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              _mockDot(const Color(0xFF10B981)),
              const Spacer(),
              Text(
                'Members',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 9,
                  color: _slateSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final c in [_primary, _orange, _blue])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.person_rounded, size: 12, color: c),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 6,
                          width: 90,
                          decoration: BoxDecoration(
                            color: _fieldFill,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 5,
                          width: 50,
                          decoration: BoxDecoration(
                            color: _fieldFill,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Active',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF10B981),
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

  Widget _buildMockFinanceChart() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(90),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _mockDot(const Color(0xFFEF4444)),
              const SizedBox(width: 4),
              _mockDot(const Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              _mockDot(const Color(0xFF10B981)),
              const Spacer(),
              Text(
                'Finance',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 9,
                  color: _slateSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final h in [0.4, 0.7, 0.5, 0.9, 0.6, 0.8])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FractionallySizedBox(
                        heightFactor: h,
                        child: Container(
                          decoration: BoxDecoration(
                            color: h > 0.75 ? _orange : _primary.withAlpha(190),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
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

  Widget _mockDot(Color c) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }

  Widget _mockStat(Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: c.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 4,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 24,
            height: 6,
            decoration: BoxDecoration(
              color: c.withAlpha(150),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onSubmit,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      onFieldSubmitted: onSubmit,
      validator: validator,
      style: GoogleFonts.beVietnamPro(fontSize: 13.5, color: _slateDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.beVietnamPro(color: _slateSoft, fontSize: 12.5),
        hintText: hint,
        hintStyle: GoogleFonts.beVietnamPro(
          color: const Color(0xFFCBD5E1),
          fontSize: 12.5,
        ),
        prefixIcon: Icon(icon, color: _primary, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: _fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _blue, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
      ),
    );
  }
}
