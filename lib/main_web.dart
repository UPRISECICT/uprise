import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'auth_service.dart';
import 'screens/web/admin/admin_dashboard.dart';
import 'screens/web/admin/admin_landing_page.dart';
import 'screens/web/org/org_dashboard.dart';
import 'screens/web/org/org_landing_page.dart';
import 'screens/student/student_login.dart';
import 'screens/student/student_home_screen.dart';
import 'screens/public/certificate_verify_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Removed Firestore settings to avoid internal assertion errors

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Public certificate verification — no auth required
    if (kIsWeb) {
      final verifyCode = Uri.base.queryParameters['verify'];
      if (verifyCode != null && verifyCode.isNotEmpty) {
        return MaterialApp(
          title: 'UPRISE - Certificate Verification',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primaryColor: const Color(0xFFB45309),
            fontFamily: 'BeVietnamPro',
            useMaterial3: true,
            // Material 3's default ThemeData() has no colorScheme set here,
            // so it silently falls back to its own baseline purple seed —
            // that's what made every plain CircularProgressIndicator() in
            // the app render violet instead of the brand color.
            progressIndicatorTheme: const ProgressIndicatorThemeData(
              color: Color(0xFFB45309),
            ),
          ),
          home: CertificateVerifyScreen(verificationCode: verifyCode),
        );
      }
    }

    return MaterialApp(
      title: 'UPRISE - Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFD97706),
        fontFamily: 'BeVietnamPro',
        useMaterial3: true,
        // Same fix as above — without an explicit colorScheme, Material 3
        // defaults every unstyled loading spinner to its own purple, not
        // this app's brand color.
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFD97706),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthGate — single source of truth for routing.
// Uses a StatefulWidget so we can cache the role fetch and avoid
// re-querying Firestore on every auth-stream rebuild.
// ─────────────────────────────────────────────────────────────────────────────
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Cache the role per UID so a widget rebuild doesn't re-hit Firestore.
  String? _cachedUid;
  Future<String?>? _roleFuture;

  Future<String?> _getRoleFuture(String uid) {
    if (_cachedUid != uid) {
      _cachedUid = uid;
      final cachedRole = AuthService.getCachedRole(uid);
      if (cachedRole != null) {
        _roleFuture = Future.value(cachedRole);
      } else {
        _roleFuture = Future<String?>(() async {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            if (!doc.exists) return null;
            final role = (doc.data()?['role'] as String?)?.toLowerCase();
            if (role != null) AuthService.cacheRole(uid, role);
            return role;
          } catch (e) {
            debugPrint('AuthGate role fetch error: $e');
            return null;
          }
        });
      }
    }
    return _roleFuture!;
  }

  void _clearCache() {
    _cachedUid = null;
    _roleFuture = null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        // ── Still resolving ──────────────────────────────────────────
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // ── Stream error (e.g. Firestore internal assertion) ─────────
        if (authSnap.hasError) {
          debugPrint('AuthGate stream error: \${authSnap.error}');
          // Sign out to clear bad state, then let the gate rebuild cleanly.
          FirebaseAuth.instance.signOut();
          return const _LoadingScreen();
        }

        // ── No user → show login / landing ───────────────────────────
        if (!authSnap.hasData) {
          _clearCache();
          if (!kIsWeb) return StudentLogin();
          return const LandingPage();
        }

        // ── User logged in → fetch role (cached) ─────────────────────
        final uid = authSnap.data!.uid;
        return FutureBuilder<String?>(
          future: _getRoleFuture(uid),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            // Role fetch failed → sign out cleanly
            if (roleSnap.hasError) {
              debugPrint('AuthGate roleSnap error: \${roleSnap.error}');
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => FirebaseAuth.instance.signOut(),
              );
              return const _LoadingScreen();
            }

            final role = roleSnap.data ?? '';
            debugPrint('AuthGate: uid=$uid role=$role kIsWeb=$kIsWeb');

            // ── Mobile routing ────────────────────────────────────────
            if (!kIsWeb) {
              if (role == 'student') return const StudentHomeScreen();
              return _WrongPlatformScreen(
                message: 'This account ($role) is only available on Web.',
                icon: Icons.computer,
              );
            }

            // ── Web routing ───────────────────────────────────────────
            if (role == 'admin') return const AdminDashboard();
            if (role == 'org') return OrgDashboard();
            if (role == 'student') {
              return _WrongPlatformScreen(
                message: 'Student accounts are only available on Mobile.',
                icon: Icons.phone_android,
              );
            }

            // Unknown / missing role → sign out, back to landing
            FirebaseAuth.instance.signOut();
            return const LandingPage();
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LoadingScreen
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    // Shown before the signed-in user's role is known, so it can't lean on
    // either the admin or org side's own palette — kept neutral/on-brand
    // for both, with the actual app mark instead of a bare spinner.
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 64,
              height: 64,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.shield_outlined,
                size: 48,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFD97706),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WrongPlatformScreen
// ─────────────────────────────────────────────────────────────────────────────
class _WrongPlatformScreen extends StatelessWidget {
  final String message;
  final IconData icon;
  const _WrongPlatformScreen({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 70, color: Colors.orange),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                // AuthGate's StreamBuilder will react and show LandingPage
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LandingPage  (web-only portal selector)
// ─────────────────────────────────────────────────────────────────────────────
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final query = Uri.base.queryParameters;
    final portal = query['portal']?.toLowerCase();

    if (portal == 'admin') {
      return const AdminLandingPage();
    }
    if (portal == 'org') {
      return const OrgLandingPage();
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF7ED), Color(0xFFFFFBF5), Color(0xFFFEF3C7)],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0xFFFDE68A).withOpacity(0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB45309).withOpacity(0.10),
                      blurRadius: 40,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Logo ────────────────────────────────────────
                    Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFAF5EE),
                        border: Border.all(
                          color: const Color(0xFFFDE68A),
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.school,
                            color: Color(0xFFD97706),
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Title ───────────────────────────────────────
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'UP',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E293B),
                              letterSpacing: 3,
                            ),
                          ),
                          TextSpan(
                            text: 'RISE',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFD97706),
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'CICT Organization Management Portal',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    // ── Divider label ────────────────────────────────
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(color: Color(0xFFF1F5F9)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'SELECT YOUR PORTAL',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10,
                              color: const Color(0xFF94A3B8),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(color: Color(0xFFF1F5F9)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── Admin portal button ──────────────────────────
                    _PortalButton(
                      label: 'Admin Portal',
                      description: 'Manage system & organizations',
                      icon: Icons.shield_rounded,
                      isPrimary: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminLandingPage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Org portal button ────────────────────────────
                    _PortalButton(
                      label: 'Organization Portal',
                      description: 'Access your org dashboard',
                      icon: Icons.domain_rounded,
                      isPrimary: false,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OrgLandingPage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // ── Badges ───────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Badge(label: 'Secure Login', showDot: true),
                        const SizedBox(width: 6),
                        _Badge(
                          label: 'CICT Verified',
                          icon: Icons.verified_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No account? Contact your System Administrator',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LandingPage helpers
// ─────────────────────────────────────────────────────────────────────────────
class _PortalButton extends StatelessWidget {
  final String label, description;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _PortalButton({
    required this.label,
    required this.description,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: isPrimary
                ? const LinearGradient(
                    colors: [Color(0xFFD97706), Color(0xFFB45309)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isPrimary ? null : const Color(0xFFFFFBF5),
            border: isPrimary
                ? null
                : Border.all(color: const Color(0xFFFDE68A), width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? Colors.white.withOpacity(0.22)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isPrimary ? Colors.white : const Color(0xFFB45309),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isPrimary
                              ? Colors.white
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10.5,
                          color: isPrimary
                              ? Colors.white.withOpacity(0.72)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isPrimary
                      ? Colors.white.withOpacity(0.6)
                      : const Color(0xFFD97706),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final bool showDot;
  final IconData? icon;
  const _Badge({required this.label, this.showDot = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 11, color: const Color(0xFFD97706)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
