import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'firebase_options.dart';
import 'screens/public/certificate_verify_screen.dart';
import 'screens/web/admin/admin_dashboard.dart';
import 'screens/web/admin/admin_landing_page.dart';
import 'services/app_sign_out.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Same public ?verify=CODE handling as main_org.dart, so a verification
  // link works on either portal's domain.
  final verifyCode = certificateVerifyCodeFromUrl();
  if (verifyCode != null) {
    runApp(CertificateVerifyApp(verificationCode: verifyCode));
    return;
  }

  runApp(
    const MaterialApp(
      title: 'UPRISE Admin',
      debugShowCheckedModeBanner: false,
      home: AdminAuthGate(),
    ),
  );
}

class AdminAuthGate extends StatefulWidget {
  const AdminAuthGate({super.key});

  @override
  State<AdminAuthGate> createState() => _AdminAuthGateState();
}

class _AdminAuthGateState extends State<AdminAuthGate> {
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
          return const AdminLandingPage();
        }

        final user = authSnap.data!;
        return FutureBuilder<String?>(
          future: _getRole(user.uid),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final role = (roleSnap.data ?? '').toLowerCase();
            if (role == 'admin') {
              return const AdminDashboard();
            }

            AppSignOut.signOut();
            _clearCache();
            return const AdminLandingPage();
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
