// lib/screens/guest/guest_access_gateway_screen.dart
//
// GUEST ACCESS GATEWAY — Replaces the old "Continue as Guest" direct flow.
//
// Presents three options:
//   1. Visit as Guest (Visitor mode — no account)
//   2. Sign Up (apply for guest account)
//   3. Log In (authenticated guest with Feedback + Digital ID)
//
// Navigation:
//   Visit as Guest  → GuestHomeScreen (visitor mode, no auth)
//   Sign Up         → GuestRegistrationScreen (in guest_profile_screen.dart)
//   Log In          → GuestLoginScreen → GuestHomeScreen (authenticated mode)
//

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../auth_service.dart';
import '../../services/activity_logger.dart' as activity_log;
import '../../services/password_change_service.dart';
import '../../widgets/common/terms_and_conditions.dart';
import '../../widgets/student/app_colors.dart';
import 'guest_auth_service.dart'; // GuestAuthService.saveSession() + GuestMode enum
import 'guest_home_screen.dart'
    hide
        GuestMode; // GuestHomeScreen only — GuestMode comes from guest_auth_service
import 'guest_profile_screen.dart'; // exposes RegistrationScreen via re-export
import '../../services/app_sign_out.dart';

// ─────────────────────────────────────────────────────────────
//  THEME — matches the shared light AppColors palette used across
//  the rest of mobile (see student_login.dart) instead of a
//  standalone dark theme.
// ─────────────────────────────────────────────────────────────
const _kOrange = AppColors.primaryDark;
const _kBg = AppColors.background;
final _kCardShadow = [
  BoxShadow(
    color: Colors.black.withAlpha(20),
    blurRadius: 30,
    offset: const Offset(0, 12),
  ),
  BoxShadow(
    color: Colors.black.withAlpha(8),
    blurRadius: 6,
    offset: const Offset(0, 2),
  ),
];

Widget _lightBackIcon(BuildContext context) {
  return IconButton(
    onPressed: () => Navigator.pop(context),
    icon: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.arrow_back, color: Colors.grey.shade800, size: 18),
    ),
    padding: EdgeInsets.zero,
    alignment: Alignment.centerLeft,
  );
}

// ─────────────────────────────────────────────────────────────
//  GATEWAY SCREEN
// ─────────────────────────────────────────────────────────────
class GuestAccessGatewayScreen extends StatelessWidget {
  const GuestAccessGatewayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Faint decorative accents — much lower alpha than the old
          // dark-theme circles since they now sit on a light field.
          Positioned(
            right: -60,
            top: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kOrange.withAlpha(13),
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: 100,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kOrange.withAlpha(8),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Back arrow ──────────────────────────────
                  _lightBackIcon(context),

                  const SizedBox(height: 28),

                  // ── UPRISE logo ──────────────────────────────
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: _kOrange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.local_fire_department,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'UPRISE',
                        style: GoogleFonts.beVietnamPro(
                          color: _kOrange,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  Text(
                    'How would you\nlike to continue?',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey.shade900,
                      height: 1.25,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Choose your access mode below.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Option 1: Visit as Guest ─────────────────
                  _AccessCard(
                    icon: Icons.explore_outlined,
                    iconBg: const Color(0xFF1565C0),
                    badge: 'NO ACCOUNT NEEDED',
                    badgeColor: const Color(0xFF1565C0),
                    title: 'Visit as Guest',
                    subtitle:
                        'Browse events, announcements, and the calendar without signing up.',
                    features: const [
                      'Event Feed',
                      'Announcements',
                      'Calendar',
                      'Public Profile',
                    ],
                    buttonLabel: 'Continue as Visitor',
                    buttonColor: const Color(0xFF1565C0),
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const GuestHomeScreen(mode: GuestMode.visitor),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Option 2: Sign Up ────────────────────────
                  _AccessCard(
                    icon: Icons.person_add_outlined,
                    iconBg: const Color(0xFF2E7D32),
                    badge: 'FREE REGISTRATION',
                    badgeColor: const Color(0xFF2E7D32),
                    title: 'Sign Up',
                    subtitle:
                        'Apply for a guest account. Once approved, you unlock more features.',
                    features: const [
                      'Event Feed',
                      'Announcements',
                      'Calendar',
                      'Profile',
                      'Feedback',
                      'Digital ID',
                    ],
                    buttonLabel: 'Apply for Access',
                    buttonColor: const Color(0xFF2E7D32),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GuestSignUpScreen(
                            onSubmitted: (_) => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const GuestHomeScreen(
                                  mode: GuestMode.visitor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Option 3: Log In ─────────────────────────
                  _AccessCard(
                    icon: Icons.login_rounded,
                    iconBg: _kOrange,
                    badge: 'FULL ACCESS',
                    badgeColor: _kOrange,
                    title: 'Log In',
                    subtitle:
                        'Already have guest credentials? Log in to access all features.',
                    features: const [
                      'Event Feed',
                      'Announcements',
                      'Calendar',
                      'Profile',
                      'Feedback',
                      'Digital ID',
                    ],
                    buttonLabel: 'Log In as Guest',
                    buttonColor: _kOrange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GuestLoginScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ACCESS OPTION CARD
// ─────────────────────────────────────────────────────────────
class _AccessCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final List<String> features;
  final String buttonLabel;
  final Color buttonColor;
  final VoidCallback onTap;

  const _AccessCard({
    required this.icon,
    required this.iconBg,
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.buttonLabel,
    required this.buttonColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: _kCardShadow,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg.withAlpha(38),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: iconBg.withAlpha(77)),
                ),
                child: Icon(icon, color: iconBg, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withAlpha(38),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: badgeColor.withAlpha(77)),
                      ),
                      child: Text(
                        badge,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            subtitle,
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 12),

          // Feature pills
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: features
                .map(
                  (f) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 10, color: badgeColor),
                        const SizedBox(width: 4),
                        Text(
                          f,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 10,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonLabel,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  GUEST SIGN UP SCREEN (wrapper — delegates to GuestProfileScreen logic)
// ─────────────────────────────────────────────────────────────
/// Thin wrapper that exposes the registration form from guest_profile_screen
/// as a standalone route reachable from the gateway.
class GuestSignUpScreen extends StatelessWidget {
  final Future<void> Function(String docId) onSubmitted;
  const GuestSignUpScreen({super.key, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return RegistrationScreen(onSubmitted: onSubmitted);
  }
}

// ─────────────────────────────────────────────────────────────
//  GUEST LOGIN SCREEN
// ─────────────────────────────────────────────────────────────
class GuestLoginScreen extends StatefulWidget {
  const GuestLoginScreen({super.key});

  @override
  State<GuestLoginScreen> createState() => _GuestLoginScreenState();
}

class _GuestLoginScreenState extends State<GuestLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _snack('Please enter your email and password.');
      return;
    }
    if (!email.contains('@')) {
      _snack('Please enter a valid email address.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ── Step 1: Authenticate with Firebase Auth ──────────────────
      // The admin created this account via createUserWithEmailAndPassword
      // in external_account.dart (_approveAndCreateAccount), using the
      // generated tempPassword (e.g. "GST-AB1234").
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      final uid = cred.user!.uid;

      // ── Step 1b: Reject accounts that belong to another role ─────
      // A student, org or admin credential authenticates here perfectly
      // well. Without this they fall through to the lookup below, find no
      // approved request, and get told to "wait for admin review" — an
      // approval that is never coming, because theirs is not a guest
      // account. A null role means no users/{uid} doc at all, which the
      // approved-request check below is itself a positive test for.
      final role = await AuthService().getRecordedRole(uid);
      if (role != null && role != 'guest') {
        await AppSignOut.signOut();
        await activity_log.ActivityLogger.log(
          action: 'Blocked non-guest login on guest portal',
          module: 'Authentication',
          severity: 'security',
          details: {'uid': uid, 'email': email, 'role': role},
        );
        if (!mounted) return;
        _snack(
          'This is a ${_roleLabel(role)} account. '
          'Please sign in on the student login screen.',
        );
        setState(() => _isLoading = false);
        return;
      }

      // ── Step 2: Look up the matching external_requests doc by uid ─
      // The admin batch-write stored uid in both external_requests and
      // the guests collection when approving.
      QuerySnapshot snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection('external_requests')
            .where('uid', isEqualTo: uid)
            .where('status', isEqualTo: 'approved')
            .limit(1)
            .get();
      } catch (_) {
        // Fallback: look up by email in case uid wasn't written yet
        snap = await FirebaseFirestore.instance
            .collection('external_requests')
            .where('email', isEqualTo: email)
            .where('status', isEqualTo: 'approved')
            .limit(1)
            .get();
      }

      if (!mounted) return;

      if (snap.docs.isEmpty) {
        // Auth succeeded but no matching approved request — sign out
        // and tell the user their account isn't approved yet.
        await AppSignOut.signOut();
        _snack(
          'Your account is not yet approved. Please wait for admin review.',
        );
        setState(() => _isLoading = false);
        return;
      }

      final docId = snap.docs.first.id;
      final data = snap.docs.first.data() as Map<String, dynamic>;
      final fullName = (data['userName'] as String?) ?? '';
      final mustChange = data['mustChangePassword'] == true;

      // ── Step 3: Persist the session ──────────────────────────────
      await GuestAuthService.saveSession(
        docId: docId,
        email: email,
        fullName: fullName,
      );

      await activity_log.ActivityLogger.log(
        action: 'Guest login',
        module: 'Authentication',
        severity: 'security',
        details: {'uid': uid, 'docId': docId, 'email': email},
      );

      if (!mounted) return;

      // ── Step 4: First-login password change prompt ────────────────
      if (mustChange) {
        // Show the change-password screen before entering the app.
        // After the user changes their password we clear the flag and
        // push to GuestHomeScreen.
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GuestChangePasswordScreen(uid: uid, docId: docId),
          ),
        );
        if (!mounted) return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const GuestHomeScreen(mode: GuestMode.authenticated),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' => 'No account found for this email.',
        'wrong-password' => 'Incorrect password.',
        'invalid-email' => 'Invalid email address.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => e.message ?? 'Login failed.',
      };
      await activity_log.ActivityLogger.log(
        action: 'Failed guest login attempt',
        module: 'Authentication',
        severity: 'warning',
        details: {'email': email, 'reason': e.code},
      );
      _snack(msg);
      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        _snack('Login failed: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  /// How a rejected role reads in a message to the person holding it.
  String _roleLabel(String role) => switch (role) {
    'student' => 'student',
    'org' => 'organization',
    'admin' => 'admin',
    _ => role,
  };

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro(fontSize: 13)),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Guests previously had no self-service way to recover a forgotten
  // password once past their forced first-login change — only an admin
  // could trigger a reset for them from external_account.dart. Same
  // mechanism (Firebase's own password-reset email), just self-service.
  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Enter your email above first, then tap "Forgot password?".');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      await activity_log.ActivityLogger.log(
        action: 'Guest requested password reset',
        module: 'Authentication',
        severity: 'security',
        details: {'email': email},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Password reset link sent to $email.',
              style: GoogleFonts.beVietnamPro(fontSize: 13),
            ),
            backgroundColor: _kOrange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'user-not-found' => 'No account found for this email.',
        'invalid-email' => 'Invalid email address.',
        _ => e.message ?? 'Could not send reset email.',
      };
      _snack(msg);
    } catch (e) {
      _snack('Could not send reset email: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: _lightBackIcon(context),
      ),
      body: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kOrange.withAlpha(13),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: _kOrange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.login_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Guest Login',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.grey.shade900,
                            ),
                          ),
                          Text(
                            'Enter your guest credentials',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),

                  // Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: _kCardShadow,
                    ),
                    child: Column(
                      children: [
                        // Email
                        _buildField(
                          label: 'Email Address',
                          controller: _emailCtrl,
                          hint: 'your@email.com',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        // Password
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Password',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter your password',
                                hintStyle: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: Colors.grey.shade400,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                  color: Colors.grey.shade500,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18,
                                    color: Colors.grey.shade500,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                                filled: true,
                                fillColor: _kBg,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(10),
                                  ),
                                  borderSide: BorderSide(
                                    color: _kOrange,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading ? null : _forgotPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: _kOrange,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kOrange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Log In',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Info about credentials
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kOrange.withAlpha(64)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: _kOrange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your login credentials were provided by the CICT admin after your guest application was approved.',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: Colors.grey.shade700,
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
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.beVietnamPro(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
            prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade500),
            filled: true,
            fillColor: _kBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: _kOrange, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  CHANGE PASSWORD SCREEN
//
//  Used two ways:
//   • forced=true  — shown once after the guest logs in with their
//     admin-issued tempPassword (can't be skipped/backed out of). Pops
//     back so _login() can push GuestHomeScreen. The session is seconds
//     old here, so updatePassword is still "recent" to Firebase and no
//     current-password confirmation is needed (or possible — all the
//     guest has is the temp password). On success it also clears
//     mustChangePassword in both external_requests and users.
//   • forced=false — opened voluntarily from GuestSettingsScreen, on a
//     session that may be days old. Firebase rejects updatePassword with
//     `requires-recent-login` on a stale token, so this path asks for the
//     current password and reauthenticates first. Nothing else changes:
//     the first-login flags are already cleared.
// ─────────────────────────────────────────────────────────────
class GuestChangePasswordScreen extends StatefulWidget {
  final String uid;
  final String docId;
  final bool forced;

  const GuestChangePasswordScreen({
    super.key,
    required this.uid,
    required this.docId,
    this.forced = true,
  });

  @override
  State<GuestChangePasswordScreen> createState() =>
      _GuestChangePasswordScreenState();
}

class _GuestChangePasswordScreenState extends State<GuestChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final currentPw = _currentCtrl.text.trim();
    final newPw = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (newPw.isEmpty || confirm.isEmpty) {
      _snack('Please fill in both fields.');
      return;
    }
    if (!widget.forced && currentPw.isEmpty) {
      _snack('Please enter your current password.');
      return;
    }
    if (newPw.length < 8) {
      _snack('Password must be at least 8 characters.');
      return;
    }
    if (newPw != confirm) {
      _snack('Passwords do not match.');
      return;
    }
    if (widget.forced && !_agreedToTerms) {
      _snack('Please agree to the Terms and Conditions to continue.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-signed-out',
          message: 'Your session expired. Please sign in again.',
        );
      }

      if (widget.forced) {
        // Token is seconds old here — Firebase still counts it as recent.
        await user.updatePassword(newPw);

        // First-login cleanup: drop the temp password and the flag that
        // routed the guest here. Only meaningful on this path.
        final batch = FirebaseFirestore.instance.batch();
        batch.update(
          FirebaseFirestore.instance
              .collection('external_requests')
              .doc(widget.docId),
          {'mustChangePassword': false, 'tempPassword': FieldValue.delete()},
        );
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(widget.uid),
          {'mustChangePassword': false},
        );
        await batch.commit();

        if (mounted) Navigator.pop(context); // return to _login flow
        return;
      }

      // Voluntary change from Settings: the session is old, so confirm the
      // current password to refresh the token before the sensitive call.
      await reauthenticateAndUpdatePassword(
        user: user,
        currentPassword: currentPw,
        newPassword: newPw,
      );

      await activity_log.ActivityLogger.log(
        action: 'Guest changed password',
        module: 'Authentication',
        severity: 'security',
        details: {'uid': widget.uid, 'docId': widget.docId},
      );

      if (!mounted) return;
      _snack('Password updated successfully.', success: true);
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        _snack(passwordChangeErrorMessage(e));
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        _snack('Error: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.beVietnamPro(fontSize: 13)),
        backgroundColor: success
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        foregroundColor: Colors.grey.shade800,
        automaticallyImplyLeading:
            !widget.forced, // forced step can't be skipped/backed out of
        title: Text(
          widget.forced ? 'Set Your Password' : 'Change Password',
          style: GoogleFonts.beVietnamPro(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade900,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kOrange.withAlpha(26),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kOrange.withAlpha(77)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: _kOrange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.forced
                          ? 'You are using a temporary password issued by the CICT admin. '
                                'Please set a new personal password before continuing.'
                          : 'Choose a new password for your account.',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Current password — only on the voluntary path, where it is
            // what refreshes the token Firebase demands for updatePassword.
            if (!widget.forced) ...[
              _buildPasswordField(
                label: 'Current Password',
                controller: _currentCtrl,
                hint: 'Enter your current password',
                obscure: _obscureCurrent,
                onToggle: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              const SizedBox(height: 16),
            ],

            // New password field
            _buildPasswordField(
              label: 'New Password',
              controller: _newCtrl,
              hint: 'At least 8 characters',
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),

            const SizedBox(height: 16),

            // Confirm password field
            _buildPasswordField(
              label: 'Confirm New Password',
              controller: _confirmCtrl,
              hint: 'Re-enter your new password',
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),

            if (widget.forced) ...[
              const SizedBox(height: 20),
              TermsAgreementCheckbox(
                value: _agreedToTerms,
                onChanged: (v) => setState(() => _agreedToTerms = v),
                accent: _kOrange,
                textColor: Colors.grey.shade700,
              ),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : (widget.forced && !_agreedToTerms)
                    ? null
                    : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.forced
                            ? 'Set Password & Continue'
                            : 'Update Password',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          style: GoogleFonts.beVietnamPro(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
            prefixIcon: Icon(
              Icons.lock_outline,
              size: 18,
              color: Colors.grey.shade500,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: Colors.grey.shade500,
              ),
              onPressed: onToggle,
            ),
            filled: true,
            fillColor: _kBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide(color: _kOrange, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
