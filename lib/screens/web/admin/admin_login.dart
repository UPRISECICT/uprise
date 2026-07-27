import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../auth_service.dart';
import '../../../main_web.dart';
import '../../auth/change_password_screen.dart';
import 'admin_dashboard.dart';

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  _AdminLoginState createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController    = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading       = false;
  bool _obscurePassword = true;
  bool _rememberMe      = false;
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  final AuthService _auth = AuthService();

  // ── Palette ──────────────────────────────────────────────────────────────
  static const Color _rust       = Color(0xFFB6430E);
  static const Color _rustDeep   = Color(0xFF7A2B08);
  static const Color _accent     = Color(0xFFF97316);
  static const Color _accentDeep = Color(0xFFEA580C);
  static const Color _navy       = Color(0xFF0F172A);
  static const Color _slateDark  = Color(0xFF1E1B16);
  static const Color _slateMid   = Color(0xFF6B7280);
  static const Color _slateSoft  = Color(0xFFAEB4C4);
  static const Color _fieldFill  = Color(0xFFFAF6F2);
  static const Color _fieldBorder= Color(0xFFEDE4DC);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeIn  = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
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
    try { return await SharedPreferences.getInstance(); }
    catch (_) { return null; }
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await _getPrefs();
    if (prefs == null) return;
    final saved = prefs.getString('admin_email');
    if (saved != null && saved.isNotEmpty) {
      setState(() { _emailController.text = saved; _rememberMe = true; });
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
          _emailController.text.trim(), _passwordController.text.trim());
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()?['role'] == 'admin') {
          await _saveEmail(_emailController.text.trim());
          final needsChange = await _auth.needsPasswordChange(user.uid);
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(
              builder: (_) => needsChange
                  ? ChangePasswordScreen(userId: user.uid, isFirstLogin: true)
                  : AdminDashboard()));
          }
        } else {
          await FirebaseAuth.instance.signOut();
          _showError('This account is not authorized as Admin');
        }
      } else {
        _showError('Invalid email or password');
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':    msg = 'No account found with this email'; break;
        case 'wrong-password':    msg = 'Incorrect password'; break;
        case 'invalid-email':     msg = 'Please enter a valid email address'; break;
        case 'too-many-requests': msg = 'Too many attempts. Try again later'; break;
        default:                  msg = e.message ?? 'Login failed';
      }
      _showError(msg);
    } catch (e) {
      _showError('An error occurred: ${e.toString()}');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) { _showError('Please enter your email address first'); return; }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white,
        title: Text('Reset Password',
            style: GoogleFonts.beVietnamPro(
                fontWeight: FontWeight.w700, color: _slateDark)),
        content: Text('Send a password reset link to\n$email',
            style: GoogleFonts.beVietnamPro(color: _slateMid)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.beVietnamPro(color: _slateSoft))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _rust,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Send Link',
                style: GoogleFonts.beVietnamPro(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reset link sent! Check your inbox.',
              style: GoogleFonts.beVietnamPro()),
          backgroundColor: const Color(0xFF3FA672),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      _showError('Failed to send reset email: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.beVietnamPro()),
      backgroundColor: const Color(0xFFDC2626),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: LayoutBuilder(builder: (_, c) {
        return Stack(fit: StackFit.expand, children: [
          // Full-bleed campus photo
          Image.asset(
            'assets/images/bg_pattern.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [_rustDeep, _navy]),
              ),
            ),
          ),
          // Vignette overlay — darker at the edges (for text/card contrast),
          // lighter in the middle so the building photo stays visible instead
          // of being fully washed out by a flat diagonal tint.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xE07A2B08),
                  Color(0x996B2A08),
                  Color(0x99B6430E),
                  Color(0xD2551F07),
                ],
                stops: [0.0, 0.38, 0.62, 1.0],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x4D0F172A), Colors.transparent, Color(0x660F172A)],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: c.maxWidth > 900 ? _buildWideHero() : _buildCompactHero(),
          ),
        ]);
      }),
    );
  }

  // ── Wide: branding on the photo, form card floating on the right ──────────

  Widget _buildWideHero() {
    return Center(
      child: ConstrainedBox(
        // Caps the content width on ultra-wide screens so branding and the
        // card sit close enough together instead of stretching apart with a
        // dead gap of photo between them.
        constraints: const BoxConstraints(maxWidth: 1240),
        child: FadeTransition(
          opacity: _fadeIn,
          child: SlideTransition(
            position: _slideUp,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 5, child: _buildHeroBranding()),
                  const SizedBox(width: 56),
                  SizedBox(width: 420, child: _buildFormCard()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBranding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 152, height: 152,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withAlpha(70),
                  blurRadius: 24, offset: const Offset(0, 10)),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Image.asset('assets/images/logo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.shield_outlined, size: 64, color: _rust)),
        ),
        const SizedBox(height: 26),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('UP',
              style: GoogleFonts.beVietnamPro(
                fontSize: 56, fontWeight: FontWeight.w800,
                color: Colors.white, letterSpacing: 1.5, height: 1)),
          Text('RISE',
              style: GoogleFonts.beVietnamPro(
                fontSize: 56, fontWeight: FontWeight.w800,
                color: const Color(0xFFFFC79A), letterSpacing: 1.5, height: 1)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(40),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text('ADMIN PORTAL',
              style: GoogleFonts.beVietnamPro(
                fontSize: 10.5, fontWeight: FontWeight.w700,
                color: Colors.white, letterSpacing: 3)),
        ),
        const SizedBox(height: 30),
        Text(
          'Manage students, organizations,\nand campus events from one\nunified dashboard.',
          style: GoogleFonts.beVietnamPro(
            fontSize: 17, fontWeight: FontWeight.w400,
            color: Colors.white.withAlpha(235), height: 1.7,
            shadows: [Shadow(color: Colors.black.withAlpha(90), blurRadius: 12)],
          ),
        ),
        const SizedBox(height: 40),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: _accent),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'College of Information and\nCommunications Technology',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12, color: Colors.white.withAlpha(220), height: 1.6),
          ),
        ]),
      ],
    );
  }

  // ── Narrow: photo backdrop, everything in one centered card ────────────────

  Widget _buildCompactHero() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: FadeTransition(
          opacity: _fadeIn,
          child: SlideTransition(
            position: _slideUp,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withAlpha(70),
                          blurRadius: 20, offset: const Offset(0, 8)),
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Image.asset('assets/images/logo.png', fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.shield_outlined, size: 52, color: _rust)),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('UP',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 32, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: 1, height: 1)),
                  Text('RISE',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 32, fontWeight: FontWeight.w800,
                        color: const Color(0xFFFFC79A), letterSpacing: 1, height: 1)),
                ]),
                const SizedBox(height: 8),
                Text('ADMIN PORTAL',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: Colors.white.withAlpha(215), letterSpacing: 3)),
                const SizedBox(height: 22),
                _buildFormCard(),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared form card ────────────────────────────────────────────────────────

  Widget _buildFormCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        // Frosted-glass effect: blurs the campus photo behind the card so
        // the panel feels like part of the scene rather than a flat sticker
        // pasted on top of it.
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(232),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(90), width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withAlpha(120),
                  blurRadius: 50, offset: const Offset(0, 20)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(32, 34, 32, 30),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Welcome back',
              style: GoogleFonts.beVietnamPro(
                fontSize: 22, fontWeight: FontWeight.w700,
                color: _slateDark, letterSpacing: -0.3)),
          const SizedBox(height: 5),
          Text('Sign in to access the admin dashboard.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5, color: _slateMid, height: 1.5)),
          const SizedBox(height: 24),

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
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
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
                      color: _slateSoft, size: 18),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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

          Row(children: [
            GestureDetector(
              onTap: () {
                setState(() => _rememberMe = !_rememberMe);
                if (!_rememberMe) _saveEmail('');
              },
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 17, height: 17,
                  decoration: BoxDecoration(
                    color: _rememberMe ? _rust : Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: _rememberMe ? _rust : const Color(0xFFC7CDD6),
                      width: 1.5),
                  ),
                  child: _rememberMe
                      ? const Icon(Icons.check, size: 11, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 7),
                Text('Remember me',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12, color: _slateMid)),
              ]),
            ),
            const Spacer(),
            TextButton(
              onPressed: _resetPassword,
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text('Forgot password?',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12, color: _rust,
                    fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 20),

          AnimatedOpacity(
            opacity: _isLoading ? 0.7 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: double.infinity, height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accentDeep, _accent]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: _accent.withAlpha(80),
                      blurRadius: 16, offset: const Offset(0, 7)),
                ],
              ),
              child: TextButton(
                onPressed: _isLoading ? null : _login,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text('Sign In to Dashboard',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13.5, fontWeight: FontWeight.w700,
                          letterSpacing: 0.1)),
              ),
            ),
          ),
          const SizedBox(height: 18),

          Row(children: [
            Expanded(child: Divider(color: const Color(0xFFF1EAE3), thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or',
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5, color: _slateSoft))),
            Expanded(child: Divider(color: const Color(0xFFF1EAE3), thickness: 1)),
          ]),
          const SizedBox(height: 16),

          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Don't have an admin account?",
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 12, color: _slateSoft)),
              const SizedBox(height: 2),
              Text('Contact System Administrator',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12, color: _slateDark,
                    fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LandingPage())),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 10.5, color: _rust),
                label: Text('Back to Portal Selection',
                    style: GoogleFonts.beVietnamPro(
                      color: _rust,
                      fontWeight: FontWeight.w600, fontSize: 12)),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ]),
          ),
        ],
          ),
        ),
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
        labelStyle: GoogleFonts.beVietnamPro(
            color: _slateSoft, fontSize: 12.5),
        hintText: hint,
        hintStyle: GoogleFonts.beVietnamPro(
            color: const Color(0xFFD8D2C8), fontSize: 12.5),
        prefixIcon: Icon(icon, color: _rust, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: _fieldFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _fieldBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _fieldBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _rust, width: 1.6)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      ),
    );
  }
}