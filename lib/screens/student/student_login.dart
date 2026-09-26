// lib/screens/student/student_login.dart
//
// STUDENT LOGIN — Gray Card Background
// Auto-triggers "Forgot Password" flow after 3 consecutive failed attempts.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth_service.dart';
import '../../services/activity_logger.dart' as activity_log;
import '../guest/guest_access_gateway_screen.dart';
import '../student/student_home_screen.dart';
import '../../widgets/student/app_colors.dart';
import 'student_change_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../services/app_sign_out.dart';

class StudentLogin extends StatefulWidget {
  const StudentLogin({super.key});

  @override
  State<StudentLogin> createState() => _StudentLoginState();
}

class _StudentLoginState extends State<StudentLogin> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  int _failedAttempts = 0;
  static const int _maxFailedAttempts = 3;

  // ── Inline login error ──
  // Shown in the form, right above the Login button, instead of a floating
  // SnackBar: the SnackBar covered the bottom of the form, grew to two lines
  // with its action, and vanished before it was always read. This stays until
  // the student edits either field.
  String? _loginError;
  bool _emailInvalid = false;
  bool _passwordInvalid = false;

  /// Bumped on every new error so the banner shakes even when the message is
  /// the same as the one already showing.
  int _errorTick = 0;

  final AuthService _auth = AuthService();
  // Credentials are kept in the platform Keychain/Keystore (encrypted at
  // rest) rather than SharedPreferences — SharedPreferences is plain text,
  // which isn't a safe place to hold a real password even locally.
  static const _secureStorage = FlutterSecureStorage();
  static const _kRememberedEmailKey = 'student_remembered_email';
  static const _kRememberedPasswordKey = 'student_remembered_password';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    if (!remember) return;
    final savedEmail = await _secureStorage.read(key: _kRememberedEmailKey);
    final savedPassword = await _secureStorage.read(
      key: _kRememberedPasswordKey,
    );
    if (savedEmail != null && savedPassword != null && mounted) {
      setState(() {
        _emailCtrl.text = savedEmail;
        _passwordCtrl.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  Future<void> _persistRememberedCredentials(
    String email,
    String password,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await _secureStorage.write(key: _kRememberedEmailKey, value: email);
      await _secureStorage.write(key: _kRememberedPasswordKey, value: password);
      await prefs.setBool('remember_me', true);
    } else {
      await _secureStorage.delete(key: _kRememberedEmailKey);
      await _secureStorage.delete(key: _kRememberedPasswordKey);
      await prefs.setBool('remember_me', false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Whether [uid] may use the student app.
  ///
  /// Positive identification, not a deny-list. The recorded role decides it
  /// whenever there is one — a guest, org or admin account is turned away
  /// because it isn't a student, not because it happened to be on a list.
  ///
  /// A null role means there is no users/{uid} doc or the read failed, which
  /// is not the same as "not a student": accounts predating the users-doc
  /// write still have a students roster entry. Falling back to that keeps
  /// them working without letting an unreadable role pass as 'student', which
  /// is what AuthService.getUserRole would have done.
  Future<bool> _isStudentAccount(String uid, String? role) async {
    if (role == 'student') return true;
    if (role != null) return false;

    try {
      // Queried by the `uid` field, the same way RoleRouter does it — the
      // students doc id is the uid in practice, but not by contract.
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _setLoginError(
    String message, {
    bool email = false,
    bool password = false,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _loginError = message;
      _emailInvalid = email;
      _passwordInvalid = password;
      _errorTick++;
    });
  }

  /// Cleared as soon as the student starts correcting a field.
  void _clearLoginError() {
    if (_loginError == null && !_emailInvalid && !_passwordInvalid) return;
    setState(() {
      _loginError = null;
      _emailInvalid = false;
      _passwordInvalid = false;
    });
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _setLoginError(
        email.isEmpty && password.isEmpty
            ? 'Enter your email and password.'
            : email.isEmpty
            ? 'Enter your email address.'
            : 'Enter your password.',
        email: email.isEmpty,
        password: password.isEmpty,
      );
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _setLoginError('Enter a valid email address.', email: true);
      return;
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    try {
      final user = await _auth.loginWithEmail(email, password);

      if (user == null) {
        if (!mounted) return;
        _handleFailedAttempt(email, _wrongCredentialsMessage);
      } else {
        // The credentials are valid — but valid for *some* account, not
        // necessarily a student one. Guest, org and admin accounts all
        // authenticate here, and the success path below is a
        // pushAndRemoveUntil that skips RoleRouter for the rest of the
        // session, so this is the only place that can stop them.
        // Read while still signed in — a Firestore read after signOut() can
        // be refused by the rules, which would log every rejection as
        // 'unknown' and hide which role was actually turned away.
        final recordedRole = await _auth.getRecordedRole(user.uid);
        if (!await _isStudentAccount(user.uid, recordedRole)) {
          await AppSignOut.signOut();
          await activity_log.ActivityLogger.log(
            action: 'Blocked non-student login on student portal',
            module: 'Authentication',
            severity: 'security',
            details: {
              'uid': user.uid,
              'email': email,
              'role': recordedRole ?? 'unknown',
            },
          );
          if (!mounted) return;
          // Deliberately not _handleFailedAttempt: that counts toward the
          // lockout and auto-opens Forgot Password after three tries, and a
          // new password will never make this account a student one.
          _setLoginError(
            'This isn\'t a student account. If you signed up as a guest, '
            'use the guest option below.',
          );
          setState(() => _isLoading = false);
          return;
        }

        _failedAttempts = 0;

        // ✅ Remember Me logic — after the gate, so a rejected account's
        // credentials never land in this screen's secure storage (and get
        // auto-filled on the next visit).
        await _persistRememberedCredentials(email, password);

        await activity_log.ActivityLogger.log(
          action: 'Student login',
          module: 'Authentication',
          severity: 'security',
          details: {'uid': user.uid, 'email': email, 'role': 'student'},
        );

        final mustChange = await _auth.needsPasswordChange(user.uid);
        if (!mounted) return;

        if (mustChange) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => StudentChangePasswordScreen()),
            (route) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const StudentHomeScreen()),
            (route) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      await activity_log.ActivityLogger.log(
        action: 'Failed student login attempt',
        module: 'Authentication',
        severity: 'warning',
        details: {'email': email, 'reason': e.code},
      );
      switch (e.code) {
        // One message for every wrong-credentials case. Newer Firebase Auth
        // reports all of them as `invalid-credential` (which used to fall
        // through to a vague "Login failed"), and saying "no account found"
        // separately told anyone typing an email whether it was registered.
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
        case 'INVALID_LOGIN_CREDENTIALS':
          _handleFailedAttempt(email, _wrongCredentialsMessage);
          break;
        // None of these is fixed by a new password, so they don't count
        // toward opening Forgot Password.
        case 'invalid-email':
          _setLoginError('Enter a valid email address.', email: true);
          break;
        case 'too-many-requests':
          _setLoginError(
            'Too many sign-in attempts. Please wait a few minutes and try '
            'again.',
          );
          break;
        case 'user-disabled':
          _setLoginError(
            'This account has been disabled. Please contact your '
            'administrator.',
          );
          break;
        case 'network-request-failed':
          _setLoginError('No internet connection. Check it and try again.');
          break;
        default:
          _setLoginError('Couldn\'t sign in right now. Please try again.');
      }
    } catch (_) {
      _setLoginError('Couldn\'t sign in right now. Please try again.');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  static const String _wrongCredentialsMessage =
      'Incorrect email or password.';

  // ── Handles a wrong-credentials attempt ──
  //
  // No "(2 attempts left)" countdown: there is no lockout here — the third
  // miss only opens Forgot Password — so a countdown warned of something that
  // never happens, and told anyone guessing exactly how many tries they had.
  // Firebase Auth's own rate limit (too-many-requests) is the real throttle.
  // The form's own "Forgot Password?" link sits right above the error, so the
  // error doesn't repeat it; the third miss opens the reset for them.
  void _handleFailedAttempt(String email, String errorMessage) {
    _failedAttempts++;

    if (_failedAttempts >= _maxFailedAttempts) {
      _failedAttempts = 0; // reset so it doesn't keep firing every time
      _setLoginError(errorMessage, email: true, password: true);
      // A beat for the error to register before the reset dialog opens.
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _openForgotPasswordDialog(prefillEmail: email);
      });
    } else {
      _setLoginError(errorMessage, email: true, password: true);
    }
  }

  void _openGuestGateway() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GuestAccessGatewayScreen()),
    );
  }

  // Login errors show inline (see _setLoginError); this SnackBar is for the
  // Forgot Password dialog, where the form behind it can't show anything.
  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.beVietnamPro(fontSize: 13)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.beVietnamPro(fontSize: 13)),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Forgot Password ──────────────────────────────────────────
  void _openForgotPasswordDialog({String? prefillEmail}) {
    final resetEmailCtrl = TextEditingController(
      text: prefillEmail ?? _emailCtrl.text.trim(),
    );
    bool isSending = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> handleSendResetEmail() async {
              final email = resetEmailCtrl.text.trim();

              if (email.isEmpty) {
                _showError('Please enter your email address');
                return;
              }
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                _showError('Please enter a valid email address');
                return;
              }

              setDialogState(() => isSending = true);

              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: email,
                );

                await activity_log.ActivityLogger.log(
                  action: 'Password reset requested',
                  module: 'Authentication',
                  severity: 'security',
                  details: {'email': email},
                );

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                _showSuccess('Password reset link sent to $email');
              } on FirebaseAuthException catch (e) {
                String message =
                    'Could not send reset email. Please try again.';
                switch (e.code) {
                  case 'user-not-found':
                    message = 'No account found with this email';
                    break;
                  case 'invalid-email':
                    message = 'Please enter a valid email address';
                    break;
                  case 'too-many-requests':
                    message = 'Too many attempts. Please wait and try again.';
                    break;
                }
                setDialogState(() => isSending = false);
                _showError(message);
              } catch (_) {
                setDialogState(() => isSending = false);
                _showError('An error occurred. Please try again.');
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Reset Password',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter your email address and we\'ll send you a link to reset your password.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    enabled: !isSending,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'student@outlook.com',
                      hintStyle: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        color: Colors.grey.shade400,
                      ),
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        color: Colors.grey.shade500,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.primaryDark,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (_) => handleSendResetEmail(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.beVietnamPro(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSending ? null : handleSendResetEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : Text(
                          'Send Link',
                          style: GoogleFonts.beVietnamPro(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Logo ──
                  Image.asset(
                    'assets/images/logo.png',
                    height: 150,
                    width: 150,
                    fit: BoxFit.contain,
                    color: AppColors.primaryDark,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.school,
                      size: 120,
                      color: AppColors.primaryDark,
                    ),
                  ),

                  const SizedBox(height: 2),

                  // ── App Name ──
                  Text(
                    'UPRISE',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryDark,
                      letterSpacing: 2,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // ── Student Portal ──
                  Text(
                    'Student Portal',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                      letterSpacing: 4,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Login Card ──
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header ──
                        Center(
                          child: Column(
                            children: [
                              Text(
                                'Welcome Back!',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Login to continue your learning journey',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Email Field ──
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Email Address',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) => _clearLoginError(),
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: 'student@outlook.com',
                                hintStyle: GoogleFonts.beVietnamPro(
                                  fontSize: 14,
                                  color: Colors.grey.shade400,
                                ),
                                prefixIcon: Icon(
                                  Icons.email_outlined,
                                  color: Colors.grey.shade500,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _emailInvalid
                                        ? AppColors.error
                                        : Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _emailInvalid
                                        ? AppColors.error
                                        : AppColors.primaryDark,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // ── Password Field ──
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Password',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: _obscurePassword,
                              onChanged: (_) => _clearLoginError(),
                              onSubmitted: (_) {
                                if (!_isLoading) _login();
                              },
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: '••••••••',
                                hintStyle: GoogleFonts.beVietnamPro(
                                  fontSize: 14,
                                  color: Colors.grey.shade400,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outline,
                                  color: Colors.grey.shade500,
                                  size: 20,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    size: 20,
                                    color: Colors.grey.shade500,
                                  ),
                                  onPressed: () {
                                    if (!mounted) return;
                                    setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    );
                                  },
                                ),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _passwordInvalid
                                        ? AppColors.error
                                        : Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _passwordInvalid
                                        ? AppColors.error
                                        : AppColors.primaryDark,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // ── Remember Me & Forgot Password ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) {
                                      setState(
                                        () => _rememberMe = value ?? false,
                                      );
                                    },
                                    activeColor: AppColors.primaryDark,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Remember me',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: _openForgotPasswordDialog,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot Password?',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Inline login error ──
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _loginError == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: _LoginErrorBanner(
                                    key: ValueKey(_errorTick),
                                    message: _loginError!,
                                  ),
                                ),
                        ),

                        const SizedBox(height: 20),

                        // ── Login Button ──
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryDark,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shadowColor: AppColors.primaryDark.withOpacity(
                                0.3,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    'Login',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Divider ──
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Colors.grey.shade300,
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                'OR',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Colors.grey.shade300,
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // ── Guest Button ──
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openGuestGateway,
                            icon: Icon(
                              Icons.explore_outlined,
                              color: AppColors.primaryDark,
                              size: 20,
                            ),
                            label: Text(
                              'Continue as Guest',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryDark,
                              side: BorderSide(
                                color: AppColors.primaryDark.withOpacity(0.3),
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Footer ──
                  Text(
                    '© ${DateTime.now().year} UPRISE. All rights reserved.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: Colors.grey.shade500,
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

/// The login form's error line: soft red box, icon, message. No reset link of
/// its own — the form's "Forgot Password?" is right above it.
///
/// Keyed by the caller on every new error, so it replays its short shake even
/// when the message hasn't changed; the same text reappearing with no motion
/// read as "nothing happened".
class _LoginErrorBanner extends StatelessWidget {
  final String message;

  const _LoginErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.beVietnamPro(
      fontSize: 13,
      height: 1.4,
      color: const Color(0xFF991B1B),
      fontWeight: FontWeight.w500,
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (context, t, child) => Transform.translate(
        // Three damped swings.
        offset: Offset(math.sin(t * math.pi * 6) * 6 * (1 - t), 0),
        child: child,
      ),
      child: Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withAlpha(70)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(message, style: textStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
