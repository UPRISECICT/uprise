import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../auth_service.dart';
import '../../auth/change_password_screen.dart';
import 'admin_dashboard.dart';
import 'admin_forgot_password.dart';
import 'admin_landing_page.dart';
import '../../../widgets/app_toast.dart';
import '../../../services/app_sign_out.dart';

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  _AdminLoginState createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  // After 3 straight failed attempts, nudge toward resetting the password
  // instead of letting the admin keep guessing indefinitely.
  int _failedAttempts = 0;
  static const int _maxAttemptsBeforePrompt = 3;
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  final AuthService _auth = AuthService();

  // Showcase carousel — swipeable, auto-advancing every 5s, with the active
  // indicator dot filling like a progress bar (Stories-style) instead of a
  // plain static dot — a small, deliberate "futuristic" touch that stays
  // out of the way rather than a flashy one.
  final PageController _showcaseController = PageController();
  int _showcasePage = 0;
  static const int _showcaseSlideCount = 3;
  late final AnimationController _showcaseProgress;

  // ── Palette ──────────────────────────────────────────────────────────────
  // CICT professional scheme: gray is the structural primary (backgrounds,
  // icons, borders), blue carries interactive/actionable elements (links,
  // focus states, the sign-in CTA), and orange is reserved as a single
  // accent spark (wordmark, bullet) rather than spread across the page.
  // Both primary and the CTA gradient were deepened a step for a richer,
  // more premium blend instead of sitting at the same tonal weight.
  static const Color _primary = Color(0xFF1E293B);
  static const Color _blue = Color(0xFF2563EB);
  static const Color _orange = Color(0xFFF97316);
  static const Color _navy = Color(0xFF0F172A);
  static const Color _slateDark = Color(0xFF111827);
  static const Color _slateMid = Color(0xFF6B7280);
  static const Color _slateSoft = Color(0xFFAEB4C4);
  static const Color _fieldFill = Color(0xFFF8FAFC);
  static const Color _fieldBorder = Color(0xFFE2E8F0);

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

  // Called whenever the visible slide changes, whether the auto-advance
  // timer triggered it or the admin swiped/tapped a dot manually — either
  // way the progress fill for the new active dot should start from zero
  // instead of picking up wherever the old one left off.
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
    final saved = prefs.getString('admin_email');
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
      await prefs.setString('admin_email', email);
    } else {
      await prefs.remove('admin_email');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = await _auth.loginWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && doc.data()?['role'] == 'admin') {
          _failedAttempts = 0;
          await _saveEmail(_emailController.text.trim());
          final needsChange = await _auth.needsPasswordChange(user.uid);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => needsChange
                    ? ChangePasswordScreen(userId: user.uid, isFirstLogin: true)
                    : AdminDashboard(),
              ),
            );
          }
        } else {
          await AppSignOut.signOut();
          _registerFailedAttempt('This account is not authorized as Admin');
        }
      } else {
        _registerFailedAttempt('Invalid email or password');
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found with this email';
          break;
        case 'wrong-password':
          msg = 'Incorrect password';
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
    } catch (e) {
      _registerFailedAttempt('An error occurred: ${e.toString()}');
    }
    if (mounted) setState(() => _isLoading = false);
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
            AdminForgotPassword(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  // Split-card layout: a single floating white card holding the sign-in form
  // on one side and an illustrated showcase panel on the other, instead of
  // the previous full-bleed photo hero. Matches the structure of the
  // reference (plain page background, one rounded card, form + visual
  // panel side by side) while keeping the app's own gray/blue/orange scheme.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF1F6),
      body: Stack(
        children: [
          // Soft, oversized glows behind the card for a little depth on the
          // plain page background instead of it being completely flat.
          Positioned(
            top: -160,
            left: -160,
            child: _softGlow(380, _primary.withAlpha(20)),
          ),
          Positioned(
            bottom: -180,
            right: -140,
            child: _softGlow(420, _orange.withAlpha(18)),
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
                            // Without a bounded height here, Center() inside
                            // _buildFormSide has no extra space to center
                            // into — the card just shrink-wraps the form and
                            // everything renders flush to the top instead.
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

  // A soft radial glow that fades to nothing at the edge — reads as subtle
  // depth rather than a flat, hard-edged "sticker" circle.
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
    // Centered vertically instead of pinned to the top — the form's content
    // is shorter than the showcase side, so top-aligning it left a big dead
    // gap at the bottom instead of the two sides feeling balanced.
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
                      Icons.shield_outlined,
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
              'Sign in to access the admin dashboard.',
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
                    hint: 'admin@uprise.org',
                    icon: Icons.mail_outline_rounded,
                    type: TextInputType.emailAddress,
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty)
                        return 'Please enter your email address';
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
                  // Flat, deep gray instead of a bright blue gradient — a
                  // more restrained, enterprise-tool primary action rather
                  // than a loud consumer-SaaS button.
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
                          'Sign In to Dashboard',
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
                    "Don't have an admin account?",
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: _slateSoft,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Contact System Administrator',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: _slateDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      // Ordinary back — returns to the Admin landing page
                      // this login screen was pushed from. Only falls back
                      // to opening that landing page fresh if there's
                      // nothing to pop to (e.g. reached directly as the
                      // app's root route, with no prior screen at all).
                      final nav = Navigator.of(context);
                      if (nav.canPop()) {
                        nav.pop();
                      } else {
                        nav.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const AdminLandingPage(),
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
                ], // Center's inner Column children
              ), // Center's inner Column
            ), // Center
          ], // form-side content column children
        ), // form-side content column
      ), // Padding
    ); // Center
  }

  // ── Right: illustrated showcase panel ───────────────────────────────────

  Widget _buildShowcaseSide() {
    final slides = [
      (
        visual: _buildMockDashboard(),
        title: 'CICT Organization Management',
        subtitle:
            'Oversee student organizations, event approvals,\nand academic reports for the College of\nInformation and Communications Technology.',
      ),
      (
        visual: _buildMockStudentList(),
        title: 'Manage Students & Advisers',
        subtitle:
            'Keep student records, adviser assignments, and\naccount access up to date, all in one place.',
      ),
      (
        visual: _buildMockReportsChart(),
        title: 'Track Reports & Analytics',
        subtitle:
            'Monitor financial and accomplishment reports,\ndeadlines, and submission status at a glance.',
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primary, _navy],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Two restrained glows — no hard shapes, no scattered icons.
          // Understated depth instead of a busy illustration.
          Positioned(
            top: -60,
            right: -60,
            child: _softGlow(220, _orange.withAlpha(50)),
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
    // Active dot fills like a progress bar tracking the 5s auto-advance
    // timer instead of just sitting there as a static, wider pill.
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

  // A small stylized "dashboard preview" mockup built from plain widgets
  // (no real screenshot asset exists) — echoes the reference's floating
  // app-screenshot card using our own stat-card/table conventions.
  Widget _buildMockDashboard() {
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
                'Dashboard',
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

  // Second carousel slide — a mocked student roster instead of the
  // dashboard, so the swipe genuinely shows a different capability rather
  // than the same card twice with new text underneath.
  Widget _buildMockStudentList() {
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
                'Students',
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

  // Third carousel slide — a mocked bar chart standing in for the reports
  // & analytics side of the dashboard.
  Widget _buildMockReportsChart() {
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
                'Reports',
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
