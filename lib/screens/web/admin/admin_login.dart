import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../auth_service.dart';
import '../../../main_web.dart';
import '../../auth/change_password_screen.dart';
import 'admin_dashboard.dart';
import 'admin_forgot_password.dart';
import '../../../widgets/app_toast.dart';

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  _AdminLoginState createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin>
    with SingleTickerProviderStateMixin {
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
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
          await FirebaseAuth.instance.signOut();
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
                        builder: (_, c) {
                          final wide = c.maxWidth > 760;
                          if (!wide) return _buildFormSide(compact: true);
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
    return Padding(
      padding: EdgeInsets.all(compact ? 32 : 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _fieldBorder),
                ),
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: _primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'UPRISE',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: _slateDark,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 36 : 56),
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
                    if (value.isEmpty) return 'Please enter your email address';
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
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LandingPage()),
                  ),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 10.5,
                    color: _blue,
                  ),
                  label: Text(
                    'Back to Portal Selection',
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
    ); // Padding
  }

  // ── Right: illustrated showcase panel ───────────────────────────────────

  Widget _buildShowcaseSide() {
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
                _buildMockDashboard(),
                const SizedBox(height: 28),
                Text(
                  'CICT Organization Management',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Oversee student organizations, event approvals,\nand academic reports for the College of\nInformation and Communications Technology.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    color: Colors.white.withAlpha(200),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _pageDot(active: true),
                    const SizedBox(width: 6),
                    _pageDot(active: false),
                    const SizedBox(width: 6),
                    _pageDot(active: false),
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
    return Container(
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? _orange : Colors.white.withAlpha(60),
        borderRadius: BorderRadius.circular(3),
      ),
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
