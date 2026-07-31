// lib/screens/web/org/org_forgot_password.dart
//
// Dedicated in-app "Forgot Password" screen for the org side — mirrors
// admin_forgot_password.dart's structure and flow, themed with the org
// side's own orange/gray/white/blue palette (theme/org_theme.dart) instead
// of admin's amber scheme.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/org_theme.dart';
import '../../../widgets/app_toast.dart';

class OrgForgotPassword extends StatefulWidget {
  final String? initialEmail;
  const OrgForgotPassword({super.key, this.initialEmail});

  @override
  State<OrgForgotPassword> createState() => _OrgForgotPasswordState();
}

class _OrgForgotPasswordState extends State<OrgForgotPassword> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _isLoading = false;
  bool _sent = false;

  static const Color _primaryDeep = UpriseColors.primaryDark;
  static const Color _blue = UpriseColors.info;
  static const Color _orange = UpriseColors.accent;
  static const Color _orangeLight = Color(0xFFFDBA74);
  static const Color _navy = Color(0xFF1C1410);
  static const Color _slateDark = UpriseColors.charcoal;
  static const Color _slateMid = UpriseColors.darkGray;
  static const Color _slateSoft = Color(0xFFC9B8AC);
  static const Color _fieldFill = UpriseColors.lightGray;
  static const Color _fieldBorder = UpriseColors.mediumGray;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _sent = true);
      AppToast.success(context, 'Reset link sent! Check your inbox.');
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found with this email';
          break;
        case 'invalid-email':
          msg = 'Please enter a valid email address';
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Please try again later';
          break;
        default:
          msg = e.message ?? 'Failed to send reset email';
      }
      if (mounted) AppToast.error(context, msg);
    } catch (e) {
      if (mounted) AppToast.error(context, 'Failed to send reset email: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_primaryDeep, _navy],
              ),
            ),
          ),
          Positioned(
            right: -140,
            bottom: -140,
            child: Opacity(
              opacity: 0.05,
              child: Image.asset(
                'assets/images/logo.png',
                width: 520,
                height: 520,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_orange, _orangeLight],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _orange.withAlpha(110),
                              blurRadius: 28,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: Colors.black.withAlpha(70),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.business_outlined,
                              size: 32,
                              color: _blue,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.fromLTRB(32, 34, 32, 30),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(240),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withAlpha(90),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(120),
                              blurRadius: 50,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 22),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_primaryDeep, _orange],
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 16,
                                      color: _slateMid,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Back to Login',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _slateMid,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: _blue.withAlpha(24),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _sent
                                      ? Icons.mark_email_read_rounded
                                      : Icons.lock_reset_rounded,
                                  color: _blue,
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _sent
                                  ? 'Check your inbox'
                                  : 'Reset your password',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: _slateDark,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _sent
                                  ? 'We sent a password reset link to ${_emailController.text.trim()}. Open it to choose a new password, then come back and log in.'
                                  : 'Enter the email address linked to your organization account. We\'ll send you a link to reset your password.',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12.5,
                                color: _slateMid,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (!_sent) ...[
                              Form(
                                key: _formKey,
                                child: TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 14,
                                    color: _slateDark,
                                  ),
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
                                  decoration: InputDecoration(
                                    hintText: 'org@uprise.org',
                                    hintStyle: GoogleFonts.beVietnamPro(
                                      color: _slateSoft,
                                      fontSize: 13,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.mail_outline_rounded,
                                      size: 18,
                                      color: _slateSoft,
                                    ),
                                    filled: true,
                                    fillColor: _fieldFill,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 14,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: _fieldBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: _fieldBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: _blue,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _sendResetLink,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _blue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          'Send Reset Link',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                              ),
                            ] else
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _blue,
                                    side: const BorderSide(color: _blue),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'Back to Login',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
