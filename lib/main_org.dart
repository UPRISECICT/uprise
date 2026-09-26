import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'firebase_options.dart';
import 'screens/public/certificate_verify_screen.dart';
import 'screens/web/org/org_dashboard.dart';
import 'screens/web/org/org_landing_page.dart';
import 'services/app_sign_out.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Certificate QR codes open this site with ?verify=CODE — show the public
  // verification page instead of the landing page. Nothing else changes when
  // the parameter is absent.
  final verifyCode = certificateVerifyCodeFromUrl();
  if (verifyCode != null) {
    runApp(CertificateVerifyApp(verificationCode: verifyCode));
    return;
  }

  runApp(
    const MaterialApp(
      title: 'UPRISE Organization',
      debugShowCheckedModeBanner: false,
      home: OrgAuthGate(),
    ),
  );
}

class OrgAuthGate extends StatefulWidget {
  const OrgAuthGate({super.key});

  @override
  State<OrgAuthGate> createState() => _OrgAuthGateState();
}

class _OrgAuthGateState extends State<OrgAuthGate> {
  String? _cachedUid;
  Future<String?>? _roleFuture;

  Future<String?> _getRole(String uid) {
    if (_cachedUid != uid || _roleFuture == null) {
      _cachedUid = uid;
      final cachedRole = AuthService.getCachedRole(uid);
      if (cachedRole != null) {
        _roleFuture = Future.value(cachedRole);
      } else {
        _roleFuture = AuthService().getUserRole(uid);
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
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        if (!authSnap.hasData) {
          _clearCache();
          return const OrgLandingPage();
        }

        final user = authSnap.data!;
        return FutureBuilder<String?>(
          future: _getRole(user.uid),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final role = (roleSnap.data ?? '').toLowerCase();
            if (role == 'org') {
              return const OrgDashboard();
            }

            AppSignOut.signOut();
            _clearCache();
            return const OrgLandingPage();
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
